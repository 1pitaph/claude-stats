#import "LlamaChatBridge.h"

#import <llama/llama.h>

#include <algorithm>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

static NSString * const LlamaChatBridgeErrorDomain = @"com.claudestats.LlamaChatBridge";

static NSError * LlamaChatError(NSInteger code, NSString * message) {
    return [NSError errorWithDomain:LlamaChatBridgeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void EnsureLlamaChatBackend() {
    static std::once_flag once;
    std::call_once(once, [] {
        llama_backend_init();
    });
}

@interface LlamaChatBridge ()
@property(nonatomic, assign) struct llama_model * model;
@property(nonatomic, assign) struct llama_context * context;
@property(nonatomic, assign) NSInteger maxContextTokens;
@property(nonatomic, assign) NSInteger decodeBatchTokenLimit;
@end

@implementation LlamaChatBridge

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                          maxContextTokens:(NSInteger)maxContextTokens
                                  useMetal:(BOOL)useMetal
                                     error:(NSError **)error {
    self = [super init];
    if (!self) { return nil; }

    EnsureLlamaChatBackend();
    _maxContextTokens = std::max<NSInteger>(512, maxContextTokens);
    _decodeBatchTokenLimit = std::min<NSInteger>(_maxContextTokens, 2048);

    llama_model_params modelParams = llama_model_default_params();
    modelParams.n_gpu_layers = useMetal ? -1 : 0;
    modelParams.use_mmap = true;

    _model = llama_model_load_from_file(modelPath.fileSystemRepresentation, modelParams);
    if (_model == nullptr) {
        if (error) { *error = LlamaChatError(1, @"Unable to load GGUF LLM model."); }
        return nil;
    }

    llama_context_params contextParams = llama_context_default_params();
    contextParams.n_ctx = (uint32_t)_maxContextTokens;
    contextParams.n_batch = (uint32_t)_decodeBatchTokenLimit;
    contextParams.n_ubatch = (uint32_t)std::min<NSInteger>(_maxContextTokens, 512);
    contextParams.n_seq_max = 1;
    contextParams.n_threads = (int32_t)std::max(2u, std::thread::hardware_concurrency() / 2);
    contextParams.n_threads_batch = (int32_t)std::max(2u, std::thread::hardware_concurrency());
    contextParams.embeddings = false;

    _context = llama_init_from_model(_model, contextParams);
    if (_context == nullptr) {
        llama_model_free(_model);
        _model = nullptr;
        if (error) { *error = LlamaChatError(2, @"Unable to initialize llama chat context."); }
        return nil;
    }

    return self;
}

- (void)dealloc {
    if (_context != nullptr) {
        llama_free(_context);
        _context = nullptr;
    }
    if (_model != nullptr) {
        llama_model_free(_model);
        _model = nullptr;
    }
}

- (nullable NSString *)completeMessages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
                            maxNewTokens:(NSInteger)maxNewTokens
                            temperature:(double)temperature
                                  error:(NSError **)error {
    NSMutableString * output = [NSMutableString string];
    BOOL ok = [self streamMessages:messages
                       maxNewTokens:maxNewTokens
                        temperature:temperature
                       tokenHandler:^BOOL(NSString * token) {
        [output appendString:token];
        return YES;
    } error:error];
    return ok ? [output copy] : nil;
}

- (BOOL)streamMessages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
          maxNewTokens:(NSInteger)maxNewTokens
           temperature:(double)temperature
          tokenHandler:(LlamaChatTokenHandler)tokenHandler
                 error:(NSError **)error {
    if (_model == nullptr || _context == nullptr) {
        if (error) { *error = LlamaChatError(3, @"llama chat runtime is not initialized."); }
        return NO;
    }
    if (messages.count == 0) {
        if (error) { *error = LlamaChatError(4, @"Chat completion requires at least one message."); }
        return NO;
    }

    std::vector<std::string> roles;
    std::vector<std::string> contents;
    std::vector<llama_chat_message> chatMessages;
    roles.reserve(messages.count);
    contents.reserve(messages.count);
    chatMessages.reserve(messages.count);

    for (NSDictionary<NSString *, NSString *> * message in messages) {
        NSString * role = message[@"role"] ?: @"user";
        NSString * content = message[@"content"] ?: @"";
        roles.emplace_back(role.UTF8String ?: "user");
        contents.emplace_back(content.UTF8String ?: "");
    }
    for (size_t index = 0; index < roles.size(); index++) {
        chatMessages.push_back({roles[index].c_str(), contents[index].c_str()});
    }

    std::string prompt;
    const char * tmpl = llama_model_chat_template(_model, nullptr);
    int formattedLength = llama_chat_apply_template(
        tmpl,
        chatMessages.data(),
        chatMessages.size(),
        true,
        nullptr,
        0
    );
    if (formattedLength > 0) {
        std::vector<char> formatted((size_t)formattedLength);
        formattedLength = llama_chat_apply_template(
            tmpl,
            chatMessages.data(),
            chatMessages.size(),
            true,
            formatted.data(),
            formatted.size()
        );
        if (formattedLength > 0) {
            prompt.assign(formatted.data(), (size_t)formattedLength);
        }
    }

    if (prompt.empty()) {
        for (size_t index = 0; index < roles.size(); index++) {
            prompt += roles[index];
            prompt += ": ";
            prompt += contents[index];
            prompt += "\n";
        }
        prompt += "assistant: ";
    }

    const llama_vocab * vocab = llama_model_get_vocab(_model);
    int32_t promptTokenCount = -llama_tokenize(
        vocab,
        prompt.c_str(),
        (int32_t)prompt.size(),
        nullptr,
        0,
        true,
        true
    );
    if (promptTokenCount <= 0) {
        if (error) { *error = LlamaChatError(5, @"Unable to tokenize chat prompt."); }
        return NO;
    }
    std::vector<llama_token> promptTokens((size_t)promptTokenCount);
    promptTokenCount = llama_tokenize(
        vocab,
        prompt.c_str(),
        (int32_t)prompt.size(),
        promptTokens.data(),
        (int32_t)promptTokens.size(),
        true,
        true
    );
    if (promptTokenCount <= 0) {
        if (error) { *error = LlamaChatError(6, @"Unable to tokenize chat prompt."); }
        return NO;
    }
    promptTokens.resize((size_t)promptTokenCount);

    NSInteger requestedNewTokens = maxNewTokens > 0 ? maxNewTokens : 512;
    NSInteger cappedNewTokens = std::min<NSInteger>(requestedNewTokens, 2048);
    int32_t maxPromptTokens = std::max<int32_t>(16, (int32_t)_maxContextTokens - (int32_t)cappedNewTokens - 1);
    if ((int32_t)promptTokens.size() > maxPromptTokens) {
        promptTokens.erase(promptTokens.begin(), promptTokens.end() - maxPromptTokens);
    }

    llama_memory_clear(llama_get_memory(_context), true);

    int32_t decodeLimit = std::max<int32_t>(1, (int32_t)_decodeBatchTokenLimit);
    for (size_t offset = 0; offset < promptTokens.size(); offset += (size_t)decodeLimit) {
        int32_t chunkTokenCount = (int32_t)std::min<size_t>(
            (size_t)decodeLimit,
            promptTokens.size() - offset
        );
        llama_batch batch = llama_batch_get_one(promptTokens.data() + offset, chunkTokenCount);
        if (llama_decode(_context, batch) != 0) {
            if (error) { *error = LlamaChatError(7, @"llama_decode failed while evaluating chat prompt."); }
            return NO;
        }
    }

    llama_sampler * sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (temperature <= 0.0) {
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
    } else {
        llama_sampler_chain_add(sampler, llama_sampler_init_min_p(0.05f, 1));
        llama_sampler_chain_add(sampler, llama_sampler_init_temp((float)temperature));
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    }

    std::string response;
    size_t emittedBytes = 0;
    for (NSInteger index = 0; index < cappedNewTokens; index++) {
        llama_token token = llama_sampler_sample(sampler, _context, -1);
        if (llama_vocab_is_eog(vocab, token)) {
            break;
        }

        char pieceBuffer[512];
        int pieceLength = llama_token_to_piece(vocab, token, pieceBuffer, sizeof(pieceBuffer), 0, true);
        if (pieceLength < 0) {
            llama_sampler_free(sampler);
            if (error) { *error = LlamaChatError(8, @"Unable to convert sampled token to text."); }
            return NO;
        }
        response.append(pieceBuffer, (size_t)pieceLength);

        if (tokenHandler && response.size() > emittedBytes) {
            NSString * tokenText = [[NSString alloc] initWithBytes:response.data() + emittedBytes
                                                            length:response.size() - emittedBytes
                                                          encoding:NSUTF8StringEncoding];
            if (tokenText != nil && tokenText.length > 0) {
                emittedBytes = response.size();
                if (!tokenHandler(tokenText)) {
                    break;
                }
            }
        }

        llama_batch next = llama_batch_get_one(&token, 1);
        if (llama_decode(_context, next) != 0) {
            llama_sampler_free(sampler);
            if (error) { *error = LlamaChatError(9, @"llama_decode failed while generating chat response."); }
            return NO;
        }
    }

    llama_sampler_free(sampler);
    if (tokenHandler && response.size() > emittedBytes) {
        NSString * remaining = [[NSString alloc] initWithBytes:response.data() + emittedBytes
                                                        length:response.size() - emittedBytes
                                                      encoding:NSUTF8StringEncoding];
        if (remaining != nil && remaining.length > 0) {
            tokenHandler(remaining);
        }
    }
    return YES;
}

@end
