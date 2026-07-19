import Testing
@testable import KinetoCore

@Test func exposesProductContract() {
    #expect(KinetoCore.productName == "Kineto")
    #expect(KinetoCore.minimumSystemVersion.majorVersion == 26)
    #expect(KinetoCore.minimumSystemVersion.minorVersion == 1)
}
