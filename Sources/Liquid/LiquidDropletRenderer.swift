import Foundation
import MetalKit
import simd

struct DropletParams {
    var uSize: SIMD2<Float>
    var thickness: Float
    var ior: Float
    var chromaticAberration: Float
    var lightAngle: Float
    var lightIntensity: Float
    var ambientStrength: Float
    var gaussianBlur: Float
    var shapeCenter: SIMD2<Float>
    var shapeRadius: Float
    var time: Float
}


final class LiquidDropletRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState

    private var vbuf: MTLBuffer!
    private var ubuf: MTLBuffer!

    private var bgTexture: MTLTexture!

    var params = DropletParams(
        uSize: .zero,
        thickness: 32.0,
        ior: 1.65,
        chromaticAberration: 0.08,
        lightAngle: .pi * 0.25,
        lightIntensity: 1.0,
        ambientStrength: 0.25,
        gaussianBlur: 10.0,
        shapeCenter: SIMD2(0.5, 0.5),
        shapeRadius: 0.28,
        time: 0
    )


    init?(mtkView: MTKView) {
        guard let dev = mtkView.device ?? MTLCreateSystemDefaultDevice() else { return nil }
        device = dev
        queue = dev.makeCommandQueue()!

        let library = try! device.makeDefaultLibrary(bundle: .module)

        let vfn = library.makeFunction(name: "vsMain2")!
        let ffn = library.makeFunction(name: "fsDroplet")!
        
        mtkView.colorPixelFormat = .bgra8Unorm_srgb

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        pipeline = try! device.makeRenderPipelineState(descriptor: desc)

        let sdesc = MTLSamplerDescriptor()
        sdesc.minFilter = .linear
        sdesc.magFilter = .linear
        sdesc.sAddressMode = .clampToEdge
        sdesc.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: sdesc)!
        
        super.init()
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        mtkView.addGestureRecognizer(tap)
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        mtkView.addGestureRecognizer(pan)
        
        let verts: [Float] = [
            //   x,   y,   u,   v
            -1, -1,  0,   1,
             1, -1,  1,   1,
            -1,  1,  0,   0,
             1,  1,  1,   0,
        ]
        vbuf = device.makeBuffer(bytes: verts, length: verts.count * MemoryLayout<Float>.size)!

        bgTexture = Self.makeImageTexture(device: device, name: "pic_c.jpg") ?? Self.makeCheckerTexture(device: device, width: 1024, height: 1024, tile: 64)
        params.uSize = SIMD2(Float(bgTexture.width), Float(bgTexture.height))

        ubuf = device.makeBuffer(length: MemoryLayout<DropletParams>.stride, options: [])
        updateUniformsBuffer()
    }

    func updateUniformsBuffer() {
        var p = params
        
        p.thickness = max(0, p.thickness)
        p.gaussianBlur = max(0, p.gaussianBlur)
        p.shapeCenter.x = simd_clamp(p.shapeCenter.x, 0, 1)
        p.shapeCenter.y = simd_clamp(p.shapeCenter.y, 0, 1)
        p.shapeRadius   = simd_clamp(p.shapeRadius, 0.0, 0.5)

        memcpy(ubuf.contents(), &p, MemoryLayout<DropletParams>.stride)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor else { return }

        let t = Float(CACurrentMediaTime())
        params.time = t
        updateUniformsBuffer()

        let cmd = queue.makeCommandBuffer()!
        let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)!
        enc.setRenderPipelineState(pipeline)

        enc.setVertexBuffer(vbuf, offset: 0, index: 0)
        enc.setFragmentBuffer(ubuf, offset: 0, index: 1)
        enc.setFragmentTexture(bgTexture, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)

        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cmd.present(drawable)
        cmd.commit()
    }

    static func makeCheckerTexture(device: MTLDevice, width: Int, height: Int, tile: Int) -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                            width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead]
        let tex = device.makeTexture(descriptor: desc)!

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let cx = (x / tile) & 1
                let cy = (y / tile) & 1
                let on = (cx ^ cy) == 0
                let base: UInt8 = on ? 230 : 200
                let idx = (y * width + x) * 4
                pixels[idx+0] = base
                pixels[idx+1] = base
                pixels[idx+2] = base
                pixels[idx+3] = 255
            }
        }
        let region = MTLRegionMake2D(0, 0, width, height)
        tex.replace(region: region, mipmapLevel: 0, withBytes: pixels, bytesPerRow: width * 4)
        return tex
    }
    
    static func makeImageTexture(device: MTLDevice,
                                 name: String,
                                 bundle: Bundle = .main) -> MTLTexture? {
        guard let url = bundle.url(forResource: name, withExtension: nil) else {
            print("Image not found in bundle: \(name)")
            return nil
        }
        let loader = MTKTextureLoader(device: device)
        do {
            let opts: [MTKTextureLoader.Option: Any] = [
                .SRGB: true,
                .origin: MTKTextureLoader.Origin.topLeft
            ]
            let tex = try loader.newTexture(URL: url, options: opts)
            tex.label = "ImageTexture:\(name)"
            return tex
        } catch {
            print("Texture load failed:", error)
            return nil
        }
    }
    
    private func pointToUV(_ pt: CGPoint, in view: MTKView) -> SIMD2<Float> {
        let ds = view.drawableSize
        let sx = ds.width  / Double(view.bounds.width)
        let sy = ds.height / Double(view.bounds.height)

        let px = Double(pt.x) * sx
        let py = Double(pt.y) * sy

        let u = max(0.0, min(1.0, px / ds.width))
        let v = max(0.0, min(1.0, py / ds.height))
        return SIMD2(Float(u), Float(v))
    }

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        guard let view = gr.view as? MTKView else { return }
        let p = gr.location(in: view)
        params.shapeCenter = pointToUV(p, in: view)
        updateUniformsBuffer()
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let view = gr.view as? MTKView else { return }
        let p = gr.location(in: view)
        params.shapeCenter = pointToUV(p, in: view)
        updateUniformsBuffer()
    }
}


