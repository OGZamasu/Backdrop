import SwiftUI

@main
struct BackdropApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObject(model)
        } label: {
            // A red dot joins the icon while your screen is going out.
            Image(nsImage: MenuBarIcon.image(on: model.isOn, sharing: model.isScreenGoingOut))
        }
        .menuBarExtraStyle(.window)

        Window("Backdrop Studio", id: "studio") {
            StudioView().environmentObject(model)
        }
        .defaultSize(width: 1060, height: 700)
        .commands { StudioCommands(model: model) }
    }
}

/// ⌘, opens the Studio's Settings, like any other Mac app.
private struct StudioCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                model.studioPane = .settings
                openWindow(id: "studio")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",")
        }
    }
}
