import SwiftUI
import UIKit
import Foundation

private struct Message: Identifiable {
    let id: UUID
    var content: String
    let isUser: Bool
}

private struct MarkdownImage {
    let alt: String
    let source: String
}

private enum MessageContentKind {
    case text(String)
    case image(MarkdownImage)
}

private struct MessageContentPart {
    let kind: MessageContentKind
}

private struct MessageImageToken {
    let range: NSRange
    let image: MarkdownImage
    let priority: Int
}

private enum SSEConfig {
    static let baseURL = "https://www.iconsolepro.com/oauth"
    static let endpoint = "/iConsoleProAIApi/AiTest"
    static let token = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJsb2dpblR5cGUiOiJsb2dpbiIsImxvZ2luSWQiOiIyMDEzNTM5NTAyNDgzNTgyOTc2Iiwicm5TdHIiOiJXUTh5ZUo1QjJrQnU2MmkxRG9kQVdEck1CUXp0MHZJcyJ9.jGsDDtp_leyTbQRJ3VnM-SsM1LVFUxgvksYFUIadz08"
    static let maxRetryCount = 2
    static let debugImageParsing = false
}

private struct SSEPayload: Decodable {
    let text: String?
    let content: String?
    let title: String?
    let thumbnail: String?
    let videoArray: [SSEVideoItem]?
    let data: SSECourseData?
    let result: SSECourseData?
}

private struct SSEVideoItem: Decodable {
    let thumbnail: String?
}

private struct SSECourseData: Decodable {
    let title: String?
    let thumbnail: String?
    let videoArray: [SSEVideoItem]?
}

private struct SSECourseCard {
    let title: String
    let thumbnail: String
}

struct ContentView: View {
    private enum ScrollTriggerSource {
        case newMessage
        case streamingChunk
        case keyboardFocus
    }

    private enum VoiceDropTarget {
        case none
        case cancel
        case transcribe
    }

    @State private var selectedTab: ChatTab = .chat
    @State private var inputText = ""
    @State private var avatarBreathing = false
    @State private var messages: [Message] = []
    @State private var lastAutoScrollAnimationTime: CFTimeInterval = 0
    @State private var voiceButtonMode = false
    @State private var isVoicePressing = false
    @State private var showVoiceOverlay = false
    @State private var voiceDropTarget: VoiceDropTarget = .none
    @State private var voiceRippleAnimating = false
    @FocusState private var isInputFocused: Bool
    private let bottomAnchorID = "bottom"
    private let voiceAccentColor = Color(hex: "FF9800")
    private let imageCornerRadius: CGFloat = 20

    private let suggestions = [
        "低碳水饮食 vs 低脂饮食, 哪种更适合减脂?",
        "如何避免运动损伤?",
        "居家高效燃脂动作有哪些?"
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    header
                    tabControl

                    ScrollView {
                        VStack(spacing: 14) {
                            avatarSection
                            suggestionsSection
                            chatSection
                            Spacer().frame(height: 7)
                        }
                        .padding(.top, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissKeyboard()
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .bottom) {
                inputBar {
                    sendMessage()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(.ultraThinMaterial)
            }
            .overlay {
                if showVoiceOverlay {
                    voiceOverlay
                        .transition(.opacity)
                }
            }
            .onChange(of: isInputFocused) { _, focused in
                if focused {
                    scrollToBottom(using: proxy, source: .keyboardFocus)
                }
            }
            .onChange(of: messages.last?.id) { _, _ in
                scrollToBottom(using: proxy, source: .newMessage)
            }
            .onChange(of: messages.last?.content) { _, _ in
                scrollToBottom(using: proxy, source: .streamingChunk)
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(hex: "E3D3FA"), Color(hex: "FFFAE0"), Color(hex: "CAEAF7")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var header: some View {
        HStack {
            HStack {
                Button {} label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.75))
                }
                Spacer()
            }
            .frame(width: 88)

            Spacer(minLength: 0)

            Text("AI对话")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.72))

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                Button {} label: {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.black.opacity(0.72))
                }
                Button {} label: {
                    Image(systemName: "clock")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.black.opacity(0.72))
                }
            }
            .frame(width: 88, alignment: .trailing)
        }
    }

    private var tabControl: some View {
        HStack {
            Spacer()
            HStack(spacing: 8) {
                tabButton(title: "对话", icon: "message", tab: .chat)
                tabButton(title: "生成的内容", icon: nil, tab: .generated)
            }
            .padding(4)
            Spacer()
        }
    }

    private func tabButton(title: String, icon: String?, tab: ChatTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? Color.white : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var avatarSection: some View {
        VStack(spacing: 8) {
            avatarImage
                .frame(width: 124, height: 124)
                .scaleEffect(avatarBreathing ? 1.04 : 0.96)
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 6)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                        avatarBreathing = true
                    }
                }

            VStack(spacing: 4) {
                Text("Hi~我是你的助理小佑")
                Text("随意为你解答有关健身的问题")
            }
            .font(.system(size: 18, weight: .medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.black.opacity(0.56))
        }
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let image = UIImage(named: "小佑") ?? UIImage(named: "img/小佑") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Circle()
                .fill(Color.white.opacity(0.9))
                .overlay(
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.orange)
                )
        }
    }

    private var suggestionsSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Rectangle().fill(Color.black.opacity(0.2)).frame(height: 1)
                Text("你可能感兴趣")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.38))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Rectangle().fill(Color.black.opacity(0.2)).frame(height: 1)
            }
            .padding(.horizontal, 42)

            VStack(spacing: 10) {
                ForEach(suggestions, id: \.self) { item in
                    Button {} label: {
                        HStack(spacing: 10) {
                            suggestionIcon

                            Text(item)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.7))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.9, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(Color.white.opacity(0.74))
                        )
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var chatSection: some View {
        VStack(spacing: 16) {
            ForEach(messages) { message in
                HStack {
                    if message.isUser {
                        Spacer()
                        Text(message.content)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(Color(hex: "FF9C00"))
                            )
                            .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: .trailing)
                    } else {
                        if message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            assistantLoadingBubble
                                .frame(maxWidth: UIScreen.main.bounds.width * 0.9, alignment: .leading)
                        } else {
                            assistantMessageStream(content: message.content)
                                .frame(maxWidth: UIScreen.main.bounds.width * 0.9, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                }
                .id(message.id)
            }
            Color.clear
                .frame(height: 1)
                .id(bottomAnchorID)
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func assistantMessageStream(content: String) -> some View {
        let parts = buildAssistantParts(from: content)

        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part.kind {
                case .text(let text):
                    assistantTextBubble(text)
                case .image(let image):
                    assistantImageCard(image)
                }
            }
        }
    }

    @ViewBuilder
    private func assistantTextBubble(_ text: String) -> some View {
        Text(.init(text))
            .foregroundStyle(Color.black.opacity(0.78))
            .lineSpacing(4)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
            )
    }

    private var assistantLoadingBubble: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    let pulse = 0.5 + 0.5 * sin((t * 6) - Double(index) * 0.9)
                    Circle()
                        .fill(Color.gray.opacity(0.62))
                        .frame(width: 10, height: 10)
                        .opacity(0.24 + pulse * 0.66)
                        .scaleEffect(0.82 + pulse * 0.22)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
            )
        }
    }

    @ViewBuilder
    private func assistantImageCard(_ image: MarkdownImage) -> some View {
        let cardWidth = UIScreen.main.bounds.width * 0.45
        ZStack(alignment: .bottomLeading) {
            assistantImageView(image)
            if let caption = imageCaption(from: image) {
                Rectangle()
                    .fill(Color.black.opacity(0.42))
                    .frame(height: 34)
                    .overlay(alignment: .leading) {
                        Text(caption)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                    }
            }
        }
        .frame(width: cardWidth, height: cardWidth * 0.58, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func assistantImageView(_ image: MarkdownImage) -> some View {
        let url = URL(string: image.source)
        if let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    imagePlaceholder
                        .onAppear { debugLog("Image loading started: \(image.source)") }
                case .success(let loadedImage):
                    loadedImage
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear { debugLog("Image loaded success: \(image.source)") }
                case .failure:
                    imagePlaceholder
                        .onAppear { debugLog("Image loaded failed: \(image.source)") }
                @unknown default:
                    imagePlaceholder
                }
            }
            .clipped()
        } else if let localImage = UIImage(named: image.source) ?? UIImage(named: "img/\(image.source)") {
            Image(uiImage: localImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { debugLog("Image loaded from local assets: \(image.source)") }
                .clipped()
        } else {
            imagePlaceholder
                .clipped()
                .onAppear { debugLog("Image source invalid/unresolved: \(image.source)") }
        }
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.black.opacity(0.08))
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.35))
            )
    }

    private func imageCaption(from image: MarkdownImage) -> String? {
        let trimmedAlt = image.alt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAlt.isEmpty {
            return trimmedAlt
        }
        return nil
    }

    private func inputBar(onSend: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    voiceButtonMode.toggle()
                    if voiceButtonMode {
                        dismissKeyboard()
                    }
                }
            } label: {
                Image(systemName: "mic")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(voiceButtonMode ? .white : .black.opacity(0.95))
                    .frame(width: 74, height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(voiceButtonMode ? voiceAccentColor : Color.white.opacity(0.8))
                    )
            }
            .buttonStyle(.plain)

            if voiceButtonMode {
                Text("按住说话")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isVoicePressing ? .white : Color.black.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isVoicePressing ? voiceAccentColor : Color.white.opacity(0.86))
                    )
                    .contentShape(Rectangle())
                    .gesture(voiceDragGesture)
            } else {
                HStack(spacing: 10) {
                    TextField("有什么健康问题需要问我吗~", text: $inputText)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.black.opacity(0.72))
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .onSubmit {
                            onSend()
                        }

                    Button(action: onSend) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color(hex: "F4A31B"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .frame(height: 62)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.8))
                )
            }
        }
    }

    private var voiceDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if !isVoicePressing {
                    isVoicePressing = true
                    showVoiceOverlay = true
                    startRecording()
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        voiceRippleAnimating = true
                    }
                }
                voiceDropTarget = detectVoiceDropTarget(at: value.location)
            }
            .onEnded { value in
                let target = detectVoiceDropTarget(at: value.location)
                handleVoiceRelease(target: target)
            }
    }

    private var voiceOverlay: some View {
        GeometryReader { geo in
            let height = geo.size.height

            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()

                VStack(spacing: 36) {
                    ZStack {
                        Circle()
                            .fill(voiceAccentColor.opacity(0.2))
                            .frame(width: voiceRippleAnimating ? 200 : 150, height: voiceRippleAnimating ? 200 : 150)
                        Circle()
                            .fill(voiceAccentColor.opacity(0.35))
                            .frame(width: voiceRippleAnimating ? 140 : 100, height: voiceRippleAnimating ? 140 : 100)
                        Circle()
                            .fill(voiceAccentColor)
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 34, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                    }
                    .animation(.easeInOut(duration: 0.9), value: voiceRippleAnimating)
                    .padding(.top, height * 0.18)

                    Text(voiceOverlayHintText)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.78))

                    Spacer()

                    HStack(spacing: 32) {
                        voiceTarget(
                            title: "取消",
                            activeText: "松开取消",
                            icon: "xmark.circle.fill",
                            activeColor: .red,
                            isActive: voiceDropTarget == .cancel
                        )

                        voiceTarget(
                            title: "转文字",
                            activeText: "松开转文字",
                            icon: "text.bubble.fill",
                            activeColor: voiceAccentColor,
                            isActive: voiceDropTarget == .transcribe
                        )
                    }
                    .padding(.bottom, max(40, geo.safeAreaInsets.bottom + 16))
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentShape(Rectangle())
        }
        .allowsHitTesting(false)
    }

    private var voiceOverlayHintText: String {
        switch voiceDropTarget {
        case .none:
            return "松开发送语音"
        case .cancel:
            return "松开取消"
        case .transcribe:
            return "松开转文字"
        }
    }

    private func voiceTarget(title: String, activeText: String, icon: String, activeColor: Color, isActive: Bool) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill((isActive ? activeColor : Color.white).opacity(isActive ? 0.24 : 0.92))
                    .frame(width: isActive ? 92 : 76, height: isActive ? 92 : 76)

                Image(systemName: icon)
                    .font(.system(size: isActive ? 36 : 30, weight: .semibold))
                    .foregroundStyle(isActive ? activeColor : Color.black.opacity(0.65))
            }

            Text(isActive ? activeText : title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isActive ? activeColor : Color.black.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.18, dampingFraction: 0.82), value: isActive)
    }

    private func detectVoiceDropTarget(at location: CGPoint) -> VoiceDropTarget {
        let screen = UIScreen.main.bounds
        let bottomThreshold = screen.height * 0.63
        guard location.y >= bottomThreshold else { return .none }
        if location.x < screen.width * 0.4 {
            return .cancel
        }
        if location.x > screen.width * 0.6 {
            return .transcribe
        }
        return .none
    }

    private func handleVoiceRelease(target: VoiceDropTarget) {
        switch target {
        case .none:
            stopRecording(sendVoice: true, transcribe: false)
        case .cancel:
            cancelRecording()
        case .transcribe:
            let text = stopRecording(sendVoice: false, transcribe: true)
            if !text.isEmpty {
                inputText = text
                voiceButtonMode = false
                isInputFocused = true
            }
        }

        withAnimation(.easeOut(duration: 0.18)) {
            isVoicePressing = false
            showVoiceOverlay = false
            voiceDropTarget = .none
        }
        voiceRippleAnimating = false
    }

    // MARK: - Voice SDK placeholders
    private func startRecording() {
        // TODO: 接入语音 SDK 的开始录音逻辑
    }

    private func stopRecording(sendVoice: Bool, transcribe: Bool) -> String {
        // TODO: 接入语音 SDK 的停止录音逻辑
        // sendVoice = true: 发送语音消息
        // transcribe = true: 返回转写文本
        return transcribe ? "（语音转文字结果）" : ""
    }

    private func cancelRecording() {
        // TODO: 接入语音 SDK 的取消录音逻辑
    }

    @ViewBuilder
    private var suggestionIcon: some View {
        if let icon = UIImage(named: "message") ?? UIImage(named: "img/message") {
            Image(uiImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 21)
        } else {
            Circle()
                .fill(Color(hex: "FFCB74"))
                .frame(width: 18, height: 21)
        }
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dismissKeyboard()
            return
        }

        let newMessage = Message(id: UUID(), content: trimmed, isUser: true)
        messages.append(newMessage)

        let aiMessageID = UUID()
        messages.append(Message(id: aiMessageID, content: "", isUser: false))

        inputText = ""
        dismissKeyboard()

        Task {
            await startSSEStream(userText: trimmed, aiMessageID: aiMessageID)
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, source: ScrollTriggerSource) {
        DispatchQueue.main.async {
            let now = CACurrentMediaTime()
            let shouldAnimate: Bool
            switch source {
            case .streamingChunk:
                // SSE 高频更新时仅做低频动画，避免持续闪烁抖动。
                shouldAnimate = now - lastAutoScrollAnimationTime > 0.35
            case .newMessage, .keyboardFocus:
                shouldAnimate = true
            }

            if shouldAnimate {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
                lastAutoScrollAnimationTime = now
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            }
        }
    }

    private func dismissKeyboard() {
        isInputFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func makeSSERequest(userText: String) throws -> URLRequest {
        guard var components = URLComponents(string: SSEConfig.baseURL + SSEConfig.endpoint) else {
            throw URLError(.badURL)
        }

        components.queryItems = [
            URLQueryItem(name: "text", value: userText),
            URLQueryItem(name: "langCode", value: "0")
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(SSEConfig.token, forHTTPHeaderField: "Authorization")
        request.setValue(SSEConfig.token, forHTTPHeaderField: "token")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        return request
    }

    private func startSSEStream(userText: String, aiMessageID: UUID, attempt: Int = 0) async {
        var hasReceivedChunk = false
        do {
            let request = try makeSSERequest(userText: userText)
            print("SSE Request URL: \(request.url?.absoluteString ?? "-")")
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                await appendToAIMessage("请求失败：无效响应。", aiMessageID: aiMessageID)
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                let authHint = httpResponse.value(forHTTPHeaderField: "WWW-Authenticate") ?? "-"
                print("SSE URL: \(request.url?.absoluteString ?? "-")")
                print("SSE HTTP \(httpResponse.statusCode), Content-Type: \(contentType), WWW-Authenticate: \(authHint)")
                await appendToAIMessage("请求失败（HTTP \(httpResponse.statusCode)）。", aiMessageID: aiMessageID)
                return
            }

            for try await line in bytes.lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("data:") else { continue }

                let jsonString = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !jsonString.isEmpty, jsonString != "[DONE]" else { continue }

                guard let data = jsonString.data(using: .utf8) else { continue }
                let payload = try? JSONDecoder().decode(SSEPayload.self, from: data)
                let chunk = payload?.text ?? payload?.content ?? ""
                if !chunk.isEmpty {
                    hasReceivedChunk = true
                    await appendToAIMessage(chunk, aiMessageID: aiMessageID)
                }

                if let courseCard = extractCourseCard(from: payload) {
                    hasReceivedChunk = true
                    await appendCourseCardIfNeeded(courseCard, aiMessageID: aiMessageID)
                }
            }
        } catch {
            let nsError = error as NSError
            let code = nsError.code
            let domain = nsError.domain
            let failingURL = (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String) ?? "-"
            print("SSE Error domain=\(domain) code=\(code) desc=\(error.localizedDescription) url=\(failingURL)")

            if shouldRetry(error: nsError, attempt: attempt, hasReceivedChunk: hasReceivedChunk) {
                let nextAttempt = attempt + 1
                let delayInSeconds = UInt64(1 << attempt)
                print("SSE Retry \(nextAttempt)/\(SSEConfig.maxRetryCount) after \(delayInSeconds)s")
                try? await Task.sleep(nanoseconds: delayInSeconds * 1_000_000_000)
                await startSSEStream(userText: userText, aiMessageID: aiMessageID, attempt: nextAttempt)
                return
            }

            // 已经收到正文时再断连，通常是服务端主动收流，不再污染消息内容。
            if !hasReceivedChunk {
                await appendToAIMessage("\n[\(networkErrorHint(from: nsError))：\(error.localizedDescription)]", aiMessageID: aiMessageID)
            } else {
                debugLog("SSE ended after partial/full content: \(error.localizedDescription)")
            }
        }
    }

    private func shouldRetry(error: NSError, attempt: Int, hasReceivedChunk: Bool) -> Bool {
        guard attempt < SSEConfig.maxRetryCount else { return false }
        guard !hasReceivedChunk else { return false }
        guard error.domain == NSURLErrorDomain else { return false }
        switch error.code {
        case NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut, NSURLErrorNotConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private func networkErrorHint(from error: NSError) -> String {
        guard error.domain == NSURLErrorDomain else { return "连接中断" }
        switch error.code {
        case NSURLErrorNotConnectedToInternet:
            return "网络不可用(-1009)"
        case NSURLErrorNetworkConnectionLost:
            return "网络连接丢失(-1005)"
        case NSURLErrorTimedOut:
            return "请求超时(-1001)"
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return "无法连接服务器(-1003/-1004)"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot:
            return "HTTPS证书异常"
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return "ATS拦截(-1022)"
        default:
            return "连接中断(\(error.code))"
        }
    }

    @MainActor
    private func appendToAIMessage(_ chunk: String, aiMessageID: UUID) {
        guard let idx = messages.lastIndex(where: { $0.id == aiMessageID }) else { return }
        messages[idx].content += chunk
    }

    private func extractCourseCard(from payload: SSEPayload?) -> SSECourseCard? {
        guard let payload else { return nil }

        let topLevelThumbnail = payload.thumbnail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let topLevelTitle = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !topLevelThumbnail.isEmpty {
            return SSECourseCard(title: topLevelTitle.isEmpty ? "课程封面" : topLevelTitle, thumbnail: topLevelThumbnail)
        }

        if let data = payload.data ?? payload.result {
            let nestedThumbnail = data.thumbnail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let nestedTitle = data.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !nestedThumbnail.isEmpty {
                return SSECourseCard(title: nestedTitle.isEmpty ? "课程封面" : nestedTitle, thumbnail: nestedThumbnail)
            }

            if let firstVideoThumb = data.videoArray?.compactMap({ $0.thumbnail?.trimmingCharacters(in: .whitespacesAndNewlines) }).first,
               !firstVideoThumb.isEmpty {
                return SSECourseCard(title: nestedTitle.isEmpty ? "课程封面" : nestedTitle, thumbnail: firstVideoThumb)
            }
        }

        if let firstVideoThumb = payload.videoArray?.compactMap({ $0.thumbnail?.trimmingCharacters(in: .whitespacesAndNewlines) }).first,
           !firstVideoThumb.isEmpty {
            return SSECourseCard(title: topLevelTitle.isEmpty ? "课程封面" : topLevelTitle, thumbnail: firstVideoThumb)
        }

        return nil
    }

    @MainActor
    private func appendCourseCardIfNeeded(_ card: SSECourseCard, aiMessageID: UUID) {
        guard let idx = messages.lastIndex(where: { $0.id == aiMessageID }) else { return }
        let content = messages[idx].content
        guard !content.contains(card.thumbnail) else { return }

        let title = card.title.replacingOccurrences(of: "]", with: "")
        let imageMarkdown = "\n\n![\(title)](\(card.thumbnail))"
        messages[idx].content += imageMarkdown
        debugLog("Course card appended: \(card.thumbnail)")
    }

    private func buildAssistantParts(from content: String) -> [MessageContentPart] {
        if SSEConfig.debugImageParsing {
            print("Assistant raw message: \(content)")
        }

        let fullRange = NSRange(content.startIndex..<content.endIndex, in: content)
        var tokens: [MessageImageToken] = []

        if let markdownImageRegex = try? NSRegularExpression(pattern: #"\!\[([^\]]*)\]\(([^)]+)\)"#, options: []) {
            for match in markdownImageRegex.matches(in: content, options: [], range: fullRange) {
                guard let altRange = Range(match.range(at: 1), in: content),
                      let sourceRange = Range(match.range(at: 2), in: content) else { continue }
                let alt = String(content[altRange])
                let source = String(content[sourceRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !source.isEmpty else { continue }
                tokens.append(MessageImageToken(range: match.range(at: 0), image: MarkdownImage(alt: alt, source: source), priority: 0))
            }
        }

        if let htmlImageRegex = try? NSRegularExpression(pattern: #"<img[^>]*src=['"]([^'"]+)['"][^>]*>"#, options: [.caseInsensitive]) {
            for match in htmlImageRegex.matches(in: content, options: [], range: fullRange) {
                guard let sourceRange = Range(match.range(at: 1), in: content) else { continue }
                let source = String(content[sourceRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !source.isEmpty else { continue }
                tokens.append(MessageImageToken(range: match.range(at: 0), image: MarkdownImage(alt: "", source: source), priority: 1))
            }
        }

        if let markdownLinkRegex = try? NSRegularExpression(pattern: #"\[([^\]]*)\]\((https?:\/\/[^)]+)\)"#, options: []) {
            for match in markdownLinkRegex.matches(in: content, options: [], range: fullRange) {
                guard let titleRange = Range(match.range(at: 1), in: content),
                      let sourceRange = Range(match.range(at: 2), in: content) else { continue }
                let title = String(content[titleRange])
                let source = String(content[sourceRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !source.isEmpty else { continue }
                if looksLikeImageURL(source) {
                    tokens.append(MessageImageToken(range: match.range(at: 0), image: MarkdownImage(alt: title, source: source), priority: 2))
                }
            }
        }

        if let anyURLRegex = try? NSRegularExpression(pattern: #"https?:\/\/[^\s\)\]>"']+"#, options: [.caseInsensitive]) {
            for match in anyURLRegex.matches(in: content, options: [], range: fullRange) {
                guard let sourceRange = Range(match.range(at: 0), in: content) else { continue }
                let source = String(content[sourceRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !source.isEmpty else { continue }
                tokens.append(MessageImageToken(range: match.range(at: 0), image: MarkdownImage(alt: "", source: source), priority: 3))
            }
        }

        let selected = selectNonOverlappingTokens(tokens)
        if SSEConfig.debugImageParsing {
            let urls = selected.map(\.image.source)
            print("Assistant image tokens count: \(urls.count)")
            if !urls.isEmpty {
                print("Assistant image token urls: \(urls)")
            }
        }
        guard !selected.isEmpty else {
            let normalized = normalizeTextSegment(content)
            return normalized.isEmpty ? [] : [MessageContentPart(kind: .text(normalized))]
        }

        var parts: [MessageContentPart] = []
        var cursor = content.startIndex
        for token in selected {
            guard let tokenRange = Range(token.range, in: content) else { continue }
            if cursor < tokenRange.lowerBound {
                let text = normalizeTextSegment(String(content[cursor..<tokenRange.lowerBound]))
                if !text.isEmpty {
                    parts.append(MessageContentPart(kind: .text(text)))
                }
            }
            parts.append(MessageContentPart(kind: .image(token.image)))
            cursor = tokenRange.upperBound
        }

        if cursor < content.endIndex {
            let tailText = normalizeTextSegment(String(content[cursor..<content.endIndex]))
            if !tailText.isEmpty {
                parts.append(MessageContentPart(kind: .text(tailText)))
            }
        }

        return parts
    }

    private func selectNonOverlappingTokens(_ tokens: [MessageImageToken]) -> [MessageImageToken] {
        let sorted = tokens.sorted { lhs, rhs in
            if lhs.range.location != rhs.range.location {
                return lhs.range.location < rhs.range.location
            }
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.range.length > rhs.range.length
        }

        var result: [MessageImageToken] = []
        var lastEnd = -1
        for token in sorted {
            let tokenStart = token.range.location
            let tokenEnd = token.range.location + token.range.length
            if tokenStart >= lastEnd {
                result.append(token)
                lastEnd = tokenEnd
            }
        }
        return result
    }

    private func looksLikeImageURL(_ source: String) -> Bool {
        let lower = source.lowercased()
        return lower.contains(".png")
            || lower.contains(".jpg")
            || lower.contains(".jpeg")
            || lower.contains(".gif")
            || lower.contains(".webp")
            || lower.contains("/image")
            || lower.contains("/img")
            || lower.contains("photo")
            || lower.contains("picture")
    }

    private func normalizeTextSegment(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func debugLog(_ message: String) {
        guard SSEConfig.debugImageParsing else { return }
        print(message)
    }
}

private enum ChatTab {
    case chat
    case generated
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

#Preview {
    ContentView()
}
