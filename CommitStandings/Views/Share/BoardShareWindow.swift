import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The menu-bar board opens a regular window so the preview and system share controls can take focus.
struct BoardShareWindow: Scene {
    static let id = "shareBoard"
    let snapshot: WidgetSnapshot?

    var body: some Scene {
        Window("Share board", id: Self.id) {
            if let snapshot {
                BoardShareWindowContent(snapshot: snapshot)
            }
        }
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
    }
}

private struct BoardShareWindowContent: View {
    private static let avatars = GitHubAvatarPrefetcher.live()
    let snapshot: WidgetSnapshot
    @State private var style: BoardShareStyle = .board
    @State private var format: BoardShareFormat = .square
    @State private var exportURL: URL?
    @State private var errorMessage: String?
    @State private var preparedSnapshot: WidgetSnapshot?

    private struct Selection: Equatable {
        let snapshot: WidgetSnapshot
        let style: BoardShareStyle
        let format: BoardShareFormat
        let avatarsReady: Bool
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Picker("Style", selection: $style) {
                    ForEach(BoardShareStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }

                Picker("Format", selection: $format) {
                    ForEach(BoardShareFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            BoardSharePreview(snapshot: snapshot, style: style, format: format,
                              avatarCache: preparedSnapshot == snapshot ? .shared : nil)

            HStack {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if preparedSnapshot != snapshot {
                    ProgressView("Preparing image…")
                        .controlSize(.small)
                }
                Spacer()
                if preparedSnapshot == snapshot, let exportURL {
                    Button("Save PNG…") { save(exportURL) }
                    ShareLink(item: exportURL)
                } else {
                    Button("Save PNG…") {}
                        .disabled(true)
                    Button("Share", systemImage: "square.and.arrow.up") {}
                        .disabled(true)
                }
            }
        }
        .padding(20)
        .frame(width: 460, height: 574)
        .task(id: snapshot) {
            preparedSnapshot = nil
            errorMessage = nil
            if snapshot.isSampleBoard != true {
                let neighbors = [snapshot.state.above?.login, snapshot.state.below?.login].compactMap { $0 }
                let logins = Set(snapshot.top.map(\.login) + neighbors + [snapshot.selfLogin])
                await Self.avatars.prefetch(logins.sorted())
            }
            guard !Task.isCancelled else { return }
            preparedSnapshot = snapshot
        }
        .onChange(of: Selection(snapshot: snapshot, style: style, format: format,
                                avatarsReady: preparedSnapshot == snapshot), initial: true) {
            prepareExport()
        }
    }

    private func prepareExport() {
        guard preparedSnapshot == snapshot else { return }
        errorMessage = nil
        do {
            exportURL = try BoardShareRenderer.file(snapshot, style: style, format: format)
        } catch {
            exportURL = nil
            errorMessage = "Couldn’t prepare the image."
        }
    }

    private func save(_ url: URL) {
        do {
            // Freeze the selected PNG before presenting the save dialog.
            let png = try Data(contentsOf: url)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = url.lastPathComponent
            guard let window = NSApp.keyWindow else { return }
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let destination = panel.url else { return }
                do {
                    try png.write(to: destination, options: .atomic)
                    errorMessage = nil
                } catch {
                    errorMessage = "Couldn’t save the image."
                }
            }
        } catch {
            errorMessage = "Couldn’t open the image."
        }
    }
}
