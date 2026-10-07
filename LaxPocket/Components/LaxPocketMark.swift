import SwiftUI

/// Vector paths for the SportsPocket mark, drawn in a 100 × 100 box: a stitched pocket holding a ball drawn as the
/// weekly-goal ring. The same shapes as docs/app-icon.svg, which the app icons are made from.
enum MarkPaths {
    static let stitch: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 23, y: 32))
        p.addLine(to: CGPoint(x: 77, y: 32))
        return p
    }()

    static let pocket: Path = {
        var p = Path()
        p.addLines([CGPoint(x: 18, y: 25), CGPoint(x: 82, y: 25), CGPoint(x: 79, y: 66), CGPoint(x: 50, y: 86), CGPoint(x: 21, y: 66)])
        p.closeSubpath()
        return p
    }()

    static let ring = Path(ellipseIn: CGRect(x: 36, y: 38, width: 28, height: 28))

    /// Three quarters of the ring, clockwise from the top.
    static let progress: Path = {
        var p = Path()
        p.addArc(center: CGPoint(x: 50, y: 52), radius: 14, startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: false)
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
    var accentColor: Color
    var style: Style = .inline

    var body: some View {
        Canvas { context, size in
            let box: CGRect
            let widths: (stitch: CGFloat, pocket: CGFloat, ring: CGFloat)
            switch style {
            case .inline:
                box = CGRect(x: 14, y: 20, width: 72, height: 72)
                widths = (3.5, 7, 7)
            case .icon:
                box = CGRect(x: 50 - 59.52, y: 50 - 59.52, width: 119.05, height: 119.05)
                widths = (2.6, 6, 6)
            }
            let scale: CGFloat = min(size.width / box.width, size.height / box.height)
            let dx: CGFloat = size.width / 2 - box.midX * scale
            let dy: CGFloat = size.height / 2 - box.midY * scale
            let transform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)

            context.stroke(MarkPaths.stitch.applying(transform), with: .color(frameColor.opacity(0.7)),
                           style: StrokeStyle(lineWidth: widths.stitch * scale, lineCap: .round, dash: [4 * scale, 4 * scale]))
            context.stroke(MarkPaths.pocket.applying(transform), with: .color(frameColor),
                           style: StrokeStyle(lineWidth: widths.pocket * scale, lineJoin: .round))
            context.stroke(MarkPaths.ring.applying(transform), with: .color(frameColor.opacity(0.35)),
                           style: StrokeStyle(lineWidth: widths.ring * scale))
            context.stroke(MarkPaths.progress.applying(transform), with: .color(accentColor),
                           style: StrokeStyle(lineWidth: widths.ring * scale, lineCap: .round))
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
            .overlay(LaxPocketMark(frameColor: .white, accentColor: theme.iconAccent, style: .icon))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// "SportsPocket" with the mark, for coloured headers.
struct Wordmark: View {
    let theme: AppTheme
    var size: CGFloat = 23

    var body: some View {
        HStack(spacing: 8) {
            LaxPocketMark(frameColor: .white, accentColor: theme.iconAccent)
                .frame(width: size * 1.05, height: size * 1.05)
            (Text("Sports").foregroundColor(theme.onPrimary) + Text("Pocket").foregroundColor(.white))
                .font(.display(size))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SportsPocket")
    }
}
