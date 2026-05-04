//
//  RockyState.swift
//  agentrocky
//

import SwiftUI
import Combine
import Darwin

/// The type of a session tab
enum SessionType {
    case chat
    case terminal

    var icon: String {
        switch self {
        case .chat:     return "bubble.left.and.bubble.right.fill"
        case .terminal: return "terminal.fill"
        }
    }

    var label: String {
        switch self {
        case .chat:     return "Chat"
        case .terminal: return "Terminal"
        }
    }
}

/// A wrapper so both session kinds can live in the same tab array
class AnySession: ObservableObject, Identifiable {
    let id = UUID()
    let type: SessionType
    var title: String

    // Only one of these will be set
    var chatSession: GeminiSession?
    var terminalSession: TerminalSession?

    @Published var isRunning: Bool = false

    init(chat: GeminiSession, title: String) {
        self.type = .chat
        self.chatSession = chat
        self.title = title
        // mirror isRunning
        chat.$isRunning
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRunning)
    }

    init(terminal: TerminalSession, title: String) {
        self.type = .terminal
        self.terminalSession = terminal
        self.title = title
        terminal.$isRunning
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRunning)
    }
}

/// Shared observable state
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
    @Published var sessions: [AnySession] = []
    @Published var activeSessionIndex: Int = 0

    var activeSession: AnySession? {
        guard !sessions.isEmpty, activeSessionIndex < sessions.count else { return nil }
        return sessions[activeSessionIndex]
    }

    var apiKey: String {
        ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
            ?? UserDefaults.standard.string(forKey: "gemini_api_key")
            ?? ""
    }

    private var realHome: String {
        getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_dir, encoding: .utf8) }
            ?? NSHomeDirectory()
    }

    init() {
        let chat = GeminiSession(title: "Chat #1", workingDirectory: realHome, apiKey: apiKey)
        sessions = [AnySession(chat: chat, title: "Chat #1")]
    }

    func addChatSession() {
        let num = sessions.filter { $0.type == .chat }.count + 1
        let title = "Chat #\(num)"
        let chat = GeminiSession(title: title, workingDirectory: realHome, apiKey: apiKey)
        let s = AnySession(chat: chat, title: title)
        sessions.append(s)
        activeSessionIndex = sessions.count - 1
    }

    func addTerminalSession() {
        let num = sessions.filter { $0.type == .terminal }.count + 1
        let title = "Terminal #\(num)"
        let term = TerminalSession(workingDirectory: realHome)
        let s = AnySession(terminal: term, title: title)
        sessions.append(s)
        activeSessionIndex = sessions.count - 1
    }

    func closeSession(at index: Int) {
        guard sessions.count > 1 else { return }
        sessions[index].terminalSession?.close()
        sessions.remove(at: index)
        if activeSessionIndex >= sessions.count {
            activeSessionIndex = sessions.count - 1
        }
    }

    func restartActiveSession() {
        if let chat = activeSession?.chatSession {
            chat.restart()
        } else if let term = activeSession?.terminalSession {
            term.restart()
        }
    }
}
