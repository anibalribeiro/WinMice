import AppKit
import Preferences
import SwiftUI

struct GeneralPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: UpdateController

    @State private var loginItemError: String?
    @State private var isConfirmingReset = false

    var body: some View {
        SettingsForm {
            Section("Startup") {
                Toggle(isOn: launchAtLogin) {
                    Text("Open at login")
                    Text("Start WinMice automatically when you log in to your Mac.")
                }

                if let loginItemError {
                    Label(loginItemError, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            Section("Menu Bar") {
                Toggle(isOn: $settings.menuBarIconHidden) {
                    Text("Hide the menu bar icon")
                    Text("WinMice keeps running. Open it again from Finder or Spotlight to bring the icon back. A pending update will show the icon until you dismiss it.")
                }
            }

            Section("Updates") {
                Toggle(isOn: automaticallyChecksForUpdates) {
                    Text("Check for updates automatically")
                    Text("WinMice checks once a day and asks before installing anything.")
                }
            }

            Section {
                LabeledContent {
                    Button("Restore Defaults…") {
                        isConfirmingReset = true
                    }
                } label: {
                    Text("Reset")
                    Text("Puts scrolling, button mapping, and menu bar options back the way they shipped.")
                }

                LabeledContent {
                    Button("Quit WinMice") {
                        NSApp.terminate(nil)
                    }
                } label: {
                    Text("Quit")
                    Text("Stops the event tap, so the mouse goes back to its default behavior.")
                }
            }
        }
        .confirmationDialog(
            "Restore all settings to their defaults?",
            isPresented: $isConfirmingReset
        ) {
            Button("Restore Defaults", role: .destructive) {
                settings.restoreDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Open at login and the automatic update check are handled outside WinMice's own settings and stay as they are.")
        }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { enabled in
                do {
                    try settings.setLaunchAtLogin(enabled)
                    loginItemError = nil
                } catch {
                    loginItemError = "macOS refused the login item: \(error.localizedDescription)"
                }
            }
        )
    }

    private var automaticallyChecksForUpdates: Binding<Bool> {
        Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        )
    }
}
