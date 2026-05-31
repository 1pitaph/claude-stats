import AppKit
import SwiftUI

/// A previewable mock of the DMG install window. The release DMG uses Finder's
/// real app and Applications icons over a matching generated background.
struct InstallerBackgroundView: View {
    private enum Layout {
        static let size = CGSize(width: 920, height: 520)
        static let appPosition = CGPoint(x: 235, y: 255)
        static let applicationsPosition = CGPoint(x: 665, y: 255)
        static let iconSize: CGFloat = 128
        static let appPanelSize = CGSize(width: 214, height: 214)
    }

    var showsMockIcons = true

    var body: some View {
        ZStack {
            Color(red: 0.955, green: 0.960, blue: 0.980)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.865, green: 0.875, blue: 0.905))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.62), lineWidth: 3)
                }
                .shadow(color: .white.opacity(0.7), radius: 18, x: -10, y: -10)
                .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 6)
                .frame(width: Layout.appPanelSize.width, height: Layout.appPanelSize.height)
                .position(Layout.appPosition)

            InstallerChevron()
                .stroke(
                    Color(red: 0.16, green: 0.17, blue: 0.19),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 54, height: 78)
                .position(x: 460, y: 255)

            if showsMockIcons {
                InstallerIconPair(
                    appPosition: Layout.appPosition,
                    applicationsPosition: Layout.applicationsPosition,
                    iconSize: Layout.iconSize
                )
            }
        }
        .frame(width: Layout.size.width, height: Layout.size.height)
    }
}

private struct InstallerIconPair: View {
    var appPosition: CGPoint
    var applicationsPosition: CGPoint
    var iconSize: CGFloat

    var body: some View {
        ZStack {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 8)
                .position(appPosition)

            Text(verbatim: "Claude Stats")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 2)
                .background(Color(red: 0.02, green: 0.37, blue: 0.88), in: Capsule())
                .position(x: appPosition.x, y: appPosition.y + 96)

            ApplicationsFolderIcon(iconSize: iconSize)
                .position(applicationsPosition)

            Text(verbatim: "Applications")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color(red: 0.14, green: 0.14, blue: 0.15))
                .position(x: applicationsPosition.x, y: applicationsPosition.y + 96)
        }
    }

    @MainActor
    private var appIcon: NSImage {
        NSImage(named: NSImage.applicationIconName) ?? NSApplication.shared.applicationIconImage
    }
}

private struct ApplicationsFolderIcon: View {
    var iconSize: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(nsImage: applicationsIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize + 26, height: iconSize + 26)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 7)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.96, blue: 0.95),
                            Color(red: 0.82, green: 0.83, blue: 0.83),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Circle().stroke(.black.opacity(0.22), lineWidth: 1))
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: AppIcon.Navigation.turnUpRight)
                        .font(.system(size: 31, weight: .heavy))
                        .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.19))
                        .offset(x: 2, y: -1)
                }
                .offset(x: -12, y: 7)
        }
        .frame(width: iconSize + 52, height: iconSize + 52)
    }

    @MainActor
    private var applicationsIcon: NSImage {
        let icon = NSWorkspace.shared.icon(forFile: "/Applications")
        icon.size = NSSize(width: iconSize + 26, height: iconSize + 26)
        return icon
    }
}

private struct InstallerChevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.82))
        return path
    }
}

#if DEBUG
private struct InstallerWindowPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            FinderTitleBar()
            InstallerBackgroundView()
            FinderPathBar()
        }
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 18)
        .padding(24)
    }
}

private struct FinderTitleBar: View {
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 14) {
                trafficLight(.red)
                trafficLight(.yellow)
                trafficLight(.green)
            }

            HStack(spacing: 8) {
                Image(systemName: AppIcon.Action.installApp)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(verbatim: "Claude Stats")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(red: 0.73, green: 0.69, blue: 0.70))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Color(red: 0.16, green: 0.11, blue: 0.13))
    }

    private func trafficLight(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 18, height: 18)
    }
}

private struct FinderPathBar: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: AppIcon.Action.installApp)
            Text(verbatim: "Claude Stats")
            Image(systemName: AppIcon.Navigation.disclosure)
                .font(.system(size: 12, weight: .bold))
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
            Text(verbatim: "Claude Stats")
            Spacer()
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color(red: 0.72, green: 0.68, blue: 0.69))
        .padding(.horizontal, 20)
        .frame(height: 38)
        .background(Color(red: 0.20, green: 0.15, blue: 0.17))
    }
}

#Preview("DMG install window") {
    InstallerWindowPreview()
        .preferredColorScheme(.light)
}

#Preview("DMG background only") {
    InstallerBackgroundView()
        .preferredColorScheme(.light)
}
#endif
