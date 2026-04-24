//
//  GeminiSession.swift
//  agentrocky
//

import Foundation
import Combine
import Darwin

class GeminiSession: ObservableObject {
    @Published var lines: [OutputLine] = []
    @Published var isReady: Bool = true
    @Published var isRunning: Bool = false

    let workingDirectory: String
    private var isFirstPrompt = true
    private let queue = DispatchQueue(label: "rocky.session", qos: .userInitiated)

    struct OutputLine: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
        enum Kind { case text, tool, system, error }
    }

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    // MARK: - Public

    func send(prompt: String) {
        guard !isRunning else { return }
        isRunning = true

        queue.async { [weak self] in
            self?.runProcess(prompt: prompt)
        }
    }

    // MARK: - Process lifecycle

    private func runProcess(prompt: String) {
        guard let geminiPath = findGemini() else {
            self.append("gemini binary not found — checked:\n" + searchPaths().joined(separator: "\n"), kind: .error)
            DispatchQueue.main.async { self.isRunning = false }
            return
        }

        let proc = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: geminiPath)
        
        var args = [
            "-p", prompt,
            "--output-format", "stream-json"
        ]
        
        if !isFirstPrompt {
            args.append(contentsOf: ["--resume", "latest"])
        }
        
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        var env = ProcessInfo.processInfo.environment
        
        let home = realHome
        let extraPaths = [
            "\(home)/.local/bin",
            "\(home)/.nvm/versions/node/v23.5.0/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")

        proc.environment = env

        proc.standardOutput = stdoutPipe
        proc.standardError  = stderrPipe

        var readBuffer = Data()

        // Read stdout on dedicated queue
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            
            readBuffer.append(data)
            while let idx = readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = readBuffer[readBuffer.startIndex..<idx]
                readBuffer.removeSubrange(readBuffer.startIndex...idx)
                guard let lineStr = String(data: lineData, encoding: .utf8),
                      !lineStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { continue }
                self?.parse(lineStr)
            }
        }

        // Show stderr in terminal (helps diagnose auth issues, etc.)
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            DispatchQueue.main.async { self?.append(trimmed, kind: .error) }
        }

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.append("Process exited (code \(p.terminationStatus))", kind: .system)
            }
        }

        do {
            try proc.run()
            DispatchQueue.main.async { self.isFirstPrompt = false }
        } catch {
            self.append("Failed to launch gemini: \(error.localizedDescription)", kind: .error)
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    // MARK: - Output parsing

    private func parse(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }

        let type = json["type"] as? String ?? ""

        DispatchQueue.main.async { [weak self] in
            switch type {

            case "init":
                // No longer need to set isReady here since it's always true
                break

            case "message", "assistant":
                if let msg = json["message"] as? [String: Any],
                   let content = msg["content"] as? String {
                    self?.append("rocky: \(content)", kind: .text)
                } else if let content = json["content"] as? String {
                    self?.append("rocky: \(content)", kind: .text)
                } else if let msg = json["message"] as? [String: Any],
                          let blocks = msg["content"] as? [[String: Any]] {
                    // Fallback for Claude-style block content
                    for block in blocks { self?.renderBlock(block) }
                }

            case "tool_use":
                self?.renderToolUse(json)

            case "result":
                // The termination handler will manage isRunning = false
                self?.append("", kind: .text)

            default: break
            }
        }
    }

    private func renderToolUse(_ json: [String: Any]) {
        let name = json["name"] as? String ?? "tool"
        let input = json["input"] as? [String: Any] ?? json["arguments"] as? [String: Any] ?? [:]
        let detail: String
        
        if      let cmd  = input["command"]     as? String { detail = cmd }
        else if let path = input["path"]        as? String { detail = path }
        else if let desc = input["description"] as? String { detail = desc }
        else { detail = input.keys.joined(separator: ", ") }
        
        self.append("[\(name)] \(detail)", kind: .tool)
    }

    private func renderBlock(_ block: [String: Any]) {
        switch block["type"] as? String ?? "" {

        case "text":
            if let text = block["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.append("rocky: \(text)", kind: .text)
            }

        case "tool_use":
            self.renderToolUse(block)

        default: break
        }
    }

    // MARK: - Helpers

    private func append(_ text: String, kind: OutputLine.Kind) {
        DispatchQueue.main.async { [weak self] in
            self?.lines.append(OutputLine(text: text, kind: kind))
        }
    }

    private func findGemini() -> String? {
        searchPaths().first { FileManager.default.fileExists(atPath: $0) }
    }

    private func searchPaths() -> [String] {
        let home = realHome
        return [
            "\(home)/.local/bin/gemini",
            "\(home)/.npm-global/bin/gemini",
            "/opt/homebrew/bin/gemini",
            "/usr/local/bin/gemini",
            "/usr/bin/gemini",
        ]
    }

    private var realHome: String {
        getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_dir, encoding: .utf8) }
            ?? NSHomeDirectory()
    }
}
