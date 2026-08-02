import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

    /// The "LaunchBackground" asset catalog color resource.
    static let launchBackground = DeveloperToolsSupport.ColorResource(name: "LaunchBackground", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "bear_no_background" asset catalog image resource.
    static let bearNoBackground = DeveloperToolsSupport.ImageResource(name: "bear_no_background", bundle: resourceBundle)

    /// The "bubble" asset catalog image resource.
    static let bubble = DeveloperToolsSupport.ImageResource(name: "bubble", bundle: resourceBundle)

    /// The "bunny_no_background" asset catalog image resource.
    static let bunnyNoBackground = DeveloperToolsSupport.ImageResource(name: "bunny_no_background", bundle: resourceBundle)

    /// The "crab_no_background" asset catalog image resource.
    static let crabNoBackground = DeveloperToolsSupport.ImageResource(name: "crab_no_background", bundle: resourceBundle)

    /// The "dog_no_background" asset catalog image resource.
    static let dogNoBackground = DeveloperToolsSupport.ImageResource(name: "dog_no_background", bundle: resourceBundle)

    /// The "elephant_no_background" asset catalog image resource.
    static let elephantNoBackground = DeveloperToolsSupport.ImageResource(name: "elephant_no_background", bundle: resourceBundle)

    /// The "frog_no_background" asset catalog image resource.
    static let frogNoBackground = DeveloperToolsSupport.ImageResource(name: "frog_no_background", bundle: resourceBundle)

    /// The "lion_no_background" asset catalog image resource.
    static let lionNoBackground = DeveloperToolsSupport.ImageResource(name: "lion_no_background", bundle: resourceBundle)

    /// The "no_background" asset catalog image resource.
    static let noBackground = DeveloperToolsSupport.ImageResource(name: "no_background", bundle: resourceBundle)

    /// The "octupus_no_background" asset catalog image resource.
    static let octupusNoBackground = DeveloperToolsSupport.ImageResource(name: "octupus_no_background", bundle: resourceBundle)

    /// The "pinquin_no_background" asset catalog image resource.
    static let pinquinNoBackground = DeveloperToolsSupport.ImageResource(name: "pinquin_no_background", bundle: resourceBundle)

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// The "LaunchBackground" asset catalog color.
    static var launchBackground: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .launchBackground)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// The "LaunchBackground" asset catalog color.
    static var launchBackground: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .launchBackground)
#else
        .init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    /// The "LaunchBackground" asset catalog color.
    static var launchBackground: SwiftUI.Color { .init(.launchBackground) }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    /// The "LaunchBackground" asset catalog color.
    static var launchBackground: SwiftUI.Color { .init(.launchBackground) }

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    /// The "bear_no_background" asset catalog image.
    static var bearNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .bearNoBackground)
#else
        .init()
#endif
    }

    /// The "bubble" asset catalog image.
    static var bubble: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .bubble)
#else
        .init()
#endif
    }

    /// The "bunny_no_background" asset catalog image.
    static var bunnyNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .bunnyNoBackground)
#else
        .init()
#endif
    }

    /// The "crab_no_background" asset catalog image.
    static var crabNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .crabNoBackground)
#else
        .init()
#endif
    }

    /// The "dog_no_background" asset catalog image.
    static var dogNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .dogNoBackground)
#else
        .init()
#endif
    }

    /// The "elephant_no_background" asset catalog image.
    static var elephantNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .elephantNoBackground)
#else
        .init()
#endif
    }

    /// The "frog_no_background" asset catalog image.
    static var frogNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .frogNoBackground)
#else
        .init()
#endif
    }

    /// The "lion_no_background" asset catalog image.
    static var lionNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .lionNoBackground)
#else
        .init()
#endif
    }

    /// The "no_background" asset catalog image.
    static var noBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .noBackground)
#else
        .init()
#endif
    }

    /// The "octupus_no_background" asset catalog image.
    static var octupusNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .octupusNoBackground)
#else
        .init()
#endif
    }

    /// The "pinquin_no_background" asset catalog image.
    static var pinquinNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .pinquinNoBackground)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// The "bear_no_background" asset catalog image.
    static var bearNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .bearNoBackground)
#else
        .init()
#endif
    }

    /// The "bubble" asset catalog image.
    static var bubble: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .bubble)
#else
        .init()
#endif
    }

    /// The "bunny_no_background" asset catalog image.
    static var bunnyNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .bunnyNoBackground)
#else
        .init()
#endif
    }

    /// The "crab_no_background" asset catalog image.
    static var crabNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .crabNoBackground)
#else
        .init()
#endif
    }

    /// The "dog_no_background" asset catalog image.
    static var dogNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .dogNoBackground)
#else
        .init()
#endif
    }

    /// The "elephant_no_background" asset catalog image.
    static var elephantNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .elephantNoBackground)
#else
        .init()
#endif
    }

    /// The "frog_no_background" asset catalog image.
    static var frogNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .frogNoBackground)
#else
        .init()
#endif
    }

    /// The "lion_no_background" asset catalog image.
    static var lionNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .lionNoBackground)
#else
        .init()
#endif
    }

    /// The "no_background" asset catalog image.
    static var noBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .noBackground)
#else
        .init()
#endif
    }

    /// The "octupus_no_background" asset catalog image.
    static var octupusNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .octupusNoBackground)
#else
        .init()
#endif
    }

    /// The "pinquin_no_background" asset catalog image.
    static var pinquinNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .pinquinNoBackground)
#else
        .init()
#endif
    }

}
#endif

// MARK: - Thinnable Asset Support -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ColorResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ImageResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

