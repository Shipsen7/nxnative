import XCTest
import Darwin
@testable import PortCore

final class LocalSafetyTests: XCTestCase {
    func testSymlinkAndSiblingPathBoundaries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("engine"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: root.appendingPathComponent("engine"))
        XCTAssertTrue(PathSafety.contains(root.appendingPathComponent("engine"), root.appendingPathComponent("linked/private")))
        XCTAssertFalse(PathSafety.contains(root.appendingPathComponent("engine"), root.appendingPathComponent("engine-other")))
    }

    func testGameKeysAndExportsCannotEnterSourceTree() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = root.appendingPathComponent("engine")
        let game = root.appendingPathComponent("game")
        try fm.createDirectory(at: repo.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try fm.createDirectory(at: game, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("# fixture".utf8).write(to: repo.appendingPathComponent("scripts/build_ipa_from_nsp.py"))
        try Data("fixture".utf8).write(to: game.appendingPathComponent("game.nsp"))
        let keys = root.appendingPathComponent("prod.keys")
        try Data("synthetic only".utf8).write(to: keys)
        var config = BuildConfiguration(repositoryURL: repo, gameDirectoryURL: game, keysURL: keys,
            outputURL: root.appendingPathComponent("export.app"), destination: .macOS)
        _ = try BuildCommand.make(configuration: config, pythonURL: ToolEnvironment.defaultPythonURL)
        config.outputURL = repo.appendingPathComponent("export.app")
        XCTAssertThrowsError(try BuildCommand.make(configuration: config, pythonURL: ToolEnvironment.defaultPythonURL))
        config.outputURL = root.appendingPathComponent("export.app")
        config.keysURL = repo.appendingPathComponent("private.keys")
        try Data("synthetic only".utf8).write(to: config.keysURL)
        XCTAssertThrowsError(try BuildCommand.make(configuration: config, pythonURL: ToolEnvironment.defaultPythonURL))
        config.keysURL = keys
        config.gameDirectoryURL = repo
        XCTAssertThrowsError(try BuildCommand.make(configuration: config, pythonURL: ToolEnvironment.defaultPythonURL))
    }

    func testCredentialEnvironmentIsNotInherited() {
        setenv("PORT_STUDIO_SYNTHETIC_SECRET", "fixture", 1)
        setenv("PYTHONPATH", "/synthetic/untrusted", 1)
        defer { unsetenv("PORT_STUDIO_SYNTHETIC_SECRET"); unsetenv("PYTHONPATH") }
        let env = ToolEnvironment.values
        XCTAssertNil(env["PORT_STUDIO_SYNTHETIC_SECRET"])
        XCTAssertNil(env["PYTHONPATH"])
        XCTAssertNil(env["SSH_AUTH_SOCK"])
        XCTAssertEqual(env["DOTNET_CLI_TELEMETRY_OPTOUT"], "1")
        XCTAssertFalse(env["TMPDIR", default: ""].isEmpty)
    }

    func testDisplayRedactionPreservesProgressAndPrivatePaths() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let syntheticValue = String(repeating: "01", count: 16)
        let line = "at " + home + "/game, /private/location/prod.keys owner@example.invalid 00000000-0000000000000000 header_key = " + syntheticValue
        let safe = LogRedactor.display(line, privatePaths: ["/private/location/prod.keys"])
        XCTAssertFalse(safe.contains(home)); XCTAssertFalse(safe.contains("owner@"))
        XCTAssertFalse(safe.contains("/private/location")); XCTAssertFalse(safe.contains(syntheticValue))
        XCTAssertTrue(safe.contains("<device ID>"))
        XCTAssertEqual(ProgressEvent.decode(line: #"{"ev":"progress","frac":0.25,"elapsed":2,"eta":8}"#)?.fraction, 0.25)
    }

    func testUnknownProgressClearsPreviousETAAndNewStageResetsCounts() {
        var state = BuildProgress()
        state.receive(ProgressEvent.decode(line: #"{"ev":"stage","k":1,"n":2,"name":"extract"}"#)!)
        state.receive(ProgressEvent.decode(line: #"{"ev":"progress","frac":0.25,"elapsed":2,"eta":8,"done":25,"total":100}"#)!)
        XCTAssertEqual(state.eta, 8)
        state.receive(ProgressEvent.decode(line: #"{"ev":"progress","frac":null,"eta":null,"done":null,"total":null}"#)!)
        XCTAssertNil(state.eta); XCTAssertNil(state.fraction); XCTAssertNil(state.done)
        state.receive(ProgressEvent.decode(line: #"{"ev":"stage_end","ok":true}"#)!)
        state.receive(ProgressEvent.decode(line: #"{"ev":"stage","k":2,"n":2,"name":"shaders","step":"scan"}"#)!)
        XCTAssertEqual(state.stages.first?.finished, true)
        XCTAssertEqual(state.step, "scan"); XCTAssertNil(state.total)
    }

    func testOutboundConnectionsBlockedWithoutContactingInternet() async throws {
        let script = "import socket,errno; s=socket.socket(); code=s.connect_ex(('127.0.0.1',9)); print(code); assert code in (errno.EPERM,errno.EACCES), code"
        let result = try await ProcessRunner().run(ProcessCommand(executableURL: ToolEnvironment.defaultPythonURL,
            arguments: ["-u", "-c", script]), timeout: 10)
        XCTAssertEqual(result.exitCode, 0, result.output)
    }

    func testProcessTimeoutStopsHungCheck() async throws {
        let runner = ProcessRunner()
        let start = ContinuousClock.now
        do {
            _ = try await runner.run(ProcessCommand(executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"]), timeout: 0.2)
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        XCTAssertLessThan(start.duration(to: .now), .seconds(3))
    }

    func testSyntheticPipelineDeliversStructuredStagesAndFailure() async throws {
        // No real game, keys, project generation or signing is involved.
        let program = #"import json,sys; print(json.dumps({'ev':'stage','k':1,'n':1,'name':'synthetic'}),flush=True); print(json.dumps({'ev':'stage_end','ok':False,'summary':'fixture failure'}),flush=True); sys.exit(7)"#
        let result = try await ProcessRunner().run(ProcessCommand(executableURL: ToolEnvironment.defaultPythonURL, arguments: ["-u", "-c", program]))
        let events = result.output.split(separator: "\n").compactMap { ProgressEvent.decode(line: String($0)) }
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(events.map(\.ev), ["stage", "stage_end"])
        XCTAssertEqual(events.last?.ok, false)
    }

    func testLocalToolchainGateMatchesIndependentLockCheckWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["PORT_STUDIO_TEST_REPOSITORY"] else {
            throw XCTSkip("Set PORT_STUDIO_TEST_REPOSITORY for the local toolchain check.")
        }
        let statuses = await EnvironmentInspector.inspect(repositoryURL: URL(fileURLWithPath: path), destination: .iOS)
        XCTAssertFalse(statuses.isEmpty)
        let repo = URL(fileURLWithPath: path)
        let independent = try await ProcessRunner().run(ProcessCommand(executableURL: ToolEnvironment.pythonURL(in: repo),
            arguments: ["-B", repo.appendingPathComponent("dm/gfx/tools/dmsh_chain.py").path, "--check-tools"], workingDirectoryURL: repo), timeout: 90)
        let chain = try XCTUnwrap(statuses.first { $0.id == "chain" })
        XCTAssertEqual(chain.isAvailable, independent.exitCode == 0)
        XCTAssertTrue(chain.isRequired, "A compiler mismatch must block the GUI build.")
        XCTAssertEqual(statuses.first { $0.id == "engine" }?.isAvailable, true)
        if !chain.isAvailable { XCTAssertNotNil(chain.remediation) }
    }
}
