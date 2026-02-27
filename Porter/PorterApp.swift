import SwiftUI

// ──────────────────────────────────────────────
// App
// ──────────────────────────────────────────────

@main
struct PorterApp: App {
    @ObservedObject private var store = PortStore.shared

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
// Model
// ──────────────────────────────────────────────

struct ActivePort: Identifiable {
    let id: UInt16
    let pid: Int32
    let command: String
    let projectName: String
    let projectPath: String
    let gitRootPath: String
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

    private init() {}

    func ensurePolling() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ports = Self.discoverPorts()
            DispatchQueue.main.async {
                self?.entries = ports
            }
        }
    }

    // MARK: - Actions

    func killProcess(pid: Int32) {
        kill(pid, SIGTERM)
    }

    func removeEntry(id: UInt16) {
        withAnimation(.easeInOut(duration: 0.3)) {
            entries.removeAll { $0.id == id }
        }
    }

    func killAll() {
        for entry in entries { kill(entry.pid, SIGTERM) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
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
        var portInfos: [(port: UInt16, pid: Int32, command: String)] = []

        for line in output.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 10 else { continue }
            guard let pid = Int32(cols[1]) else { continue }

            let lastCol = String(cols[cols.count - 1])
            guard lastCol == "(LISTEN)" else { continue }
            let namePart = String(cols[cols.count - 2])
            guard let colonIdx = namePart.lastIndex(of: ":"),
                  let port = UInt16(namePart[namePart.index(after: colonIdx)...]) else { continue }

            guard port >= 1024 else { continue }
            guard seen.insert(port).inserted else { continue }

            portInfos.append((port, pid, String(cols[0])))
        }

        let pids = Set(portInfos.map(\.pid))
        let cwds = resolveCWDs(pids: pids)
        let startTimes = resolveStartTimes(pids: pids)

        var gitRoots = [String: URL]()
        var branches = [String: String]()

        for (_, cwd) in cwds {
            guard gitRoots[cwd] == nil else { continue }
            if let root = findGitRoot(from: cwd) {
                gitRoots[cwd] = root
                let rootPath = root.path
                if branches[rootPath] == nil {
                    branches[rootPath] = resolveGitBranch(at: rootPath)
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
                    command: info.command,
                    projectName: gitRoot.lastPathComponent,
                    projectPath: cwd,
                    gitRootPath: rootPath,
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

    private static func resolveStartTimes(pids: Set<Int32>) -> [Int32: Date] {
        guard !pids.isEmpty else { return [:] }
        let pidList = pids.map(String.init).joined(separator: ",")
        guard let output = shell("/bin/ps -p \(pidList) -o pid=,lstart= 2>/dev/null") else { return [:] }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"

        var result = [Int32: Date]()
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
            let normalized = parts[1].split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            if let date = formatter.date(from: normalized) {
                result[pid] = date
            }
        }
        return result
    }

    private static func resolveGitBranch(at gitRoot: String) -> String {
        guard let output = shell("git -C '\(gitRoot)' rev-parse --abbrev-ref HEAD 2>/dev/null") else { return "" }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
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

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct PortListView: View {
    @ObservedObject private var store = PortStore.shared

    var body: some View {
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
        .frame(width: 340)
        .onAppear { store.ensurePolling() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Porter").font(.headline)
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
            Text("No projects running")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Start a dev server to see it here")
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
                    HoverButton("Open") { NSWorkspace.shared.open(entry.url) }
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
            Button("Open in Browser") { NSWorkspace.shared.open(entry.url) }
            Divider()
            Button("Kill Server", role: .destructive) { killWithAnimation() }
        }
    }

    private func killWithAnimation() {
        store.killProcess(pid: entry.pid)
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
    @State private var isHovered = false

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
                .background(
                    Capsule()
                        .fill(backgroundColor)
                )
                .foregroundStyle(foregroundColor)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var backgroundColor: Color {
        if role == .destructive {
            return isHovered ? .red.opacity(0.15) : .clear
        }
        return isHovered ? .primary.opacity(0.1) : .primary.opacity(0.05)
    }

    private var foregroundColor: Color {
        if role == .destructive {
            return isHovered ? .red : .secondary
        }
        return .primary
    }
}

// MARK: - Helpers

private func formatUptime(from start: Date) -> String {
    let s = Int(Date().timeIntervalSince(start))
    if s < 60 { return "<1m" }
    let m = s / 60
    if m < 60 { return "\(m)m" }
    let h = m / 60
    if h < 24 { return "\(h)h \(m % 60)m" }
    return "\(h / 24)d \(h % 24)h"
}
