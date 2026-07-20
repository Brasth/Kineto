import SwiftUI

struct SummaryViewportLayout: Layout {
    private enum Child: Int {
        case header
        case review
        case footer
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        precondition(subviews.count == 3, "SummaryViewportLayout requires header, review, and footer subviews.")

        let measurementProposal = ProposedViewSize(width: proposal.width, height: nil)
        let headerSize = subviews[Child.header.rawValue].sizeThatFits(measurementProposal)
        let footerSize = subviews[Child.footer.rawValue].sizeThatFits(measurementProposal)
        let idealReviewSize = subviews[Child.review.rawValue].sizeThatFits(measurementProposal)
        let height = proposal.height ?? (headerSize.height + idealReviewSize.height + footerSize.height)
        let reviewHeight = max(0, height - headerSize.height - footerSize.height)
        let reviewSize = subviews[Child.review.rawValue].sizeThatFits(
            ProposedViewSize(width: proposal.width, height: reviewHeight)
        )
        let width = proposal.width ?? max(headerSize.width, max(reviewSize.width, footerSize.width))

        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        precondition(subviews.count == 3, "SummaryViewportLayout requires header, review, and footer subviews.")

        let measurementProposal = ProposedViewSize(width: bounds.width, height: nil)
        let headerSize = subviews[Child.header.rawValue].sizeThatFits(measurementProposal)
        let footerSize = subviews[Child.footer.rawValue].sizeThatFits(measurementProposal)
        let reviewHeight = max(0, bounds.height - headerSize.height - footerSize.height)
        let headerProposal = ProposedViewSize(width: bounds.width, height: headerSize.height)
        let reviewProposal = ProposedViewSize(width: bounds.width, height: reviewHeight)
        let footerProposal = ProposedViewSize(width: bounds.width, height: footerSize.height)

        subviews[Child.header.rawValue].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: headerProposal
        )
        subviews[Child.review.rawValue].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + headerSize.height),
            anchor: .topLeading,
            proposal: reviewProposal
        )
        subviews[Child.footer.rawValue].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + headerSize.height + reviewHeight),
            anchor: .topLeading,
            proposal: footerProposal
        )
    }
}
