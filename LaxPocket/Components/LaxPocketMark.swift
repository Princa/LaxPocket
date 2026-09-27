import SwiftUI

/// Vector paths for the LaxPocket mark, drawn in a 100 × 100 box:
/// a field-lacrosse head with shooting strings, a short handle, and a growth arrow in the pocket.
enum MarkPaths {
    static let head: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 26, y: 13))
        p.addCurve(to: CGPoint(x: 74, y: 13), control1: CGPoint(x: 38, y: 17), control2: CGPoint(x: 62, y: 17))
        p.addCurve(to: CGPoint(x: 80, y: 23), control1: CGPoint(x: 79, y: 12), control2: CGPoint(x: 81, y: 17))
        p.addCurve(to: CGPoint(x: 71, y: 44), control1: CGPoint(x: 79, y: 31), control2: CGPoint(x: 76, y: 38))
        p.addCurve(to: CGPoint(x: 61, y: 61), control1: CGPoint(x: 66, y: 50), control2: CGPoint(x: 63, y: 55))
        p.addCurve(to: CGPoint(x: 56, y: 84), control1: CGPoint(x: 59, y: 68), control2: CGPoint(x: 57, y: 76))
        p.addLine(to: CGPoint(x: 44, y: 84))
        p.addCurve(to: CGPoint(x: 39, y: 61), control1: CGPoint(x: 43, y: 76), control2: CGPoint(x: 41, y: 68))
        p.addCurve(to: CGPoint(x: 29, y: 44), control1: CGPoint(x: 37, y: 55), control2: CGPoint(x: 34, y: 50))
        p.addCurve(to: CGPoint(x: 20, y: 23), control1: CGPoint(x: 24, y: 38), control2: CGPoint(x: 21, y: 31))
        p.addCurve(to: CGPoint(x: 26, y: 13), control1: CGPoint(x: 19, y: 17), control2: CGPoint(x: 21, y: 12))
        p.closeSubpath()
        return p
    }()

    static let strings: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 23, y: 22))
        p.addQuadCurve(to: CGPoint(x: 77, y: 22), control: CGPoint(x: 50, y: 27))
        p.move(to: CGPoint(x: 24.5, y: 29))
        p.addQuadCurve(to: CGPoint(x: 75.5, y: 29), control: CGPoint(x: 50, y: 34))
        return p
    }()

    static let handle: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 50, y: 84))
        p.addLine(to: CGPoint(x: 50, y: 97))
        return p
    }()

    static let arrow: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 50, y: 72))
        p.addLine(to: CGPoint(x: 50, y: 40))
        p.move(to: CGPoint(x: 41.5, y: 48.5))
        p.addLine(to: CGPoint(x: 50, y: 40))
        p.addLine(to: CGPoint(x: 58.5, y: 48.5))
        return p
    }()
}

/// The mark on its own. `.inline` crops tightly for use beside the wordmark;
/// `.icon` adds the padding used inside the app icon.
struct LaxPocketMark: View {
    enum Style {
        case inline
        case icon
    }

    var frameColor: Color = .white
    var arrowColor: Color
    var style: Style = .inline

    var body: some View {
        Canvas { context, size in
            let box: CGRect
            let widths: (strings: CGFloat, head: CGFloat, handle: CGFloat, arrow: CGFloat)
            switch style {
            case .inline:
                box = CGRect(x: 14, y: 8, width: 72, height: 92)
                widths = (4, 7, 8, 8)
            case .icon:
                box = CGRect(x: 50 - 59.52, y: 50 - 59.52, width: 119.05, height: 119.05)
                widths = (2.6, 6, 7, 7)
            }
            let scale = min(size.width / box.width, size.height / box.height)
            let transform = CGAffineTransform(translationX: size.width / 2 - box.midX * scale, y: size.height / 2 - box.midY * scale)
                .scaledBy(x: scale, y: scale)

            context.stroke(MarkPaths.strings.applying(transform), with: .color(frameColor.opacity(0.7)),
                           style: StrokeStyle(lineWidth: widths.strings * scale))
            context.stroke(MarkPaths.head.applying(transform), with: .color(frameColor),
                           style: StrokeStyle(lineWidth: widths.head * scale, lineJoin: .round))
            context.stroke(MarkPaths.handle.applying(transform), with: .color(frameColor),
                           style: StrokeStyle(lineWidth: widths.handle * scale, lineCap: .round))
            context.stroke(MarkPaths.arrow.applying(transform), with: .color(arrowColor),
                           style: StrokeStyle(lineWidth: widths.arrow * scale, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// The full app icon (rounded square + mark), used on the Theme screen.
struct AppIconPreview: View {
    let theme: AppTheme
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
            .fill(theme.primary)
            .overlay(LaxPocketMark(frameColor: .white, arrowColor: theme.iconAccent, style: .icon))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// "LaxPocket" with the mark, for coloured headers.
struct Wordmark: View {
    let theme: AppTheme
    var size: CGFloat = 23

    var body: some View {
        HStack(spacing: 8) {
            LaxPocketMark(frameColor: .white, arrowColor: theme.iconAccent)
                .frame(width: size * 0.95, height: size * 1.2)
            (Text("Lax").foregroundColor(theme.onPrimary) + Text("Pocket").foregroundColor(.white))
                .font(.display(size))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("LaxPocket")
    }
}
