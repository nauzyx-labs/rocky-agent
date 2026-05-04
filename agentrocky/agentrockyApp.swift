//
//  agentrockyApp.swift
//  agentrocky
//

import SwiftUI
import AppKit
import Combine

@main
struct agentrockyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Native macOS menu bar
        MenuBarExtra("rocky", systemImage: "desktopcomputer") {
            MenuBarContent(appDelegate: appDelegate)
        }

        Settings { EmptyView() }
    }
}

// MARK: - Menu Bar Content

struct MenuBarContent: View {
    let appDelegate: AppDelegate

    var body: some View {
        Group {
            Text("rocky agent")
                .font(.headline)

            Divider()

            Button("Open Chat") {
                appDelegate.rockyState.isChatOpen = true
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("New Chat") {
                appDelegate.rockyState.addChatSession()
                appDelegate.rockyState.isChatOpen = true
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("New Terminal") {
                appDelegate.rockyState.addTerminalSession()
                appDelegate.rockyState.isChatOpen = true
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("Restart Session") {
                appDelegate.rockyState.restartActiveSession()
            }

            Divider()

            Button("Set API Key…") {
                appDelegate.showApiKeyAlert()
            }

            Divider()

            Button("Quit rocky") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var rockyWindow: NSPanel?
    var rockyState = RockyState()

    private var walkTimer: Timer?
    private var frameTimer: Timer?
    private let rockyWidth: CGFloat = 180
    private let rockyHeight: CGFloat = 140
    private let walkSpeed: CGFloat = 100
    private var lastTick: Date = Date()

    private var jazzWorkItem: DispatchWorkItem?
    private var bubbleWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private let workingMessages = ["rocky building", "rocky do big science", "rocky save erid"]
    private let jazzMessages = ["fist my bump", "amaze amaze amaze", "rocky hate mark"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupRockyWindow()
        startWalking()
        setupJazzTriggers()
        setupSpeechBubble()
    }

    // MARK: - Window

    func setupRockyWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: rockyWidth, height: rockyHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        if let screen = NSScreen.main {
            let dockTop = screen.visibleFrame.minY
            let startX = screen.frame.midX - rockyWidth / 2
            panel.setFrameOrigin(NSPoint(x: startX, y: dockTop))
            rockyState.positionX = startX
            rockyState.screenBounds = screen.frame
            rockyState.dockY = dockTop
        }

        let contentView = NSHostingView(rootView: RockyView(state: rockyState))
        contentView.frame = panel.contentView!.bounds
        contentView.autoresizingMask = [.width, .height]
        panel.contentView = contentView

        panel.makeKeyAndOrderFront(nil)
        rockyWindow = panel
    }

    // MARK: - Walk

    func startWalking() {
        lastTick = Date()

        walkTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 8.0, repeats: true) { [weak self] _ in
            self?.updateFrame()
        }
    }

    private func updatePosition() {
        let now = Date()
        defer { lastTick = now }
        guard !rockyState.isChatOpen, !rockyState.isJazzing else { return }

        let dt = now.timeIntervalSince(lastTick)
        let screen = rockyState.screenBounds
        let maxX = screen.maxX - rockyWidth

        rockyState.positionX += CGFloat(dt) * walkSpeed * rockyState.direction

        if rockyState.positionX >= maxX {
            rockyState.positionX = maxX
            rockyState.direction = -1
        } else if rockyState.positionX <= screen.minX {
            rockyState.positionX = screen.minX
            rockyState.direction = 1
        }

        rockyWindow?.setFrameOrigin(NSPoint(x: rockyState.positionX, y: rockyState.dockY))
    }

    private func updateFrame() {
        if rockyState.isJazzing {
            rockyState.jazzFrameIndex = (rockyState.jazzFrameIndex + 1) % 3
        } else if !rockyState.isChatOpen {
            rockyState.walkFrameIndex = (rockyState.walkFrameIndex + 1) % 2
        }
    }

    // MARK: - Jazz (triggered by any session completing)

    private func setupJazzTriggers() {
        // Observe all sessions via state changes
        rockyState.$sessions
            .flatMap { sessions in
                Publishers.MergeMany(sessions.map { $0.$isRunning })
            }
            .removeDuplicates()
            .dropFirst()
            .filter { !$0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.startJazz(duration: 3.0) }
            .store(in: &cancellables)

        scheduleRandomJazz()
    }

    private func setupSpeechBubble() {
        rockyState.$sessions
            .flatMap { sessions in
                Publishers.MergeMany(sessions.map { $0.$isRunning })
            }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self else { return }
                self.bubbleWorkItem?.cancel()
                if running {
                    withAnimation {
                        self.rockyState.speechBubble = self.workingMessages.randomElement()!
                    }
                } else {
                    withAnimation {
                        self.rockyState.speechBubble = "rocky done!"
                    }
                    let work = DispatchWorkItem { [weak self] in
                        withAnimation { self?.rockyState.speechBubble = nil }
                    }
                    self.bubbleWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
                }
            }
            .store(in: &cancellables)
    }

    func startJazz(duration: TimeInterval) {
        guard !rockyState.isJazzing else { return }
        rockyState.isJazzing = true

        jazzWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rockyState.isJazzing = false
        }
        jazzWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func scheduleRandomJazz() {
        let delay = Double.random(in: 15...45)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if !self.rockyState.isChatOpen {
                self.startJazz(duration: 2.0)
                withAnimation { self.rockyState.speechBubble = self.jazzMessages.randomElement()! }
                self.bubbleWorkItem?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    withAnimation { self?.rockyState.speechBubble = nil }
                }
                self.bubbleWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
            }
            self.scheduleRandomJazz()
        }
    }

    // MARK: - API Key

    func showApiKeyAlert() {
        let alert = NSAlert()
        alert.messageText = "Gemini API Key"
        alert.informativeText = "Enter your Gemini API key. It will be stored in app preferences."
        alert.alertStyle = .informational

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = "AIza..."
        input.stringValue = UserDefaults.standard.string(forKey: "gemini_api_key") ?? ""
        alert.accessoryView = input
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let key = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(key, forKey: "gemini_api_key")
            rockyState.sessions.forEach { $0.terminalSession?.close() }
            rockyState.sessions = []
            rockyState.addChatSession()
            rockyState.activeSessionIndex = 0
        }
    }
}
