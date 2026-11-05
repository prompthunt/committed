import SwiftUI

/// Keeps a centered column of controls out of a fold that runs down the screen (iPhone Duo held
/// partially folded like a book). Instead of straddling the fold, the column moves into the wider
/// side, or the trailing side when the halves are equal, since that's where things keep appearing
/// as the device closes. A fold that runs across the screen (tabletop in portrait) is left alone:
/// these columns scroll, and scrolling content may pass under the fold.
///
/// Use it only for custom centered layouts. System bars, lists, sheets, and alerts already avoid
/// the fold on their own.
enum FoldAvoidance {
    struct Insets: Equatable {
        var leading: CGFloat
        var trailing: CGFloat
    }

    /// `divisions` are active division regions in the view's leading-based coordinates, as
    /// `GeometryProxy.reservedRegions(kind: .division)` reports them. Their frames already include
    /// the clearance the system keeps for controls, so no extra padding is added.
    static func insets(width: CGFloat, divisions: [CGRect]) -> Insets {
        let folds = divisions.filter { $0.height > $0.width && $0.maxX > 0 && $0.minX < width }
        guard let fold = folds.max(by: { $0.width < $1.width }) else { return Insets(leading: 0, trailing: 0) }
        let leadingSide = max(fold.minX, 0)
        let trailingSide = max(width - fold.maxX, 0)
        return trailingSide >= leadingSide
            ? Insets(leading: width - trailingSide, trailing: 0)
            : Insets(leading: 0, trailing: width - leadingSide)
    }
}

extension View {
    /// Moves this view to one side of an active vertical fold. See `FoldAvoidance`.
    func avoidingFold() -> some View {
        modifier(FoldAvoidingModifier())
    }
}

private struct FoldAvoidingModifier: ViewModifier {
    @State private var insets = FoldAvoidance.Insets(leading: 0, trailing: 0)

    func body(content: Content) -> some View {
        content
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: FoldAvoidance.Insets.self) { proxy in
                let divisions = proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
                return FoldAvoidance.insets(width: proxy.size.width, divisions: divisions)
            } action: { insets = $0 }
    }
}
