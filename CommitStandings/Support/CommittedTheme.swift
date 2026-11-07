import SwiftUI

// The iPhone app's and Live rank's look: the marketing site's ink-and-lime world
// (`site/app/globals.css`), dark only. Compiled into the iPhone app and the Live rank extension,
// never the Mac app, which keeps the system look.

// MARK: - Palette

/// The site's tokens. Values are sRGB so contrast can be checked in tests (`ThemeTests`).
enum Palette {
    struct RGB: Sendable {
        let r: Double, g: Double, b: Double
        init(_ hex: UInt32) {
            r = Double((hex >> 16) & 0xff) / 255
            g = Double((hex >> 8) & 0xff) / 255
            b = Double(hex & 0xff) / 255
        }
        var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

        /// WCAG relative luminance.
        var luminance: Double {
            func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }

        init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

        /// `other` laid over this color at opacity `t`.
        func blended(with other: RGB, _ t: Double) -> RGB {
            RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
        }

        func mixed(with other: RGB, _ t: Double) -> Color { blended(with: other, t).color }
    }

    /// The page.
    static let ink = RGB(0x050505)
    /// Cards and grouped rows (the site's `--color-tile`).
    static let tile = RGB(0x0e100b)
    /// Controls on a card: secondary buttons, the code well.
    static let raised = RGB(0x1b1d17)
    /// The one accent: your rank, your row, the primary action.
    static let lime = RGB(0xc8ff2e)
    static let limeDeep = RGB(0x8bc41a)
    /// Text on a lime fill.
    static let onLime = RGB(0x1e2410)
    /// Secondary text. ~6:1 on ink and tile.
    static let muted = RGB(0x8e9288)
    /// Body copy that isn't primary.
    static let soft = RGB(0xd6d9d0)
    static let white = RGB(0xffffff)
    /// Failures ("—" with no data, stale Live rank).
    static let warning = RGB(0xff9f0a)

    /// The contribution graph, empty to busiest: the site's `--color-sq-0…3`, then lime.
    static let squares = [RGB(0x14170f), RGB(0x1d2e0e), RGB(0x355c12), RGB(0x6aa81a), lime]

    /// The rows' 2×2 squares glyph, by `SquareRamp` level: gray for no contributions (GitHub's empty
    /// square), then greens brightening to the deeper lime. Unlike `squares`, every shade is a mark
    /// in its own right (3:1 on ink, tile, and the island's black), since the glyph is drawn alone.
    /// Full lime stays the hero's and the burst's.
    static let rowGlyphs = [muted, RGB(0x4f8a14), RGB(0x6aa81a), RGB(0x7ab61a), limeDeep]

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (hi, lo) = a.luminance > b.luminance ? (a.luminance, b.luminance) : (b.luminance, a.luminance)
        return (hi + 0.05) / (lo + 0.05)
    }
}

extension Color {
    static let ink = Palette.ink.color
    static let tile = Palette.tile.color
    static let raised = Palette.raised.color
    static let lime = Palette.lime.color
    static let limeDeep = Palette.limeDeep.color
    static let onLime = Palette.onLime.color
    static let muted = Palette.muted.color
    static let soft = Palette.soft.color
    static let warning = Palette.warning.color
    /// Hairlines between rows and around cards, as on the site (`white / .08`).
    static let hairline = Color.white.opacity(0.08)
    static let contributionSquares = Palette.squares.map(\.color)
    /// The rows' squares glyph, empty to busiest (`Palette.rowGlyphs`). The board and Live rank
    /// draw the same rows, so they share it.
    static let rowGlyphs = Palette.rowGlyphs.map(\.color)
}

extension AvatarFallbackStyle {
    /// A tile with a hairline and soft initials, instead of a saturated colored circle. The board
    /// and Live rank both use it.
    static let committed = AvatarFallbackStyle(fill: .raised, stroke: .hairline, text: .soft)
}

// MARK: - Type

/// Inter Tight, the site's display face, for numbers and headlines. Body copy, labels, and
/// controls stay San Francisco. Every size scales with Dynamic Type through `relativeTo:`.
enum CommittedType {
    static let regularFace = "InterTight-Regular"
    static let displayFace = "InterTight-ExtraBold"

    /// Headlines and big numbers. Tabular digits so ranks and counts don't jitter as they change.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(displayFace, size: size, relativeTo: style).monospacedDigit()
    }

    /// Numbers that sit beside body text.
    static func numeral(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(regularFace, size: size, relativeTo: style).monospacedDigit()
    }

    /// Eyebrows and folios ("CONTRIBUTIONS", "6 PEOPLE · TODAY"): the site's monospace labels
    /// (`font-mono text-[11px] font-medium tracking-[.06em]`), uppercase.
    static let label = Font.caption2.monospaced().weight(.medium)
    /// The site's .06em at 11 pt.
    static let labelTracking: CGFloat = 0.7
}

extension View {
    /// The site's eyebrow: monospace, tracked, uppercase. It stops growing at accessibility 1,
    /// where wide monospace capitals would wrap a short label over three lines.
    func eyebrow() -> some View {
        font(CommittedType.label)
            .tracking(CommittedType.labelTracking)
            .textCase(.uppercase)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

extension View {
    /// The site's headline tracking: tight, but within the -0.04em floor at small sizes.
    func displayTracking(_ size: CGFloat) -> some View {
        tracking(-size * 0.04)
    }
}

// MARK: - Contribution squares

/// How bright a square field draws. Every field behind text uses one of these presets, and
/// `ThemeTests` checks white, soft, and lime text against each preset's brightest pixel.
struct FieldTone: Sendable {
    var brightness: Double
    /// The brightest square level drawn. Below lime (4) behind text.
    var maxLevel: Int = 3
    /// The most opaque any square gets, whatever the light. Dim squares keep their look; only the
    /// hottest ones are held back, so text over them stays at 4.5:1.
    var maxOpacity: Double = 0.45

    /// The glow under the squares, at the light's center.
    var glowOpacity: Double { 0.16 * brightness }

    /// A square's opacity where the light reaches `lit` (0…1).
    func squareOpacity(lit: Double) -> Double {
        min(min(1, lit * 1.4) * brightness, maxOpacity)
    }

    /// The brightest pixel this field can draw on `background`: the glow's center with the top
    /// square at its highest opacity.
    func brightest(on background: Palette.RGB) -> Palette.RGB {
        background
            .blended(with: Palette.lime, glowOpacity)
            .blended(with: Palette.squares[maxLevel], squareOpacity(lit: 1))
    }

    /// The Board's hero card (on tile).
    static let hero = FieldTone(brightness: 0.8)
    /// Live rank's Lock Screen card (on ink).
    static let lockScreen = FieldTone(brightness: 0.55)
    /// Connect GitHub, behind the headline (on ink).
    static let connect = FieldTone(brightness: 0.7)
    /// The Live rank relay disclosure, behind the headline (on ink).
    static let disclosure = FieldTone(brightness: 0.55)
}

/// One square of the contribution graph.
struct ContributionSquare: View {
    var level: Int
    var size: CGFloat = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        shape
            .fill(Color.contributionSquares[min(max(level, 0), Palette.squares.count - 1)])
            .overlay { shape.strokeBorder(.white.opacity(level == 0 ? 0.1 : 0), lineWidth: 1) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A field of contribution squares lit by a soft lime light, the site's hero backdrop. Pure
/// drawing, no state: pass a time to animate it (`AnimatedSquareField` in the app); the Live
/// Activity draws it still.
struct SquareFieldCanvas: View {
    /// Where the light sits, in unit coordinates.
    var light: UnitPoint = UnitPoint(x: 0.72, y: 0.3)
    /// The light's reach as a fraction of the larger side.
    var reach: Double = 0.55
    var cell: CGFloat = 18
    var gap: CGFloat = 4
    /// Seconds; 0 for a still field.
    var time: Double = 0
    var tone: FieldTone

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            draw(in: &context, size: size)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let step = cell + gap
        let columns = Int(ceil(size.width / step)) + 1
        let rows = Int(ceil(size.height / step)) + 1
        let span = max(size.width, size.height)
        let center = CGPoint(x: light.x * size.width, y: light.y * size.height)
        // The glow under the squares, like the site's wallpaper.
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [Color.lime.opacity(tone.glowOpacity), Color.limeDeep.opacity(0.05 * tone.brightness), .clear]),
                center: center, startRadius: 0, endRadius: span * reach
            )
        )
        let t = time * 0.35
        let ramp = Array(Palette.squares.prefix(max(1, min(tone.maxLevel, Palette.squares.count - 1)) + 1))
        for row in 0..<rows {
            for column in 0..<columns {
                let x = CGFloat(column) * step
                let y = CGFloat(row) * step
                let dx = (x + cell / 2 - center.x) / (span * reach)
                let dy = (y + cell / 2 - center.y) / (span * reach)
                let lit = exp(-(dx * dx + dy * dy) * 2.6)
                guard lit > 0.02 else { continue }
                // A fixed "calendar" per square, nudged by slow cosine waves (the site's shader).
                let seed = Self.hash(column, row)
                let u = Double(column) / Double(columns), v = Double(row) / Double(rows)
                let wave = (cos(3 * u + t) + cos(u * cos(t) + 5 * v * sin(t) + t)) / 4 + 0.5
                let value = min(max((0.62 * seed + 0.38 * wave) * (0.35 + 0.9 * lit), 0), 0.999) * Double(ramp.count - 1)
                let level = Int(value)
                let next = min(level + 1, ramp.count - 1)
                // Ease between levels so moving squares fade rather than pop.
                let blend = max(0, (value - Double(level) - 0.7) / 0.3)
                let rect = CGRect(x: x, y: y, width: cell, height: cell)
                context.opacity = tone.squareOpacity(lit: lit)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: cell * 0.22, style: .continuous),
                    with: .color(ramp[level].mixed(with: ramp[next], blend))
                )
            }
        }
    }

    private static func hash(_ a: Int, _ b: Int) -> Double {
        var x = Double(a) * 123.34, y = Double(b) * 456.21
        x = x - floor(x); y = y - floor(y)
        let d = x * (x + 45.32) + y * (y + 45.32)
        x += d; y += d
        let p = x * y
        return p - floor(p)
    }
}

// MARK: - The trophy

/// The Committed mark: the GitHub-cat trophy (`docs/design/committed-trophy-glyph.svg`).
struct TrophyGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 16
        let offset = CGPoint(x: rect.midX - 8 * scale, y: rect.midY - 8 * scale)
        return Self.unitPath.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: offset.x, ty: offset.y))
    }

    /// The 16 × 16 glyph, parsed once from the SVG path (M, C, and Z only).
    private static let unitPath: Path = {
        var path = Path()
        let tokens = svg.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        var index = 0
        func number() -> CGFloat { defer { index += 1 }; return CGFloat(Double(tokens[index]) ?? 0) }
        func point() -> CGPoint { let x = number(); return CGPoint(x: x, y: number()) }
        while index < tokens.count {
            let command = tokens[index]; index += 1
            switch command {
            case "M": path.move(to: point())
            case "C":
                let c1 = point(), c2 = point()
                path.addCurve(to: point(), control1: c1, control2: c2)
            case "Z": path.closeSubpath()
            default: break
            }
        }
        return path
    }()

    private static let svg = "M 0.945 3.391 C 1.309 3.184 1.699 3.16 2.09 3.152 C 2.359 3.148 2.629 3.152 2.895 3.148 C 3.066 3.148 3.082 3.125 3.062 2.961 C 3 2.359 3.023 1.758 3.18 1.172 C 3.266 0.848 3.551 0.672 3.879 0.746 C 4.508 0.883 5.012 1.238 5.488 1.648 C 5.508 1.668 5.531 1.684 5.543 1.703 C 5.75 2.004 6 2.02 6.348 1.918 C 7.281 1.645 8.238 1.613 9.203 1.793 C 9.477 1.848 9.746 1.914 10.008 1.996 C 10.113 2.031 10.18 2.012 10.254 1.934 C 10.695 1.453 11.219 1.082 11.824 0.84 C 12.039 0.754 12.262 0.656 12.508 0.758 C 12.68 0.824 12.793 0.938 12.855 1.105 C 12.945 1.348 12.98 1.605 13 1.863 C 13.023 2.215 13.039 2.57 12.988 2.926 C 12.957 3.137 12.977 3.148 13.191 3.152 C 13.578 3.16 13.965 3.145 14.352 3.172 C 15.027 3.215 15.68 3.73 15.887 4.379 C 16.055 4.895 16.008 5.414 15.93 5.934 C 15.832 6.57 15.602 7.16 15.262 7.711 C 14.785 8.484 14.148 9.086 13.359 9.523 C 12.438 10.035 11.441 10.293 10.391 10.371 C 9.973 10.398 9.625 10.648 9.633 11.141 C 9.637 11.574 9.594 12.008 9.707 12.43 C 9.863 13.016 10.199 13.445 10.824 13.578 C 10.973 13.613 11.129 13.605 11.277 13.648 C 11.828 13.812 12.066 14.555 11.703 14.996 C 11.555 15.176 11.359 15.246 11.129 15.246 C 9.688 15.242 8.246 15.246 6.805 15.246 C 6.199 15.246 5.598 15.246 4.996 15.246 C 4.555 15.246 4.262 15.012 4.195 14.609 C 4.129 14.207 4.371 13.793 4.75 13.664 C 4.887 13.621 5.031 13.609 5.172 13.586 C 5.609 13.512 5.938 13.27 6.152 12.883 C 6.316 12.59 6.395 12.27 6.41 11.938 C 6.426 11.672 6.414 11.402 6.414 11.133 C 6.418 10.664 6.086 10.387 5.645 10.363 C 4.465 10.297 3.363 9.977 2.363 9.344 C 1.344 8.695 0.664 7.777 0.254 6.648 C 0.016 5.988 -0.059 5.312 0.043 4.625 C 0.125 4.078 0.445 3.668 0.945 3.391 Z M 1.68 6.645 C 2.086 7.574 3.492 8.773 4.082 8.695 C 4.082 8.684 4.082 8.672 4.078 8.664 C 4.055 8.621 4.027 8.574 3.996 8.535 C 3.551 7.879 3.238 7.168 3.086 6.391 C 2.969 5.781 2.906 5.16 2.984 4.535 C 3 4.41 2.961 4.355 2.828 4.359 C 2.59 4.363 2.352 4.355 2.117 4.359 C 1.723 4.367 1.422 4.629 1.391 5 C 1.34 5.562 1.426 6.109 1.68 6.645 Z M 14.621 5.926 C 14.672 5.676 14.707 5.422 14.695 5.16 C 14.676 4.648 14.391 4.363 13.879 4.359 C 13.68 4.359 13.484 4.367 13.289 4.355 C 13.152 4.352 13.113 4.395 13.129 4.535 C 13.203 5.246 13.137 5.953 12.961 6.645 C 12.812 7.234 12.566 7.789 12.25 8.312 C 12.176 8.434 12.078 8.539 12.031 8.684 C 12.992 8.461 14.246 7.473 14.621 5.926 Z"
}

/// The trophy as an icon: lime, scaled with the text it sits beside.
struct TrophyMark: View {
    var size: CGFloat = 20
    var color: Color = .lime

    var body: some View {
        TrophyGlyph()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
