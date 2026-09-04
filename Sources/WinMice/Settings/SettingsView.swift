import Preferences
import SwiftUI

/// Sidebar plus detail layout, in the shape of System Settings.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissions: PermissionsMonitor
    @ObservedObject var recorder: ButtonRecorder
    @ObservedObject var updater: UpdateController

    @State private var pane: SettingsPane = .scrolling

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [WinMiceTheme.aluminumLight, WinMiceTheme.aluminumMid, WinMiceTheme.aluminumDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 0) {
                SettingsSidebar(selection: $pane, permissions: permissions)
                Divider().overlay(WinMiceTheme.sheetBorder)
                detail
            }
            .background(WinMiceTheme.sheetFill)
            .clipShape(RoundedRectangle(cornerRadius: WinMiceTheme.sheetCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WinMiceTheme.sheetCornerRadius, style: .continuous)
                    .strokeBorder(WinMiceTheme.sheetBorder)
            }
            .padding(.top, WinMiceTheme.sheetTopMargin)
            .padding([.leading, .trailing, .bottom], WinMiceTheme.sheetMargin)
        }
        .frame(minWidth: 560, minHeight: 520)
        .tint(WinMiceTheme.controlAccent)
        .foregroundStyle(WinMiceTheme.charcoal)
        .onChange(of: pane) { _, newPane in
            if newPane != .buttons {
                recorder.cancel()
            }
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneHeader
            Divider().overlay(WinMiceTheme.sheetBorder)
            paneContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var paneHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pane.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WinMiceTheme.charcoal)
            Text(pane.subtitle)
                .font(.caption)
                .foregroundStyle(WinMiceTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsMetrics.contentPadding)
        .padding(.top, SettingsMetrics.titlebarInset)
        .padding(.bottom, 6)
    }

    private var paneContent: some View {
        VStack(spacing: 0) {
            if !permissions.allGranted, pane != .permissions {
                NoticeBanner(
                    symbol: "exclamationmark.triangle.fill",
                    message: "WinMice needs system permissions before it can read your mouse buttons.",
                    actionTitle: "Review"
                ) {
                    pane = .permissions
                }
            }
            selectedPane
        }
    }

    @ViewBuilder
    private var selectedPane: some View {
        switch pane {
        case .scrolling:
            ScrollingPane(settings: settings)
        case .buttons:
            ButtonsPane(settings: settings, recorder: recorder)
        case .general:
            GeneralPane(settings: settings, updater: updater)
        case .permissions:
            PermissionsPane(permissions: permissions)
        case .about:
            AboutPane()
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane
    @ObservedObject var permissions: PermissionsMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            identity
            VStack(spacing: 1) {
                ForEach(SettingsPane.allCases) { pane in
                    SidebarRow(
                        pane: pane,
                        isSelected: pane == selection,
                        needsAttention: pane == .permissions && !permissions.allGranted
                    ) {
                        selection = pane
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            Spacer(minLength: 0)
            permissionsFooter
        }
        .frame(width: SettingsMetrics.sidebarWidth)
    }

    private var identity: some View {
        HStack(spacing: 8) {
            AppIconView()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(AppInfo.name)
                    .font(.system(size: 12, weight: .semibold))
                Text(versionLine)
                    .font(.caption2)
                    .foregroundStyle(WinMiceTheme.mutedText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, SettingsMetrics.titlebarInset)
        .padding(.bottom, 6)
    }

    private var versionLine: String {
        let version = AppInfo.versionDescription
        return version.isEmpty ? AppInfo.tagline : "Version \(version)"
    }

    private var permissionsFooter: some View {
        Button {
            selection = .permissions
        } label: {
            HStack(spacing: 6) {
                Image(systemName: permissions.allGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(permissions.allGranted ? Color.green : Color.orange)
                Text(permissions.allGranted ? "Permissions granted" : "Permissions needed")
                    .font(.caption)
                    .foregroundStyle(WinMiceTheme.mutedText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Divider().overlay(WinMiceTheme.sheetBorder) }
    }
}

private struct SidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    let needsAttention: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                PaneIcon(symbol: pane.symbol, tint: pane.tint, side: 18)
                Text(pane.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(WinMiceTheme.charcoal)
                Spacer(minLength: 0)
                if needsAttention {
                    Circle()
                        .fill(isSelected ? WinMiceTheme.charcoal : Color.orange)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(rowBackground)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: WinMiceTheme.rowCornerRadius, style: .continuous)
        if isSelected {
            shape.fill(WinMiceTheme.accent)
        } else if isHovering {
            shape.fill(WinMiceTheme.charcoal.opacity(0.07))
        }
    }
}
