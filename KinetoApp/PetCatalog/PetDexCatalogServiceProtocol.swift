import Foundation

/// Objective-C compatible XPC protocol for the isolated PetDex catalog service.
/// The main app (without network entitlement) communicates exclusively through this interface.
/// All network access and asset validation happens inside the sandboxed XPC helper.
@objc protocol PetDexCatalogServiceProtocol {
    func refreshCatalog(
        withReply reply: @escaping @Sendable (NSData?, NSError?) -> Void
    )
    func downloadPet(
        slug: String,
        withReply reply: @escaping @Sendable (NSData?, NSData?, NSData?, NSError?) -> Void
    )
}
