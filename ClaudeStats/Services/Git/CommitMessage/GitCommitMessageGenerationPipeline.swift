import Foundation

struct GitCommitMessageGenerationPipeline: Sendable {
    private let generator: any LLMGenerating
    private let prompts: GitCommitMessagePromptFactory
    private let resultBuilder: GitCommitMessageResultBuilder

    init(
        generator: any LLMGenerating,
        prompts: GitCommitMessagePromptFactory = GitCommitMessagePromptFactory(),
        resultBuilder: GitCommitMessageResultBuilder = GitCommitMessageResultBuilder()
    ) {
        self.generator = generator
        self.prompts = prompts
        self.resultBuilder = resultBuilder
    }

    func generate(
        snapshot: GitCommitMessageSnapshot,
        analysis: GitCommitMessageAnalysis,
        chunks: [GitDiffChunk],
        plan: GitCommitMessagePlan,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        runID: String
    ) async throws -> GitCommitMessageResult {
        switch plan.algorithm {
        case .singleShot:
            return try await runSingleShot(
                snapshot: snapshot,
                analysis: analysis,
                plan: plan,
                endpoint: endpoint,
                language: language,
                runID: runID
            )
        case .fileLevel, .mapReduce:
            return try await runMapReduce(
                snapshot: snapshot,
                analysis: analysis,
                chunks: chunks,
                plan: plan,
                endpoint: endpoint,
                language: language,
                runID: runID
            )
        }
    }

    private func runSingleShot(
        snapshot: GitCommitMessageSnapshot,
        analysis: GitCommitMessageAnalysis,
        plan: GitCommitMessagePlan,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        runID: String
    ) async throws -> GitCommitMessageResult {
        let context = prompts.singleShotContext(snapshot: snapshot, analysis: analysis)
        let request = LLMGenerationRequest(
            systemPrompt: prompts.finalSystemPrompt(language: language),
            userPrompt: prompts.finalUserInstruction(context: context, algorithm: plan.algorithm),
            maxTokens: 1_400,
            temperature: 0.2,
            outputShape: .jsonObject
        )
        let logged = try await generateLogged(
            endpoint: endpoint,
            request: request,
            runID: runID,
            phase: "single-shot",
            snapshot: snapshot,
            analysis: analysis,
            plan: plan
        )
        var usage = GitLLMUsage.zero
        usage.add(logged.response)
        let outcome = resultBuilder.build(
            from: logged.response.text,
            snapshot: snapshot,
            plan: plan,
            modelName: logged.response.model,
            usage: usage,
            language: language
        )
        recordParse(
            runID: runID,
            callID: logged.callID,
            phase: "single-shot",
            jsonParseOK: outcome.jsonParseOK,
            snapshot: snapshot,
            analysis: analysis,
            plan: plan,
            endpoint: endpoint
        )
        return outcome.result
    }

    private func runMapReduce(
        snapshot: GitCommitMessageSnapshot,
        analysis: GitCommitMessageAnalysis,
        chunks: [GitDiffChunk],
        plan: GitCommitMessagePlan,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        runID: String
    ) async throws -> GitCommitMessageResult {
        let observations = try await summarizeChunks(
            chunks,
            snapshot: snapshot,
            analysis: analysis,
            plan: plan,
            endpoint: endpoint,
            language: language,
            runID: runID
        )
        var usage = observations.usage
        var allObservations = observations.values
        var modelName = observations.modelName ?? endpoint.model

        if plan.useRiskAgent {
            let risk = try await runRiskAgent(
                snapshot: snapshot,
                analysis: analysis,
                chunks: chunks,
                plan: plan,
                endpoint: endpoint,
                language: language,
                runID: runID
            )
            usage.add(risk.usage)
            allObservations.append(risk.observation)
            modelName = risk.modelName
        }

        let repoContext = plan.includeRepoContext ? await repositoryContext(for: snapshot) : ""
        let reduceContext = prompts.reduceContext(
            snapshot: snapshot,
            analysis: analysis,
            repoContext: repoContext,
            observations: allObservations
        )
        let reduceRequest = LLMGenerationRequest(
            systemPrompt: prompts.finalSystemPrompt(language: language),
            userPrompt: prompts.finalUserInstruction(context: reduceContext, algorithm: plan.algorithm),
            maxTokens: 1_600,
            temperature: 0.2,
            outputShape: .jsonObject
        )
        let reduced = try await generateLogged(
            endpoint: endpoint,
            request: reduceRequest,
            runID: runID,
            phase: "reduce",
            snapshot: snapshot,
            analysis: analysis,
            plan: plan
        )
        usage.add(reduced.response)
        modelName = reduced.response.model
        let outcome = resultBuilder.build(
            from: reduced.response.text,
            snapshot: snapshot,
            plan: plan,
            modelName: modelName,
            usage: usage,
            language: language
        )
        recordParse(
            runID: runID,
            callID: reduced.callID,
            phase: "reduce",
            jsonParseOK: outcome.jsonParseOK,
            snapshot: snapshot,
            analysis: analysis,
            plan: plan,
            endpoint: endpoint
        )

        return outcome.result
    }

    private func summarizeChunks(
        _ chunks: [GitDiffChunk],
        snapshot: GitCommitMessageSnapshot,
        analysis: GitCommitMessageAnalysis,
        plan: GitCommitMessagePlan,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        runID: String
    ) async throws -> (values: [GitCommitMessageObservation], usage: GitLLMUsage, modelName: String?) {
        if chunks.isEmpty {
            return ([], .zero, nil)
        }

        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: (GitCommitMessageObservation, LLMGenerationResult).self) { group in
            for chunk in chunks {
                group.addTask {
                    let request = LLMGenerationRequest(
                        systemPrompt: prompts.chunkSystemPrompt(language: language),
                        userPrompt: prompts.chunkPrompt(chunk),
                        maxTokens: 800,
                        temperature: 0.15,
                        outputShape: .jsonObject
                    )
                    let logged = try await generateLogged(
                        endpoint: endpoint,
                        request: request,
                        runID: runID,
                        phase: "chunk",
                        snapshot: snapshot,
                        analysis: analysis,
                        plan: plan,
                        chunkID: chunk.id
                    )
                    let parsed = GitCommitMessageResponseParser.parseObservation(
                        logged.response.text,
                        fallbackPath: chunk.path,
                        fallbackID: chunk.id
                    )
                    recordParse(
                        runID: runID,
                        callID: logged.callID,
                        phase: "chunk",
                        jsonParseOK: parsed.jsonParseOK,
                        snapshot: snapshot,
                        analysis: analysis,
                        plan: plan,
                        endpoint: endpoint,
                        chunkID: chunk.id
                    )
                    return (parsed.observation, logged.response)
                }
            }

            var values: [GitCommitMessageObservation] = []
            var usage = GitLLMUsage.zero
            var modelName: String?
            for try await (observation, response) in group {
                values.append(observation)
                usage.add(response)
                modelName = response.model
            }
            values.sort { $0.id < $1.id }
            return (values, usage, modelName)
        }
    }

    private func runRiskAgent(
        snapshot: GitCommitMessageSnapshot,
        analysis: GitCommitMessageAnalysis,
        chunks: [GitDiffChunk],
        plan: GitCommitMessagePlan,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        runID: String
    ) async throws -> (observation: GitCommitMessageObservation, usage: GitLLMUsage, modelName: String) {
        let request = LLMGenerationRequest(
            systemPrompt: prompts.chunkSystemPrompt(language: language),
            userPrompt: prompts.riskAgentPrompt(snapshot: snapshot, analysis: analysis, chunks: chunks, language: language),
            maxTokens: 900,
            temperature: 0.1,
            outputShape: .jsonObject
        )
        let logged = try await generateLogged(
            endpoint: endpoint,
            request: request,
            runID: runID,
            phase: "risk-agent",
            snapshot: snapshot,
            analysis: analysis,
            plan: plan
        )
        var usage = GitLLMUsage.zero
        usage.add(logged.response)
        let parsed = GitCommitMessageResponseParser.parseObservation(
            logged.response.text,
            fallbackPath: "risk-agent",
            fallbackID: "risk-agent"
        )
        recordParse(
            runID: runID,
            callID: logged.callID,
            phase: "risk-agent",
            jsonParseOK: parsed.jsonParseOK,
            snapshot: snapshot,
            analysis: analysis,
            plan: plan,
            endpoint: endpoint
        )
        var observation = parsed.observation
        observation.id = "risk-agent"
        observation.path = "risk-agent"
        return (observation, usage, logged.response.model)
    }

    private func repositoryContext(for snapshot: GitCommitMessageSnapshot) async -> String {
        await Task.detached(priority: .utility) {
            let root = URL(fileURLWithPath: snapshot.repo.rootPath)
            let candidates = [
                "AGENTS.md",
                "README.md",
                "Package.swift",
                "project.yml",
                "Info.plist",
                ".github/workflows/release.yml",
            ]
            var blocks: [String] = []
            for candidate in candidates {
                let url = root.appendingPathComponent(candidate)
                guard let data = try? Data(contentsOf: url), data.count <= 96 * 1024,
                      let text = String(data: data, encoding: .utf8)
                else { continue }
                blocks.append("### \(candidate)\n\(text.gitCommitMessageTruncated(to: 4_000))")
            }
            return blocks.joined(separator: "\n\n").gitCommitMessageTruncated(to: 24_000)
        }.value
    }

    private func generateLogged(
        endpoint: AppLLMGenerationEndpoint,
        request: LLMGenerationRequest,
        runID: String,
        phase: String,
        snapshot: GitCommitMessageSnapshot,
        analysis: GitCommitMessageAnalysis,
        plan: GitCommitMessagePlan,
        chunkID: String? = nil
    ) async throws -> LoggedLLMResponse {
        let callID = UUID().uuidString
        var fields = diagnosticsFields(
            runID: runID,
            callID: callID,
            phase: phase,
            snapshot: snapshot,
            analysis: analysis,
            plan: plan,
            endpoint: endpoint,
            request: request,
            chunkID: chunkID
        )
        GitCommitMessageDiagnosticsLog.record("llm.call.start", fields: fields)
        let started = Date()
        do {
            let response = try await generator.generate(endpoint: endpoint, request: request)
            fields["duration_ms"] = durationMilliseconds(since: started)
            fields["input_tokens"] = "\(response.inputTokens)"
            fields["output_tokens"] = "\(response.outputTokens)"
            fields["total_tokens"] = "\(response.totalTokens)"
            fields["response_chars"] = "\(response.text.count)"
            fields["response_hash"] = GitCommitMessageDiagnosticsLog.hash(response.text)
            fields["model"] = response.model
            GitCommitMessageDiagnosticsLog.record("llm.call.end", fields: fields)
            return LoggedLLMResponse(callID: callID, response: response)
        } catch {
            let diagnostic = diagnosticError(error)
            fields["duration_ms"] = durationMilliseconds(since: started)
            fields["error_type"] = diagnostic.type
            fields["error"] = diagnostic.message
            GitCommitMessageDiagnosticsLog.record("llm.call.error", level: "error", fields: fields)
            throw error
        }
    }

    private func recordParse(
        runID: String,
        callID: String,
        phase: String,
        jsonParseOK: Bool,
        snapshot: GitCommitMessageSnapshot,
        analysis: GitCommitMessageAnalysis,
        plan: GitCommitMessagePlan,
        endpoint: AppLLMGenerationEndpoint,
        chunkID: String? = nil
    ) {
        var fields = diagnosticsFields(
            runID: runID,
            callID: callID,
            phase: phase,
            snapshot: snapshot,
            analysis: analysis,
            plan: plan,
            endpoint: endpoint,
            request: nil,
            chunkID: chunkID
        )
        fields["json_parse_ok"] = jsonParseOK ? "true" : "false"
        GitCommitMessageDiagnosticsLog.record("llm.call.parse", level: jsonParseOK ? "info" : "warn", fields: fields)
    }

    private func diagnosticsFields(
        runID: String,
        callID: String,
        phase: String,
        snapshot: GitCommitMessageSnapshot,
        analysis: GitCommitMessageAnalysis,
        plan: GitCommitMessagePlan,
        endpoint: AppLLMGenerationEndpoint,
        request: LLMGenerationRequest?,
        chunkID: String?
    ) -> [String: String] {
        var fields: [String: String] = [
            "run_id": runID,
            "call_id": callID,
            "phase": phase,
            "algorithm": plan.algorithm.title,
            "target_kind": snapshot.target.kind,
            "target_id_hash": GitCommitMessageDiagnosticsLog.hash(snapshot.target.identity),
            "repo_key_hash": GitCommitMessageDiagnosticsLog.hash(snapshot.repo.cacheKey),
            "diff_hash": snapshot.diffHash,
            "file_count": "\(plan.fileCount)",
            "risk_categories": riskCategories(analysis),
            "prompt_version": GitCommitMessageService.promptVersion,
            "algorithm_version": GitCommitMessageService.algorithmVersion,
            "mode": endpoint.mode.rawValue,
            "protocol": endpoint.protocol.rawValue,
            "base_host": endpoint.baseURL.host ?? "-",
            "model": endpoint.model,
        ]
        if let chunkID {
            fields["chunk_id"] = chunkID
        }
        if let request {
            let prompt = request.systemPrompt + "\n" + request.userPrompt
            fields["output_shape"] = request.outputShape.diagnosticsValue
            fields["max_tokens"] = "\(request.maxTokens)"
            fields["temperature"] = String(format: "%.3f", request.temperature)
            fields["prompt_chars"] = "\(prompt.count)"
            fields["prompt_hash"] = GitCommitMessageDiagnosticsLog.hash(prompt)
        }
        return fields
    }

    private func riskCategories(_ analysis: GitCommitMessageAnalysis) -> String {
        let categories = Set(analysis.riskLabels.map { $0.category.rawValue })
        return categories.sorted().joined(separator: ",").gitCommitMessageNilIfEmpty ?? "-"
    }

    private func durationMilliseconds(since started: Date) -> String {
        "\(Int(Date().timeIntervalSince(started) * 1_000))"
    }

    private func diagnosticError(_ error: Error) -> (type: String, message: String) {
        switch error {
        case LLMClientError.invalidResponse:
            return ("LLMClientError.invalidResponse", "LLM service returned an invalid response.")
        case LLMClientError.emptyOutput:
            return ("LLMClientError.emptyOutput", "LLM service returned an empty response.")
        case LLMClientError.httpStatus(let status, _):
            return ("LLMClientError.httpStatus", "HTTP \(status)")
        case is CancellationError:
            return ("CancellationError", "Cancelled")
        default:
            return (String(describing: type(of: error)), error.localizedDescription.gitCommitMessageTruncated(to: 240))
        }
    }
}

private struct LoggedLLMResponse: Sendable {
    var callID: String
    var response: LLMGenerationResult
}

private extension LLMGenerationOutputShape {
    var diagnosticsValue: String {
        switch self {
        case .text: "text"
        case .jsonObject: "json_object"
        }
    }
}
