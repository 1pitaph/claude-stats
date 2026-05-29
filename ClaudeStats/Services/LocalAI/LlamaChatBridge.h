#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^LlamaChatTokenHandler)(NSString *token);

@interface LlamaChatBridge : NSObject

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                          maxContextTokens:(NSInteger)maxContextTokens
                                  useMetal:(BOOL)useMetal
                                     error:(NSError **)error;

- (nullable NSString *)completeMessages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
                           maxNewTokens:(NSInteger)maxNewTokens
                            temperature:(double)temperature
                                  error:(NSError **)error;

- (BOOL)streamMessages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
          maxNewTokens:(NSInteger)maxNewTokens
           temperature:(double)temperature
          tokenHandler:(LlamaChatTokenHandler)tokenHandler
                 error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
