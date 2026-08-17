//
//  PromoTrailerRuntime.swift
//  Number Reef
//
//  Development-only App Store teaser entry. Activated solely by launch
//  arguments so Release production gameplay is untouched.
//

import Foundation
import CoreGraphics

enum PromoTrailerRuntime {
    /// `-PromoTrailer` enables the deterministic teaser host.
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-PromoTrailer")
    }

    /// `-PromoSize=886x1920` or `1200x1600`. Defaults to iPhone teaser size.
    static var exportSize: CGSize {
        let prefix = "-PromoSize="
        let value = ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
        switch value {
        case "1200x1600":
            return CGSize(width: 1200, height: 1600)
        default:
            return CGSize(width: 886, height: 1920)
        }
    }

    /// Logical SwiftUI layout matching real device proportions so bubble / fish /
    /// HUD sizes match production. The recorder scales this up to `exportSize`.
    static var layoutSize: CGSize {
        switch (Int(exportSize.width), Int(exportSize.height)) {
        case (1200, 1600):
            // Same 3:4 aspect as the iPad export, with pad metrics.
            return CGSize(width: 834, height: 1_112)
        default:
            // Same ~9:19.5 aspect as the iPhone export, with phone metrics.
            return CGSize(width: 393, height: 852)
        }
    }

    static var exportTag: String {
        let size = exportSize
        return "\(Int(size.width))x\(Int(size.height))"
    }

    /// iPad composition uses the game's pad metrics (bubble diameter, fish size).
    /// iPhone teasers use phone metrics so bubbles match real gameplay size.
    static var usesPadMetrics: Bool {
        exportSize.width >= 1000
    }

    static var framesPerSecond: Int { 30 }

    /// Soft ceiling; the director ends when the icon settles after swim-out.
    static var maximumDuration: TimeInterval { 32 }
}
