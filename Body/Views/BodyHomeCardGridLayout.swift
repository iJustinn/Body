//
//  BodyHomeCardGridLayout.swift
//  Body
//

import SwiftUI

/// Lays the Home summary cards out two slots to a row, with a two-slot card (Activity
/// Rings) owning its row.
///
/// This exists so the grid can be a single flat `ForEach` over cards instead of a
/// `ForEach` of rows that each hold their own `ForEach`. Row views were identified by the
/// cards they contained, so a reorder — which `BodyHomeCardDropDelegate` performs while a
/// drag is still in flight — changed those ids and made SwiftUI destroy and rebuild the
/// rows, taking the card being dragged with them. UIKit then had nothing to animate the
/// item back to when the drop was cancelled and read a freed AttributeGraph attribute
/// (`previewForCancelling` -> `UIViewSnapshotResponder.animatedPositionTranslation`,
/// EXC_BAD_ACCESS). With one flat `ForEach` every card keeps a stable identity and a
/// reorder moves it instead of rebuilding it.
struct BodyHomeCardGridLayout: Layout {
    var spacing: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = resolvedWidth(proposal: proposal, subviews: subviews)
        let frames = frames(forWidth: width, subviews: subviews)

        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(forWidth: bounds.width, subviews: subviews)

        for index in subviews.indices {
            let frame = frames[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    /// SwiftUI probes a layout with unspecified, zero, and infinite widths to work out how
    /// flexible it is — on iPad the grid shares an `HStack` with the trends column, so a
    /// wrong answer here skews that split. A concrete width is taken as given (the grid is
    /// as wide as it is offered, like the `HStack` of `maxWidth: .infinity` cards it
    /// replaced); only an unspecified or infinite proposal falls back to an ideal width.
    private func resolvedWidth(proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        if let width = proposal.width, width.isFinite {
            return max(0, width)
        }

        let idealColumn = subviews.indices.map { index -> CGFloat in
            let ideal = subviews[index].sizeThatFits(.unspecified).width
            return slotCount(of: subviews[index]) >= BodyHomeCardGridPacking.slotsPerRow
                ? max(0, (ideal - spacing) / 2)
                : ideal
        }.max() ?? 0

        return idealColumn * 2 + spacing
    }

    /// Rects for every subview in the layout's own coordinate space (origin `.zero`).
    private func frames(forWidth width: CGFloat, subviews: Subviews) -> [CGRect] {
        let slotCounts = subviews.map { slotCount(of: $0) }
        let rows = BodyHomeCardGridPacking.rows(slotCounts: slotCounts)
        let columnWidth = max(0, (width - spacing) / 2)

        var frames = [CGRect](repeating: .zero, count: subviews.count)
        var y: CGFloat = 0

        for (rowIndex, row) in rows.enumerated() {
            if rowIndex > 0 {
                y += spacing
            }

            let widths = row.map { index in
                slotCounts[index] >= BodyHomeCardGridPacking.slotsPerRow ? max(0, width) : columnWidth
            }
            let heights = row.enumerated().map { offset, index in
                subviews[index].sizeThatFits(ProposedViewSize(width: widths[offset], height: nil)).height
            }
            let rowHeight = heights.max() ?? 0
            var x: CGFloat = 0

            for (offset, index) in row.enumerated() {
                // Reproduces the `HStack`'s default `.center` alignment: a short card sits
                // centered against a taller neighbour rather than pinned to the top.
                frames[index] = CGRect(
                    x: x,
                    y: y + (rowHeight - heights[offset]) / 2,
                    width: widths[offset],
                    height: heights[offset]
                )
                x += columnWidth + spacing
            }

            y += rowHeight
        }

        return frames
    }

    private func slotCount(of subview: LayoutSubview) -> Int {
        max(1, subview[BodyHomeCardSlotCountLayoutValue.self])
    }
}

/// How many of a row's two slots a Home grid card occupies.
struct BodyHomeCardSlotCountLayoutValue: LayoutValueKey {
    static let defaultValue = 1
}

extension View {
    func bodyHomeCardSlots(_ count: Int) -> some View {
        layoutValue(key: BodyHomeCardSlotCountLayoutValue.self, value: count)
    }
}
