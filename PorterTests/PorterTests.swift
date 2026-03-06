import Testing
import Foundation
@testable import Port_Menu

// MARK: - lsof Parser Tests

struct LsofParserTests {

    @Test func parsesStandardLsofOutput() {
        let output = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node      12345   user   22u  IPv4 0x1234567890      0t0  TCP *:3000 (LISTEN)
        node      12345   user   23u  IPv6 0x1234567891      0t0  TCP *:3000 (LISTEN)
        python3   23456   user   5u   IPv4 0x2345678901      0t0  TCP 127.0.0.1:8080 (LISTEN)
        java      34567   user   10u  IPv4 0x3456789012      0t0  TCP [::1]:5173 (LISTEN)
        """

        let parsed = LivePortScanner.parseLsofOutput(output)

        #expect(parsed.count == 3)
        #expect(parsed[0].port == 3000)
        #expect(parsed[0].pid == 12345)
        #expect(parsed[0].processName == "node")
        #expect(parsed[1].port == 5173)
        #expect(parsed[1].pid == 34567)
        #expect(parsed[1].processName == "java")
        #expect(parsed[2].port == 8080)
        #expect(parsed[2].pid == 23456)
        #expect(parsed[2].processName == "python3")
    }

    @Test func deduplicatesSamePort() {
        let output = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node      12345   user   22u  IPv4 0x1234567890      0t0  TCP *:3000 (LISTEN)
        node      12345   user   23u  IPv6 0x9876543210      0t0  TCP *:3000 (LISTEN)
        """

        let parsed = LivePortScanner.parseLsofOutput(output)
        #expect(parsed.count == 1)
        #expect(parsed[0].port == 3000)
    }

    @Test func skipsPrivilegedPorts() {
        let output = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        nginx     12345   root   6u   IPv4 0x1234567890      0t0  TCP *:80 (LISTEN)
        nginx     12345   root   7u   IPv4 0x1234567891      0t0  TCP *:443 (LISTEN)
        node      23456   user   22u  IPv4 0x2345678901      0t0  TCP *:3000 (LISTEN)
        """

        let parsed = LivePortScanner.parseLsofOutput(output)
        #expect(parsed.count == 1)
        #expect(parsed[0].port == 3000)
    }

    @Test func skipsEphemeralPorts() {
        let output = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        Cursor    13797   user   33u  IPv4 0x1234567890      0t0  TCP 127.0.0.1:52722 (LISTEN)
        Beeper    64785   user   69u  IPv4 0x2345678901      0t0  TCP 127.0.0.1:55829 (LISTEN)
        node      23456   user   22u  IPv4 0x3456789012      0t0  TCP *:3000 (LISTEN)
        """

        let parsed = LivePortScanner.parseLsofOutput(output)
        #expect(parsed.count == 1)
        #expect(parsed[0].port == 3000)
    }

    @Test func skipsNonListenLines() {
        let output = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node      12345   user   22u  IPv4 0x1234567890      0t0  TCP 127.0.0.1:3000->127.0.0.1:52341 (ESTABLISHED)
        node      23456   user   5u   IPv4 0x2345678901      0t0  TCP *:8080 (LISTEN)
        """

        let parsed = LivePortScanner.parseLsofOutput(output)
        #expect(parsed.count == 1)
        #expect(parsed[0].port == 8080)
    }

    @Test func handlesEmptyOutput() {
        let parsed = LivePortScanner.parseLsofOutput("")
        #expect(parsed.isEmpty)
    }

    @Test func handlesHeaderOnly() {
        let output = "COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME\n"
        let parsed = LivePortScanner.parseLsofOutput(output)
        #expect(parsed.isEmpty)
    }

    @Test func handlesIPv6Addresses() {
        let output = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node      12345   user   22u  IPv6 0x1234567890      0t0  TCP [::1]:4000 (LISTEN)
        node      23456   user   23u  IPv6 0x2345678901      0t0  TCP [::]:9090 (LISTEN)
        """

        let parsed = LivePortScanner.parseLsofOutput(output)
        #expect(parsed.count == 2)
        #expect(parsed[0].port == 4000)
        #expect(parsed[1].port == 9090)
    }

    @Test func handlesProcessNamesWithVariousLengths() {
        let output = """
        COMMAND          PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        com.docker.be  12345   user   22u  IPv4 0x1234567890      0t0  TCP *:3000 (LISTEN)
        a              23456   user   5u   IPv4 0x2345678901      0t0  TCP *:8080 (LISTEN)
        """

        let parsed = LivePortScanner.parseLsofOutput(output)
        #expect(parsed.count == 2)
    }

    @Test func handlesMalformedLines() {
        let output = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        this is garbage
        node      12345   user   22u  IPv4 0x1234567890      0t0  TCP *:3000 (LISTEN)
        
        node      badpid  user   22u  IPv4 0x1234567890      0t0  TCP *:4000 (LISTEN)
        """

        let parsed = LivePortScanner.parseLsofOutput(output)
        #expect(parsed.count == 1)
        #expect(parsed[0].port == 3000)
    }

    @Test func sortsPortsNumerically() {
        let output = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node      12345   user   22u  IPv4 0x1234567890      0t0  TCP *:8080 (LISTEN)
        node      23456   user   5u   IPv4 0x2345678901      0t0  TCP *:3000 (LISTEN)
        node      34567   user   8u   IPv4 0x3456789012      0t0  TCP *:5173 (LISTEN)
        """

        let parsed = LivePortScanner.parseLsofOutput(output)
        #expect(parsed.count == 3)
        #expect(parsed[0].port == 3000)
        #expect(parsed[1].port == 5173)
        #expect(parsed[2].port == 8080)
    }
}

// MARK: - Model Tests

struct ActivePortTests {

    @Test func urlConstruction() {
        let port = ActivePort(port: 3000, pid: 123, projectName: "test", branch: "main", startTime: nil)
        #expect(port.url.absoluteString == "http://localhost:3000")
    }

    @Test func compositeIdentity() {
        let a = ActivePort(port: 3000, pid: 100, projectName: "test", branch: "main", startTime: nil)
        let b = ActivePort(port: 3000, pid: 200, projectName: "test", branch: "main", startTime: nil)
        #expect(a.id != b.id)
    }

    @Test func equalityCheck() {
        let time = Date()
        let a = ActivePort(port: 3000, pid: 100, projectName: "test", branch: "main", startTime: time)
        let b = ActivePort(port: 3000, pid: 100, projectName: "test", branch: "main", startTime: time)
        #expect(a == b)
    }
}

// MARK: - FakeScanner Tests

struct FakeScannerTests {

    @Test func returnsConfiguredPorts() async {
        let ports = [
            ActivePort(port: 3000, pid: 1, projectName: "a", branch: "", startTime: nil),
            ActivePort(port: 8080, pid: 2, projectName: "b", branch: "", startTime: nil),
        ]
        let scanner = FakePortScanner(ports: ports, delay: 0)
        let result = await scanner.scan()
        if case .success(let found, let diag) = result {
            #expect(found.count == 2)
            #expect(diag.dataSource == "fake")
        } else {
            Issue.record("Expected success")
        }
    }

    @Test func simulatesFailure() async {
        let scanner = FakePortScanner(shouldFail: true)
        let result = await scanner.scan()
        if case .failure(let error, _) = result {
            #expect(error.localizedDescription.contains("Simulated"))
        } else {
            Issue.record("Expected failure")
        }
    }
}

// MARK: - Uptime Formatter Tests

struct UptimeFormatterTests {

    @Test func lessThanOneMinute() {
        let result = formatUptime(from: Date().addingTimeInterval(-30))
        #expect(result == "<1m")
    }

    @Test func minutes() {
        let result = formatUptime(from: Date().addingTimeInterval(-300))
        #expect(result == "5m")
    }

    @Test func hoursAndMinutes() {
        let result = formatUptime(from: Date().addingTimeInterval(-3660))
        #expect(result == "1h 1m")
    }

    @Test func daysAndHours() {
        let result = formatUptime(from: Date().addingTimeInterval(-90000))
        #expect(result == "1d 1h")
    }
}

// MARK: - Refresh Interval Tests

struct RefreshIntervalTests {

    @Test func defaultInterval() {
        #expect(RefreshInterval.defaultInterval == .normal)
        #expect(RefreshInterval.defaultInterval.rawValue == 5)
    }

    @Test func allCasesOrdered() {
        let values = RefreshInterval.allCases.map(\.rawValue)
        #expect(values == values.sorted())
    }
}

// MARK: - Git Root Detection Tests

struct GitRootTests {

    @Test func findsGitRootInCurrentDir() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let gitDir = tmpDir.appendingPathComponent(".git")
        try? FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let result = LivePortScanner.findGitRoot(from: tmpDir.path)
        #expect(result?.path == tmpDir.path)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @Test func findsGitRootInParentDir() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let childDir = tmpDir.appendingPathComponent("src/components")
        try? FileManager.default.createDirectory(at: childDir, withIntermediateDirectories: true)
        let gitDir = tmpDir.appendingPathComponent(".git")
        try? FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let result = LivePortScanner.findGitRoot(from: childDir.path)
        #expect(result?.path == tmpDir.path)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @Test func returnsNilWhenNoGitRoot() {
        let result = LivePortScanner.findGitRoot(from: "/tmp")
        #expect(result == nil)
    }
}

// MARK: - Display Name Tests

struct DisplayNameTests {

    @Test func prefersGitRootName() {
        let name = LivePortScanner.displayName(
            processName: "beam.smp",
            cwd: "/Users/me/work/backend",
            gitRoot: URL(filePath: "/Users/me/work/agidb-backend")
        )
        #expect(name == "agidb-backend")
    }

    @Test func fallsBackToMeaningfulCwdBasename() {
        let name = LivePortScanner.displayName(
            processName: "beam.smp",
            cwd: "/Users/me/work/agidb-backend",
            gitRoot: nil
        )
        #expect(name == "agidb-backend")
    }

    @Test func fallsBackToProcessNameForGenericDirectory() {
        let name = LivePortScanner.displayName(
            processName: "beam.smp",
            cwd: "/Users/me/work/agidb-backend/_build",
            gitRoot: nil
        )
        #expect(name == "beam.smp")
    }

    @Test func fallsBackToProcessNameWithoutCwd() {
        let name = LivePortScanner.displayName(
            processName: "beam.smp",
            cwd: nil,
            gitRoot: nil
        )
        #expect(name == "beam.smp")
    }
}

// MARK: - Fallback Filter Tests

struct FallbackFilterTests {

    @Test func keepsKnownDevRuntimeWithoutGitRoot() {
        #expect(LivePortScanner.shouldKeepFallbackProcess(
            processName: "beam.smp",
            cwd: "/Users/me/work/agidb-backend"
        ))
    }

    @Test func keepsVersionedPythonRuntime() {
        #expect(LivePortScanner.shouldKeepFallbackProcess(
            processName: "python3.12",
            cwd: "/Users/me/work/api"
        ))
    }

    @Test func rejectsDesktopAppWithoutGitRoot() {
        #expect(!LivePortScanner.shouldKeepFallbackProcess(
            processName: "Spotify",
            cwd: "/Applications/Spotify.app/Contents/MacOS"
        ))
    }

    @Test func rejectsFigmaWithoutGitRoot() {
        #expect(!LivePortScanner.shouldKeepFallbackProcess(
            processName: "Figma",
            cwd: "/Applications/Figma.app/Contents/MacOS"
        ))
    }
}

// MARK: - PortStore Tests

@Suite(.serialized) struct PortStoreTests {

    @Test @MainActor func storeInitializesEmpty() {
        let store = PortStore(scanner: FakePortScanner(ports: [], delay: 0))
        #expect(store.entries.isEmpty)
        #expect(store.lastError == nil)
        #expect(!store.isScanning)
    }

    @Test @MainActor func refreshPopulatesEntries() async throws {
        let ports = [
            ActivePort(port: 3000, pid: 1, projectName: "test", branch: "main", startTime: nil)
        ]
        let store = PortStore(scanner: FakePortScanner(ports: ports, delay: 0))

        store.refresh()
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(store.entries.count == 1)
        #expect(store.entries[0].port == 3000)
    }

    @Test @MainActor func refreshHandlesFailure() async throws {
        let store = PortStore(scanner: FakePortScanner(shouldFail: true))

        store.refresh()
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(store.lastError != nil)
    }

    @Test @MainActor func killProcessAddsToRecentlyKilled() async throws {
        let ports = [
            ActivePort(port: 3000, pid: 99999, projectName: "test", branch: "", startTime: nil)
        ]
        let store = PortStore(scanner: FakePortScanner(ports: ports, delay: 0))

        store.refresh()
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(store.entries.count == 1)

        store.killProcess(pid: 99999, port: 3000)
        store.refresh()
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(store.entries.isEmpty)
    }

    @Test @MainActor func diagnosticsSnapshot() {
        let store = PortStore(scanner: FakePortScanner(ports: [], delay: 0))
        let snapshot = store.diagnosticsSnapshot
        #expect(snapshot.contains("Port Menu Diagnostics"))
        #expect(snapshot.contains("Ports found: 0"))
    }
}

// MARK: - ScanDiagnostics Tests

struct ScanDiagnosticsTests {

    @Test func summaryFormat() {
        let diag = ScanDiagnostics(
            duration: 0.042,
            portsFound: 3,
            dataSource: "lsof",
            timestamp: Date()
        )
        let summary = diag.summary
        #expect(summary.contains("42"))
        #expect(summary.contains("3 ports"))
        #expect(summary.contains("lsof"))
    }
}
