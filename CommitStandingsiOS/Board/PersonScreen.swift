import SwiftUI

/// The person view on iPhone: the shared `PersonViewContent` in the app's materials, scrolling on
/// ink: on your own view, Your records under the stats and the iPhone's private-contributions tip;
/// on someone else's, Challenge under Your race. `BoardView` pushes it onto
/// the Board, or shows it in the second pane on iPhone Duo when the panes sit side by side.
///
/// Wherever it's wider than tall and has room for two readable columns (the closed iPhone Duo or
/// another phone in landscape), the overview and the month sit side by side, each scrolling on its
/// own. That's an `HStack`, not a split `ArrangementView`: an arrangement shows only its primary
/// view on a closed iPhone Duo in landscape, which would hide the month. The person view never
/// spans the fold: on the open iPhone Duo it's the Board's second pane, one column, and taller
/// than wide it's one column that scrolls, which needs nothing from the fold.
struct PersonScreen: View {
    @Environment(AppModel.self) private var model
    let person: PersonSummary
    /// Your records, drawn under the stats on your own view only.
    var records: PersonalRecords?
    /// Off in the Board's second pane, which is already one half of the Board.
    var allowsColumns = true
    @State private var size: CGSize = .zero

    var body: some View {
        Group {
            if usesColumns {
                HStack(spacing: 0) {
                    column(.overview)
                    column(.month)
                }
            } else {
                column(.all)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .background(Color.ink)
        .environment(\.personViewStyle, .committed)
        // A different person starts on their own today.
        .id(person.login)
    }

    /// Two columns once the space is wide rather than tall and each column gets room for the stat
    /// tiles side by side; the closed iPhone Duo in landscape has about 580 pt inside its safe
    /// area. Before their count loads there's only the overview to show.
    private var usesColumns: Bool {
        allowsColumns && person.days != nil && size.width >= 2 * Self.minimumColumnWidth && size.width > size.height
    }

    private static let minimumColumnWidth: CGFloat = 280

    private func column(_ part: PersonViewPart) -> some View {
        ScrollView {
            PersonViewContent(person: person, initialDay: Self.initialDay, part: part) {
                PrivateWorkTip()
            } raceAccessory: {
                // Hidden on the Sample board and until the race loads.
                if let challenge = model.challenge(for: person) {
                    ChallengeButton(challenge: challenge, person: person)
                }
                // The Weekly record, under Your race. A rivalry needs both calendars, as the race
                // does, so it's never without the race card above it.
                if let rivalry = person.rivalry {
                    WeeklyRecordCard(record: rivalry, login: person.login)
                }
            } underStats: {
                if person.isYou, let records {
                    YourRecordsSection(records: records)
                }
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(Self.scrollAnchor)
        .scrollContentBackground(.hidden)
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

/// Their GitHub profile, in the bar rather than in the header, so the header's only bright color
/// is their data.
struct PersonProfileLink: View {
    let person: PersonSummary

    var body: some View {
        // Text, not an icon: no symbol says "GitHub profile" on its own.
        Link("GitHub", destination: person.profileURL)
            .tint(.lime)
        .accessibilityLabel("GitHub profile")
        .accessibilityHint("Opens \(person.login) on GitHub")
    }
}

/// Rival, in the bar beside GitHub on someone else's view: a pin labelled "Rival", or "Pinned" when
/// on, read as "Rival" or "Rival, pinned". With three rivals pinned it stays tappable and explains
/// the limit instead, offering no replacement. Your own view has none.
struct RivalPinButton: View {
    @Environment(StandingsStore.self) private var store
    @Environment(AppModel.self) private var model
    let person: PersonSummary
    @State private var explainingLimit = false

    var body: some View {
        if !person.isYou {
            let pinned = store.isPinned(person.login)
            let atLimit = !pinned && !store.canPinAnotherRival
            Button {
                // Through the model, so the relay hears the new rivals right away.
                if pinned {
                    Task { await model.setRivalPinned(false, username: person.login) }
                } else if atLimit {
                    explainingLimit = true
                } else {
                    Task { await model.setRivalPinned(true, username: person.login) }
                }
            } label: {
                // The pin and its word, not a `Label`: a bar shows a label's icon alone, and the
                // word is the state.
                HStack(spacing: 5) {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .contentTransition(.symbolEffect(.replace))
                    Text(pinned ? "Pinned" : "Rival")
                }
            }
            .tint(.lime)
            .sensoryFeedback(.selection, trigger: pinned)
            .accessibilityLabel("Rival")
            .accessibilityInputLabels(["Rival", "Pinned"])
            .accessibilityValue(pinned ? "pinned" : "")
            .accessibilityHint(pinned ? "Unpins \(person.login) from Your rivals"
                               : atLimit ? Self.limitMessage
                               : "Pins \(person.login) to Your rivals on the Board")
            .popover(isPresented: $explainingLimit) {
                Text(Self.limitMessage)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .presentationCompactAdaptation(.popover)
            }
            #if DEBUG
            .task {
                // After the push settles, so the popover has a bar button to point at.
                guard ScreenshotFixture.explainsRivalLimit else { return }
                try? await Task.sleep(for: .seconds(4))
                if !store.isPinned(person.login) && !store.canPinAnotherRival { explainingLimit = true }
            }
            #endif
        }
    }

    static let limitMessage = "You can pin up to \(StandingsStore.maxPinnedRivals) rivals"
}

/// The person view pushed onto the Board: back to the Board on the leading side, Rival and their
/// GitHub profile on the trailing side, and the tab bar still there.
struct PersonDestination: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let person = model.shownPerson {
                PersonScreen(person: person, records: person.isYou ? model.yourRecords : nil)
                    .navigationTitle(person.isYou ? "Your month" : "\(person.login)’s month")
                    .toolbar {
                        if !person.isYou {
                            ToolbarItem(placement: .topBarTrailing) {
                                RivalPinButton(person: person)
                            }
                            // Beside GitHub with its words on iPhone Duo too: in the vertical bar it
                            // would be a bare pin, and "Rival" / "Pinned" is the state.
                            .axisBehavior(.horizontalOnly)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            PersonProfileLink(person: person)
                        }
                    }
            } else {
                Color.ink
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.ink)
    }
}

/// The person view in the second pane on the open iPhone Duo, where your summary otherwise sits,
/// with a button back to your summary, Rival and their GitHub profile.
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
                HStack(spacing: 18) {
                    RivalPinButton(person: person)
                    PersonProfileLink(person: person)
                }
                .font(.callout.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            PersonScreen(person: person, records: person.isYou ? model.yourRecords : nil, allowsColumns: false)
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
