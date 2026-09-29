import SwiftUI

struct AITabView: View {
    @State private var vm = AIViewModel()
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .topLeading, endPoint: .bottomTrailing))
                            Text("Pearl")
                                .font(.pearlTitle)
                                .foregroundColor(.primaryText)
                        }
                        Text("Your on-device health AI")
                            .font(.pearlCaption)
                            .foregroundColor(.tertiaryText)
                    }
                    Spacer()
                    if !vm.messages.isEmpty {
                        Button {
                            withAnimation { vm.clearConversation() }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.quaternaryText)
                                .frame(width: 36, height: 36)
                                .glassBackground(cornerRadius: 10)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if vm.messages.isEmpty && !vm.isStreaming {
                                PearlWelcomeView(suggestions: vm.welcomeSuggestions()) { suggestion in
                                    inputText = suggestion
                                    send()
                                }
                                .padding(.top, 20)
                            }

                            ForEach(vm.messages) { msg in
                                ChatBubble(message: msg)
                                    .id(msg.id)
                            }

                            // Live streaming bubble
                            if vm.isStreaming {
                                StreamingBubble(content: vm.streamingContent)
                                    .id("streaming")
                            }

                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .onChange(of: vm.messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom") }
                    }
                    .onChange(of: vm.isStreaming) { _, _ in
                        withAnimation { proxy.scrollTo("bottom") }
                    }
                    .onChange(of: vm.streamingContent) { _, _ in
                        proxy.scrollTo("bottom")
                    }
                }
                .scrollDismissesKeyboard(.interactively)

                // Input bar
                HStack(spacing: 10) {
                    TextField("Ask Pearl...", text: $inputText, axis: .vertical)
                        .font(.pearlBody)
                        .foregroundColor(.primaryText)
                        .focused($inputFocused)
                        .lineLimit(1...4)
                        .submitLabel(.send)
                        .onSubmit { send() }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.glassBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.glassBorder, lineWidth: 1)
                        }

                    Button { send() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(inputText.isEmpty ? .quaternaryText : .white)
                            .frame(width: 44, height: 44)
                            .background {
                                if inputText.isEmpty {
                                    Color.glassBackground
                                } else {
                                    LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .topLeading, endPoint: .bottomTrailing)
                                }
                            }
                            .clipShape(Circle())
                    }
                    .disabled(inputText.isEmpty || vm.isStreaming)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .padding(.top, 8)
                .background(.ultraThinMaterial)
            }
        }
        .navigationBarHidden(true)
        .onAppear { vm.load() }
        .onDisappear { vm.streamingTask?.cancel() }
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        vm.send(text)
    }
}

// MARK: - Streaming bubble

struct StreamingBubble: View {
    let content: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 30)
                .glassBackground(cornerRadius: 10)

            VStack(alignment: .leading, spacing: 4) {
                if content.isEmpty {
                    // Thinking dots while waiting for first token
                    ThinkingDotsView()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.glassBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.glassBorder, lineWidth: 1)
                        }
                } else {
                    Text(content)
                        .font(.pearlBody)
                        .foregroundColor(.primaryText)
                        .lineSpacing(5)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.glassBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.glassBorder, lineWidth: 1)
                        }
                }
            }
            .frame(maxWidth: 280, alignment: .leading)

            Spacer(minLength: 8)
        }
    }
}

// MARK: - Thinking dots

struct ThinkingDotsView: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.pearlGreen.opacity(0.7))
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == i ? 1.3 : 0.8)
                    .animation(.easeInOut(duration: 0.35), value: phase)
            }
        }
        .onAppear { phase = 0 }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// MARK: - Welcome prompts

struct PearlWelcomeView: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundStyle(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("Ask Pearl anything")
                    .font(.pearlTitle2).foregroundColor(.primaryText)
                Text("Pearl is your AI health companion. She reads your body data and thinks with you, not at you. Private, on-device, no internet needed.")
                    .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button { onSelect(s) } label: {
                        HStack {
                            Text(s)
                                .font(.pearlSubheadline)
                                .foregroundColor(.secondaryText)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.quaternaryText)
                        }
                        .padding(14)
                        .glassBackground(cornerRadius: 14)
                    }
                }
            }
        }
    }
}

// MARK: - Gradient helper

extension LinearGradient {
    func asAnyShapeStyle() -> AnyShapeStyle { AnyShapeStyle(self) }
}
