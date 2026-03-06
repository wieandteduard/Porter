import ServiceManagement
import SwiftUI

// MARK: - Port List

struct PortListView: View {
    @Environment(PortStore.self) private var store
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                PortMainContentView()
            } else {
                OnboardingView()
            }
        }
        .frame(width: 340)
        .animation(.easeInOut(duration: 0.25), value: hasCompletedOnboarding)
    }
}

// MARK: - Main Content

struct PortMainContentView: View {
    @Environment(PortStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PortHeaderView()
            Divider()

            if let error = store.lastError, store.entries.isEmpty {
                PortErrorStateView(error: error)
            } else if store.entries.isEmpty && !store.isScanning {
                PortEmptyStateView()
            } else if store.entries.isEmpty && store.isScanning {
                PortScanningStateView()
            } else {
                PortEntryListView()
            }
        }
    }
}

// MARK: - Header

struct PortHeaderView: View {
    @Environment(PortStore.self) private var store
    @State private var menuHovered = false
    @State private var showMenu = false
    @State private var launchAtLoginError: String?

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLoginError = error.localizedDescription
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("Port Menu").font(.headline)
            Spacer()

            HStack(spacing: 2) {
                if !store.entries.isEmpty {
                    HeaderControlButton(
                        tooltip: nil,
                        destructive: true,
                        action: store.killAllProcesses
                    ) {
                        Text("Kill all")
                    }
                }

                HeaderControlButton(
                    tooltip: "Quit Port Menu",
                    action: { NSApplication.shared.terminate(nil) }
                ) {
                    Image(systemName: "power")
                }

                Button { showMenu.toggle() } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .frame(minHeight: 14)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.primary.opacity(menuHovered ? 0.08 : 0))
                        )
                        .foregroundStyle(.secondary)
                        .scaleEffect(menuHovered ? 1.04 : 1)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: menuHovered)
                }
                .buttonStyle(.plain)
                .onHover { menuHovered = $0 }
                .background(FloatingTooltipAnchor(text: "Settings", isVisible: menuHovered && !showMenu))
                .popover(isPresented: $showMenu, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Port Menu \(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Toggle("Launch at Login", isOn: launchAtLogin)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                    .padding(12)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .alert("Couldn't Update Launch at Login", isPresented: launchAtLoginErrorBinding) {
            Button("OK") { launchAtLoginError = nil }
        } message: {
            Text(launchAtLoginError ?? "Port Menu couldn't change its launch-at-login setting.")
        }
    }

    private var launchAtLoginErrorBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginError != nil },
            set: { newValue in
                if !newValue { launchAtLoginError = nil }
            }
        )
    }
}

struct HeaderControlButton<Label: View>: View {
    let tooltip: String?
    var destructive: Bool = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(HeaderButtonStyle(destructive: destructive, isHovered: isHovered))
        .background(FloatingTooltipAnchor(text: tooltip, isVisible: isHovered))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

struct HeaderButtonStyle: ButtonStyle {
    var destructive: Bool = false
    var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 4)
            .background(Capsule().fill(backgroundColor(configuration)))
            .foregroundStyle(foregroundColor)
            .scaleEffect(configuration.isPressed ? 0.92 : isHovered ? 1.04 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
    }

    private var horizontalPadding: CGFloat { destructive ? 10 : 7 }

    private func backgroundColor(_ c: ButtonStyleConfiguration) -> Color {
        if destructive {
            if c.isPressed { return .red.opacity(0.18) }
            return isHovered ? .red.opacity(0.12) : .clear
        }
        if c.isPressed { return .primary.opacity(0.14) }
        return isHovered ? .primary.opacity(0.08) : .clear
    }

    private var foregroundColor: Color {
        if destructive {
            return isHovered ? .red : .secondary
        }
        return .secondary
    }
}

// MARK: - Entry List

struct PortEntryListView: View {
    @Environment(PortStore.self) private var store

    var body: some View {
        ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
            PortRow(entry: entry, showTopDivider: index > 0)
        }
        .padding(.bottom, 6)
    }
}

// MARK: - Empty State

struct PortEmptyStateView: View {
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.fill")
                .font(.system(size: 24))
                .foregroundStyle(.quaternary)
                .rotationEffect(.degrees(rotation))
            Text("No dev servers detected")
                .font(.callout.bold())
                .foregroundStyle(.secondary)
            Text("Start a dev server to see it here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                withAnimation(.easeInOut(duration: 0.8)) {
                    rotation += 360
                }
            }
        }
    }
}

// MARK: - Scanning State

struct PortScanningStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Scanning ports…")
                .font(.callout.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Error State

struct PortErrorStateView: View {
    @Environment(PortStore.self) private var store
    let error: ScanError

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
            Text("Scan failed")
                .font(.callout.bold())
                .foregroundStyle(.secondary)
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Retry") { store.refresh() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Port Row

struct PortRow: View {
    let entry: ActivePort
    let showTopDivider: Bool
    @Environment(PortStore.self) private var store
    @State private var isHovered = false
    @State private var slidOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showTopDivider {
                Divider()
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
                        .truncationMode(.tail)

                    Spacer()

                    HStack(spacing: 2) {
                        HoverButton("Kill", role: .destructive) { killWithAnimation() }
                        HoverButton("Open") {
                            NSWorkspace.shared.open(entry.url)
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

                    Text(":\(String(entry.port))")
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
            Button("Copy URL") {
                PortStore.copyToClipboard(entry.url.absoluteString)
            }
            Button("Copy Port") {
                PortStore.copyToClipboard(String(entry.port))
            }
            Divider()
            Button("Open in Browser") {
                NSWorkspace.shared.open(entry.url)
            }
            Divider()
            Button("Kill Server", role: .destructive) { killWithAnimation() }
        }
    }

    private func killWithAnimation() {
        store.killProcess(pid: entry.pid, port: entry.port)
        withAnimation(.easeOut(duration: 0.3)) {
            slidOut = true
        }
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            store.removeEntry(port: entry.port)
        }
    }
}

// MARK: - Hover Button

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

// MARK: - Row Button Style

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

// MARK: - Floating Tooltip

@MainActor
final class FloatingTooltipPanel {
    static let shared = FloatingTooltipPanel()
    private var panel: NSPanel?
    func show(text: String, below anchorFrame: CGRect) {
        present(text: text, below: anchorFrame)
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.alphaValue = 0
    }

    private func present(text: String, below anchorFrame: CGRect) {
        let hosting = NSHostingView(rootView:
            Text(text)
                .font(.caption2)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.white.opacity(0.96))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.black.opacity(0.82))
                )
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        )
        hosting.frame.size = hosting.fittingSize
        let size = hosting.fittingSize

        if panel == nil {
            let p = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .popUpMenu
            p.hasShadow = false
            p.ignoresMouseEvents = true
            panel = p
        }

        panel?.contentView = hosting
        panel?.setContentSize(size)
        panel?.setFrameOrigin(NSPoint(
            x: anchorFrame.midX - size.width / 2,
            y: anchorFrame.minY - size.height - 4
        ))

        panel?.alphaValue = 1
        panel?.orderFront(nil)
    }
}

struct FloatingTooltipAnchor: NSViewRepresentable {
    let text: String?
    let isVisible: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isVisible, let text, !text.isEmpty, let window = nsView.window {
            let windowRect = nsView.convert(nsView.bounds, to: nil)
            let screenRect = window.convertToScreen(windowRect)
            FloatingTooltipPanel.shared.show(text: text, below: screenRect)
        } else {
            FloatingTooltipPanel.shared.hide()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        FloatingTooltipPanel.shared.hide()
    }
}

// MARK: - Helpers

func formatUptime(from start: Date) -> String {
    let s = Int(Date().timeIntervalSince(start))
    if s < 60 { return "<1m" }
    let m = s / 60
    if m < 60 { return "\(m)m" }
    let h = m / 60
    if h < 24 { return "\(h)h \(m % 60)m" }
    return "\(h / 24)d \(h % 24)h"
}
