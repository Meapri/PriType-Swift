import AppKit

public class MASShortcutViewButtonCell: NSButtonCell {

    public override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        var paddedFrame = cellFrame

        // Fix display on Big Sur
        if #available(macOS 11, *) {
            // Fix vertical alignment
            paddedFrame.origin.y -= 1.0

            // Fix cancel button alignment
            if alignment == .right &&
               (bezelStyle == .texturedRounded || bezelStyle == .rounded) {
                paddedFrame.size.width -= 14.0

                if bezelStyle == .texturedRounded {
                    paddedFrame.origin.x += 7.0
                }
            }
        }

        super.drawInterior(withFrame: paddedFrame, in: controlView)
    }
}
