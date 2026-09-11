import AppKit
import MetalKit
import MetalPerformanceShaders
import OSLog

enum FoldError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

final class FoldTextures {
    let levels: [MTLTexture]
    init(_ levels: [MTLTexture]) { self.levels = levels }
}

final class FoldGPU {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState

    init(shaderURL: URL? = Bundle.main.url(forResource: "Fold", withExtension: "metal")) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw AppMessage(key: "metal_unavailable")
        }
        self.device = device
        self.queue = queue
        guard let shaderURL else {
            throw AppMessage(key: "shader_missing")
        }
        let library = try device.makeLibrary(source: String(contentsOf: shaderURL, encoding: .utf8), options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "foldVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "foldFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func textures(for image: CGImage) throws -> FoldTextures {
        let loader = MTKTextureLoader(device: device)
        let source = try loader.newTexture(cgImage: image, options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft])
        let width = min(1280, image.width)
        let height = max(1, image.height * width / image.width)
        func texture() throws -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
            d.usage = [.shaderRead, .shaderWrite]
            guard let t = device.makeTexture(descriptor: d) else { throw AppMessage(key: "blur_memory") }
            return t
        }
        guard let command = queue.makeCommandBuffer() else { throw AppMessage(key: "metal_buffer") }
        let reduced = try texture()
        MPSImageLanczosScale(device: device).encode(commandBuffer: command, sourceTexture: source, destinationTexture: reduced)
        var levels = [source]
        for radius in [6.0, 18.0, 42.0, 96.0] {
            let dest = try texture()
            let blur = MPSImageGaussianBlur(device: device, sigma: Float(radius * Double(width) / 2560.0))
            blur.edgeMode = .clamp
            blur.encode(commandBuffer: command, sourceTexture: reduced, destinationTexture: dest)
            levels.append(dest)
        }
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        return FoldTextures(levels)
    }

    func encode(_ command: MTLCommandBuffer, pass: MTLRenderPassDescriptor, textures: FoldTextures, angle: Double, settings: FoldSettings) {
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        let state = FoldState.at(angle: angle, settings: settings)
        var uniforms = SIMD4<Float>(state.progress, state.projection, Float(settings.blur), Float(settings.darkness))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        for (i, texture) in textures.levels.enumerated() { encoder.setFragmentTexture(texture, index: i) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

final class FoldRenderer: NSObject, MTKViewDelegate {
    let gpu: FoldGPU
    weak var view: MTKView?
    var textures: FoldTextures?
    var angle: Double = 90
    var settings = FoldSettings()
    var firstFrameReady: (() -> Void)?
    private(set) var submittedFrames = 0
    private let logger = Logger(subsystem: "local.foldglass", category: "effect")

    init(gpu: FoldGPU) { self.gpu = gpu }
    func makeView() -> MTKView {
        let view = MTKView(frame: .zero, device: gpu.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = self
        view.layer?.isOpaque = true
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        self.view = view
        return view
    }
    func update(angle: Double, settings: FoldSettings) {
        self.angle = angle
        self.settings = settings
        view?.needsDisplay = true
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let textures, let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = gpu.queue.makeCommandBuffer() else { return }
        gpu.encode(command, pass: pass, textures: textures, angle: angle, settings: settings)
        command.present(drawable)
        submittedFrames += 1
        command.addCompletedHandler { [logger] command in
            if let error = command.error { logger.error("GPU frame failed: \(error.localizedDescription, privacy: .public)") }
        }
        if let ready = firstFrameReady {
            firstFrameReady = nil
            command.addCompletedHandler { _ in DispatchQueue.main.async { ready() } }
        }
        command.commit()
    }
}
