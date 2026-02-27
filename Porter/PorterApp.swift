import SwiftUI
import Network

// ──────────────────────────────────────────────
// App entry point
// ──────────────────────────────────────────────

@main
struct PorterApp: App {
    var body: some Scene {
        MenuBarExtra("Porter", systemImage: "network") {
            PortListView()
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

    static func == (lhs: ActivePort, rhs: ActivePort) -> Bool {
        lhs.id == rhs.id && lhs.pid == rhs.pid &&
        lhs.projectName == rhs.projectName && lhs.branch == rhs.branch
    }
}

extension ActivePort: Equatable {}

// ──────────────────────────────────────────────
// ViewModel – singleton, polls via lsof
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
                guard let self else { return }
                if self.entries != ports {
                    self.entries = ports
                }
            }
        }
    }

    // MARK: - Actions

    func killProcess(pid: Int32) {
        kill(pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    func killAll() {
        for entry in entries { kill(entry.pid, SIGTERM) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    static func openInEditor(gitRoot: String) {
        let cursorURL = URL(fileURLWithPath: "/Applications/Cursor.app")
        guard FileManager.default.fileExists(atPath: cursorURL.path) else { return }
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: gitRoot)],
            withApplicationAt: cursorURL,
            configuration: config,
            completionHandler: nil
        )
    }

    static func copyURL(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    // MARK: - Port discovery via lsof

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
// Helpers
// ──────────────────────────────────────────────

func formatUptime(from start: Date?) -> String {
    guard let start else { return "" }
    let seconds = Int(Date().timeIntervalSince(start))
    if seconds < 60 { return "<1m" }
    let m = seconds / 60
    if m < 60 { return "\(m)m" }
    let h = m / 60
    if h < 24 { return "\(h)h \(m % 60)m" }
    return "\(h / 24)d \(h % 24)h"
}

// ──────────────────────────────────────────────
// Views
// ──────────────────────────────────────────────

struct PortListView: View {
    @ObservedObject private var store = PortStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if store.entries.isEmpty {
                emptyState
            } else {
                ForEach(store.entries) { entry in
                    PortRow(entry: entry, store: store)
                }
            }

            Divider()
            footer
        }
        .frame(width: 340)
        .onAppear { store.ensurePolling() }
    }

    private var header: some View {
        HStack {
            Text("Porter").font(.headline)
            Spacer()
            Button(action: store.refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "network.slash")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No active ports")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(store.entries.count) active")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if !store.entries.isEmpty {
                Button("Kill All") { store.killAll() }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
            }
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .controlSize(.small)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

struct PortRow: View {
    let entry: ActivePort
    let store: PortStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)

                Text(entry.projectName)
                    .font(.system(.body, weight: .medium))

                Spacer()

                Text(formatUptime(from: entry.startTime))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack {
                HStack(spacing: 4) {
                    if !entry.branch.isEmpty {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption2)
                        Text(entry.branch)
                            .font(.caption)
                            .lineLimit(1)
                        Text("·")
                            .font(.caption)
                    }
                    Text(":\(entry.id)")
                        .font(.system(.caption, design: .monospaced))
                    Text("·")
                        .font(.caption)
                    Text(entry.command)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 2) {
                    Button { PortStore.openInEditor(gitRoot: entry.gitRootPath) } label: {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                    }
                    .help("Open in Cursor")

                    Button { NSWorkspace.shared.open(entry.url) } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .help("Open in browser")

                    Button { store.killProcess(pid: entry.pid) } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .help("Kill process")
                }
                .buttonStyle(.borderless)
                .font(.callout)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy URL") { PortStore.copyURL(entry.url) }
            Button("Open in Browser") { NSWorkspace.shared.open(entry.url) }
            Button("Open in Cursor") { PortStore.openInEditor(gitRoot: entry.gitRootPath) }
            Divider()
            Button("Kill Process", role: .destructive) { store.killProcess(pid: entry.pid) }
        }
    }
}
