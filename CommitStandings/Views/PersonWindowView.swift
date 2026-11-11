import SwiftUI

/// The Mac's person window: the shared `PersonViewContent` (the iPhone's person view, in the Mac's
/// system look) for whoever was last clicked on the board, scrolling in a resizable window like
/// People. Before anyone is clicked, or once they leave the board, it says how to pick someone.
struct PersonWindowView: View {
    @Environment(PersonWindowModel.self) private var model
    /// The bar selected when a person opens; nil = today. Only the capture host sets it.
    var initialDay: Int?

    var body: some View {
        Group {
            if let person = model.shown {
                ScrollView {
                    PersonViewContent(person: person, initialDay: initialDay)
                        .padding(20)
                }
                // A different person starts on their own today.
                .id(person.login)
                .navigationTitle(person.isYou ? "Your month" : "\(person.login)’s month")
            } else {
                ContentUnavailableView(
                    "Nobody chosen",
                    systemImage: "person.crop.circle",
                    description: Text("Click someone on the board to see their month.")
                )
                .navigationTitle("Person")
            }
        }
        .frame(minWidth: PersonWindow.minWidth, minHeight: 360)
    }
}

/// A board row that opens that person in the person window: the shared `StandingRow`, unchanged,
/// as a button. Clicking the person already shown brings their window forward.
struct PersonWindowRowButton<Row: View>: View {
    @Environment(PersonWindowModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let login: String
    @ViewBuilder let row: () -> Row

    var body: some View {
        Button {
            PersonWindow.open(login, model: model, using: openWindow)
        } label: {
            row().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows their month")
    }
}
