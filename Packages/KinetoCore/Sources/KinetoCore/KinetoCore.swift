import Foundation

/// Stable public boundary consumed by the macOS application.
public enum KinetoCore {
    public static let productName = "Kineto"
    public static let minimumSystemVersion = OperatingSystemVersion(
        majorVersion: 26,
        minorVersion: 1,
        patchVersion: 0
    )
}
