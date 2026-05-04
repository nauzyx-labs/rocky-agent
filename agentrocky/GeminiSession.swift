//
//  GeminiSession.swift
//  agentrocky
//

import Foundation
import Combine

class GeminiSession: ObservableObject, Identifiable {
    let id = UUID()

    @Published var lines: [OutputLine] = []
    @Published var isRunning: Bool = false
    @Published var streamingText: String = ""

    var title: String
    let workingDirectory: String

    private let apiKey: String
    private let model: String = "gemini-flash-lite-latest"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    /// Conversation history for multi-turn
    private var history: [[String: Any]] = []

    /// Keep session alive for the duration of streaming
    private var urlSession: URLSession?
    private var streamTask: URLSessionDataTask?

    struct OutputLine: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
        enum Kind { case text, tool, system, error }
    }

    init(title: String = "Session", workingDirectory: String, apiKey: String) {
        self.title = title
        self.workingDirectory = workingDirectory
        self.apiKey = apiKey
    }

    // MARK: - Public

    func send(prompt: String) {
        guard !isRunning else { return }
        // Show user message as a chat bubble immediately
        appendMain(prompt, kind: .system)
        DispatchQueue.main.async {
            self.isRunning = true
            self.streamingText = ""
        }

        // Add user turn to conversation history
        let userTurn: [String: Any] = [
            "role": "user",
            "parts": [["text": prompt]]
        ]
        history.append(userTurn)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.callGeminiAPI()
        }
    }

    func restart() {
        streamTask?.cancel()
        streamTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        history = []
        DispatchQueue.main.async {
            self.lines = []
            self.streamingText = ""
            self.isRunning = false
        }
    }

    // MARK: - API call

    private func callGeminiAPI() {
        guard !apiKey.isEmpty else {
            appendMain("⚠ API key not configured. Use Menu Bar → Set API Key…", kind: .error)
            DispatchQueue.main.async { self.isRunning = false }
            return
        }

        let urlStr = "\(baseURL)/\(model):streamGenerateContent?alt=sse&key=\(apiKey)"
        guard let url = URL(string: urlStr) else {
            appendMain("⚠ Invalid API URL", kind: .error)
            DispatchQueue.main.async { self.isRunning = false }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let systemInstruction: [String: Any] = [
            "parts": [["text": "You are Rocky, a friendly and helpful AI assistant. Respond naturally in a conversational tone. Be concise, clear, and friendly. Do NOT use terminal prompts or shell-style output. Working directory context: \(workingDirectory)"]]
        ]

        let body: [String: Any] = [
            "system_instruction": systemInstruction,
            "contents": history,
            "generationConfig": [
                "temperature": 1.0,
                "maxOutputTokens": 8192
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            appendMain("⚠ Failed to build request", kind: .error)
            DispatchQueue.main.async { self.isRunning = false }
            return
        }
        request.httpBody = bodyData


        // Accumulate full response for history
        var fullResponse = ""
        // SSE line buffer
        var sseBuffer = ""

        let delegate = SSEDelegate(
            onData: { [weak self] chunk in
                guard let self else { return }
                // Handle direct JSON error responses (e.g., 429 Quota Exceeded)
                let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("{") && trimmed.contains("\"error\"") {
                    if let data = trimmed.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = json["error"] as? [String: Any],
                       let msg = error["message"] as? String {
                        self.appendMain("⚠ API Error: \(msg)", kind: .error)
                        return
                    }
                }

                sseBuffer += chunk

                // Split on newlines, process complete lines
                var lines = sseBuffer.components(separatedBy: "\n")
                // The last element may be incomplete — keep it in the buffer
                sseBuffer = lines.removeLast()

                for line in lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let jsonStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    guard !jsonStr.isEmpty, jsonStr != "[DONE]" else { continue }

                    guard let data = jsonStr.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { continue }

                    // Extract text from candidates[0].content.parts[].text
                    if let candidates = json["candidates"] as? [[String: Any]],
                       let first = candidates.first,
                       let content = first["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]] {
                        let text = parts.compactMap { $0["text"] as? String }.joined()
                        if !text.isEmpty {
                            fullResponse += text
                            let snapshot = fullResponse
                            DispatchQueue.main.async {
                                self.streamingText = snapshot
                            }
                        }
                    }

                    // Surface API errors
                    if let error = json["error"] as? [String: Any],
                       let msg = error["message"] as? String {
                        self.appendMain("⚠ API error: \(msg)", kind: .error)
                    }
                }
            },
            onComplete: { [weak self] error in
                guard let self else { return }
                DispatchQueue.main.async {
                    if let error, (error as NSError).code != NSURLErrorCancelled {
                        self.appendMain("⚠ \(error.localizedDescription)", kind: .error)
                    } else if !fullResponse.isEmpty {
                        // Commit streamed text as a final AI bubble
                        self.lines.append(OutputLine(text: fullResponse, kind: .text))
                        // Add to conversation history
                        self.history.append([
                            "role": "model",
                            "parts": [["text": fullResponse]]
                        ])
                    }
                    self.streamingText = ""
                    self.isRunning = false
                }

                // Release session
                self.urlSession?.finishTasksAndInvalidate()
                self.urlSession = nil
            }
        )

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        urlSession = session
        streamTask = session.dataTask(with: request)
        streamTask?.resume()
    }

    // MARK: - Helpers

    private func appendMain(_ text: String, kind: OutputLine.Kind) {
        DispatchQueue.main.async { [weak self] in
            self?.lines.append(OutputLine(text: text, kind: kind))
        }
    }
}

// MARK: - URLSession SSE Delegate

private class SSEDelegate: NSObject, URLSessionDataDelegate {
    private let onData: (String) -> Void
    private let onComplete: (Error?) -> Void

    init(onData: @escaping (String) -> Void, onComplete: @escaping (Error?) -> Void) {
        self.onData = onData
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        if let str = String(data: data, encoding: .utf8) {
            onData(str)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        onComplete(error)
    }
}
