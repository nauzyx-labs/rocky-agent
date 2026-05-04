//
//  ChatView.swift
//  agentrocky
//

import SwiftUI
import Combine

struct ChatView: View {
    @ObservedObject var state: RockyState

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            SessionTabBar(state: state)

            Divider().background(Color.green.opacity(0.3))

            // Active session terminal
            if let session = state.activeSession {
                TerminalView(session: session)
            } else {
                Spacer()
                Text("no session")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.green.opacity(0.4))
                Spacer()
            }
        }
        .background(Color(red: 0.04, green: 0.04, blue: 0.04))
    }
}

// MARK: - Session Tab Bar

struct SessionTabBar: View {
    @ObservedObject var state: RockyState

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(Array(state.sessions.enumerated()), id: \.element.id) { index, session in
                        SessionTab(
                            session: session,
                            isActive: index == state.activeSessionIndex,
                            canClose: state.sessions.count > 1
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                state.activeSessionIndex = index
                            }
                        } onClose: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                state.closeSession(at: index)
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 4)
            }

            // New session button
            Button(action: { state.addSession() }) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.green.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .padding(.top, 4)
            .help("New session")
        }
        .frame(height: 34)
        .background(Color(red: 0.06, green: 0.06, blue: 0.06))
    }
}

struct SessionTab: View {
    @ObservedObject var session: GeminiSession
    let isActive: Bool
    let canClose: Bool
    let onTap: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            // Running indicator dot
            if session.isRunning {
                LoadingDots()
            }

            Text(session.title)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(isActive ? .green : .green.opacity(0.45))
                .lineLimit(1)

            if canClose && (isActive || isHovered) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.green.opacity(0.6))
                }
                .buttonStyle(.plain)
                .frame(width: 12, height: 12)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive
                      ? Color.green.opacity(0.12)
                      : (isHovered ? Color.green.opacity(0.06) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isActive ? Color.green.opacity(0.35) : Color.clear, lineWidth: 0.5)
        )
        .onTapGesture { onTap() }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isActive)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Animated Loading Dots

struct LoadingDots: View {
    @State private var phase = 0

    let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.green)
                    .frame(width: 3, height: 3)
                    .opacity(phase == i ? 1.0 : 0.25)
                    .scaleEffect(phase == i ? 1.2 : 0.8)
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// MARK: - Terminal View (per session)

struct TerminalView: View {
    @ObservedObject var session: GeminiSession
    @State private var input: String = ""
    @FocusState private var inputFocused: Bool

    private var promptLabel: String {
        URL(fileURLWithPath: session.workingDirectory).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Terminal output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(session.lines) { line in
                            TerminalLine(line: line)
                        }

                        // Live streaming ghost line — shows text as tokens arrive
                        if session.isRunning {
                            if session.streamingText.isEmpty {
                                // Waiting for first token
                                HStack(spacing: 6) {
                                    LoadingDots()
                                    Text("rocky thinking…")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.green.opacity(0.4))
                                }
                                .padding(.top, 2)
                            } else {
                                // Tokens are arriving — show live text
                                HStack(alignment: .top, spacing: 6) {
                                    Text("rocky: \(session.streamingText)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.green.opacity(0.85))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    // Blinking cursor
                                    BlinkingCursor()
                                }
                                .padding(.top, 2)
                            }
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(10)
                }
                .onChange(of: session.lines.count) { _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
                .onChange(of: session.isRunning) { _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
                .onChange(of: session.streamingText) { _ in
                    proxy.scrollTo("bottom")
                }
            }

            Divider().background(Color.green.opacity(0.3))

            // Input row
            HStack(spacing: 6) {
                Text(promptLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.green.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.head)

                Text("❯")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(session.isRunning ? .green.opacity(0.3) : .green)

                TextField("", text: $input)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.green)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .disabled(session.isRunning)
                    .onSubmit { sendMessage() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))
        }
        .onAppear { inputFocused = true }
    }

    private func sendMessage() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !session.isRunning else { return }
        session.lines.append(.init(text: "\(promptLabel) ❯ \(trimmed)", kind: .system))
        input = ""
        session.send(prompt: trimmed)
        inputFocused = true
    }
}

// MARK: - Terminal Line

struct TerminalLine: View {
    let line: GeminiSession.OutputLine

    var body: some View {
        Text(line.text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var color: Color {
        switch line.kind {
        case .text:   return .green
        case .tool:   return Color(red: 0.4, green: 0.8, blue: 1.0)
        case .system: return .green.opacity(0.5)
        case .error:  return Color(red: 1.0, green: 0.4, blue: 0.4)
        }
    }
}

// MARK: - Blinking Cursor

struct BlinkingCursor: View {
    @State private var visible = true
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Text("▋")
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.green)
            .opacity(visible ? 1 : 0)
            .onReceive(timer) { _ in visible.toggle() }
    }
}
