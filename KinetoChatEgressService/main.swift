import Foundation

fileprivate final class ChatEgressServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: ChatEgressServiceProtocol.self)
        newConnection.exportedObject = ChatEgressXPCService()
        newConnection.interruptionHandler = { }
        newConnection.invalidationHandler = { }
        newConnection.resume()
        return true
    }
}

fileprivate let delegate = ChatEgressServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
dispatchMain()
