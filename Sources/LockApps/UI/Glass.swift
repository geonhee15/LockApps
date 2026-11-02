import SwiftUI
import AppKit

/// Screenshot runs render the window offscreen (`cacheDisplay`), where behind-window blur and Liquid Glass come out
/// empty. Flat mode swaps them for plain translucent fills over a painted "wallpaper" so README images still read as glass.
enum RenderMode {
    static let flat: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["LOCKAPPS_FLAT_GLASS"] == "1" || env["LOCKAPPS_SNAPSHOT"] != nil || env["LOCKAPPS_SNAPSHOT_PROMPT"] != nil
    }()
}

/// Stand-in for the desktop behind the window (flat mode only): soft gradient + frosted layer.
struct SimulatedWallpaper: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.09, green: 0.11, blue: 0.28), Color(red: 0.30, green: 0.14, blue: 0.42), Color(red: 0.07, green: 0.28, blue: 0.42)]
                    : [Color(red: 0.52, green: 0.70, blue: 1.00), Color(red: 0.84, green: 0.70, blue: 0.96), Color(red: 1.00, green: 0.80, blue: 0.64)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(colors: [Color.white.opacity(scheme == .dark ? 0.10 : 0.45), .clear], center: .center, startRadius: 0, endRadius: 260)
                .frame(width: 520, height: 520)
                .offset(x: -170, y: -240)
            RadialGradient(colors: [(scheme == .dark ? Color.purple : Color.orange).opacity(0.40), .clear], center: .center, startRadius: 0, endRadius: 300)
                .frame(width: 600, height: 600)
                .offset(x: 220, y: 280)
            VisualEffectBackdrop(material: .popover, blending: .withinWindow)
        }
    }
}

/// Fake traffic lights for flat-mode captures (the real ones live in the window frame, outside the content view).
struct FakeTrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34))
            Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18))
            Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.26))
        }
        .frame(width: 52, height: 12)
    }
}

/// Liquid Glass on macOS 26, a translucent material with a hairline on older systems.
/// Used for the floating controls (search field, bottom bar, unlock card) — content rows stay flat cards.
struct GlassSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat
    var interactive: Bool
    var tint: Color?

    func body(content: Content) -> some View {
        if RenderMode.flat {
            content
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(scheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.62))
                )
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(tint?.opacity(0.18) ?? Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(scheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.75), lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.10), radius: 14, y: 6)
        } else if #available(macOS 26.0, *) {
            let glass: Glass = {
                var g = Glass.regular
                if let tint { g = g.tint(tint) }
                if interactive { g = g.interactive() }
                return g
            }()
            content.glassEffect(glass, in: .rect(cornerRadius: radius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(tint?.opacity(0.18) ?? Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(scheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.7), lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.10), radius: 14, y: 6)
        }
    }
}

extension View {
    func glass(radius: CGFloat = 18, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(GlassSurface(radius: radius, interactive: interactive, tint: tint))
    }
}

/// Behind-window blur used as the window / overlay backdrop (NSVisualEffectView).
struct VisualEffectBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = emphasized
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.isEmphasized = emphasized
    }
}

/// Small press-scale feedback for custom buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
