import KinetoCore
import Foundation

struct EvidenceSelection: Identifiable {
    let id = UUID()
    let segment: Segment
    let supportingText: String
}
