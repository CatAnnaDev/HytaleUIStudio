import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HytaleUICore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct HytaleUIStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = DocumentStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { store.newDocument() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open...") { openFile() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("Save") { saveFile() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Save As...") { saveFileAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { store.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo") { store.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let type = UTType(filenameExtension: "ui") {
            panel.allowedContentTypes = [type, .plainText, .data]
        }
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK, let url = panel.url {
            store.loadFile(url)
        }
    }

    private func saveFile() {
        if store.fileURL != nil {
            store.save()
        } else {
            saveFileAs()
        }
    }

    private func saveFileAs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = store.fileURL?.lastPathComponent ?? "Untitled.ui"
        if let type = UTType(filenameExtension: "ui") {
            panel.allowedContentTypes = [type]
        }
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK, let url = panel.url {
            store.saveAs(url)
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: DocumentStore
    @State private var showInspector = true

    var body: some View {
        NavigationSplitView {
            VSplitView {
                HierarchyView(store: store)
                    .frame(minHeight: 160)
                PaletteView(store: store)
                    .frame(minHeight: 160)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            VSplitView {
                CanvasView(store: store)
                    .environmentObject(store)
                    .frame(minHeight: 260)
                SourceView(store: store)
                    .frame(minHeight: 140)
            }
        }
        .inspector(isPresented: $showInspector) {
            InspectorView(store: store)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { store.newDocument() } label: { Image(systemName: "doc.badge.plus") }
                    .help("New")
                Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("Undo")
                Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .help("Redo")
                Spacer()
                gameDataStatus
                Button { showInspector.toggle() } label: { Image(systemName: "sidebar.trailing") }
                    .help("Toggle inspector")
            }
        }
        .navigationTitle(store.fileURL?.lastPathComponent ?? "Untitled.ui")
    }

    @ViewBuilder
    private var gameDataStatus: some View {
        if store.gameDataURL != nil {
            Label("Game assets", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.caption)
                .help("Hytale game textures found for faithful preview")
        } else {
            Button {
                pickGameData()
            } label: {
                Label("Locate game", systemImage: "exclamationmark.triangle")
                    .font(.caption)
            }
            .help("Point to Hytale.app Data folder for faithful textures")
        }
    }

    private func pickGameData() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Select the Hytale Data folder (…/Hytale.app/Contents/Resources/Data)"
        if panel.runModal() == .OK, let url = panel.url {
            store.gameDataURL = url
            store.refreshTextureRoots()
        }
    }
}
