import SwiftUI
import UIKit

// Share face-off, in the bar of someone else's person view: you and them side by side on the same
// Window, as an image for the share sheet. Contributions only, no rank. Drawn the way Share board
// and Challenge draw theirs: a fixed-size SwiftUI card on the board's squares, rendered with
// `ImageRenderer` (`ShareImageRenderer`). Unlike Challenge it works over Today, 7 days and 30 days,
// and carries no link, so it reads the same whoever is ahead.

/// You against `friend` over one Window, as the Board counts it: each person's own total for the
/// Window (`ContributionHistory.total(for:asOf:)`), so the numbers match the Board's.
struct FaceOff: Equatable, Sendable {
    /// Your login, as GitHub shows it.
    let you: String
    /// Theirs.
    let friend: String
    let window: ContributionWindow
    let yourTotal: Int
    let theirTotal: Int
    /// The days counted, as the image prints them: "Nov 22", "Nov 16 – Nov 22".
    let rangeText: String
    /// Numbers are grouped for this locale: "1,204".
    var locale: Locale = .current

    /// Whose number is lime: the leader's, or both when level.
    var youLead: Bool { yourTotal >= theirTotal }
    var theyLead: Bool { theirTotal >= yourTotal }

    /// How much of the bar is yours: half when neither of you has contributed.
    var yourShare: Double {
        let combined = yourTotal + theirTotal
        return combined == 0 ? 0.5 : Double(yourTotal) / Double(combined)
    }

    /// The eyebrow over the card: "Head to head · 7 days".
    var eyebrow: String { "Head to head · \(window.shortTitle)" }

    /// "Who shipped more" and the Window, as Share board's headline words them.
    var when: String {
        switch window {
        case .daily: "today?"
        case .weekly: "this week?"
        case .monthly: "in 30 days?"
        }
    }

    func formatted(_ total: Int) -> String {
        total.formatted(.number.locale(locale))
    }

    var accessibilityLabel: String {
        "\(you) \(yourTotal), \(friend) \(theirTotal), \(window.accessibilityDescription)"
    }

    /// The name the PNG is saved under.
    func fileName(_ format: BoardShareFormat) -> String {
        "Committed-faceoff-\(you.lowercased())-vs-\(friend.lowercased())-\(window.shortTitle.replacingOccurrences(of: " ", with: "-"))-\(format.rawValue).png"
    }
}

extension FaceOff {
    /// You against `friend` over `window` as of `reference`: nil until both calendars have loaded,
    /// on your own view, and before you're known.
    @MainActor
    init?(store: StandingsStore, friend: String, window: ContributionWindow, asOf reference: Date,
          locale: Locale = .current) {
        guard let you = store.selfCompetitor?.username, you.lowercased() != friend.lowercased(),
              let mine = store.history(for: you), let theirs = store.history(for: friend) else { return nil }
        let range = mine.days(in: window, asOf: reference)
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.locale = locale
        style.timeZone = mine.timeZone
        let first = range.lowerBound.formatted(style), last = range.upperBound.formatted(style)
        self.init(you: you, friend: friend, window: window,
                  yourTotal: mine.total(for: window, asOf: reference),
                  theirTotal: theirs.total(for: window, asOf: reference),
                  rangeText: first == last ? first : "\(first) – \(last)", locale: locale)
    }
}

// MARK: - The image

/// Square (1080 × 1080) or story (1080 × 1920): the squares, "Head to head · 7 days", on a story the
/// headline, then you and them with your totals and a bar, and Committed at the foot.
struct FaceOffCard: View {
    let faceOff: FaceOff
    let format: BoardShareFormat
    /// Saved avatars: a renderer can't wait for network images.
    var savedAvatars: AvatarCache? = .shared

    var body: some View {
        let canvas = format.canvas
        ZStack {
            Color.ink
            BoardShareSquareField(brightness: format == .story ? 1 : 0.55)
            if format == .story {
                // The squares fade out behind the headline, so it reads.
                LinearGradient(colors: [Color.ink.opacity(0.94), Color.ink.opacity(0.8), Color.ink.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 470)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            LinearGradient(colors: [Color.ink.opacity(0), Color.ink.opacity(0.85), Color.ink.opacity(0.95)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: format == .story ? 300 : 150)
                .frame(maxHeight: .infinity, alignment: .bottom)
            VStack(spacing: 0) {
                Text(faceOff.eyebrow)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.lime)
                    .padding(.top, format == .story ? 104 : 40)
                if format == .story {
                    FaceOffHeadline(faceOff: faceOff)
                        .padding(.top, 22)
                    Spacer(minLength: 24)
                } else {
                    Spacer(minLength: 0)
                }
                FaceOffVersus(faceOff: faceOff, compact: format == .square)
                Spacer(minLength: 0)
                BoardShareFooter(peopleCount: 0)
                    .padding(.bottom, format == .story ? 72 : 26)
            }
            .padding(.horizontal, 32)
        }
        .frame(width: canvas.width, height: canvas.height)
        .clipped()
        // An image looks the same whatever the phone's settings, as Share board's do.
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.avatarFallbackStyle, .committed)
        .environment(\.loadsGitHubAvatars, false)
        .environment(\.savedAvatars, savedAvatars)
    }
}

/// "Who shipped more", then the Window in lime on its own line, so it never breaks mid-phrase.
private struct FaceOffHeadline: View {
    let faceOff: FaceOff

    var body: some View {
        Text("Who shipped more\n\(Text(faceOff.when).foregroundStyle(Color.lime))")
            .font(CommittedType.display(54, relativeTo: .largeTitle))
            .displayTracking(54)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(-4)
            .frame(maxWidth: .infinity)
    }
}

/// You and them, a VS between, the leader's total in lime (both when level), a bar of how the two
/// totals divide, and the days counted.
private struct FaceOffVersus: View {
    let faceOff: FaceOff
    /// The square has less height to spend.
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 20 : 26) {
            HStack(alignment: .top, spacing: 0) {
                side(login: faceOff.you, total: faceOff.yourTotal, leads: faceOff.youLead)
                Text("VS")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Color.muted)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.ink, in: .capsule)
                    .overlay { Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
                    .padding(.top, compact ? 26 : 34)
                side(login: faceOff.friend, total: faceOff.theirTotal, leads: faceOff.theyLead)
            }
            FaceOffBar(faceOff: faceOff)
            Text(faceOff.rangeText)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Color.soft)
        }
        .padding(compact ? 24 : 28)
        .background(Color.ink, in: .rect(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
    }

    private func side(login: String, total: Int, leads: Bool) -> some View {
        VStack(spacing: compact ? 8 : 12) {
            AvatarView(username: login, size: compact ? 72 : 92)
            Text(login)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
            Text(faceOff.formatted(total))
                .font(CommittedType.display(compact ? 64 : 76, relativeTo: .largeTitle))
                .displayTracking(compact ? 64 : 76)
                .foregroundStyle(leads ? Color.lime : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
    }
}

/// How the two totals divide: yours on the left, theirs on the right, the leader's in lime. Level
/// totals are both lime; with nothing from either of you, an empty bar; with nothing from one, the
/// other's fills it.
private struct FaceOffBar: View {
    let faceOff: FaceOff

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 4
            let both = faceOff.yourTotal > 0 && faceOff.theirTotal > 0
            let minimum: CGFloat = 10
            let mine = min(max((proxy.size.width - gap) * faceOff.yourShare, minimum),
                           proxy.size.width - gap - minimum)
            Capsule()
                .fill(Color.white.opacity(0.1))
                .overlay {
                    if both {
                        HStack(spacing: gap) {
                            Capsule().fill(color(leads: faceOff.youLead)).frame(width: mine)
                            Capsule().fill(color(leads: faceOff.theyLead))
                        }
                    } else if faceOff.yourTotal > 0 {
                        Capsule().fill(color(leads: true))
                    } else if faceOff.theirTotal > 0 {
                        Capsule().fill(color(leads: true))
                    }
                }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func color(leads: Bool) -> Color {
        leads ? Color.lime : Color.soft.opacity(0.55)
    }
}

// MARK: - Rendering

@MainActor
enum FaceOffShareRenderer {
    /// The image as a PNG in a temporary folder, for the share sheet. Each render replaces the last
    /// one of the same people, Window and format.
    static func file(_ faceOff: FaceOff, format: BoardShareFormat, savedAvatars: AvatarCache?) throws -> URL {
        try ShareImageRenderer.file(FaceOffCard(faceOff: faceOff, format: format, savedAvatars: savedAvatars),
                                    folder: "faceoff-share", name: faceOff.fileName(format))
    }
}

/// The card scaled to fit its preview.
private struct FaceOffSharePreview: View {
    let faceOff: FaceOff
    let format: BoardShareFormat
    let savedAvatars: AvatarCache?

    var body: some View {
        GeometryReader { proxy in
            let canvas = format.canvas
            let scale = min(proxy.size.width / canvas.width, proxy.size.height / canvas.height)
            FaceOffCard(faceOff: faceOff, format: format, savedAvatars: savedAvatars)
                .scaleEffect(scale)
                .frame(width: canvas.width * scale, height: canvas.height * scale)
                .clipShape(.rect(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.hairline, lineWidth: 1) }
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Face-off, \(format.title.lowercased()) image. \(faceOff.accessibilityLabel)")
    }
}

// MARK: - Sheet

/// What Share opens: the image, who you're up against (from the view you came from, changeable to
/// anyone on your board), the Window and the shape, and Share.
struct FaceOffShareSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var friend: String
    @State private var window: ContributionWindow
    @State private var format: BoardShareFormat
    @State private var sharing: SharedFile?

    init(friend: String, window: ContributionWindow, format: BoardShareFormat = .square) {
        _friend = State(initialValue: friend)
        _window = State(initialValue: window)
        _format = State(initialValue: format)
    }

    private struct SharedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private var faceOff: FaceOff? { model.faceOff(with: friend, window: window) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Group {
                    if let faceOff {
                        FaceOffSharePreview(faceOff: faceOff, format: format, savedAvatars: model.savedAvatars)
                    } else {
                        // Their calendar hasn't loaded: nothing to compare yet.
                        Text("\(friend)’s contributions are still loading.")
                            .font(.subheadline)
                            .foregroundStyle(Color.soft)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                compareRow
                    .padding(.horizontal, 24)

                Picker("Window", selection: $window) {
                    ForEach(ContributionWindow.allCases) { window in
                        Text(window.shortTitle).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)

                Picker("Format", selection: $format) {
                    ForEach(BoardShareFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)

                Button {
                    guard let faceOff else { return }
                    sharing = (try? FaceOffShareRenderer.file(faceOff, format: format, savedAvatars: model.savedAvatars))
                        .map(SharedFile.init)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LimeButtonStyle())
                .disabled(faceOff == nil)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .inkScreen()
            .navigationTitle("Share face-off")
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

    /// Who you're up against, and a menu of everyone else on your board.
    private var compareRow: some View {
        Menu {
            Picker("Compare with", selection: $friend) {
                ForEach(model.faceOffPeople, id: \.self) { login in
                    Text(login).tag(login)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text("Compare with")
                    .foregroundStyle(Color.soft)
                Spacer(minLength: 8)
                AvatarView(username: friend, size: 24)
                Text(friend)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.soft)
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 12))
        }
        .accessibilityLabel("Compare with")
        .accessibilityValue(friend)
    }
}

// MARK: - Button

/// Share, in the bar of someone else's person view, on the right with the other bar buttons as
/// Share board's is: opens the face-off sheet on the Board's current Window.
struct FaceOffShareButton: View {
    @Environment(AppModel.self) private var model
    @Environment(StandingsStore.self) private var store
    let person: PersonSummary
    @State private var sharing: FaceOffRequest?

    var body: some View {
        if !person.isYou {
            Button("Share face-off", systemImage: "square.and.arrow.up") {
                sharing = FaceOffRequest(friend: person.login, window: store.selectedWindow)
            }
            // Until both calendars have loaded there's nothing to compare.
            .disabled(model.faceOff(with: person.login, window: store.selectedWindow) == nil)
            .tint(.lime)
            .accessibilityHint("Shares a picture of you and \(person.login) side by side")
            .sheet(item: $sharing) { request in
                FaceOffShareSheet(friend: request.friend, window: request.window)
            }
        }
    }
}

private struct FaceOffRequest: Identifiable {
    let id = UUID()
    let friend: String
    let window: ContributionWindow
}
