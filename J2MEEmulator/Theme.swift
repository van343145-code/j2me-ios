import UIKit

/// Exact color palette extracted 1:1 from J2ME NST (`J2me.iOS.Ui.Apk`, `Lic`, `HomeTabBar`, `MicroController`).
enum NstTheme {
    enum Apk {
        static let accent = UIColor(rgb255: (255, 46, 81))       // #FF2E51
        static let toolbar = UIColor(rgb255: (33, 33, 33))       // #212121
        static let background = UIColor(rgb255: (250, 250, 250)) // #FAFAFA
        static let divider = UIColor(rgb255: (220, 220, 220))    // #DCDCDC
        static let selected = UIColor(rgb255: (192, 253, 192))   // #C0FDC0
        static let text = UIColor(rgb255: (34, 34, 34))          // #222222
    }

    enum Lic {
        static let page = UIColor(hex: 0xF3F1EA)
        static let card = UIColor(hex: 0xFFFEFA)
        static let line = UIColor(hex: 0xE4DFD2)
        static let text = UIColor(hex: 0x2A2822)
        static let muted = UIColor(hex: 0x6F695C)
        static let accent = UIColor(hex: 0xC9541F)
        static let danger = UIColor(hex: 0xA12F2F)
        static let neutralSoft = UIColor(hex: 0xEEEAE0)
        static let codeBg = UIColor(hex: 0x2A2822)
        static let codeMuted = UIColor(hex: 0xCFC8B8)
        static let codeLine = UIColor(hex: 0x403C33)
        static let zaloBtn = UIColor(hex: 0xB84A19)
    }

    enum HomeTab {
        static let accent = UIColor(rgb255: (184, 74, 25))       // #B84A19
        static let track = UIColor(rgb255: (230, 223, 216))      // #E6DFD8
        static let inactiveText = UIColor(rgb255: (125, 111, 100)) // #7D6F64
    }

    enum Player {
        static let barBg = UIColor(rgb255: (28, 37, 52))         // #1C2534
        static let tabActive = UIColor(rgb255: (105, 210, 30))   // #69D21E
        static let tabText = UIColor(rgb255: (198, 210, 190))    // #C6D2BE
        static let playBg = UIColor(rgb255: (208, 208, 208))     // #D0D0D0
    }
}

extension UIColor {
    convenience init(rgb255: (Int, Int, Int), alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat(rgb255.0) / 255.0,
            green: CGFloat(rgb255.1) / 255.0,
            blue: CGFloat(rgb255.2) / 255.0,
            alpha: alpha
        )
    }

    convenience init(hex: Int, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }

    static func argb(rgb: Int, alphaByte: Int) -> UIColor {
        let a = max(0, min(255, alphaByte))
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: CGFloat(a) / 255.0
        )
    }
}
