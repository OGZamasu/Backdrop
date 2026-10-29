import SwiftUI

@main
struct BackdropApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObject(model)
        } label: {
            Image(systemName: model.isOn ? "person.crop.rectangle.fill" : "person.crop.rectangle")
        }
        .menuBarExtraStyle(.window)

        Window("Backdrop Studio", id: "studio") {
            StudioView().environmentObject(model)
        }
        .defaultSize(width: 920, height: 620)
    }
}
