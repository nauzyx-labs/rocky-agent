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

    /// Single persistent Gemini session — survives popover open/close.
    lazy var session: GeminiSession = GeminiSession(workingDirectory: realHome)

    private var realHome: String {
        getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_dir, encoding: .utf8) }
            ?? NSHomeDirectory()
    }
}
