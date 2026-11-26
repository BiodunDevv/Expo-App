import AppKit
import SwiftUI

@main
struct ExpoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(delegate: delegate).environment(delegate.model)
        } label: {
            if let image = delegate.model.mark.nsImage(points: 18, tile: false) {
                Image(nsImage: image).renderingMode(.original).accessibilityLabel("Expo")
            } else {
                Text("Expo")
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session") { delegate.model.requestAssistStart() }.keyboardShortcut("n")
                Button("Open Expo") { delegate.showMain() }.keyboardShortcut("o")
            }
            CommandGroup(before: .toolbar) {
                Button("Toggle Sidebar") { delegate.model.sidebarCollapsed.toggle() }.keyboardShortcut("\\")
                ForEach(Array(Route.allCases.enumerated()), id: \.element) { index, route in
                    Button(route.title) { delegate.model.open(route) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
                Divider()
            }
            CommandGroup(after: .toolbar) {
                Button("Zoom In") { delegate.model.zoom(1) }.keyboardShortcut("=")
                Button("Zoom Out") { delegate.model.zoom(-1) }.keyboardShortcut("-")
                Button("Actual Size") { delegate.model.zoom(nil) }.keyboardShortcut("0")
            }
        }
    }
}
