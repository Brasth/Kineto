import Foundation

fileprivate final class PetDexCatalogServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: PetDexCatalogServiceProtocol.self)
        let exportedObject = PetDexCatalogXPCService()
        newConnection.exportedObject = exportedObject

        newConnection.interruptionHandler = { }
        newConnection.invalidationHandler = { }

        newConnection.resume()
        return true
    }
}

// Top-level entry point for the embedded XPC service (no @main).
fileprivate let delegate = PetDexCatalogServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
dispatchMain()
