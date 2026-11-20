import SwiftUI

/// What the Share button opens: swipe between the widget styles, pick Square or Story, and share.
struct BoardShareSheet: View {
    let snapshot: WidgetSnapshot
    @State private var style: BoardShareStyle = .board
    @State private var format: BoardShareFormat
    @State private var sharing: SharedFile?
    @Environment(\.dismiss) private var dismiss

    init(snapshot: WidgetSnapshot, initialFormat: BoardShareFormat = .square) {
        self.snapshot = snapshot
        _format = State(initialValue: initialFormat)
    }

    private struct SharedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                TabView(selection: $style) {
                    ForEach(BoardShareStyle.allCases) { style in
                        BoardSharePreview(snapshot: snapshot, style: style, format: format)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 36)
                            .tag(style)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))

                Text(style.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.soft)
                    .contentTransition(.opacity)

                Picker("Format", selection: $format) {
                    ForEach(BoardShareFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)

                Button {
                    sharing = (try? BoardShareRenderer.file(snapshot, style: style, format: format)).map(SharedFile.init)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LimeButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .inkScreen()
            .navigationTitle("Share board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // The image alone: no title or caption rides along into the post or message.
        .sheet(item: $sharing) { file in
            ShareActivity(items: [file.url])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }
}
