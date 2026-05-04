//
//  RockyView.swift
//  agentrocky
//

import SwiftUI

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct RockyView: View {
    @ObservedObject var state: RockyState
    @State private var showChat = false

    private var currentSpriteName: String {
        if state.isJazzing { return "jazz\(state.jazzFrameIndex + 1)" }
        if state.isChatOpen { return "stand" }
        return state.walkFrameIndex == 0 ? "walkleft1" : "walkleft2"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear

            if let bubble = state.speechBubble {
                VStack(spacing: 0) {
                    Text(bubble)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                        )
                    BubbleTail()
                        .fill(Color.white)
                        .frame(width: 14, height: 8)
                }
                .padding(.bottom, 84)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.7, anchor: .bottom).combined(with: .opacity),
                    removal: .scale(scale: 0.7, anchor: .bottom).combined(with: .opacity)
                ))
            }

            Button(action: {
                state.isChatOpen.toggle()
                showChat = state.isChatOpen
                if showChat {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }) {
                if let img = NSImage(named: currentSpriteName) {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 80, height: 80)
                        .scaleEffect(x: state.direction > 0 ? -1 : 1, y: 1)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.8))
                        .frame(width: 60, height: 60)
                        .overlay(Text("R").foregroundColor(.white).font(.title))
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showChat, arrowEdge: .top) {
                ChatView(state: state)
                    .frame(width: 480, height: 560)
            }
            .onChange(of: showChat) { open in
                state.isChatOpen = open
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: state.speechBubble)
    }
}
