import SwiftUI
import PortCore

// Layout and visual primitives adapted from seedds/nxnative PR #280.
enum StudioStyle {
    static let ground = Color(white: 0.045)
    static let surface = Color(white: 0.085)
    static let raised = Color(white: 0.14)
    static let muted = Color(white: 0.70)
    static let signal = Color(red: 0.94, green: 0.69, blue: 0.39)
}

struct StudioView: View {
    @Bindable var model: StudioModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 200)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.page.rawValue).font(.system(size: 26, weight: .semibold))
                        Text(model.status).foregroundStyle(StudioStyle.muted)
                    }
                    Spacer()
                    Label("Local workflow", systemImage: "lock.shield").font(.system(size: 12))
                        .padding(10).background(StudioStyle.raised, in: Capsule())
                }.padding(26)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let failure = model.failure {
                            Label(failure, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(StudioStyle.signal).textSelection(.enabled)
                                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(StudioStyle.raised, in: RoundedRectangle(cornerRadius: 10))
                        }
                        switch model.page {
                        case .create: createPage
                        case .environment: environmentPage
                        case .guide: guidePage
                        case .activity: activityPage
                        }
                    }.padding(26)
                }
                if model.isBusy || model.completedURL != nil { footer }
            }
        }
        .font(.system(size: 14))
        .background(StudioStyle.ground).foregroundStyle(.white)
        .onChange(of: model.destination) { model.targetChanged() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                PortMark().frame(width: 30, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("NX PORT").font(.system(size: 15, weight: .bold))
                    Text("STUDIO · LOCAL").font(.system(size: 10, weight: .medium)).tracking(1.2).foregroundStyle(StudioStyle.muted)
                }
            }.padding(.top, 12)
            VStack(spacing: 8) {
                ForEach(StudioPage.allCases) { page in
                    Button { model.page = page } label: {
                        Label(page.rawValue, systemImage: page.icon)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(model.page == page ? StudioStyle.raised : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "externaldrive")
                Text("Your engine.\nYour game files.").fontWeight(.medium)
                Text("Builds run with outbound IP connections blocked. Paths and key selections stay in this session.")
                    .font(.system(size: 11)).foregroundStyle(StudioStyle.muted).fixedSize(horizontal: false, vertical: true)
            }.padding(10)
        }.padding(18).background(StudioStyle.surface)
    }

    private var createPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            StudioPanel {
                VStack(alignment: .leading, spacing: 14) {
                    sectionTitle("1 · Local source", icon: "folder")
                    Text(model.repositoryPath.isEmpty ? "Choose your existing, trusted NXNativ checkout." : model.repositoryPath)
                        .font(.system(size: 12)).foregroundStyle(StudioStyle.muted).textSelection(.enabled)
                    HStack {
                        Button("Choose engine…") { model.chooseRepository() }
                        Button(model.isChecking ? "Checking…" : "Check tools") { model.checkEnvironment() }
                            .disabled(model.repositoryPath.isEmpty)
                        Spacer()
                        if !model.dependencies.isEmpty {
                            Button(model.missingRequirements.isEmpty ? "Tools ready" : "Review tools") { model.page = .environment }
                        }
                    }
                }
            }.disabled(model.isBusy || model.isChecking)
            HStack(alignment: .top, spacing: 20) {
                StudioPanel {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionTitle("2 · Your game", icon: "sdcard")
                        Text("One folder with the base game, plus its update and DLC. Files are read in place.")
                            .foregroundStyle(StudioStyle.muted).font(.system(size: 12))
                        Button { model.chooseGame() } label: {
                            Label(model.gamePath.isEmpty ? "Choose game folder…" : URL(fileURLWithPath: model.gamePath).lastPathComponent, systemImage: "folder.badge.plus")
                                .frame(maxWidth: .infinity, minHeight: 60).background(StudioStyle.raised, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                        if !model.gameFiles.isEmpty {
                            ForEach(model.gameFiles.prefix(4), id: \.path) { file in
                                Text(file.lastPathComponent).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                            }
                            Text("\(model.gameFiles.count) files · " + ByteCountFormatter.string(fromByteCount: model.inputBytes, countStyle: .file))
                                .font(.system(size: 12)).foregroundStyle(StudioStyle.muted)
                        }
                        Divider()
                        Button(model.keysPath.isEmpty ? "Choose existing prod.keys…" : "prod.keys selected · change…") { model.chooseKeys() }
                        Text("The GUI passes the selected path to local tools. It never copies the key file or remembers its path after quitting.")
                            .font(.system(size: 12)).foregroundStyle(StudioStyle.muted)
                    }
                }.frame(maxWidth: .infinity)
                StudioPanel {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionTitle("3 · Destination", icon: "arrow.up.forward.app")
                        Picker("Build for", selection: $model.destination) {
                            Text("This Mac").tag(BuildDestination.macOS)
                            Text("iPhone / iPad").tag(BuildDestination.iOS)
                        }.pickerStyle(.segmented)
                        if model.destination == .iOS {
                            Picker("Output", selection: $model.prepareXcode) {
                                Text("Xcode workspace").tag(true)
                                Text("Unsigned IPA").tag(false)
                            }.pickerStyle(.segmented)
                            Text(model.prepareXcode ? "Prepare the game and shaders, then open Xcode to select your own team and device." : "Export an unsigned package for your sideloading tool.")
                                .foregroundStyle(StudioStyle.muted).font(.system(size: 12))
                        } else {
                            Text("Create a standalone Mac app with a local ad-hoc signature. The game is not launched automatically.")
                                .foregroundStyle(StudioStyle.muted).font(.system(size: 12))
                        }
                        Divider()
                        TextField("App name · game default", text: $model.appName).textFieldStyle(.roundedBorder)
                        Picker("Game language", selection: $model.language) {
                            Text("Engine default").tag("")
                            Text("Deutsch").tag("de")
                            Text("English").tag("en-US")
                        }
                        Toggle("Show FPS", isOn: $model.showFPS)
                        if model.destination == .macOS || !model.prepareXcode {
                            Text(model.outputFolder.isEmpty ? "Output defaults to the game folder." : model.outputFolder)
                                .font(.system(size: 11)).foregroundStyle(StudioStyle.muted).lineLimit(2).truncationMode(.middle)
                            Button("Choose export folder…") { model.chooseOutput() }
                        }
                    }
                }.frame(maxWidth: .infinity)
            }.disabled(model.isBusy || model.isChecking)
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Progress comes from the build itself.").fontWeight(.medium)
                    Text("A successful build does not establish full game compatibility. Existing exports are protected.")
                        .font(.system(size: 12)).foregroundStyle(StudioStyle.muted)
                }
                Spacer()
                Button { model.build() } label: {
                    Label(model.destination == .iOS && model.prepareXcode ? "Prepare Xcode workspace" : "Build port", systemImage: "play.fill")
                }.buttonStyle(PrimaryButtonStyle()).disabled(!model.canBuild)
            }
            if !model.buildProgress.stages.isEmpty { progressPanel }
        }
    }

    private var environmentPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            StudioPanel {
                VStack(alignment: .leading, spacing: 14) {
                    sectionTitle("Verify the existing toolchain", icon: "checklist")
                    Text("Checks use the checkout's local Python environment, .NET manifests and locked compiler fingerprints. Missing or changed tools stop the build.")
                        .foregroundStyle(StudioStyle.muted)
                    HStack {
                        Button("Choose engine…") { model.chooseRepository() }
                        Button("Check tools") { model.checkEnvironment() }.disabled(model.repositoryPath.isEmpty)
                        if !model.repositoryPath.isEmpty { Button("Open local setup guide") { model.openLocalGuide() } }
                    }.disabled(model.isBusy || model.isChecking)
                }
            }
            if model.isChecking { ProgressView("Checking local tools…") }
            ForEach(model.dependencies) { item in
                StudioPanel {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.isAvailable ? "checkmark.circle" : "exclamationmark.circle")
                            .foregroundStyle(item.isAvailable ? .green : StudioStyle.signal)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.name).fontWeight(.medium)
                            Text(item.detail).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).foregroundStyle(StudioStyle.muted)
                            if let repair = item.remediation { Text(repair).font(.system(size: 12)) }
                        }
                        Spacer()
                        Text(item.isAvailable ? "Ready" : item.isRequired || (item.id == "nsz" && model.requiresNSZ) ? "Required" : "Optional")
                            .font(.system(size: 11)).foregroundStyle(StudioStyle.muted)
                    }
                }
            }
            Text("Install or update dependencies deliberately using the local guide. This GUI has no package installer or engine updater.")
                .font(.system(size: 12)).foregroundStyle(StudioStyle.muted)
        }
    }

    private var guidePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            StudioPanel {
                VStack(alignment: .leading, spacing: 14) {
                    sectionTitle("From game files to Xcode", icon: "ipad.and.iphone")
                    Text("Choose iPhone / iPad → Xcode workspace on New port. The existing pipeline prepares code, resources and shaders, then generates a project for that game.")
                        .foregroundStyle(StudioStyle.muted)
                    guideStep(1, "Open the generated workspace", "Use Open in Xcode below when preparation finishes. All game resources stay linked to the selected game folder; keep its drive connected.")
                    guideStep(2, "Select your Apple account and team", "In Xcode → Settings → Apple Accounts, add your account. In the DmIOS target → Signing & Capabilities, enable automatic signing and select your team. Keep the same bundle ID when updating an existing installation to preserve its app identity.")
                    guideStep(3, "Select the game and iPhone", "Choose the game's scheme and your connected device. Unlock and trust the Mac, and enable Developer Mode on the iPhone if Xcode requests it.")
                    guideStep(4, "Review signing, then Run in Xcode", "Xcode handles signing and installation when you choose Run. Account limits and required memory capabilities depend on your team. This GUI does not read signing identities, pair devices or install apps.")
                    guideStep(5, "Test on the device", "Check startup, controls, rotation, sound and saves on the actual iPhone. A successful Mac build or synthetic iOS compile does not prove device gameplay.")
                    if model.workspaceURL != nil {
                        HStack {
                            Button("Open in Xcode") { model.openWorkspace() }.buttonStyle(PrimaryButtonStyle())
                            Button("Show in Finder") { model.revealOutput() }
                        }
                    }
                }
            }
            StudioPanel {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("What stays local", icon: "lock.shield")
                    Text("Your selected games and keys are used only by the local pipeline. Build subprocesses have outbound IP connections blocked. The app does not download engines, query Apple accounts, collect analytics or upload diagnostics.")
                    Text("The redacted activity view stays in memory. Detailed engine logs and extracted game data are stored beside the game in its *_build folder. Review those files before sharing them.")
                        .foregroundStyle(StudioStyle.muted)
                }
            }
        }
    }

    private var activityPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !model.buildProgress.stages.isEmpty { progressPanel }
            StudioPanel {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Local build activity", icon: "text.alignleft")
                    Text(model.logs.isEmpty ? "The next build's status and errors appear here." : model.logs.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(StudioStyle.muted)
                        .textSelection(.enabled).frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
                }
            }
        }
    }
    private var progressPanel: some View {
        StudioPanel {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Build stages", icon: "list.bullet")
                ForEach(model.buildProgress.stages) { stage in
                    Label(stage.name, systemImage: stage.finished == true ? "checkmark.circle.fill" : stage.finished == false ? "xmark.circle.fill" : "circle.dotted")
                        .foregroundStyle(stage.finished == false ? StudioStyle.signal : .white)
                }
                Text(model.buildProgress.step).font(.system(size: 12)).foregroundStyle(StudioStyle.muted)
            }
        }
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isBusy ? model.buildProgress.stages.last?.name ?? model.status : model.status).fontWeight(.medium)
                    HStack(spacing: 14) {
                        if model.buildProgress.stageTotal > 0 { Text("Stage \(model.buildProgress.stageIndex) / \(model.buildProgress.stageTotal)") }
                        if let elapsed = model.buildProgress.elapsed { Text("Elapsed " + duration(elapsed)) }
                        if let eta = model.buildProgress.eta { Text("Remaining ~" + duration(eta)) }
                        if let fraction = model.buildProgress.fraction { Text("\(Int(fraction * 100))% of stage") }
                    }.font(.system(size: 11)).monospacedDigit().foregroundStyle(StudioStyle.muted)
                }
                Spacer()
                if model.isBusy {
                    Button("Activity") { model.page = .activity }
                    Button("Cancel") { model.cancel() }.buttonStyle(QuietButtonStyle())
                } else {
                    if model.workspaceURL != nil { Button("Open in Xcode") { model.openWorkspace() }.buttonStyle(PrimaryButtonStyle()) }
                    Button("Show in Finder") { model.revealOutput() }.buttonStyle(QuietButtonStyle())
                }
            }
            if model.isBusy {
                if let progress = model.buildProgress.fraction { ProgressView(value: progress).tint(StudioStyle.signal) }
                else { ProgressView().progressViewStyle(.linear).tint(StudioStyle.signal) }
            }
        }.padding(20).background(StudioStyle.surface)
    }
    private func guideStep(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)").font(.system(size: 12, weight: .bold)).frame(width: 26, height: 26).background(StudioStyle.raised, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).fontWeight(.medium)
                Text(detail).foregroundStyle(StudioStyle.muted).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 5)
    }
    private func duration(_ seconds: Double) -> String {
        let seconds = Int(max(0, seconds))
        return seconds >= 3600 ? "\(seconds / 3600)h \(seconds % 3600 / 60)m" : "\(seconds / 60)m \(seconds % 60)s"
    }
    private func sectionTitle(_ title: String, icon: String) -> some View { Label(title, systemImage: icon).font(.system(size: 16, weight: .medium)) }
}

struct StudioPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(StudioStyle.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 15).frame(minHeight: 36)
            .foregroundStyle(enabled ? .black : .white.opacity(0.6))
            .background(enabled ? Color(white: configuration.isPressed ? 0.75 : 0.95) : Color(white: 0.22), in: Capsule())
    }
}
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 12).frame(minHeight: 32)
            .background(Color(white: configuration.isPressed ? 0.23 : 0.17), in: Capsule())
    }
}
struct PortMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).stroke(.white, lineWidth: 2).frame(width: 21, height: 27).offset(x: -3)
            Image(systemName: "arrow.right").font(.system(size: 20, weight: .bold)).padding(3).background(StudioStyle.surface).offset(x: 7, y: 2)
        }.accessibilityHidden(true)
    }
}
