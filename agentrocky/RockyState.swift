//
//  RockyState.swift
//  agentrocky
//

import SwiftUI
import Combine
import Darwin

/// Shared observable state between AppDelegate (walk logic) and RockyView (display).
class RockyState: ObservableObject {
    @Published var walkFrameIndex: Int = 0
    @Published var jazzFrameIndex: Int = 0
    @Published var isJazzing: Bool = false
    @Published var direction: CGFloat = 1
    @Published var isChatOpen: Bool = false
    @Published var positionX: CGFloat = 0
    @Published var speechBubble: String? = nil
    var screenBounds: CGRect = .zero
    var dockY: CGFloat = 0

    // Multi-session tab support
    @Published var sessions: [GeminiSession] = []
    @Published var activeSessionIndex: Int = 0

    var activeSession: GeminiSession? {
        guard !sessions.isEmpty, activeSessionIndex < sessions.count else { return nil }
        return sessions[activeSessionIndex]
    }

    private var apiKey: String {
        // Read from environment or a stored preference
        ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
            ?? UserDefaults.standard.string(forKey: "gemini_api_key")
            ?? ""
    }

    private var realHome: String {
        getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_dir, encoding: .utf8) }
            ?? NSHomeDirectory()
    }

    init() {
        // Start with one default session
        let first = GeminiSession(title: "rocky #1", workingDirectory: realHome, apiKey: apiKey)
        sessions = [first]
    }

    func addSession() {
        let num = sessions.count + 1
        let session = GeminiSession(title: "rocky #\(num)", workingDirectory: realHome, apiKey: apiKey)
        sessions.append(session)
        activeSessionIndex = sessions.count - 1
    }

    func closeSession(at index: Int) {
        guard sessions.count > 1 else { return }
        sessions.remove(at: index)
        if activeSessionIndex >= sessions.count {
            activeSessionIndex = sessions.count - 1
        }
    }

    func restartActiveSession() {
        activeSession?.restart()
    }
}
