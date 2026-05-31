import SwiftUI

enum LinuxDoReadingNavigatorMode: Equatable, Sendable {
    case hidden
    case rail
    case compact
}

enum LinuxDoReadingNavigatorLayout {
    static let minimumFloors = 10
    static let railEnterBreakpoint: CGFloat = 660
    static let railExitBreakpoint: CGFloat = 580
    static let railWidth: CGFloat = 48
    static let railTopInset: CGFloat = 18
    static let railTrailingInset: CGFloat = 12
    static let railVerticalPadding: CGFloat = 10
    static let railSpacing: CGFloat = 8
    static let railCornerRadius: CGFloat = 14
    static let railTrackHeight: CGFloat = 220
    static let railMaxHeight: CGFloat = 300
    static let compactTrailingInset: CGFloat = 16
    static let compactBottomInset: CGFloat = 16

    static func mode(width: CGFloat, totalFloors: Int) -> LinuxDoReadingNavigatorMode {
        guard totalFloors >= minimumFloors else { return .hidden }
        return width >= railEnterBreakpoint ? .rail : .compact
    }

    static func mode(
        width: CGFloat,
        totalFloors: Int,
        currentMode: LinuxDoReadingNavigatorMode
    ) -> LinuxDoReadingNavigatorMode {
        guard totalFloors >= minimumFloors else { return .hidden }
        switch currentMode {
        case .rail:
            return width < railExitBreakpoint ? .compact : .rail
        case .compact:
            return width >= railEnterBreakpoint ? .rail : .compact
        case .hidden:
            return mode(width: width, totalFloors: totalFloors)
        }
    }

    static func positionY(for floor: Int, totalFloors: Int, height: CGFloat) -> CGFloat {
        guard totalFloors > 1, height > 0 else { return 0 }
        let clampedFloor = max(1, min(totalFloors, floor))
        let ratio = CGFloat(clampedFloor - 1) / CGFloat(totalFloors - 1)
        return max(0, min(height, ratio * height))
    }

    static func floor(at y: CGFloat, totalFloors: Int, height: CGFloat) -> Int {
        guard totalFloors > 1, height > 0 else { return 1 }
        let ratio = max(0, min(1, y / height))
        return max(1, min(totalFloors, Int((ratio * CGFloat(totalFloors - 1)).rounded()) + 1))
    }

    static func sampledFloors(_ floors: [Int], totalFloors: Int, limit: Int = 60) -> [Int] {
        guard limit > 0 else { return [] }
        let valid = Array(Set(floors.filter { (1...max(1, totalFloors)).contains($0) })).sorted()
        guard valid.count > limit else { return valid }
        let stride = max(1, Int(ceil(Double(valid.count) / Double(limit))))
        var sampled = valid.enumerated().compactMap { index, floor in
            index.isMultiple(of: stride) ? floor : nil
        }
        if sampled.last != valid.last {
            if sampled.count >= limit {
                sampled[sampled.count - 1] = valid.last!
            } else {
                sampled.append(valid.last!)
            }
        }
        return Array(sampled.prefix(limit))
    }
}

struct LinuxDoReadingNavigator: View {
    let mode: LinuxDoReadingNavigatorMode
    let currentFloor: Int
    let totalFloors: Int
    let loadedFloors: [Int]
    let continueFloor: Int?
    let isLoading: Bool
    let onJump: (Int) -> Void

    @State private var previewFloor: Int?
    @State private var isHovering = false

    var body: some View {
        switch mode {
        case .hidden:
            EmptyView()
        case .rail:
            railBody
        case .compact:
            compactBody
        }
    }

    private var railBody: some View {
        VStack(spacing: LinuxDoReadingNavigatorLayout.railSpacing) {
            statusGlyph
            floorSummary
            trackBody
        }
        .padding(.vertical, LinuxDoReadingNavigatorLayout.railVerticalPadding)
        .frame(width: LinuxDoReadingNavigatorLayout.railWidth)
        .frame(maxHeight: LinuxDoReadingNavigatorLayout.railMaxHeight, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(.thinMaterial, in: RoundedRectangle(
            cornerRadius: LinuxDoReadingNavigatorLayout.railCornerRadius,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(
                cornerRadius: LinuxDoReadingNavigatorLayout.railCornerRadius,
                style: .continuous
            )
                .stroke(Color.primary.opacity(isHovering ? 0.16 : 0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: isHovering ? 9 : 5, x: 0, y: 3)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("LinuxDo reading position")
        .accessibilityValue("#\(boundedCurrentFloor) of \(max(totalFloors, 1))")
    }

    private var compactBody: some View {
        HStack(spacing: 0) {
            Button {
                onJump(max(1, boundedCurrentFloor - 1))
            } label: {
                Image(systemName: AppIcon.Navigation.up)
                    .frame(width: 30, height: 30)
            }
            .disabled(boundedCurrentFloor <= 1 || isLoading)
            .help("Previous post")

            Divider()
                .frame(height: 18)

            Button {
                if let continueFloor {
                    onJump(continueFloor)
                }
            } label: {
                HStack(spacing: 5) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("#\(boundedCurrentFloor)")
                            .font(.sora(11, weight: .semibold).monospacedDigit())
                    }
                    Text("/ \(max(totalFloors, 1))")
                        .font(.sora(9).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                }
                .frame(minWidth: 78)
                .frame(height: 30)
            }
            .disabled(continueFloor == nil || isLoading)
            .help(continueFloor.map { "Continue from #\($0)" } ?? "Current reading position")

            Divider()
                .frame(height: 18)

            Button {
                onJump(min(totalFloors, boundedCurrentFloor + 1))
            } label: {
                Image(systemName: AppIcon.Navigation.down)
                    .frame(width: 30, height: 30)
            }
            .disabled(boundedCurrentFloor >= totalFloors || isLoading)
            .help("Next post")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .contain)
    }

    private var statusGlyph: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: AppIcon.Navigation.verticalResize)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
            }
        }
        .frame(height: 16)
    }

    private var floorSummary: some View {
        VStack(spacing: 1) {
            Text("#\(boundedCurrentFloor)")
                .font(.sora(12, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("of \(max(totalFloors, 1))")
                .font(.sora(8).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(width: 42)
    }

    private var trackBody: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let currentY = LinuxDoReadingNavigatorLayout.positionY(
                for: boundedCurrentFloor,
                totalFloors: totalFloors,
                height: height
            )
            let activeFloor = previewFloor ?? boundedCurrentFloor
            let activeY = LinuxDoReadingNavigatorLayout.positionY(
                for: activeFloor,
                totalFloors: totalFloors,
                height: height
            )

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: 3, height: height)

                Capsule()
                    .fill(Color.stxAccent.opacity(0.55))
                    .frame(width: 3, height: max(2, currentY))

                marker(floor: 1, height: height, color: Color.stxMuted.opacity(0.7), size: 5)

                ForEach(sampledLoadedFloors, id: \.self) { floor in
                    tick(floor: floor, height: height)
                }

                if let continueFloor {
                    marker(floor: continueFloor, height: height, color: .yellow.opacity(0.95), size: 6)
                }

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.stxAccent)
                    .frame(width: isHovering || previewFloor != nil ? 22 : 18, height: 8)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                    }
                    .offset(y: markerOffset(activeY, height: height, size: 8))

                if previewFloor != nil || isHovering {
                    previewBubble(floor: activeFloor)
                        .offset(x: -54, y: markerOffset(activeY, height: height, size: 22))
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        previewFloor = LinuxDoReadingNavigatorLayout.floor(
                            at: value.location.y,
                            totalFloors: totalFloors,
                            height: height
                        )
                    }
                    .onEnded { value in
                        let floor = LinuxDoReadingNavigatorLayout.floor(
                            at: value.location.y,
                            totalFloors: totalFloors,
                            height: height
                        )
                        previewFloor = nil
                        onJump(floor)
                    }
            )
        }
        .frame(height: LinuxDoReadingNavigatorLayout.railTrackHeight)
    }

    private func tick(floor: Int, height: CGFloat) -> some View {
        Capsule()
            .fill(Color.primary.opacity(0.22))
            .frame(width: 11, height: 1.5)
            .offset(y: markerOffset(
                LinuxDoReadingNavigatorLayout.positionY(for: floor, totalFloors: totalFloors, height: height),
                height: height,
                size: 1.5
            ))
    }

    private func marker(floor: Int, height: CGFloat, color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .offset(y: markerOffset(
                LinuxDoReadingNavigatorLayout.positionY(for: floor, totalFloors: totalFloors, height: height),
                height: height,
                size: size
            ))
    }

    private func previewBubble(floor: Int) -> some View {
        Text("#\(floor)")
            .font(.sora(9, weight: .semibold).monospacedDigit())
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            }
    }

    private func markerOffset(_ y: CGFloat, height: CGFloat, size: CGFloat) -> CGFloat {
        max(0, min(max(0, height - size), y - size / 2))
    }

    private var boundedCurrentFloor: Int {
        max(1, min(max(totalFloors, 1), currentFloor))
    }

    private var sampledLoadedFloors: [Int] {
        LinuxDoReadingNavigatorLayout.sampledFloors(loadedFloors, totalFloors: totalFloors)
    }
}
