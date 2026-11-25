// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import AppKit
import QuartzCore
import OpenGL.GL3
#if canImport(Libmpv)
import Libmpv
#endif

/// 视频画面：mpv 渲染 API（vo=libmpv）+ CAOpenGLLayer。
///
/// 为什么不用 wid + CAMetalLayer：MPVKit 的 moltenvk 输出只在「重建视频输出」时读一次画布尺寸，
/// 之后拖窗口、全屏、迷你窗、改比例它都不知道，画面只画在一角；重建输出又会黑一帧（2026-11-18 自测）。
/// 渲染 API 每一帧都由我们告诉 mpv 目标尺寸（取当前 GL 视口），尺寸一变就在同一个 CA 事务里按新尺寸重画当前帧，
/// 所以任何时候都没有黑帧（IINA 也是这个做法）。
///
/// 线程：mpv 的「有新帧」回调在 mpv 线程里来，转到专用渲染队列调 display()；
/// 尺寸变化时 CA 在主线程同步调 display()。两边用锁 + CGL 上下文锁串行。
final class MPVGLLayer: CAOpenGLLayer {
    private let pixFmt: CGLPixelFormatObj
    let glContext: CGLContextObj
    private let renderQueue = DispatchQueue(label: "tanco.mpv.render", qos: .userInteractive)
    private let displayLock = NSRecursiveLock()
    #if canImport(Libmpv)
    private var renderCtx: OpaquePointer?
    #endif
    private var pendingFlush = false

    /// 自测用：每画一帧回报（像素宽、高、抽样里纯黑点数、抽样总数）。nil 时不抽样，不耗性能。
    var frameProbe: ((Int, Int, Int, Int) -> Void)?

    override init() {
        var attrs: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(rawValue: UInt32(kCGLOGLPVersion_3_2_Core.rawValue)),
            kCGLPFAAccelerated, kCGLPFADoubleBuffer, kCGLPFAAllowOfflineRenderers,
            kCGLPFAColorSize, CGLPixelFormatAttribute(rawValue: 24),
            CGLPixelFormatAttribute(rawValue: 0),
        ]
        var pf: CGLPixelFormatObj?
        var n: GLint = 0
        CGLChoosePixelFormat(&attrs, &pf, &n)
        if pf == nil {   // 退一步：去掉 AllowOfflineRenderers
            var a2: [CGLPixelFormatAttribute] = [kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(rawValue: UInt32(kCGLOGLPVersion_3_2_Core.rawValue)),
                                                 kCGLPFADoubleBuffer, CGLPixelFormatAttribute(rawValue: 0)]
            CGLChoosePixelFormat(&a2, &pf, &n)
        }
        pixFmt = pf!
        var ctx: CGLContextObj?
        CGLCreateContext(pixFmt, nil, &ctx)
        glContext = ctx!
        var swap: GLint = 1
        CGLSetParameter(glContext, kCGLCPSwapInterval, &swap)
        CGLEnable(glContext, kCGLCEMPEngine)   // 多线程 GL 引擎，渲染更顺
        super.init()
        contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        isAsynchronous = false
        needsDisplayOnBoundsChange = true
        autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backgroundColor = NSColor.black.cgColor
    }
    override init(layer: Any) {
        let o = layer as! MPVGLLayer
        pixFmt = o.pixFmt; glContext = o.glContext
        super.init(layer: layer)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj { pixFmt }
    override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj { glContext }
    override func canDraw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj,
                          forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool { true }

    #if canImport(Libmpv)
    /// mpv 初始化之后调用：建渲染上下文
    func attach(_ handle: OpaquePointer) {
        CGLLockContext(glContext); defer { CGLUnlockContext(glContext) }
        CGLSetCurrentContext(glContext)
        var initParams = mpv_opengl_init_params(get_proc_address: { _, name in
            guard let name else { return nil }
            let sym = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
            guard let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString) else { return nil }
            return CFBundleGetFunctionPointerForName(bundle, sym)
        }, get_proc_address_ctx: nil)
        let api = strdup("opengl")
        defer { free(api) }
        var ctx: OpaquePointer?
        let rc: Int32 = withUnsafeMutablePointer(to: &initParams) { ip in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(api)),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(ip)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            return mpv_render_context_create(&ctx, handle, &params)
        }
        guard rc >= 0, let ctx else { NSLog("mpv_render_context_create 失败 \(rc)"); return }
        renderCtx = ctx
        mpv_render_context_set_update_callback(ctx, { p in
            guard let p else { return }
            let layer = Unmanaged<MPVGLLayer>.fromOpaque(p).takeUnretainedValue()
            layer.requestDraw()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    /// 关闭前必须先释放渲染上下文（mpv 要求在销毁核心之前）
    func detach() {
        displayLock.lock(); defer { displayLock.unlock() }
        guard let ctx = renderCtx else { return }
        mpv_render_context_set_update_callback(ctx, nil, nil)
        CGLLockContext(glContext); CGLSetCurrentContext(glContext)
        mpv_render_context_free(ctx)
        renderCtx = nil
        CGLUnlockContext(glContext)
    }
    #endif

    /// mpv 有新帧：在渲染队列里画（不占主线程）
    /// 合并请求：渲染队列里最多排一个待画任务（2026-11-19 自测：不合并时任务堆积，主线程等锁，界面几乎停住）
    private let pendingLock = NSLock()
    private var drawPending = false
    func requestDraw() {
        pendingLock.lock()
        if drawPending { pendingLock.unlock(); return }
        drawPending = true
        pendingLock.unlock()
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.pendingLock.lock(); self.drawPending = false; self.pendingLock.unlock()
            self.display()
        }
    }

    override func display() {
        displayLock.lock(); defer { displayLock.unlock() }
        let offMain = !Thread.isMainThread
        if offMain { CATransaction.begin() }
        super.display()
        if offMain { CATransaction.commit(); CATransaction.flush() }
    }

    override func draw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj,
                       forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {
        CGLLockContext(ctx); defer { CGLUnlockContext(ctx) }
        CGLSetCurrentContext(ctx)
        var fbo: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &fbo)
        var vp: [GLint] = [0, 0, 0, 0]
        glGetIntegerv(GLenum(GL_VIEWPORT), &vp)
        let w = vp[2], h = vp[3]
        var rendered = false
        #if canImport(Libmpv)
        if let rctx = renderCtx, w > 0, h > 0 {
            var target = mpv_opengl_fbo(fbo: Int32(fbo), w: Int32(w), h: Int32(h), internal_format: 0)
            var flip: Int32 = 1
            // 不按目标时间阻塞：mpv 默认会在 render 里等到这一帧的显示时刻，主线程改尺寸时同步重画就会被卡住
            var noBlock: Int32 = 0
            withUnsafeMutablePointer(to: &target) { tp in
                withUnsafeMutablePointer(to: &flip) { fp in
                    withUnsafeMutablePointer(to: &noBlock) { bp in
                        var params = [
                            mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(tp)),
                            mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(fp)),
                            mpv_render_param(type: MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, data: UnsafeMutableRawPointer(bp)),
                            mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                        ]
                        _ = mpv_render_context_render(rctx, &params)
                    }
                }
            }
            rendered = true
        }
        #endif
        if !rendered {
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        }
        if let probe = frameProbe, w > 8, h > 8 {
            // 必须从刚画好的那个帧缓冲读（CA 给的是离屏 FBO，不是 0 号默认缓冲；2026-11-19 读错缓冲曾误报全黑）
            glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), GLuint(fbo))
            if fbo == 0 { glReadBuffer(GLenum(GL_BACK)) }
            probe(Int(w), Int(h), Self.countBlack(w: w, h: h), 25)
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLuint(fbo))
        }
        glFlush()
        #if canImport(Libmpv)
        if let rctx = renderCtx { mpv_render_context_report_swap(rctx) }
        #endif
    }

    #if canImport(Libmpv)
    /// 截图：按视频原始尺寸离屏渲染当前帧（硬解帧 mpv 的 screenshot-raw 转不了格式，所以自己画一张）
    func snapshot(width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, width <= 16384, height <= 16384 else { return nil }
        displayLock.lock(); defer { displayLock.unlock() }
        guard let rctx = renderCtx else { return nil }
        CGLLockContext(glContext); defer { CGLUnlockContext(glContext) }
        CGLSetCurrentContext(glContext)
        var prevFbo: GLint = 0
        glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &prevFbo)
        var tex: GLuint = 0, fb: GLuint = 0
        glGenTextures(1, &tex); glBindTexture(GLenum(GL_TEXTURE_2D), tex)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA8, GLsizei(width), GLsizei(height), 0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
        glGenFramebuffers(1, &fb); glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fb)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), tex, 0)
        defer {
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLuint(prevFbo))
            glDeleteFramebuffers(1, &fb); glDeleteTextures(1, &tex)
        }
        guard glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) == GLenum(GL_FRAMEBUFFER_COMPLETE) else { return nil }
        var target = mpv_opengl_fbo(fbo: Int32(fb), w: Int32(width), h: Int32(height), internal_format: 0)
        var flip: Int32 = 0, noBlock: Int32 = 0
        withUnsafeMutablePointer(to: &target) { tp in
            withUnsafeMutablePointer(to: &flip) { fp in
                withUnsafeMutablePointer(to: &noBlock) { bp in
                    var params = [
                        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(tp)),
                        mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(fp)),
                        mpv_render_param(type: MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, data: UnsafeMutableRawPointer(bp)),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                    ]
                    _ = mpv_render_context_render(rctx, &params)
                }
            }
        }
        var buf = [UInt8](repeating: 0, count: width * height * 4)
        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), fb)
        glReadPixels(0, 0, GLsizei(width), GLsizei(height), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &buf)
        for i in stride(from: 3, to: buf.count, by: 4) { buf[i] = 255 }
        guard let provider = CGDataProvider(data: Data(buf) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    #endif

    /// 在画面里 5×5 抽样（避开四周 12%），数纯黑点（RGB 都 < 12）——自测证明改尺寸时没有黑帧用
    private static func countBlack(w: GLint, h: GLint) -> Int {
        var black = 0
        var px: [UInt8] = [0, 0, 0, 0]
        for i in 0..<5 { for j in 0..<5 {
            let x = GLint(Double(w) * (0.12 + 0.19 * Double(i))), y = GLint(Double(h) * (0.12 + 0.19 * Double(j)))
            glReadPixels(x, y, 1, 1, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &px)
            if px[0] < 12 && px[1] < 12 && px[2] < 12 { black += 1 }
        } }
        return black
    }
}
