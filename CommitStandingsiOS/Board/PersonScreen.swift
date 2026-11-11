import SwiftUI

/// The person view on iPhone: the shared `PersonViewContent` in the app's materials, scrolling on
/// ink, with the iPhone's private-contributions tip on your own view. `BoardView` shows it in a
/// sheet, or in the second pane on iPhone Duo when the panes sit side by side.
struct PersonScreen: View {
    @Environment(AppModel.self) private var model
    let person: PersonSummary
    /// A past month's Final standings being shared, frozen when its share button is tapped.
    @State private var sharing: BoardShareRequest?

    var body: some View {
        ScrollView {
            PersonViewContent(
                person: person,
                initialDay: Self.initialDay,
                shareFinish: { month in
                    sharing = model.finalStandingsToShare(for: month).map(BoardShareRequest.init(finals:))
                },
                canShareFinish: { model.finalStandingsToShare(for: $0) != nil }
            ) {
                PrivateWorkTip(dismissible: false)
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(Self.scrollAnchor)
        .scrollContentBackground(.hidden)
        .background(Color.ink)
        .environment(\.personViewStyle, .committed)
        .sheet(item: $sharing) { request in
            BoardShareSheet(request: request)
        }
        // A different person starts on their own today.
        .id(person.login)
    }

    private static var scrollAnchor: UnitPoint {
        #if DEBUG
        ScreenshotFixture.personScrolledToEnd ? .bottom : .top
        #else
        .top
        #endif
    }

    private static var initialDay: Int? {
        #if DEBUG
        ScreenshotFixture.personDay
        #else
        nil
        #endif
    }
}

/// The person view as a sheet over the Board, with Done to close it.
struct PersonSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let person = model.shownPerson {
                    PersonScreen(person: person)
                } else {
                    Color.ink
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.ink)
    }
}

/// The person view in the second pane on the open iPhone Duo, where your summary otherwise sits,
/// with a button back to your summary.
struct PersonPane: View {
    @Environment(AppModel.self) private var model
    let person: PersonSummary

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.selectedPerson = nil
                } label: {
                    Label("Your standing", systemImage: "chevron.backward")
                        .font(.callout.weight(.semibold))
                }
                .tint(.lime)
                .accessibilityHint("Closes \(person.login)’s month")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            PersonScreen(person: person)
        }
        .background(Color.ink)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(person.login)’s month")
    }
}

/// A row on the Board that opens that person's view: the shared `StandingRow`, unchanged, as a
/// button.
struct PersonRowButton<Row: View>: View {
    @Environment(AppModel.self) private var model
    let login: String
    @ViewBuilder let row: () -> Row

    var body: some View {
        Button {
            model.showPerson(login)
        } label: {
            row().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows their month")
    }
}
