import AppKit
import CoreGraphics

enum DemoImage {
    static func make(language: AppLanguage = .english, bundle: Bundle = .main) -> CGImage {
        func t(_ key: String) -> String { language.text(key, bundle: bundle) }
        let size = CGSize(width: 1600, height: 1040)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError(t("demo_create_failed"))
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                    green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: alpha)
        }
        func round(_ rect: CGRect, _ radius: CGFloat, _ fill: NSColor) {
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
        func text(_ string: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 16,
                  _ tint: NSColor = .white, _ weight: NSFont.Weight = .regular,
                  mono: Bool = false) {
            let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                            : NSFont.systemFont(ofSize: size, weight: weight)
            (string as NSString).draw(at: CGPoint(x: x, y: y),
                                     withAttributes: [.font: font, .foregroundColor: tint])
        }
        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat,
                  _ tint: NSColor, _ width: CGFloat = 1) {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: x1, y: y1))
            path.line(to: CGPoint(x: x2, y: y2))
            path.lineWidth = width
            tint.setStroke()
            path.stroke()
        }
        func ellipse(_ rect: CGRect, _ tint: NSColor) {
            tint.setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
        func gradient(_ rect: CGRect, _ first: NSColor, _ second: NSColor, _ angle: CGFloat) {
            NSGradient(starting: first, ending: second)!.draw(in: rect, angle: angle)
        }
        func glow(_ rect: CGRect, _ tint: NSColor) {
            NSGradient(starting: tint, ending: tint.withAlphaComponent(0))!
                .draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
        }
        func window(_ rect: CGRect, _ fill: NSColor) {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = color(0x030811, 0.32)
            shadow.shadowBlurRadius = 42
            shadow.shadowOffset = CGSize(width: 0, height: -18)
            shadow.set()
            round(rect, 18, fill)
            NSGraphicsContext.restoreGraphicsState()
            let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 18, yRadius: 18)
            color(0xFFFFFF, 0.45).setStroke()
            outline.lineWidth = 1
            outline.stroke()
        }
        func traffic(_ x: CGFloat, _ y: CGFloat) {
            for (index, shade) in [UInt32(0xF77769), 0xEDBE57, 0x70BF88].enumerated() {
                ellipse(CGRect(x: x + CGFloat(index) * 22, y: y, width: 11, height: 11), color(shade))
            }
        }

        let full = CGRect(origin: .zero, size: size)
        gradient(full, color(0x0D1E40), color(0x254665), 75)
        glow(CGRect(x: 600, y: 90, width: 1300, height: 1200), color(0x728AA0, 0.85))
        let sand = NSBezierPath()
        sand.move(to: CGPoint(x: -90, y: 700))
        sand.curve(to: CGPoint(x: 770, y: 1080), controlPoint1: CGPoint(x: 80, y: 320), controlPoint2: CGPoint(x: 350, y: 780))
        sand.line(to: CGPoint(x: 1370, y: 1080))
        sand.curve(to: CGPoint(x: -90, y: 130), controlPoint1: CGPoint(x: 1170, y: 280), controlPoint2: CGPoint(x: 180, y: 620))
        sand.close()
        NSGradient(colors: [color(0xE9C7A7), color(0xD79672), color(0x735573)])!.draw(in: sand, angle: -45)
        let blue = NSBezierPath()
        blue.move(to: CGPoint(x: 180, y: -50))
        blue.curve(to: CGPoint(x: 1610, y: 640), controlPoint1: CGPoint(x: 350, y: 670), controlPoint2: CGPoint(x: 900, y: 230))
        blue.line(to: CGPoint(x: 1680, y: -50))
        blue.close()
        NSGradient(colors: [color(0x253F7D), color(0x5F94BE), color(0x89A8BE)])!.draw(in: blue, angle: 60)
        glow(CGRect(x: -300, y: -310, width: 1350, height: 790), color(0xA68DAC, 0.7))
        glow(CGRect(x: 1170, y: 40, width: 540, height: 840), color(0xCEAA9C, 0.4))

        round(CGRect(x: 0, y: 1006, width: 1600, height: 34), 0, color(0x101820, 0.28))
        text(t("demo_studio"), 27, 1013, 14, .white, .bold)
        text(t("demo_menu"), 103, 1013, 14, color(0xFFFFFF, 0.88))
        text(t("demo_date"), 1410, 1013, 13, color(0xFFFFFF, 0.95), .medium)

        let ink = color(0x202633)
        let muted = color(0x7D8490)
        let panel = CGRect(x: 102, y: 268, width: 904, height: 596)
        window(panel, color(0xF2F0EB))
        traffic(126, 833)
        text(t("demo_notes"), 210, 828, 15, ink, .semibold)
        text(t("demo_workspace"), 850, 829, 12, muted)
        line(102, 810, 1006, 810, color(0xDADAD7))
        round(CGRect(x: 103, y: 289, width: 194, height: 520), 0, color(0xE9E8E3))
        text(t("demo_library"), 125, 777, 12, muted, .semibold)
        let navigation = [t("demo_overview"), t("demo_materials"), t("demo_motion"), t("demo_saved") ]
        for (index, label) in navigation.enumerated() {
            let y = CGFloat(734 - index * 42)
            if index == 1 { round(CGRect(x: 113, y: y - 6, width: 172, height: 33), 7, color(0xD8DCD8)) }
            round(CGRect(x: 128, y: y + 4, width: 11, height: 11), 3, color(index == 1 ? 0x4F706B : 0xA4A9A5))
            text(label, 150, y, 13, index == 1 ? ink : muted, index == 1 ? .medium : .regular)
        }
        text(t("demo_collections"), 125, 524, 12, muted, .semibold)
        text(t("demo_light"), 128, 485, 12, ink)
        text(t("demo_geometry_item"), 128, 449, 12, ink)
        text(t("demo_refraction"), 128, 413, 12, ink)
        text(t("demo_count"), 126, 300, 12, muted, .medium, mono: true)

        text(t("demo_geometry"), 327, 745, 34, ink, .semibold)
        text(t("demo_exploration"), 329, 716, 14, muted)
        round(CGRect(x: 864, y: 750, width: 112, height: 31), 15, color(0x284B48))
        text(t("demo_new"), 880, 758, 12, .white, .medium)

        for index in 0..<3 {
            let x = CGFloat(329 + index * 222)
            let card = CGRect(x: x, y: 453, width: 204, height: 222)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10).addClip()
            gradient(card, color([0xD5C3B4, 0x7C9699, 0xB1A9B9][index]), color([0x7C5851, 0x263E56, 0x524C72][index]), 90)
            let loop = NSBezierPath(ovalIn: CGRect(x: x + 35, y: 475, width: 132, height: 173))
            loop.lineWidth = 30
            color([0xF1D8BC, 0xA9C5C6, 0xDDD3E1][index], 0.85).setStroke()
            loop.stroke()
            ellipse(CGRect(x: x + 66, y: 483, width: 72, height: 144), color(0x16202C, 0.2))
            NSGraphicsContext.restoreGraphicsState()
            text([t("demo_sand"), t("demo_tide"), t("demo_dusk")][index], x + 2, 424, 15, ink, .medium)
            text([t("demo_warm"), t("demo_fluid"), t("demo_quiet")][index], x + 2, 402, 12, muted)
        }
        line(329, 375, 976, 375, color(0xDADAD7))
        text(t("demo_activity"), 329, 347, 12, muted, .medium)
        text(t("demo_updated"), 329, 315, 13, ink)
        text(t("demo_now"), 907, 315, 12, muted)

        let notes = CGRect(x: 1070, y: 369, width: 401, height: 461)
        window(notes, color(0x192631, 0.96))
        traffic(1092, 800)
        text(t("demo_review"), 1172, 795, 14, color(0xDCE5E6), .medium)
        line(1070, 777, 1471, 777, color(0x50616B, 0.5))
        text(t("demo_make"), 1100, 708, 31, color(0xF0EEE3), .semibold)
        text(t("demo_physical"), 1100, 670, 31, color(0xDAC6A7), .semibold)
        text(t("demo_response"), 1102, 623, 12, color(0x96ABB2), .regular, mono: true)
        for (index, label) in [t("demo_follows"), t("demo_edges"), t("demo_reverse")].enumerated() {
            let y = CGFloat(571 - index * 34)
            round(CGRect(x: 1103, y: y + 3, width: 13, height: 13), 4, color(0x799C9B))
            text(label, 1129, y, 14, color(0xD4DEDD))
        }
        line(1102, 461, 1439, 461, color(0x4B626B, 0.65))
        text(t("demo_curve"), 1103, 428, 11, color(0x91A5AD), .medium, mono: true)
        let curve = NSBezierPath()
        curve.move(to: CGPoint(x: 1180, y: 410))
        curve.curve(to: CGPoint(x: 1434, y: 446), controlPoint1: CGPoint(x: 1315, y: 410), controlPoint2: CGPoint(x: 1268, y: 446))
        curve.lineWidth = 2
        color(0xD9C09D).setStroke()
        curve.stroke()
        ellipse(CGRect(x: 1177, y: 407, width: 6, height: 6), color(0xD9C09D))
        ellipse(CGRect(x: 1431, y: 443, width: 6, height: 6), color(0xD9C09D))

        window(CGRect(x: 1120, y: 181, width: 311, height: 131), color(0xF0E9DC, 0.94))
        text("11", 1146, 220, 58, ink, .light)
        text(t("demo_september"), 1240, 257, 16, ink, .medium)
        text(t("demo_friday"), 1240, 232, 13, muted)
        text(t("demo_space"), 1240, 206, 12, muted)

        round(CGRect(x: 478, y: 34, width: 643, height: 85), 25, color(0xE7EBF0, 0.28))
        let dockColors: [UInt32] = [0x4589CE, 0x5D677B, 0xE9D9A7, 0x67A298, 0xCB8275, 0xAF90B4, 0x758DA7, 0xDED6CC]
        for (index, shade) in dockColors.enumerated() {
            let x = CGFloat(492 + index * 78)
            round(CGRect(x: x, y: 49, width: 58, height: 58), 14, color(shade))
            let mark = color(0xFFFFFF, 0.85)
            switch index % 4 {
            case 0:
                round(CGRect(x: x + 13, y: 65, width: 32, height: 27), 5, mark)
                line(x + 15, 83, x + 43, 83, color(shade), 2)
            case 1:
                text(">_", x + 10, 66, 25, mark, .medium, mono: true)
            case 2:
                for row in 0..<3 { line(x + 14, CGFloat(69 + row * 9), x + 44, CGFloat(69 + row * 9), color(0x595958, 0.65), 2) }
            default:
                let path = NSBezierPath(ovalIn: CGRect(x: x + 13, y: 62, width: 32, height: 32))
                path.lineWidth = 3
                mark.setStroke()
                path.stroke()
                line(x + 29, 78, x + 37, 89, mark, 2)
                line(x + 29, 78, x + 21, 76, mark, 2)
            }
            if index == 0 || index == 1 || index == 4 {
                ellipse(CGRect(x: x + 27, y: 40, width: 4, height: 4), color(0xFFFFFF, 0.85))
            }
        }

        guard let image = context.makeImage() else { fatalError(t("demo_render_failed")) }
        return image
    }
}
