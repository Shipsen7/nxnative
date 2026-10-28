import SwiftUI
import AppKit

@main
struct StudioApp: App {
    @State private var model = StudioModel()
    var body: some Scene {
        Window("NX Port Studio · Local", id: "main") {
            StudioView(model: model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 940, minHeight: 720)
                .task { model.initialize() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.terminate() }
        }
        .defaultSize(width: 1180, height: 850)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Button("Xcode guide") { model.page = .guide }
            }
        }
    }
}
