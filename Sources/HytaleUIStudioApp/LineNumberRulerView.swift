import AppKit

final class LineNumberRulerView: NSRulerView {
    var errorLines: Set<Int> = []
    var warningLines: Set<Int> = []

    private let numberFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

    init(textView: NSTextView, scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 48
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor(white: 0.12, alpha: 1).setFill()
        bounds.fill()
        NSColor(white: 0.2, alpha: 1).setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        separator.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        separator.stroke()

        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer,
              let scrollView = scrollView else { return }

        let content = textView.string as NSString
        let visible = scrollView.contentView.bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let inset = textView.textContainerInset.height
        let relativeY = convert(NSPoint.zero, from: textView).y

        var charIndex = lineStart(before: charRange.location, in: content)
        var lineNumber = numberOfNewlines(in: content, upTo: charIndex) + 1
        let end = NSMaxRange(charRange)

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: NSColor(white: 0.5, alpha: 1)
        ]

        while charIndex <= end {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
            var effectiveRange = NSRange(location: 0, length: 0)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
            let y = lineRect.minY + relativeY + inset

            let hasError = errorLines.contains(lineNumber)
            let hasWarning = warningLines.contains(lineNumber)
            if hasError || hasWarning {
                (hasError ? NSColor.systemRed : NSColor.systemOrange).setFill()
                NSBezierPath(ovalIn: NSRect(x: 4, y: y + lineRect.height / 2 - 3, width: 6, height: 6)).fill()
            }

            var attributes = baseAttributes
            if hasError { attributes[.foregroundColor] = NSColor.systemRed }
            else if hasWarning { attributes[.foregroundColor] = NSColor.systemOrange }
            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: bounds.maxX - size.width - 6, y: y + (lineRect.height - size.height) / 2), withAttributes: attributes)

            let lineRange = content.lineRange(for: NSRange(location: charIndex, length: 0))
            if lineRange.length == 0 { break }
            charIndex = NSMaxRange(lineRange)
            lineNumber += 1
            if charIndex >= content.length { break }
        }
    }

    private func lineStart(before location: Int, in content: NSString) -> Int {
        guard location <= content.length else { return 0 }
        let range = content.lineRange(for: NSRange(location: min(location, content.length), length: 0))
        return range.location
    }

    private func numberOfNewlines(in content: NSString, upTo location: Int) -> Int {
        guard location > 0 else { return 0 }
        let upper = min(location, content.length)
        var count = 0
        for index in 0..<upper {
            let unit = content.character(at: index)
            if unit == 10 || unit == 0x2028 || unit == 0x2029 || unit == 0x0085 {
                count += 1
            }
        }
        return count
    }
}
