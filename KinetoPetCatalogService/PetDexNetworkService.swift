import Foundation

private actor ManifestCache {
    private var data: Data?
    private var itemJSONs: [String: Data] = [:]   // slug -> raw JSON Data for that pet row

    func storeManifest(_ data: Data, itemJSONs: [String: Data]) {
        self.data = data
        self.itemJSONs = itemJSONs
    }

    func clear() {
        data = nil
        itemJSONs.removeAll()
    }

    func getItemJSON(for slug: String) -> Data? { itemJSONs[slug] }
    func needsRefresh(for slug: String) -> Bool { itemJSONs[slug] == nil }
}

final class PetDexCatalogXPCService: NSObject, PetDexCatalogServiceProtocol, @unchecked Sendable {
    private let network: PetDexNetworkClient
    private let cache = ManifestCache()

    override init() {
        self.network = PetDexNetworkClient()
        super.init()
    }

    func refreshCatalog(withReply reply: @escaping @Sendable (NSData?, NSError?) -> Void) {
        let once = OnceReply(reply)
        Task {
            do {
                let data = try await network.fetchManifest()
                var rows: [String: Data] = [:]
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let pets = json["pets"] as? [[String: Any]] {
                    for pet in pets {
                        if let slug = pet["slug"] as? String,
                           let d = try? JSONSerialization.data(withJSONObject: pet) {
                            rows[slug] = d
                        }
                    }
                }
                await cache.storeManifest(data, itemJSONs: rows)
                once.call(data as NSData, nil)
            } catch let error as NSError {
                await cache.clear()
                once.call(nil, error)
            } catch {
                await cache.clear()
                once.call(nil, NSError(domain: "KinetoPetCatalog", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unexpected error fetching catalog"]))
            }
        }
    }

    func downloadPet(slug: String, withReply reply: @escaping @Sendable (NSData?, NSData?, NSData?, NSError?) -> Void) {
        let once = OnceReply3(reply)
        Task {
            do {
                if await cache.needsRefresh(for: slug) {
                    let manifestData = try await network.fetchManifest()
                    var rows: [String: Data] = [:]
                    if let json = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
                       let pets = json["pets"] as? [[String: Any]] {
                        for pet in pets {
                            if let s = pet["slug"] as? String,
                               let d = try? JSONSerialization.data(withJSONObject: pet) {
                                rows[s] = d
                            }
                        }
                    }
                    await cache.storeManifest(manifestData, itemJSONs: rows)
                }

                guard let itemData = await cache.getItemJSON(for: slug),
                      let item = try? JSONSerialization.jsonObject(with: itemData) as? [String: Any]
                else {
                    once.call(nil, _b: nil, _c: nil, _e: NSError(domain: "KinetoPetCatalog", code: 4, userInfo: [NSLocalizedDescriptionKey: "Pet not found"]))
                    return
                }

                guard let petJsonUrlStr = item["petJsonUrl"] as? String,
                      let spritesheetUrlStr = item["spritesheetUrl"] as? String,
                      let petJsonUrl = URL(string: petJsonUrlStr),
                      let spritesheetUrl = URL(string: spritesheetUrlStr)
                else {
                    once.call(nil, _b: nil, _c: nil, _e: NSError(domain: "KinetoPetCatalog", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid asset URLs in manifest"]))
                    return
                }

                let petJsonData = try await network.fetchAsset(from: petJsonUrl, maxBytes: 64 * 1024, purpose: "pet.json")
                let spriteData = try await network.fetchAsset(from: spritesheetUrl, maxBytes: 16 * 1024 * 1024, purpose: "spritesheet")

                once.call(petJsonData as NSData, _b: spriteData as NSData, _c: itemData as NSData, _e: nil)
            } catch let error as NSError {
                once.call(nil, _b: nil, _c: nil, _e: error)
            } catch {
                once.call(nil, _b: nil, _c: nil, _e: NSError(domain: "KinetoPetCatalog", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unexpected download error"]))
            }
        }
    }
}

private final class OnceReply {
    private let reply: @Sendable (NSData?, NSError?) -> Void
    private let lock = NSLock()
    private var called = false
    init(_ reply: @escaping @Sendable (NSData?, NSError?) -> Void) { self.reply = reply }
    func call(_ d: NSData?, _ e: NSError?) {
        lock.lock(); defer { lock.unlock() }
        guard !called else { return }
        called = true
        reply(d, e)
    }
}

private final class OnceReply3 {
    private let reply: @Sendable (NSData?, NSData?, NSData?, NSError?) -> Void
    private let lock = NSLock()
    private var called = false
    init(_ reply: @escaping @Sendable (NSData?, NSData?, NSData?, NSError?) -> Void) { self.reply = reply }
    func call(_ a: NSData?, _b: NSData?, _c: NSData?, _e: NSError?) {
        lock.lock(); defer { lock.unlock() }
        guard !called else { return }
        called = true
        reply(a, _b, _c, _e)
    }
}
