import BotAvatarsKit
import MetalKit
import SwiftUI

extension MarkVariant {
    /// The orb takes its three pigments from the chosen robot: base, light, shadow.
    var orbColors: (base: Int, light: Int, dark: Int) {
        switch self {
        case .paper: return (0xD9A066, 0xFFF1D6, 0x4A4038)
        case .blue: return (0x3D82E8, 0xCDEBFF, 0x1F2F6B)
        case .coral: return (0xE8754D, 0xFFE0AC, 0x7A2F2A)
        case .green: return (0x4DAA7A, 0xE4F6C8, 0x1F4D3F)
        case .violet: return (0x7C6BF0, 0xE7DCFF, 0x2E2470)
        default:
            // A bot avatar's own colour, with a pale and a deep version of it.
            let color = avatarType?.paletteColor
            func hex(_ transform: (Double) -> Double) -> Int {
                [color?.r ?? 128, color?.g ?? 128, color?.b ?? 128].reduce(0) { $0 << 8 | Int(min(255, max(0, transform($1)))) }
            }
            return (hex { $0 }, hex { $0 + (255 - $0) * 0.75 }, hex { $0 * 0.34 })
        }
    }
}

/// A liquid sphere that swells with the voice it is given. It never opens an
/// audio source itself, and holds still with Reduce Motion.
struct VoiceOrb: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 (quiet) to 1 (loud).
    var level: Double = 0
    var size: CGFloat
    /// An inactive orb is drawn once and left still.
    var active = true

    var body: some View {
        Group {
            if OrbRenderer.shared != nil {
                OrbSurface(level: level, colors: model.mark.orbColors, moving: active && !reduceMotion)
            } else {
                Circle().fill(Theme.subtle)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The compiled shader, shared by every orb.
@MainActor
final class OrbRenderer {
    struct Uniforms {
        var size: SIMD2<Float>
        var time: Float
        var activity: Float
        var base: SIMD4<Float>
        var light: SIMD4<Float>
        var dark: SIMD4<Float>
    }

    static let shared = OrbRenderer()

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: VoiceOrbShader.source, options: nil) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "orbVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "orbFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }

    static func color(_ hex: Int) -> SIMD4<Float> {
        SIMD4(Float(hex >> 16 & 255) / 255, Float(hex >> 8 & 255) / 255, Float(hex & 255) / 255, 1)
    }

    func draw(_ uniforms: Uniforms, into pass: MTLRenderPassDescriptor, present drawable: MTLDrawable?) -> MTLCommandBuffer? {
        guard let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        var uniforms = uniforms
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        if let drawable { buffer.present(drawable) }
        buffer.commit()
        return buffer
    }
}

private struct OrbSurface: NSViewRepresentable {
    var level: Double
    var colors: (base: Int, light: Int, dark: Int)
    var moving: Bool

    func makeNSView(context: Context) -> OrbView { OrbView() }

    func updateNSView(_ view: OrbView, context: Context) {
        view.target = Float(level.isFinite ? min(1, max(0, level)) : 0)
        view.colors = (OrbRenderer.color(colors.base), OrbRenderer.color(colors.light), OrbRenderer.color(colors.dark))
        view.isPaused = !moving
        view.enableSetNeedsDisplay = !moving
        if !moving { view.needsDisplay = true }
    }
}

private final class OrbView: MTKView, MTKViewDelegate {
    var target: Float = 0
    var colors = (SIMD4<Float>.zero, SIMD4<Float>.zero, SIMD4<Float>.zero)
    private var activity: Float = 0
    private var time: Float = 0
    private var last: CFTimeInterval?

    init() {
        super.init(frame: .zero, device: OrbRenderer.shared?.device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        preferredFramesPerSecond = 30
        layer?.isOpaque = false
        delegate = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    /// Decoration only: clicks belong to the view around it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { needsDisplay = true }

    func draw(in view: MTKView) {
        // Nothing is drawn while the window cannot be seen.
        guard window?.occlusionState.contains(.visible) == true,
              let pass = currentRenderPassDescriptor, let drawable = currentDrawable else { return }
        let now = CACurrentMediaTime()
        if !isPaused {
            // Eases toward the voice so the surface swells rather than jumps.
            activity += (target - activity) * 0.22
            time += Float(min(0.05, now - (last ?? now))) * (1 + activity * 0.6)
        } else {
            activity = 0
        }
        last = now
        _ = OrbRenderer.shared?.draw(.init(size: SIMD2(Float(drawableSize.width), Float(drawableSize.height)), time: time,
                                           activity: activity, base: colors.0, light: colors.1, dark: colors.2),
                                     into: pass, present: drawable)
    }
}
