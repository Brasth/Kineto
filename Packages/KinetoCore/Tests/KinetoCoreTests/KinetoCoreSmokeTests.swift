import Testing
@testable import KinetoCore

@Test func exposesProductContract() {
    #expect(KinetoCore.productName == "Kineto")
    #expect(KinetoCore.minimumSystemVersion.majorVersion == 15)
    #expect(KinetoCore.minimumSystemVersion.minorVersion == 0)
}
