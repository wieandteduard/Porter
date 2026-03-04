import SwiftUI

// ──────────────────────────────────────────────
// App
// ──────────────────────────────────────────────

@main
struct PorterApp: App {
    @ObservedObject private var store = PortStore.shared

    init() {
        moveToApplicationsIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra {
            PortListView()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: store.entries.isEmpty
                      ? "square.fill"
                      : "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(store.entries.isEmpty ? .gray : .green)
                Text(String(format: "%2d", store.entries.count))
                    .fontDesign(.monospaced)
            }
            .onAppear { store.ensurePolling() }
        }
        .menuBarExtraStyle(.window)
    }
}

// ──────────────────────────────────────────────
// Onboarding
// ──────────────────────────────────────────────

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var contentReady = false
    @State private var sequenceStarted = false
    @State private var portVisible: [Bool] = Array(repeating: false, count: 8)
    @State private var portsGone = false
    @State private var titleVisible = false
    @State private var subtitleVisible = false
    @State private var buttonsVisible = false
    private static var hasAnimatedThisLaunch = false

    // Positions scaled to 340×270
    private let ports: [(label: String, x: CGFloat, y: CGFloat)] = [
        ("localhost:3000",  53,  44),
        ("localhost:5173", 266,  31),
        ("localhost:8080",  35, 135),
        ("localhost:4000", 257, 131),
        ("localhost:3001", 140,  78),
        ("localhost:9000",  71, 222),
        ("localhost:8000", 260, 211),
        ("localhost:5000", 163, 182),
    ]

    private let revealDelays: [Double] = [0.05, 0.25, 0.42, 0.56, 0.67, 0.75, 0.81, 0.86]

    var body: some View {
        ZStack {
            ForEach(ports.indices, id: \.self) { i in
                ScrambleText(target: ports[i].label, trigger: portVisible[i])
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(portsGone ? 0 : 0.22))
                    .blur(radius: portVisible[i] ? (portsGone ? 6 : 0) : 4)
                    .scaleEffect(portVisible[i] ? (portsGone ? 0.94 : 1) : 0.88)
                    .opacity(portVisible[i] ? (portsGone ? 0 : 1) : 0)
                    .position(x: ports[i].x, y: ports[i].y)
            }

            // Phase 2: main content
            VStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 0) {
                    Text("localhost,\norganized.")
                        .font(.system(size: 32, weight: .semibold))
                        .tracking(-0.5)
                        .lineSpacing(2)
                        .padding(.bottom, 14)
                        .modifier(RevealModifier(visible: titleVisible))

                    Text("A menu bar app that tracks your\ndev servers across projects.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .modifier(RevealModifier(visible: subtitleVisible))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)

                Spacer()

                HStack(spacing: 10) {
                    Button("Get Started") {
                        hasCompletedOnboarding = true
                    }
                    .buttonStyle(OnboardingButtonStyle())

                    Spacer()

                    Button("Follow on X") {
                        NSWorkspace.shared.open(URL(string: "https://x.com/eduardwieandt")!)
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
                .modifier(RevealModifier(visible: buttonsVisible))
            }
        }
        .frame(width: 340, height: 270)
        .clipped()
        .opacity(contentReady ? 1 : 0)
        .onAppear {
            if Self.hasAnimatedThisLaunch {
                contentReady = true
                titleVisible = true
                subtitleVisible = true
                buttonsVisible = true
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                contentReady = true
                guard !sequenceStarted else { return }
                sequenceStarted = true
                runSequence()
                Self.hasAnimatedThisLaunch = true
            }
        }
    }

    private func runSequence() {
        for i in ports.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + revealDelays[i]) {
                withAnimation(.easeOut(duration: 0.16)) {
                    portVisible[i] = true
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            withAnimation(.easeInOut(duration: 0.35)) {
                portsGone = true
            }
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(1.95)) {
            titleVisible = true
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(2.12)) {
            subtitleVisible = true
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(2.25)) {
            buttonsVisible = true
        }
    }
}

struct ScrambleText: View {
    let target: String
    let trigger: Bool
    @State private var displayed: String = ""
    @State private var scrambleTimer: Timer?

    private static let glyphs: [Character] = Array("0123456789abcdefABCDEF!@#$%&*?<>{}[]|~")

    var body: some View {
        Text(displayed.isEmpty ? target : displayed)
            .onChange(of: trigger) { active in
                if active { startScramble() }
            }
            .onDisappear {
                scrambleTimer?.invalidate()
                scrambleTimer = nil
            }
    }

    private func startScramble() {
        displayed = scrambled(progress: 0)
        var step = 0
        let steps = 14
        scrambleTimer?.invalidate()
        scrambleTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { t in
            step += 1
            if step >= steps {
                displayed = target
                t.invalidate()
                scrambleTimer = nil
            } else {
                displayed = scrambled(progress: Double(step) / Double(steps))
            }
        }
    }

    private func scrambled(progress: Double) -> String {
        let resolvedUpTo = Int(Double(target.count) * progress)
        return String(target.enumerated().map { (i, c) in
            if i < resolvedUpTo || c == ":" || c == "/" || c == "." { return c }
            return Self.glyphs.randomElement() ?? c
        })
    }
}

struct RevealModifier: ViewModifier {
    let visible: Bool

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .blur(radius: visible ? 0 : 6)
            .scaleEffect(visible ? 1 : 0.96, anchor: .bottom)
            .offset(y: visible ? 0 : 8)
    }
}

struct OnboardingButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(colorScheme == .dark ? .black : .white)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.7 : 1))
            )
    }
}

struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.primary.opacity(configuration.isPressed ? 0.4 : 0.6))
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.06 : 0.08))
            )
    }
}

// ──────────────────────────────────────────────
// Model
// ──────────────────────────────────────────────

struct ActivePort: Identifiable {
    let id: UInt16
    let pid: Int32
    let projectName: String
    let branch: String
    let startTime: Date?

    var url: URL { URL(string: "http://localhost:\(id)")! }
}

// ──────────────────────────────────────────────
// ViewModel
// ──────────────────────────────────────────────

final class PortStore: ObservableObject {
    static let shared = PortStore()

    @Published var entries: [ActivePort] = []

    private var timer: Timer?
    private var isRefreshing = false
    private var recentlyKilled = Set<UInt16>()
    private static var gitRootCache = [String: URL?]()
    private static var branchCache = [String: (branch: String, resolved: Date)]()

    private init() {}

    func ensurePolling() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ports = Self.discoverPorts()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                self.entries = ports.filter { !self.recentlyKilled.contains($0.id) }
            }
        }
    }

    // MARK: - Actions

    func killProcess(pid: Int32, port: UInt16) {
        kill(pid, SIGTERM)
        recentlyKilled.insert(port)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.recentlyKilled.remove(port)
        }
    }

    func removeEntry(id: UInt16) {
        withAnimation(.easeInOut(duration: 0.3)) {
            entries.removeAll { $0.id == id }
        }
    }

    static func copyURL(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    // MARK: - Port discovery

    private static func discoverPorts() -> [ActivePort] {
        guard let output = shell("/usr/sbin/lsof -iTCP -sTCP:LISTEN -n -P 2>/dev/null") else { return [] }

        var seen = Set<UInt16>()
        var portInfos: [(port: UInt16, pid: Int32)] = []

        for line in output.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 10 else { continue }
            guard let pid = Int32(cols[1]) else { continue }

            let lastCol = String(cols[cols.count - 1])
            guard lastCol == "(LISTEN)" else { continue }
            let namePart = String(cols[cols.count - 2])
            guard let colonIdx = namePart.lastIndex(of: ":"),
                  let port = UInt16(namePart[namePart.index(after: colonIdx)...]) else { continue }

            guard port >= 1024, port < 49152 else { continue }
            guard seen.insert(port).inserted else { continue }

            portInfos.append((port, pid))
        }

        let pids = Set(portInfos.map(\.pid))
        let cwds = resolveCWDs(pids: pids)
        let startTimes = resolveStartTimes(pids: pids)

        var gitRoots = [String: URL]()
        var branches = [String: String]()
        let now = Date()

        for (_, cwd) in cwds {
            guard gitRoots[cwd] == nil else { continue }
            guard !isProtectedPath(cwd) else { continue }

            let root: URL?
            if let cached = gitRootCache[cwd] {
                root = cached
            } else {
                root = findGitRoot(from: cwd)
                gitRootCache[cwd] = root
            }

            if let root {
                gitRoots[cwd] = root
                let rootPath = root.path
                if branches[rootPath] == nil {
                    if let cached = branchCache[rootPath],
                       now.timeIntervalSince(cached.resolved) < 30 {
                        branches[rootPath] = cached.branch
                    } else {
                        let branch = resolveGitBranch(at: rootPath)
                        branches[rootPath] = branch
                        branchCache[rootPath] = (branch, now)
                    }
                }
            }
        }

        return portInfos
            .sorted { $0.port < $1.port }
            .compactMap { info -> ActivePort? in
                guard let cwd = cwds[info.pid],
                      let gitRoot = gitRoots[cwd] else { return nil }
                let rootPath = gitRoot.path
                return ActivePort(
                    id: info.port,
                    pid: info.pid,
                    projectName: gitRoot.lastPathComponent,
                    branch: branches[rootPath] ?? "",
                    startTime: startTimes[info.pid]
                )
            }
    }

    // MARK: - Resolution helpers

    private static func resolveCWDs(pids: Set<Int32>) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let pidList = pids.map(String.init).joined(separator: ",")
        guard let output = shell("/usr/sbin/lsof -a -p \(pidList) -d cwd -Fn 2>/dev/null") else { return [:] }

        var result = [Int32: String]()
        var currentPID: Int32?

        for line in output.split(separator: "\n") {
            if line.hasPrefix("p"), let pid = Int32(line.dropFirst()) {
                currentPID = pid
            } else if line.hasPrefix("n/"), let pid = currentPID {
                result[pid] = String(line.dropFirst())
            }
        }
        return result
    }

    private static let startTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return f
    }()

    private static func resolveStartTimes(pids: Set<Int32>) -> [Int32: Date] {
        guard !pids.isEmpty else { return [:] }
        let pidList = pids.map(String.init).joined(separator: ",")
        guard let output = shell("LC_ALL=C /bin/ps -p \(pidList) -o pid=,lstart= 2>/dev/null") else { return [:] }

        var result = [Int32: Date]()
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
            let normalized = parts[1].split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            if let date = startTimeFormatter.date(from: normalized) {
                result[pid] = date
            }
        }
        return result
    }

    private static func resolveGitBranch(at gitRoot: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", gitRoot, "rev-parse", "--abbrev-ref", "HEAD"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }

        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if process.isRunning { process.terminate() }
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return "" }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func isProtectedPath(_ path: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let protected = ["Downloads", "Desktop", "Documents", "Pictures", "Movies", "Music"]
        return protected.contains { path.hasPrefix("\(home)/\($0)") }
    }

    private static func findGitRoot(from path: String) -> URL? {
        var current = URL(fileURLWithPath: path)
        let fm = FileManager.default
        while current.path != "/" {
            if fm.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    // MARK: - Shell helper (deadlock-safe)

    private static func shell(_ command: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }

        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if process.isRunning { process.terminate() }
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(data: data, encoding: .utf8)
    }
}

// ──────────────────────────────────────────────
// Views
// ──────────────────────────────────────────────

struct PortListView: View {
    @ObservedObject private var store = PortStore.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainContent
            } else {
                OnboardingView()
            }
        }
        .frame(width: 340)
        .animation(.easeInOut(duration: 0.25), value: hasCompletedOnboarding)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if store.entries.isEmpty {
                emptyState
            } else {
                ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
                    PortRow(entry: entry, store: store, showTopDivider: index > 0)
                }
                .padding(.bottom, 6)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Port Menu").font(.headline)
            Spacer()

            Button(action: store.refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .font(.caption)
                .controlSize(.small)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.fill")
                .font(.system(size: 24))
                .foregroundStyle(.quaternary)
            Text("No dev servers detected")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Start a dev server in a Git project")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

struct PortRow: View {
    let entry: ActivePort
    let store: PortStore
    let showTopDivider: Bool
    @State private var isHovered = false
    @State private var slidOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showTopDivider {
                Color(nsColor: .separatorColor)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                        .offset(y: -1)

                    Text(entry.projectName)
                        .font(.system(.body, weight: .medium))
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 2) {
                        HoverButton("Kill", role: .destructive) { killWithAnimation() }
                        HoverButton("Open") {
                            DispatchQueue.main.async { NSWorkspace.shared.open(entry.url) }
                        }
                    }
                    .opacity(isHovered ? 1 : 0)
                    .scaleEffect(isHovered ? 1 : 0.85, anchor: .trailing)
                    .offset(x: isHovered ? 0 : 6)
                }

                HStack(spacing: 6) {
                    if !entry.branch.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch")
                            Text(entry.branch)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text(":\(String(entry.id))")
                        .fontDesign(.monospaced)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    if let start = entry.startTime {
                        Text(formatUptime(from: start))
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .blur(radius: slidOut ? 8 : 0)
        .opacity(slidOut ? 0 : 1)
        .offset(x: slidOut ? 340 : 0)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Copy URL") { PortStore.copyURL(entry.url) }
            Button("Open in Browser") {
                DispatchQueue.main.async { NSWorkspace.shared.open(entry.url) }
            }
            Divider()
            Button("Kill Server", role: .destructive) { killWithAnimation() }
        }
    }

    private func killWithAnimation() {
        store.killProcess(pid: entry.pid, port: entry.id)
        withAnimation(.easeOut(duration: 0.3)) {
            slidOut = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            store.removeEntry(id: entry.id)
        }
    }
}


struct HoverButton: View {
    let label: String
    let role: ButtonRole?
    let action: () -> Void

    init(_ label: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.label = label
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
        .buttonStyle(RowButtonStyle(destructive: role == .destructive))
    }
}

struct RowButtonStyle: ButtonStyle {
    let destructive: Bool
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Capsule().fill(backgroundColor(configuration)))
            .foregroundStyle(foregroundColor(configuration))
            .scaleEffect(configuration.isPressed ? 0.92 : isHovered ? 1.04 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
            .onHover { isHovered = $0 }
    }

    private func backgroundColor(_ c: ButtonStyleConfiguration) -> Color {
        if destructive { return isHovered ? .red.opacity(0.15) : .clear }
        return isHovered ? .primary.opacity(0.1) : .primary.opacity(0.05)
    }

    private func foregroundColor(_ c: ButtonStyleConfiguration) -> Color {
        if destructive { return isHovered ? .red : .secondary }
        return .primary
    }
}

// MARK: - Helpers

private func moveToApplicationsIfNeeded() {
    let bundlePath = Bundle.main.bundlePath

    // Resolve App Translocation: macOS runs apps opened directly from Downloads
    // under a read-only temp path. Find the real file in common locations.
    var sourcePath = bundlePath
    if bundlePath.contains("AppTranslocation") {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let appName = URL(fileURLWithPath: bundlePath).lastPathComponent
        let candidates = ["\(home)/Downloads/\(appName)", "\(home)/Desktop/\(appName)"]
        if let real = candidates.first(where: { fm.fileExists(atPath: $0) }) {
            sourcePath = real
        }
    }

    guard !sourcePath.hasPrefix("/Applications/"),
          !sourcePath.contains("DerivedData"),
          !sourcePath.hasPrefix("/tmp/"),
          !sourcePath.contains("AppTranslocation") else { return }

    let destination = "/Applications/Port Menu.app"

    let alert = NSAlert()
    alert.messageText = "Move to Applications Folder?"
    alert.informativeText = "Port Menu works best when run from the Applications folder."
    alert.addButton(withTitle: "Move to Applications")
    alert.addButton(withTitle: "Don't Move")
    alert.alertStyle = .informational

    guard alert.runModal() == .alertFirstButtonReturn else { return }

    do {
        if FileManager.default.fileExists(atPath: destination) {
            try FileManager.default.removeItem(atPath: destination)
        }
        try FileManager.default.moveItem(atPath: sourcePath, toPath: destination)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [destination]
        try task.run()
        NSApp.terminate(nil)
    } catch {
        // If move fails, continue running from current location
    }
}

private func formatUptime(from start: Date) -> String {
    let s = Int(Date().timeIntervalSince(start))
    if s < 60 { return "<1m" }
    let m = s / 60
    if m < 60 { return "\(m)m" }
    let h = m / 60
    if h < 24 { return "\(h)h \(m % 60)m" }
    return "\(h / 24)d \(h % 24)h"
}
