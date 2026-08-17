import Foundation

/// Stable public boundary consumed by the macOS application.
public enum KinetoCore {
    public static let productName = "Kineto"
    public static let minimumSystemVersion = OperatingSystemVersion(
        majorVersion: 15,
        minorVersion: 0,
        patchVersion: 0
    )
}
