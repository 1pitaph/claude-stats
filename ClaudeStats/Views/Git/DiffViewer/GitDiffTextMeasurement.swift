import AppKit
import CoreGraphics
import Foundation

struct GitDiffTextMeasurement {
    static func standardCodeFont() -> NSFont {
        NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    }

    let font: NSFont
    let metrics: GitDiffRenderMetrics

    func height(for text: String, width: CGFloat) -> CGFloat {
        let columns = wrappedColumnCapacity(width: width)
        let visualLength = max(expandedCharacterCount(in: text), 1)
        let lineCount = max(1, Int(ceil(CGFloat(visualLength) / CGFloat(columns))))
        return CGFloat(lineCount) * metrics.lineHeight
    }

    private func wrappedColumnCapacity(width: CGFloat) -> Int {
        let advance = max(characterAdvance, 1)
        return max(1, Int(floor(max(width, 1) / advance)))
    }

    private var characterAdvance: CGFloat {
        let width = font.maximumAdvancement.width
        if width.isFinite, width > 0 {
            return ceil(width)
        }
        return ceil(max(font.pointSize * 0.62, 1))
    }

    private func expandedCharacterCount(in text: String) -> Int {
        text.reduce(0) { count, character in
            count + (character == "\t" ? 4 : 1)
        }
    }
}
