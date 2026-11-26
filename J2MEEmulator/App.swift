import AVFAudio
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
struct J2MENSVApp: App {
    @StateObject private var library = GameLibrary()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: [.mixWithOthers]
        )
    }

    var body: some Scene {
        WindowGroup {
            LibraryView(library: library)
                .preferredColorScheme(.dark)
                .tint(NSVColor.accent)
                .onOpenURL { url in
                    Task {
                        await library.importFiles([url])
                    }
                }
        }
    }
}

private enum NSVColor {
    static let background = Color(red: 0.047, green: 0.070, blue: 0.102)
    static let surface = Color(red: 0.091, green: 0.123, blue: 0.162)
    static let border = Color(red: 0.177, green: 0.220, blue: 0.270)
    static let accent = Color(red: 0.420, green: 0.890, blue: 0.720)
}

private extension UTType {
    static var nsvJavaArchive: UTType {
        UTType(filenameExtension: "jar", conformingTo: .data)
            ?? UTType(importedAs: "com.sun.java-archive", conformingTo: .archive)
    }
}

private struct LibraryView: View {
    @ObservedObject var library: GameLibrary

    @State private var activeGame: Game?
    @State private var isMinimized = false
    @State private var isImportingFile = false
    @State private var isEnteringURL = false
    @State private var urlInput = ""
    @State private var pendingDelete: Game?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                if library.games.isEmpty {
                    emptyView
                } else {
                    gameList
                }
            }
            .background(NSVColor.background.ignoresSafeArea())

            if let game = activeGame {
                GamePresentation(
                    game: game,
                    url: library.jarURL(for: game),
                    onMinimize: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isMinimized = true
                        }
                    },
                    onExit: {
                        isMinimized = false
                        activeGame = nil
                    }
                )
                .id(game.id)
                .opacity(isMinimized ? 0 : 1)
                .allowsHitTesting(!isMinimized)
                .zIndex(isMinimized ? -1 : 10)

                if isMinimized {
                    FloatingBubbleView(
                        gameTitle: game.name,
                        onExpand: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isMinimized = false
                            }
                        },
                        onClose: {
                            isMinimized = false
                            activeGame = nil
                        }
                    )
                    .zIndex(20)
                }
            }
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [
                .nsvJavaArchive,
                UTType(importedAs: "com.sun.java-archive", conformingTo: .data),
                .archive,
                .data,
                .item,
            ],
            allowsMultipleSelection: true,
            onCompletion: importSelection
        )
        .onOpenURL { url in
            Task {
                await library.importFiles([url])
            }
        }
        .task {
            await library.scanDocumentsDirectory()
        }
        .refreshable {
            await library.scanDocumentsDirectory()
        }
        .alert(
            "Không thể thao tác",
            isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { presented in
                    if !presented {
                        library.errorMessage = nil
                    }
                }
            ),
            actions: {
                Button("Đóng", role: .cancel) {
                    library.errorMessage = nil
                }
            },
            message: {
                Text(library.errorMessage ?? "")
            }
        )
        .alert(
            "Nạp game từ đường dẫn URL",
            isPresented: $isEnteringURL,
            actions: {
                TextField("https://.../game.jar", text: $urlInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                Button("Tải về") {
                    let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let url = URL(string: trimmed),
                          let scheme = url.scheme?.lowercased(),
                          scheme == "http" || scheme == "https" else {
                        library.errorMessage = "Đường dẫn không hợp lệ. Vui lòng nhập link bắt đầu bằng http:// hoặc https://"
                        return
                    }
                    Task {
                        await library.downloadFromURL(url)
                    }
                }

                Button("Hủy", role: .cancel) {}
            },
            message: {
                Text("Dán liên kết trực tiếp (.jar) để nạp game vào J2ME NSV.")
            }
        )
        .confirmationDialog(
            "Xóa game khỏi thư viện?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { presented in
                    if !presented {
                        pendingDelete = nil
                    }
                }
            ),
            presenting: pendingDelete
        ) { game in
            Button("Xóa khỏi thư viện", role: .destructive) {
                if activeGame?.id == game.id {
                    isMinimized = false
                    activeGame = nil
                }
                library.remove(game)
                pendingDelete = nil
            }
            Button("Hủy", role: .cancel) {
                pendingDelete = nil
            }
        } message: { _ in
            Text("Dữ liệu lưu của game trong J2ME NSV cũng sẽ bị xóa.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("J2ME NSV")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                urlInput = ""
                isEnteringURL = true
            } label: {
                Image(systemName: "link.badge.plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(NSVColor.accent)
                    .background(NSVColor.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tải game từ link URL")

            Button {
                isImportingFile = true
            } label: {
                HStack(spacing: 6) {
                    if library.isImporting {
                        ProgressView()
                            .tint(NSVColor.background)
                    } else {
                        Image(systemName: "plus")
                    }
                    Text("Nạp JAR")
                        .lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .frame(height: 40)
                .foregroundStyle(NSVColor.background)
                .background(NSVColor.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(library.isImporting)
            .accessibilityLabel("Nạp tệp JAR vào thư viện")
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller.fill")
                .font(.largeTitle)
                .foregroundStyle(NSVColor.accent)
                .frame(width: 68, height: 68)
                .background(NSVColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)

            Text("Chưa có game nào")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Label("Bấm \"Nạp JAR\" để chọn tệp .jar từ ứng dụng Tệp", systemImage: "plus.circle.fill")
                Label("Bấm nút liên kết để tải game trực tiếp từ đường dẫn web", systemImage: "link.circle.fill")
                Label("Mở tệp .jar từ Safari / Zalo / Telegram chọn J2ME NSV", systemImage: "square.and.arrow.up.circle.fill")
                Label("Kết nối 3uTools hoặc Tệp sao chép .jar vào mục J2ME NSV", systemImage: "folder.circle.fill")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gameList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(library.games) { game in
                    GameRowCard(
                        game: game,
                        onPlay: {
                            isMinimized = false
                            activeGame = game
                        },
                        onDelete: {
                            pendingDelete = game
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func importSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                await library.importFiles(urls)
            }
        case .failure(let error):
            library.errorMessage = error.localizedDescription
        }
    }
}

private struct GameRowCard: View {
    let game: Game
    let onPlay: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "gamecontroller.fill")
                .foregroundStyle(NSVColor.accent)
                .font(.title3)
                .frame(width: 48, height: 48)
                .background(NSVColor.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(game.formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onPlay) {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill")
                        .font(.caption)
                    Text("Chạy")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(NSVColor.background)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(NSVColor.accent, in: Capsule())
                .shadow(color: NSVColor.accent.opacity(0.3), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chạy \(game.name)")
        }
        .padding(14)
        .background(NSVColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(NSVColor.border.opacity(0.8), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onPlay)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Xóa khỏi thư viện", systemImage: "trash")
            }
        }
    }
}

private struct FloatingBubbleView: View {
    let gameTitle: String
    let onExpand: () -> Void
    let onClose: () -> Void

    @State private var position = CGPoint(x: 48, y: 220)
    @GestureState private var dragOffset: CGSize = .zero
    @State private var pulse = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Button(action: onExpand) {
                    VStack(spacing: 2) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(NSVColor.accent)

                        Text(gameTitle)
                            .font(.system(size: 8, weight: .bold))
                            .lineLimit(1)
                            .foregroundStyle(.white)
                            .frame(maxWidth: 52)

                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 5, height: 5)
                            Text("Treo")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.green)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .background(
                        Circle()
                            .fill(NSVColor.surface)
                            .shadow(color: NSVColor.accent.opacity(pulse ? 0.45 : 0.25), radius: pulse ? 10 : 4, x: 0, y: 2)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(NSVColor.accent, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(.white, .red)
                        .background(
                            Circle()
                                .fill(Color.black)
                                .padding(2)
                        )
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
            .position(
                x: min(max(position.x + dragOffset.width, 36), max(36, geometry.size.width - 36)),
                y: min(max(position.y + dragOffset.height, 70), max(70, geometry.size.height - 70))
            )
            .gesture(
                DragGesture(minimumDistance: 10)
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        let rawX = position.x + value.translation.width
                        let rawY = position.y + value.translation.height
                        let snappedX: CGFloat = rawX < geometry.size.width * 0.5 ? 44 : max(44, geometry.size.width - 44)
                        let clampedY = min(max(rawY, 70), max(70, geometry.size.height - 70))
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            position = CGPoint(x: snappedX, y: clampedY)
                        }
                    }
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }
}

private struct GamePresentation: View {
    let game: Game
    let url: URL
    let onMinimize: () -> Void
    let onExit: () -> Void

    @State private var attemptID = UUID()

    var body: some View {
        GamePlayer(
            game: game,
            url: url,
            onMinimize: onMinimize,
            onExit: onExit,
            onRetry: {
                attemptID = UUID()
            }
        )
        .id(attemptID)
    }
}

private struct GamePlayer: View {
    let game: Game
    let onMinimize: () -> Void
    let onExit: () -> Void
    let onRetry: () -> Void

    @StateObject private var session: EmulatorSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var isExiting = false
    @State private var isSoftwareKeyboardVisible = false

    init(
        game: Game,
        url: URL,
        onMinimize: @escaping () -> Void,
        onExit: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) {
        self.game = game
        self.onMinimize = onMinimize
        self.onExit = onExit
        self.onRetry = onRetry
        _session = StateObject(wrappedValue: EmulatorSession(gameURL: url, gameID: game.id, onExit: onExit))
    }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let keyHeight: CGFloat = isLandscape
                ? max(32, min(42, (geometry.size.height - 96) / 6.2))
                : max(36, min(46, geometry.size.height * 0.052))

            let layout = isLandscape
                ? AnyLayout(HStackLayout(spacing: 5))
                : AnyLayout(VStackLayout(spacing: 5))

            VStack(spacing: 6) {
                playerHeader

                layout {
                    display

                    if !isSoftwareKeyboardVisible {
                        controls(keyHeight: keyHeight)
                            .frame(width: isLandscape ? geometry.size.width * 0.44 : nil)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .onChange(of: geometry.size) { _ in
                session.releaseAllKeys()
            }
        }
        .background(NSVColor.background.ignoresSafeArea())
        .onAppear {
            session.start()
        }
        .onDisappear {
            session.releaseAllKeys()
            session.stop()
            session.endBackgroundTask()
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                session.releaseAllKeys()
                session.beginBackgroundTask()
            case .active:
                session.endBackgroundTask()
            default:
                session.releaseAllKeys()
            }
        }
    }

    private var playerHeader: some View {
        HStack(spacing: 8) {
            Button {
                guard !isExiting else { return }
                isExiting = true
                session.stop {
                    onExit()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(NSVColor.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isExiting)
            .accessibilityLabel("Về thư viện")

            Text(game.name)
                .font(.headline)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button(action: onMinimize) {
                HStack(spacing: 5) {
                    Image(systemName: "circle.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NSVColor.accent)
                    Text("Bong bóng")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(NSVColor.surface, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(NSVColor.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Treo")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color.green.opacity(0.12), in: Capsule())
        }
    }

    private var display: some View {
        ZStack {
            PlayerSurface(
                session: session,
                onSoftwareKeyboardChange: { visible in
                    isSoftwareKeyboardVisible = visible
                }
            )
            .opacity(session.isDisplayVisible ? 1 : 0)
            .allowsHitTesting(session.isDisplayVisible)
            .accessibilityHidden(!session.isDisplayVisible)

            if let errorMessage = session.errorMessage {
                VStack(spacing: 12) {
                    Text("Không mở được game")
                        .font(.headline)

                    ScrollView(.vertical, showsIndicators: true) {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxHeight: 160)

                    Button("Thử lại", action: onRetry)
                        .buttonStyle(.bordered)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else if !session.isDisplayVisible {
                ProgressView(isExiting ? "Đang lưu game…" : "Đang mở game…")
                    .tint(NSVColor.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(NSVColor.border, lineWidth: 1)
        )
    }

    private func controls(keyHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                key("LSK (Menu)", symbol: nil, code: "F1", height: keyHeight, emphasis: true, accessibilityLabel: "LSK (Menu)")
                key("1 (HP)", symbol: nil, code: "Digit1", height: keyHeight, emphasis: false, accessibilityLabel: "1 (HP)")
                key("2 (MP)", symbol: nil, code: "Digit2", height: keyHeight, emphasis: false, accessibilityLabel: "2 (MP)")
                key("RSK (Back)", symbol: nil, code: "F2", height: keyHeight, emphasis: true, accessibilityLabel: "RSK (Back)")
            }

            HStack(spacing: 8) {
                dpadView(keyHeight: keyHeight)
                    .frame(maxWidth: .infinity)

                numpadView(keyHeight: keyHeight)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dpadView(keyHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                space(height: keyHeight)
                direction("Lên", symbol: "chevron.up", code: "ArrowUp", height: keyHeight)
                space(height: keyHeight)
            }
            HStack(spacing: 6) {
                direction("Trái", symbol: "chevron.left", code: "ArrowLeft", height: keyHeight)
                key("OK", symbol: nil, code: "Enter", height: keyHeight, emphasis: true, accessibilityLabel: "OK")
                direction("Phải", symbol: "chevron.right", code: "ArrowRight", height: keyHeight)
            }
            HStack(spacing: 6) {
                space(height: keyHeight)
                direction("Xuống", symbol: "chevron.down", code: "ArrowDown", height: keyHeight)
                space(height: keyHeight)
            }
        }
    }

    private func numpadView(keyHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                key("1", symbol: nil, code: "Digit1", height: keyHeight, emphasis: false, accessibilityLabel: "1")
                key("2", symbol: nil, code: "Digit2", height: keyHeight, emphasis: false, accessibilityLabel: "2")
                key("3", symbol: nil, code: "Digit3", height: keyHeight, emphasis: false, accessibilityLabel: "3")
            }
            HStack(spacing: 6) {
                key("4", symbol: nil, code: "Digit4", height: keyHeight, emphasis: false, accessibilityLabel: "4")
                key("5", symbol: nil, code: "Digit5", height: keyHeight, emphasis: false, accessibilityLabel: "5")
                key("6", symbol: nil, code: "Digit6", height: keyHeight, emphasis: false, accessibilityLabel: "6")
            }
            HStack(spacing: 6) {
                key("7", symbol: nil, code: "Digit7", height: keyHeight, emphasis: false, accessibilityLabel: "7")
                key("8", symbol: nil, code: "Digit8", height: keyHeight, emphasis: false, accessibilityLabel: "8")
                key("9", symbol: nil, code: "Digit9", height: keyHeight, emphasis: false, accessibilityLabel: "9")
            }
            HStack(spacing: 6) {
                key("*", symbol: nil, code: "KeyE", height: keyHeight, emphasis: false, accessibilityLabel: "Sao")
                key("0", symbol: nil, code: "Digit0", height: keyHeight, emphasis: false, accessibilityLabel: "0")
                key("#", symbol: nil, code: "KeyR", height: keyHeight, emphasis: false, accessibilityLabel: "Thăng")
            }
        }
    }

    private func direction(_ title: String, symbol: String, code: String, height: CGFloat) -> some View {
        key("", symbol: symbol, code: code, height: height, emphasis: false, accessibilityLabel: title)
    }

    private func key(
        _ title: String,
        symbol: String?,
        code: String,
        height: CGFloat,
        emphasis: Bool,
        accessibilityLabel: String
    ) -> some View {
        GameKeyButton(
            title: title,
            symbol: symbol,
            accessibilityLabel: accessibilityLabel,
            emphasized: emphasis,
            enabled: session.isReady && !isExiting,
            pressed: session.pressedCodes.contains(code),
            onPressChange: { pressed in
                session.setKey(code, pressed: pressed, source: "touch-\(code)")
            }
        )
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }

    private func space(height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

private struct GameKeyButton: UIViewRepresentable {
    let title: String
    let symbol: String?
    let accessibilityLabel: String
    let emphasized: Bool
    let enabled: Bool
    let pressed: Bool
    let onPressChange: (Bool) -> Void

    func makeUIView(context: Context) -> GameKeyControl {
        let control = GameKeyControl(frame: .zero)
        control.accessibilityLabel = accessibilityLabel
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        if let symbol {
            let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            control.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        } else {
            control.setTitle(title, for: .normal)
        }
        control.onPressChange = onPressChange
        control.isEnabled = enabled
        control.refreshAppearance(emphasized: emphasized, pressed: pressed)
        return control
    }

    func updateUIView(_ uiView: GameKeyControl, context: Context) {
        uiView.onPressChange = onPressChange
        uiView.isEnabled = enabled
        uiView.refreshAppearance(emphasized: emphasized, pressed: pressed)
    }
}

@MainActor
private final class GameKeyControl: UIButton {
    var onPressChange: ((Bool) -> Void)?
    private var isHolding = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 9
        layer.borderWidth = 1
        addTarget(self, action: #selector(handlePress), for: .touchDown)
        addTarget(
            self,
            action: #selector(handleRelease),
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshAppearance(emphasized: Bool, pressed: Bool) {
        let bgColor: UIColor
        let borderColor: UIColor
        let fgColor: UIColor

        if pressed {
            bgColor = UIColor(NSVColor.accent)
            borderColor = UIColor(NSVColor.accent)
            fgColor = UIColor(NSVColor.background)
        } else if emphasized {
            bgColor = UIColor(NSVColor.accent.opacity(0.18))
            borderColor = UIColor(NSVColor.accent.opacity(0.75))
            fgColor = UIColor(NSVColor.accent)
        } else {
            bgColor = UIColor(NSVColor.surface)
            borderColor = UIColor(NSVColor.border)
            fgColor = .white
        }

        backgroundColor = bgColor
        layer.borderColor = borderColor.cgColor
        tintColor = fgColor
        setTitleColor(fgColor, for: .normal)
        setTitleColor(fgColor, for: .highlighted)
        alpha = isEnabled ? 1.0 : 0.55

        if !isEnabled && isHolding {
            handleRelease()
        }
    }

    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onPressChange?(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.onPressChange?(false)
        }
        return true
    }

    @objc private func handlePress() {
        guard isEnabled, !isHolding else { return }
        isHolding = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onPressChange?(true)
    }

    @objc private func handleRelease() {
        guard isHolding else { return }
        isHolding = false
        onPressChange?(false)
    }
}

private struct PlayerSurface: UIViewControllerRepresentable {
    let session: EmulatorSession
    let onSoftwareKeyboardChange: (Bool) -> Void

    func makeUIViewController(context: Context) -> PlayerController {
        PlayerController(session: session, onSoftwareKeyboardChange: onSoftwareKeyboardChange)
    }

    func updateUIViewController(_ uiViewController: PlayerController, context: Context) {
        uiViewController.onSoftwareKeyboardChange = onSoftwareKeyboardChange
    }
}

@MainActor
private final class PlayerController: UIViewController {
    private let session: EmulatorSession
    var onSoftwareKeyboardChange: (Bool) -> Void
    private var activeHardwareKeys: [Int: String] = [:]
    private var isSoftwareKeyboardVisible = false

    init(session: EmulatorSession, onSoftwareKeyboardChange: @escaping (Bool) -> Void) {
        self.session = session
        self.onSoftwareKeyboardChange = onSoftwareKeyboardChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func loadView() {
        let container = UIView()
        container.backgroundColor = .black
        let webView = session.webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameWillChange(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard !session.isTextEditing else {
            super.pressesBegan(presses, with: event)
            return
        }

        var unhandled: Set<UIPress> = []
        for press in presses {
            guard session.isReady,
                  let key = press.key,
                  let mapped = code(for: key) else {
                unhandled.insert(press)
                continue
            }

            let rawCode = key.keyCode.rawValue
            activeHardwareKeys[rawCode] = mapped
            session.setKey(mapped, pressed: true, source: "keyboard-\(rawCode)")
        }

        if !unhandled.isEmpty {
            super.pressesBegan(unhandled, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = releasePresses(presses)
        if !unhandled.isEmpty {
            super.pressesEnded(unhandled, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = releasePresses(presses)
        if !unhandled.isEmpty {
            super.pressesCancelled(unhandled, with: event)
        }
    }

    private func releasePresses(_ presses: Set<UIPress>) -> Set<UIPress> {
        presses.filter { press in
            guard let key = press.key else { return true }
            let rawCode = key.keyCode.rawValue
            guard let mapped = activeHardwareKeys.removeValue(forKey: rawCode) else {
                return true
            }
            session.setKey(mapped, pressed: false, source: "keyboard-\(rawCode)")
            return false
        }
    }

    private func code(for key: UIKey) -> String? {
        if key.modifierFlags.contains(.command) || key.modifierFlags.contains(.control) || key.modifierFlags.contains(.alternate) {
            return nil
        }

        if key.characters == "*" { return "KeyE" }
        if key.characters == "#" { return "KeyR" }

        let raw = key.keyCode.rawValue
        // Main row digits 1..9 (0x1e...0x26)
        if raw >= 0x1e && raw <= 0x26 {
            return "Digit\(raw - 0x1d)"
        }
        // Main row 0 (0x27)
        if raw == 0x27 {
            return "Digit0"
        }
        // Numpad 1..9 (0x59...0x61)
        if raw >= 0x59 && raw <= 0x61 {
            return "Digit\(raw - 0x58)"
        }
        // Numpad 0 (0x62)
        if raw == 0x62 {
            return "Digit0"
        }

        switch key.keyCode {
        case .keyboardReturnOrEnter, .keypadEnter, .keyboardSpacebar:
            return "Enter"
        case .keyboardUpArrow:
            return "ArrowUp"
        case .keyboardDownArrow:
            return "ArrowDown"
        case .keyboardLeftArrow:
            return "ArrowLeft"
        case .keyboardRightArrow:
            return "ArrowRight"
        case .keyboardF1, .keyboardQ:
            return "F1"
        case .keyboardF2, .keyboardE, .keyboardEscape:
            return "F2"
        default:
            return nil
        }
    }

    @objc private func keyboardFrameWillChange(_ notification: Notification) {
        guard let window = viewIfLoaded?.window else { return }

        if notification.name == UIResponder.keyboardWillHideNotification {
            updateSoftwareKeyboardVisibility(false)
            return
        }

        guard let userInfo = notification.userInfo,
              let endFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            return
        }

        let windowFrame = window.convert(window.bounds, to: window.screen.coordinateSpace)
        let overlap = windowFrame.intersection(endFrame)
        let visible = !overlap.isEmpty && overlap.height > 1
        updateSoftwareKeyboardVisibility(visible)
    }

    private func updateSoftwareKeyboardVisibility(_ visible: Bool) {
        guard isSoftwareKeyboardVisible != visible else { return }
        isSoftwareKeyboardVisible = visible
        if visible {
            session.releaseAllKeys()
        }
        onSoftwareKeyboardChange(visible)
    }
}
