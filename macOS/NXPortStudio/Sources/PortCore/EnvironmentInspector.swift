import Foundation

public struct DependencyStatus: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isAvailable: Bool
    public let detail: String
    public let remediation: String?
    public let isRequired: Bool
    public init(id: String, name: String, isAvailable: Bool, detail: String,
                remediation: String? = nil, isRequired: Bool = true) {
        self.id = id; self.name = name; self.isAvailable = isAvailable
        self.detail = detail; self.remediation = remediation; self.isRequired = isRequired
    }
}

public enum EnvironmentInspector {
    /// Local checks only. No restore, installation, compiler override or tool download.
    public static func inspect(repositoryURL repo: URL, destination: BuildDestination) async -> [DependencyStatus] {
        let fm = FileManager.default
        guard ["scripts/build_ipa_from_nsp.py", "scripts/build_dotnet_tools.py", "global.json",
               "dm/gfx/tools/dmsh_chain.py"].allSatisfy({ fm.isReadableFile(atPath: repo.appendingPathComponent($0).path) }) else {
            return [DependencyStatus(id: "engine", name: "Local source checkout", isAvailable: false,
                                     detail: "Select the hardened NXNativ checkout.", remediation: "The local build and verification scripts must be present.")]
        }
        let python = ToolEnvironment.pythonURL(in: repo)
        let global = try? Data(contentsOf: repo.appendingPathComponent("global.json"))
        let config = global.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let sdkVersion = (config?["sdk"] as? [String: Any])?["version"] as? String
        var checks: [(String, String, ProcessCommand, String, Bool)] = []
        func add(_ id: String, _ name: String, _ executable: URL, _ args: [String], _ repair: String, required: Bool = true) {
            checks.append((id, name, ProcessCommand(executableURL: executable, arguments: args, workingDirectoryURL: repo), repair, required))
        }
        add("network", "Offline build protection", URL(fileURLWithPath: "/usr/bin/printf"), ["Network policy active"],
            "macOS must allow the local network restriction. Builds stop if it cannot be applied.")
        add("engine", "Verified local .NET artifacts", python, ["-B", repo.appendingPathComponent("scripts/build_dotnet_tools.py").path, "--verify"],
            "Follow docs/dotnet-build.md to rebuild the local tools; the GUI never downloads or restores packages.")
        add("python", "Python 3.14 and pinned packages", python,
            ["-B", "-c", "import sys,importlib.metadata as m; assert sys.version_info[:2] == (3,14), 'Python 3.14 is required'; import lz4.block,capstone,fontTools,compression.zstd; expected={'lz4':'4.4.5','capstone':'5.0.6','fonttools':'4.60.1'}; assert all(m.version(k)==v for k,v in expected.items()), 'Use the pinned packages in docs/dotnet-build.md'; print('Python 3.14 and pinned packages ready')"],
            "Use the existing .tools/venv created by docs/dotnet-build.md.")
        if let dotnet = ToolEnvironment.executable(named: "dotnet"), let sdkVersion {
            // global.json chooses the exact SDK. A later SDK is not silently accepted.
            add("dotnet", ".NET SDK " + sdkVersion, dotnet, ["--version"], "Install the exact official SDK in global.json.")
        }
        add("xcode", "Xcode", URL(fileURLWithPath: "/usr/bin/xcodebuild"), ["-version"], "Install and open full Xcode.")
        add("chain", "Locked shader toolchain", python, ["-B", repo.appendingPathComponent("dm/gfx/tools/dmsh_chain.py").path, "--check-tools"],
            "The compiler fingerprints must match the reviewed shader chain. See docs/dotnet-build.md; no bypass is offered.")
        if destination == .iOS {
            add("xcodegen", "XcodeGen", ToolEnvironment.executable(named: "xcodegen") ?? URL(fileURLWithPath: "/nonexistent/xcodegen"),
                ["--version"], "Install XcodeGen as documented in docs/dotnet-build.md.")
            add("ios", "iOS SDK", URL(fileURLWithPath: "/usr/bin/xcrun"), ["--sdk", "iphoneos", "--show-sdk-version"],
                "Install the iOS platform in Xcode Settings > Components.")
        }
        add("nsz", "Compressed NSZ / XCZ support", python, ["-B", "-c", "import importlib.util,sys; found=importlib.util.find_spec('nsz') is not None; print('nsz available' if found else 'Optional nsz module is absent. NSP and XCI are available without it.'); sys.exit(0 if found else 1)"],
            "NSP and XCI do not need nsz. Compressed inputs need a separately reviewed nsz installation.", required: false)
        var result = await withTaskGroup(of: (Int, DependencyStatus).self) { group in
            for (index, item) in checks.enumerated() {
                group.addTask {
                    let (id, name, command, remediation, required) = item
                    let status: DependencyStatus
                    do {
                        let response = try await ProcessRunner().run(command, timeout: 90)
                        let versionMatches = id != "dotnet" || response.output.trimmingCharacters(in: .whitespacesAndNewlines) == sdkVersion
                        let ok = response.exitCode == 0 && versionMatches
                        status = DependencyStatus(id: id, name: name, isAvailable: ok,
                            detail: LogRedactor.display(String(response.output.suffix(1400))),
                            remediation: ok ? nil : remediation, isRequired: required)
                    } catch {
                        status = DependencyStatus(id: id, name: name, isAvailable: false,
                            detail: LogRedactor.display(error.localizedDescription), remediation: remediation, isRequired: required)
                    }
                    return (index, status)
                }
            }
            var results: [(Int, DependencyStatus)] = []
            for await item in group { results.append(item) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
        #if !arch(arm64)
        result.insert(DependencyStatus(id: "silicon", name: "Apple silicon", isAvailable: false, detail: "An ARM64 Mac is required."), at: 0)
        #endif
        if ToolEnvironment.executable(named: "dotnet") == nil || sdkVersion == nil {
            result.append(DependencyStatus(id: "dotnet", name: ".NET SDK", isAvailable: false, detail: "The pinned SDK could not be found.", remediation: "Follow docs/dotnet-build.md."))
        }
        return result
    }
}

public struct GameFolderSummary: Sendable {
    public let files: [URL]
    public let byteCount: Int64
    public static func inspect(_ folderURL: URL) throws -> Self {
        let files = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
            .filter { ["nsp", "xci", "nsz", "xcz"].contains($0.pathExtension.lowercased()) &&
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        let bytes = files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return Self(files: files.sorted { $0.lastPathComponent < $1.lastPathComponent }, byteCount: bytes)
    }
}
