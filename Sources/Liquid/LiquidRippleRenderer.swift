import Foundation
import MetalKit
import simd

struct RippleParams {
    var uSize: SIMD2<Float>
    var thickness: Float
    var refractiveIndex: Float
    var chromaticAberration: Float
    var lightAngle: Float
    var lightIntensity: Float
    var ambientStrength: Float
    var gaussianBlur: Float
    var saturation: Float
    var lightness: Float
    var shapeCenter: SIMD2<Float>
    var shapeRadius: Float
    var time: Float
    
    var rippleCount: Int32
    var rippleAmplitude: Float
    var rippleFrequencyHz: Float
    var rippleSpeedPxPerSec: Float
    var rippleDecayTime: Float
    var rippleDecayDist: Float
    var rippleNormalScale: Float
    
    var reflectStrength: Float
    var reflectDistancePx: Float
    var specularIntensity: Float
    var specularShininess: Float
    var envRotation: Float
    
    var fresnelIor: Float
}

final class LiquidRippleRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState

    private var vbuf: MTLBuffer!
    private var ubuf: MTLBuffer!

    private var bgTexture: MTLTexture!

    var params = RippleParams(
        uSize: .zero,
        thickness: 4.0,
        refractiveIndex: 1.70,
        chromaticAberration: 0.02,
        lightAngle: .pi * 0.25,
        lightIntensity: 0.8,
        ambientStrength: 0.30,
        gaussianBlur: 1.2,
        saturation: 0.95,
        lightness: 0.98,
        shapeCenter: SIMD2(0.5, 0.5),
        shapeRadius: 0.28,
        time: 0,
        
        rippleCount: 0,
        rippleAmplitude: 40.0,
        rippleFrequencyHz: 1,
        rippleSpeedPxPerSec: 280,
        rippleDecayTime: 1.2,
        rippleDecayDist: 0.002,
        rippleNormalScale: 3.0,
        
        reflectStrength    : 1.0,
        reflectDistancePx  : 200.0,
        specularIntensity  : 0.55,
        specularShininess  : 80,
        envRotation        : 0.0,
        fresnelIor: 1.9,
    )
    
    private let MAX_RIPPLES = 16
    private var rippleBuf: MTLBuffer!
    // (u, v, startTime, 0)
    private var rippleData = [SIMD4<Float>]()

    init?(mtkView: MTKView) {
        guard let dev = mtkView.device ?? MTLCreateSystemDefaultDevice() else { return nil }
        device = dev
        queue = dev.makeCommandQueue()!

        let library = try! device.makeDefaultLibrary(bundle: .module)

        let vfn = library.makeFunction(name: "vsMain")!
        let ffn = library.makeFunction(name: "fsRipple")!
        
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
        
        // Full screen quad
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

        ubuf = device.makeBuffer(length: MemoryLayout<RippleParams>.stride, options: [])
        updateUniformsBuffer()
        
        rippleBuf = device.makeBuffer(
            length: MemoryLayout<SIMD4<Float>>.stride * MAX_RIPPLES,
            options: []
        )
        rippleBuf.label = "RippleBuffer"
    }

    func updateUniformsBuffer() {
        var p = params
        // clamp for safety
        p.thickness = max(0, p.thickness)
        p.gaussianBlur = max(0, p.gaussianBlur)
        p.shapeCenter.x = simd_clamp(p.shapeCenter.x, 0, 1)
        p.shapeCenter.y = simd_clamp(p.shapeCenter.y, 0, 1)
        p.shapeRadius   = simd_clamp(p.shapeRadius, 0.0, 0.5)
        
        memcpy(ubuf.contents(), &p, MemoryLayout<RippleParams>.stride)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor else { return }
        
        let t = Float(CACurrentMediaTime())
        params.time = t
        params.rippleCount = Int32(min(rippleData.count, MAX_RIPPLES))
        updateUniformsBuffer()
        
        if !rippleData.isEmpty {
            let n = min(rippleData.count, MAX_RIPPLES)
            rippleData.withUnsafeBytes { src in
                memcpy(rippleBuf.contents(), src.baseAddress!, n * MemoryLayout<SIMD4<Float>>.stride)
            }
        }
        
        let cmd = queue.makeCommandBuffer()!
        let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)!
        enc.setRenderPipelineState(pipeline)

        enc.setVertexBuffer(vbuf, offset: 0, index: 0)
        enc.setFragmentBuffer(ubuf, offset: 0, index: 1)
        enc.setFragmentBuffer(rippleBuf, offset: 0, index: 2)
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
        let uv = pointToUV(gr.location(in: view), in: view)

        let start = Float(CACurrentMediaTime())
        if rippleData.count >= MAX_RIPPLES { rippleData.removeFirst() }
        rippleData.append(SIMD4<Float>(uv.x, uv.y, start, 0))
        updateUniformsBuffer()
    }
    
    private var lastRippleTime: CFTimeInterval = 0
    // The interval between ripples in seconds
    private let rippleInterval: CFTimeInterval = 0.5

    private func addRipple(at uv: SIMD2<Float>) {
        let now = CACurrentMediaTime()
        if now - lastRippleTime < rippleInterval { return }
        lastRippleTime = now

        if rippleData.count >= MAX_RIPPLES {
            rippleData.removeFirst()
        }
        
        rippleData.append(SIMD4<Float>(uv.x, uv.y, Float(now), 0))
        updateUniformsBuffer()
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let view = gr.view as? MTKView else { return }
           let uv = pointToUV(gr.location(in: view), in: view)

           switch gr.state {
           case .began:
               lastRippleTime = 0
               addRipple(at: uv)
           case .changed:
               addRipple(at: uv)
           case .ended, .cancelled, .failed:
               lastRippleTime = 0
           default:
               break
           }
    }
}


