import AppKit
import Observation
import PortCore

enum StudioPage: String, CaseIterable, Identifiable {
    case create = "New port", environment = "Build tools", guide = "Xcode guide", activity = "Activity"
    var id: Self { self }
    var icon: String {
        switch self { case .create: "shippingbox"; case .environment: "checklist"; case .guide: "ipad.and.iphone"; case .activity: "text.alignleft" }
    }
}

@MainActor @Observable
final class StudioModel {
    var page: StudioPage = .create
    var repositoryPath = ""
    var gamePath = ""
    var keysPath = ""
    var outputFolder = ""
    var appName = ""
    var destination: BuildDestination = .iOS
    var prepareXcode = true
    var language = ""
    var showFPS = false
    var dependencies: [DependencyStatus] = []
    var isChecking = false
    var isBusy = false
    var status = "Choose your local engine"
    var failure: String?
    var logs: [String] = []
    var buildProgress = BuildProgress()
    var completedURL: URL?
    var workspaceURL: URL?
    var gameFiles: [URL] = []
    var inputBytes: Int64 = 0
    @ObservationIgnored let runner = ProcessRunner()
    @ObservationIgnored var currentTask: Task<Void, Never>?
    @ObservationIgnored var checkTask: Task<Void, Never>?

    var repositoryURL: URL { URL(fileURLWithPath: repositoryPath) }
    var outputName: String {
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = (name.isEmpty ? URL(fileURLWithPath: gamePath).lastPathComponent : name)
            .components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)).joined(separator: "-")
        return (safe.isEmpty ? "My Port" : safe) + (destination == .macOS ? ".app" : ".ipa")
    }
    var outputURL: URL { URL(fileURLWithPath: outputFolder).appendingPathComponent(outputName) }
    var requiresNSZ: Bool { gameFiles.contains { ["nsz", "xcz"].contains($0.pathExtension.lowercased()) } }
    var missingRequirements: [DependencyStatus] {
        dependencies.filter { ($0.isRequired || ($0.id == "nsz" && requiresNSZ)) && !$0.isAvailable }
    }
    var canBuild: Bool {
        !isBusy && !isChecking && !dependencies.isEmpty && missingRequirements.isEmpty &&
        !gameFiles.isEmpty && !keysPath.isEmpty && !repositoryPath.isEmpty
    }
    var privatePaths: [String] { [keysPath, gamePath, repositoryPath, outputFolder] }

    func initialize() {
        // An explicit local launch option is useful for development; no path is saved.
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--repository"), args.indices.contains(index + 1) {
            repositoryPath = args[index + 1]
            status = "Check the local build tools"
        }
    }

    func selectFolder(title: String, current: String = "") -> URL? {
        let panel = NSOpenPanel()
        panel.title = title; panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = false
        if !current.isEmpty { panel.directoryURL = URL(fileURLWithPath: current) }
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseRepository() {
        guard let url = selectFolder(title: "Choose your trusted NXNativ checkout", current: repositoryPath) else { return }
        repositoryPath = url.path; dependencies = []; completedURL = nil; workspaceURL = nil
        status = "Check the local build tools"; failure = nil
    }
    func chooseGame() {
        if let url = selectFolder(title: "Choose one game's folder", current: gamePath) { setGame(url) }
    }
    func setGame(_ url: URL) {
        guard !isBusy && !isChecking else { return }
        do {
            let summary = try GameFolderSummary.inspect(url)
            gamePath = url.path; gameFiles = summary.files; inputBytes = summary.byteCount
            appName = ""; outputFolder = url.path
            completedURL = nil; workspaceURL = nil
            failure = gameFiles.isEmpty ? "This folder has no NSP, XCI, NSZ or XCZ files." : nil
        } catch { failure = "Could not read the selected game folder." }
    }
    func chooseKeys() {
        let panel = NSOpenPanel(); panel.title = "Choose your existing prod.keys file"
        panel.canChooseDirectories = false; panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        keysPath = url.path
    }
    func chooseOutput() {
        if let url = selectFolder(title: "Choose an export folder outside the engine checkout", current: outputFolder) {
            outputFolder = url.path; completedURL = nil
        }
    }
    func checkEnvironment() {
        guard !isChecking && !isBusy && !repositoryPath.isEmpty else { return }
        isChecking = true; dependencies = []; failure = nil; status = "Checking local tools"
        let repo = repositoryURL, target = destination
        checkTask = Task {
            dependencies = await EnvironmentInspector.inspect(repositoryURL: repo, destination: target)
            isChecking = false; checkTask = nil
            status = missingRequirements.isEmpty ? "Ready to prepare a port" : "Build tools need attention"
        }
    }
    func targetChanged() {
        dependencies = []; completedURL = nil; workspaceURL = nil
        if destination == .iOS { prepareXcode = true }
        status = "Check tools for the selected destination"
    }
    func appendLog(_ line: String) {
        logs.append(LogRedactor.display(line, privatePaths: privatePaths))
        if logs.count > 1200 { logs.removeFirst(logs.count - 1200) }
    }
    func receive(_ line: String) {
        guard let event = ProgressEvent.decode(line: line) else { appendLog(line); return }
        buildProgress.receive(event)
        if let message = event.message { appendLog(message) }
        if event.ev == "stage_end" {
            appendLog((event.ok == false ? "Failed: " : "Completed: ") + (buildProgress.stages.last?.name ?? "stage"))
        }
    }
    func build() {
        guard canBuild else { return }
        let config = BuildConfiguration(repositoryURL: repositoryURL, gameDirectoryURL: URL(fileURLWithPath: gamePath),
            keysURL: URL(fileURLWithPath: keysPath), outputURL: outputURL, destination: destination,
            appName: appName, language: language, showFPS: showFPS, prepareXcode: destination == .iOS && prepareXcode)
        isBusy = true; failure = nil; completedURL = nil; workspaceURL = nil
        logs = []; buildProgress = BuildProgress(); status = "Preparing port"
        let python = ToolEnvironment.pythonURL(in: config.repositoryURL)
        currentTask = Task {
            let (lines, continuation) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(2048))
            let consumer = Task { for await line in lines { receive(line) } }
            do {
                // Recheck the same artifacts and compiler locks immediately before opening games/keys.
                let checks = await EnvironmentInspector.inspect(repositoryURL: config.repositoryURL, destination: config.destination)
                try Task.checkCancellation()
                dependencies = checks
                guard missingRequirements.isEmpty else {
                    throw PortError.invalidConfiguration("The local toolchain check failed. Review Build tools.")
                }
                let command = try BuildCommand.make(configuration: config, pythonURL: python)
                appendLog(command.redactedDescription)
                let result = try await runner.run(command) { continuation.yield($0) }
                continuation.finish(); await consumer.value
                try Task.checkCancellation()
                guard result.exitCode == 0 else { throw PortError.processFailed(result.exitCode, "Review Activity and the local build logs beside the game.") }
                if config.prepareXcode {
                    guard FileManager.default.fileExists(atPath: config.workspaceURL.appendingPathComponent("contents.xcworkspacedata").path) else {
                        throw PortError.invalidConfiguration("The build returned without the expected Xcode workspace.")
                    }
                    workspaceURL = config.workspaceURL; completedURL = config.workspaceURL
                    status = "Xcode workspace ready"; page = .guide
                } else {
                    guard FileManager.default.fileExists(atPath: config.outputURL.path) else {
                        throw PortError.invalidConfiguration("The build returned without the expected app or unsigned IPA.")
                    }
                    completedURL = config.outputURL; status = "Port created"
                }
            } catch is CancellationError { status = "Cancelled"; appendLog("Build cancelled. Completed cache stages remain available.") }
            catch {
                failure = LogRedactor.display(error.localizedDescription, privatePaths: privatePaths)
                status = "Build stopped"; appendLog(error.localizedDescription)
            }
            continuation.finish(); await consumer.value
            isBusy = false; currentTask = nil
        }
    }
    func cancel() { currentTask?.cancel(); runner.cancel() }
    func terminate() { currentTask?.cancel(); checkTask?.cancel(); runner.cancelImmediately() }
    func revealOutput() { if let completedURL { NSWorkspace.shared.activateFileViewerSelecting([completedURL]) } }
    func openWorkspace() { if let workspaceURL { NSWorkspace.shared.open(workspaceURL) } }
    func openLocalGuide() { NSWorkspace.shared.open(repositoryURL.appendingPathComponent("docs/dotnet-build.md")) }
}
