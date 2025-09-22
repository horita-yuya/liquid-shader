import SwiftUI
import MetalKit

public struct LiquidDropletView: UIViewRepresentable {
    @State private var thickness: Float = 8
    @State private var blur: Float = 2
    @State private var chroma: Float = 0.25
    @State private var showNormals = false
    
    public init() {}

    public final class Coordinator: NSObject, MTKViewDelegate {
        var renderer: LiquidDropletRenderer?
        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        public func draw(in view: MTKView) {
            renderer?.draw(in: view)
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm

        context.coordinator.renderer = .init(mtkView: view)
        let renderer = context.coordinator.renderer!
        view.delegate = context.coordinator

        renderer.params.thickness = thickness
        renderer.params.gaussianBlur = blur
        renderer.params.chromaticAberration = chroma
        renderer.params.time = Float(CACurrentMediaTime())

        return view
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        renderer.params.thickness = thickness
        renderer.params.gaussianBlur = blur
        renderer.params.chromaticAberration = chroma
        renderer.updateUniformsBuffer()
    }
}

