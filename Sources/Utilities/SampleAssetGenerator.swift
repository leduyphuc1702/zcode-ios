import UIKit
import PDFKit

/// Generates crisp native high-DPI images and multi-page PDF documents using CoreGraphics
/// so the Native Media/Image/PDF Inspector works offline and in E2E tests with zero WebViews.
public enum SampleAssetGenerator {
    public static func makeArchitectureDiagramPNG() -> Data {
        let size = CGSize(width: 1200, height: 760)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.pngData { ctx in
            let cg = ctx.cgContext
            // Obsidian background
            UIColor(red: 0.086, green: 0.086, blue: 0.094, alpha: 1.0).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // Subtle dot grid
            UIColor(white: 1.0, alpha: 0.06).setStroke()
            cg.setLineWidth(1)
            for x in stride(from: 40, to: Int(size.width), by: 40) {
                cg.move(to: CGPoint(x: x, y: 0))
                cg.addLine(to: CGPoint(x: x, y: Int(size.height)))
            }
            for y in stride(from: 40, to: Int(size.height), by: 40) {
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: Int(size.width), y: y))
            }
            cg.strokePath()

            // Header title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 28, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            NSString(string: "ZCode v3.16.3 — Native RPC & Multi-Agent Architecture").draw(at: CGPoint(x: 56, y: 44), withAttributes: titleAttrs)

            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: UIColor(white: 0.65, alpha: 1.0)
            ]
            NSString(string: "SocketProtocol (13-byte BE) + VQL Binary Framing + Relay V2 Multiplexer").draw(at: CGPoint(x: 56, y: 84), withAttributes: subAttrs)

            struct Box {
                let rect: CGRect
                let title: String
                let subtitle: String
                let accent: UIColor
            }

            let boxes: [Box] = [
                Box(rect: CGRect(x: 60, y: 180, width: 290, height: 150),
                    title: "ZCode iOS Native",
                    subtitle: "SwiftUI + PDFKit + Native Canvas\nZero WebView • FaceID • Keychain",
                    accent: UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1)),
                Box(rect: CGRect(x: 455, y: 180, width: 290, height: 150),
                    title: "Z.ai Relay V2 / Direct WS",
                    subtitle: "CRC32 Chunked RPC Tunnel\nws://<host>/ws • wss://.../ws2",
                    accent: UIColor(red: 0.27, green: 0.75, blue: 0.45, alpha: 1)),
                Box(rect: CGRect(x: 850, y: 180, width: 290, height: 150),
                    title: "ZCode Server Daemon",
                    subtitle: "57 Service Channels • VQL IPC\nzcode-agent • zcode-task • git",
                    accent: UIColor(red: 1.0, green: 0.54, blue: 0.19, alpha: 1)),
                Box(rect: CGRect(x: 240, y: 460, width: 310, height: 165),
                    title: "Workspace & Git Engine",
                    subtitle: "Live File Tree • Shiki Highlighting\nUnified/Split Diffs • Checkpoints",
                    accent: UIColor(red: 0.66, green: 0.55, blue: 0.98, alpha: 1)),
                Box(rect: CGRect(x: 650, y: 460, width: 310, height: 165),
                    title: "Subagents, Skills & MCP",
                    subtitle: "Explore • Plan-Architect • PTY\nGitNexus • CodeGraph • Memory",
                    accent: UIColor(red: 0.96, green: 0.38, blue: 0.48, alpha: 1))
            ]

            // Connectors
            UIColor(white: 0.85, alpha: 0.45).setStroke()
            cg.setLineWidth(3)
            let lines: [(CGPoint, CGPoint)] = [
                (CGPoint(x: 350, y: 255), CGPoint(x: 455, y: 255)),
                (CGPoint(x: 745, y: 255), CGPoint(x: 850, y: 255)),
                (CGPoint(x: 600, y: 330), CGPoint(x: 395, y: 460)),
                (CGPoint(x: 995, y: 330), CGPoint(x: 805, y: 460))
            ]
            for (p1, p2) in lines {
                cg.move(to: p1)
                cg.addLine(to: p2)
            }
            cg.strokePath()

            for box in boxes {
                let path = UIBezierPath(roundedRect: box.rect, cornerRadius: 18)
                UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1).setFill()
                path.fill()
                box.accent.setStroke()
                path.lineWidth = 2.5
                path.stroke()

                let pill = UIBezierPath(roundedRect: CGRect(x: box.rect.minX + 20, y: box.rect.minY + 18, width: 42, height: 6), cornerRadius: 3)
                box.accent.setFill()
                pill.fill()

                NSString(string: box.title).draw(
                    at: CGPoint(x: box.rect.minX + 20, y: box.rect.minY + 38),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                        .foregroundColor: UIColor.white
                    ]
                )
                NSString(string: box.subtitle).draw(
                    in: CGRect(x: box.rect.minX + 20, y: box.rect.minY + 74, width: box.rect.width - 40, height: 64),
                    withAttributes: [
                        .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                        .foregroundColor: UIColor(white: 0.78, alpha: 1.0)
                    ]
                )
            }
        }
    }

    public static func makeUIPreviewMockupPNG() -> Data {
        let size = CGSize(width: 900, height: 640)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.pngData { ctx in
            let cg = ctx.cgContext
            UIColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            let card = UIBezierPath(roundedRect: CGRect(x: 50, y: 50, width: 800, height: 540), cornerRadius: 24)
            UIColor(red: 0.15, green: 0.16, blue: 0.20, alpha: 1).setFill()
            card.fill()
            UIColor(white: 1.0, alpha: 0.14).setStroke()
            card.lineWidth = 2
            card.stroke()

            NSString(string: "Enterprise Telemetry Snapshot • P99 Latency 18.4ms").draw(
                at: CGPoint(x: 90, y: 88),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 22, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
            )

            let barHeights: [CGFloat] = [140, 210, 185, 290, 320, 265, 360, 330, 390, 410]
            for (idx, h) in barHeights.enumerated() {
                let x = CGFloat(95 + idx * 70)
                let y = 520 - h
                let bar = UIBezierPath(roundedRect: CGRect(x: x, y: y, width: 44, height: h), cornerRadius: 8)
                UIColor(red: 0.27, green: 0.75, blue: 0.45, alpha: 0.9).setFill()
                bar.fill()
            }
        }
    }

    public static func makeEnterpriseSpecPDF() -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            // Page 1
            ctx.beginPage()
            let titleFont = UIFont.systemFont(ofSize: 18.5, weight: .bold)
            let headingFont = UIFont.systemFont(ofSize: 13.5, weight: .semibold)
            let bodyFont = UIFont.systemFont(ofSize: 11.5, weight: .regular)
            let monoFont = UIFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)

            NSString(string: "ZCode Enterprise Mobile — Technical Specification v3.16.3").draw(
                in: CGRect(x: 48, y: 48, width: 516, height: 34),
                withAttributes: [.font: titleFont, .foregroundColor: UIColor.black]
            )
            NSString(string: "100% Native iOS Client • Zero WebView • Binary VQL RPC + Cloud Relay V2").draw(
                in: CGRect(x: 48, y: 80, width: 516, height: 28),
                withAttributes: [.font: headingFont, .foregroundColor: UIColor.darkGray]
            )

            let body1 = """
            1. Executive Overview
            ZCode Mobile for iOS provides full feature parity with ZCode Desktop v3.16.3 using exclusively native Apple frameworks (SwiftUI, UIKit, PDFKit, Network/URLSessionWebSocketTask, AVFoundation, LocalAuthentication, Security Keychain).

            2. Binary Wire Protocol Specification
            • SocketProtocol Frame Header: 13-byte Big-Endian [type: UInt8 = 1, id: UInt32 = 0, ack: UInt32 = 0, byteLength: UInt32].
            • VQL Variable-Length Serialization: Unsigned 7-bit LEB128 varint tags (0 Undefined, 1 String, 2 Buffer, 3 VSBuffer, 4 Array, 5 JSON Object, 6 Int32).
            • Cloud Relay V2: Authenticated WebSocket over wss://zcode.z.ai/api/v1/remote/ws2 with IEEE 802.3 CRC32 verified rpc-frame chunking.

            3. Security & Enterprise Governance
            • Credentials isolated per workstation in hardware-backed iOS Keychain.
            • Biometric Face ID / Touch ID + Salted SHA-256 3x3 Pattern Lock with progressive lockout.
            • Real-time Tool Permission Approval Gate (Allow Once, Allow Session, Deny) and Plan Mode Verification.
            """
            NSString(string: body1).draw(
                in: CGRect(x: 48, y: 126, width: 516, height: 420),
                withAttributes: [.font: bodyFont, .foregroundColor: UIColor(white: 0.15, alpha: 1)]
            )

            let codeSample = """
            // Sample SocketProtocol Frame Builder
            var frame = Data(capacity: 13 + payload.count)
            frame.append(0x01) // Regular
            frame.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])
            var lengthBE = UInt32(payload.count).bigEndian
            withUnsafeBytes(of: &lengthBE) { frame.append(contentsOf: $0) }
            frame.append(payload)
            """
            UIColor(white: 0.95, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 48, y: 540, width: 516, height: 140), cornerRadius: 10).fill()
            NSString(string: codeSample).draw(
                in: CGRect(x: 64, y: 556, width: 484, height: 112),
                withAttributes: [.font: monoFont, .foregroundColor: UIColor.black]
            )

            // Page 2
            ctx.beginPage()
            NSString(string: "Page 2 — Inspector Windows & Multi-Agent Workflows").draw(
                at: CGPoint(x: 48, y: 52),
                withAttributes: [.font: headingFont, .foregroundColor: UIColor.black]
            )
            let body2 = """
            4. Native Coding Inspector Modules
            • File Explorer & Syntax Code Viewer: 6 Shiki color palettes, line numbers, inline range comments (@file:start-end), and instant fuzzy search.
            • Media & Document Previewer: Pinch-to-zoom Image Inspector with pixel grid, native PDFKit multi-page document viewer, Markdown renderer, and CSV table grid.
            • Git & Diff Review: Unified and split side-by-side diffs, hunk inspection, stage/unstage/discard, branch switcher, AI commit generator, and commit graph.
            • Integrated Terminal: Multi-tab PTY terminal with developer key bar (ESC, TAB, CTRL, arrows, pipe) and background job monitor.
            """
            NSString(string: body2).draw(
                in: CGRect(x: 48, y: 92, width: 516, height: 400),
                withAttributes: [.font: bodyFont, .foregroundColor: UIColor(white: 0.15, alpha: 1)]
            )
        }
    }
}
