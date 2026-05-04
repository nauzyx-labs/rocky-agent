//
//  ChatView.swift
//  agentrocky
//

import SwiftUI
import Combine

// MARK: - Root Chat View

struct ChatView: View {
    @ObservedObject var state: RockyState

    var body: some View {
        VStack(spacing: 0) {
            SessionTabBar(state: state)

            if let session = state.activeSession {
                Group {
                    switch session.type {
                    case .chat:
                        if let chat = session.chatSession {
                            ChatSessionView(session: chat)
                                .id(session.id) // force re-render on tab switch
                        }
                    case .terminal:
                        if let term = session.terminalSession {
                            TerminalView(session: term)
                                .id(session.id)
                        }
                    }
                }
                .transition(.opacity)
            } else {
                Spacer()
                Text("No session open")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .background(.background)
    }
}

// MARK: - Session Tab Bar

struct SessionTabBar: View {
    @ObservedObject var state: RockyState

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
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
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 4)
            }

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 4)

            // New chat button
            Button(action: { state.addChatSession() }) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("New Chat")

            // New terminal button
            Button(action: { state.addTerminalSession() }) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .help("New Terminal")
        }
        .frame(height: 36)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - Session Tab

struct SessionTab: View {
    @ObservedObject var session: AnySession
    let isActive: Bool
    let canClose: Bool
    let onTap: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            if session.isRunning {
                LoadingDots()
            } else {
                Image(systemName: session.type.icon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isActive ? .primary : .tertiary)
            }

            Text(session.title)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)

            if canClose && (isActive || isHovered) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .frame(width: 12, height: 12)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive
                      ? Color.accentColor.opacity(0.15)
                      : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 0.5)
        )
        .onTapGesture { onTap() }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isActive)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Chat Session View (bubble UI)

struct ChatSessionView: View {
    @ObservedObject var session: GeminiSession
    @State private var input: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(session.lines) { line in
                            ChatBubbleRow(line: line)
                        }

                        // Streaming ghost bubble
                        if session.isRunning {
                            if session.streamingText.isEmpty {
                                // Waiting for first token
                                HStack(alignment: .center, spacing: 6) {
                                    AvatarDot()
                                    LoadingDots()
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14)
                                                .fill(Color.primary.opacity(0.06))
                                        )
                                    Spacer()
                                }
                                .padding(.leading, 12)
                                .padding(.vertical, 3)
                            } else {
                                // Tokens arriving — live ghost bubble
                                HStack(alignment: .top, spacing: 6) {
                                    AvatarDot()
                                    Text(session.streamingText)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14)
                                                .fill(Color.primary.opacity(0.06))
                                        )
                                        .frame(maxWidth: 380, alignment: .leading)
                                    Spacer()
                                }
                                .padding(.leading, 12)
                                .padding(.vertical, 3)
                            }
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 10)
                }
                .onChange(of: session.lines.count) {
                    withAnimation { proxy.scrollTo("bottom") }
                }
                .onChange(of: session.streamingText) {
                    proxy.scrollTo("bottom")
                }
            }

            Divider()

            // Input bar
            HStack(spacing: 8) {
                TextField("Message Rocky…", text: $input, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .disabled(session.isRunning)
                    .onSubmit { sendMessage() }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.primary.opacity(0.06))
                    )

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isRunning
                                         ? Color.secondary.opacity(0.35) : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isRunning)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear { inputFocused = true }
    }

    private func sendMessage() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !session.isRunning else { return }
        input = ""
        session.send(prompt: trimmed)
        inputFocused = true
    }
}

// MARK: - Chat Bubble Row

struct ChatBubbleRow: View {
    let line: GeminiSession.OutputLine

    var isUser: Bool { line.kind == .system }
    var isError: Bool { line.kind == .error }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if isUser {
                Spacer()
                Text(line.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.accentColor)
                    )
                    .frame(maxWidth: 360, alignment: .trailing)
                    .padding(.trailing, 12)
            } else {
                AvatarDot()
                    .padding(.top, 2)
                Text(displayText)
                    .font(isError ? .callout : .body)
                    .foregroundStyle(isError ? Color.red : Color.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isError ? Color.red.opacity(0.1) : Color.primary.opacity(0.06))
                    )
                    .frame(maxWidth: 380, alignment: .leading)
                Spacer()
            }
        }
        .padding(.leading, isUser ? 0 : 12)
        .padding(.vertical, 3)
    }

    // Strip "rocky: " prefix if present
    private var displayText: String {
        let t = line.text
        if t.hasPrefix("rocky: ") { return String(t.dropFirst(7)) }
        return t
    }
}

// MARK: - Avatar Dot

struct AvatarDot: View {
    var body: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.8))
            .frame(width: 22, height: 22)
            .overlay(
                Text("R")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Terminal View (per session)

struct TerminalView: View {
    @ObservedObject var session: TerminalSession
    @State private var input: String = ""
    @FocusState private var inputFocused: Bool
    @State private var fontSize: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(session.lines) { line in
                            Text(line.text)
                                .font(.system(size: fontSize, design: .monospaced))
                                .foregroundStyle(line.isInput ? Color.accentColor : Color.primary.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(10)
                }
                .onChange(of: session.lines.count) {
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }

            Divider()

            HStack(spacing: 6) {
                Text("$")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)

                TextField("", text: $input)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .onSubmit {
                        session.send(input)
                        input = ""
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { inputFocused = true }
    }
}

// MARK: - Animated Loading Dots

struct LoadingDots: View {
    @State private var phase = 0
    let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 5, height: 5)
                    .opacity(phase == i ? 1.0 : 0.3)
                    .scaleEffect(phase == i ? 1.2 : 0.9)
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}
