import SwiftUI
import UIKit

private struct Message: Identifiable {
    let id: UUID
    var content: String
    let isUser: Bool
}

private enum SSEConfig {
    static let baseURL = "https://www.iconsolepro.com/oauth"
    static let endpoint = "/iConsoleProAIApi/AiTest"
    static let token = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJsb2dpblR5cGUiOiJsb2dpbiIsImxvZ2luSWQiOiIyMDEzNTM5NTAyNDgzNTgyOTc2Iiwicm5TdHIiOiJXUTh5ZUo1QjJrQnU2MmkxRG9kQVdEck1CUXp0MHZJcyJ9.jGsDDtp_leyTbQRJ3VnM-SsM1LVFUxgvksYFUIadz08"
    static let maxRetryCount = 2
    static let responseFormatHint = """
请使用中文回答，并遵守以下排版：
1) 段落之间空一行；
2) 列举建议时使用“• ”项目符号；
3) 语句简洁，先结论后细节。
"""
}

private struct SSEPayload: Decodable {
    let text: String?
    let content: String?
}

struct ContentView: View {
    private enum ScrollTriggerSource {
        case newMessage
        case streamingChunk
        case keyboardFocus
    }

    @State private var selectedTab: ChatTab = .chat
    @State private var inputText = ""
    @State private var avatarBreathing = false
    @State private var messages: [Message] = []
    @State private var lastAutoScrollAnimationTime: CFTimeInterval = 0
    @FocusState private var isInputFocused: Bool
    private let bottomAnchorID = "bottom"

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
                        Text(message.content)
                            .font(.system(size: 16, weight: .medium))
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
                            .frame(maxWidth: UIScreen.main.bounds.width * 0.9, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
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

    private func inputBar(onSend: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button {} label: {
                Image(systemName: "mic")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.black.opacity(0.95))
                    .frame(width: 74, height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.8))
                    )
            }
            .buttonStyle(.plain)

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

        if isVideoGenerationRequest(trimmed) {
            Task {
                await appendToAIMessage(videoGenerationFallbackMessage(), aiMessageID: aiMessageID)
            }
            return
        }

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

        let styledInput = "\(userText)\n\n\(SSEConfig.responseFormatHint)"

        components.queryItems = [
            URLQueryItem(name: "text", value: styledInput),
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
                guard !chunk.isEmpty else { continue }

                hasReceivedChunk = true
                await appendToAIMessage(chunk, aiMessageID: aiMessageID)
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

            await appendToAIMessage("\n[\(networkErrorHint(from: nsError))：\(error.localizedDescription)]", aiMessageID: aiMessageID)
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

    private func isVideoGenerationRequest(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let keywords = [
            "视频", "生成视频", "做视频", "制作视频", "剪辑视频", "短视频",
            "video", "generate video", "make video", "create video"
        ]
        return keywords.contains { normalized.contains($0) }
    }

    private func videoGenerationFallbackMessage() -> String {
        """
当前这个入口只支持文字问答，暂不支持直接生成视频。

你可以继续问我文案、脚本、分镜，我可以先帮你产出：
• 30秒口播文案
• 镜头分镜脚本
• 配音台词与字幕稿
"""
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
