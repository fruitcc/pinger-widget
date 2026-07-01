import AppKit
import SwiftUI

/// Single source of truth for how each status is presented,
/// shared by the menu bar icon, tooltip, and panels.
extension ConnectionStatus {
    var title: String {
        switch self {
        case .unknown: "Measuring…"
        case .good: "Connected"
        case .degraded: "Degraded"
        case .down: "No connection"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .unknown: .systemGray
        case .good: .systemGreen
        case .degraded: .systemYellow
        case .down: .systemRed
        }
    }

    var color: Color {
        Color(nsColor: nsColor)
    }
}
