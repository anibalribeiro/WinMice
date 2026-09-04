import Preferences
import SwiftUI

struct ButtonsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var recorder: ButtonRecorder

    var body: some View {
        SettingsForm {
            Section {
                Toggle(isOn: $settings.sideButtonsEnabled) {
                    Text("Use the side buttons")
                    Text("Send Back and Forward to the app under the pointer.")
                }
            }

            Section {
                ForEach(NavigationDirection.allCases) { direction in
                    MappingRow(
                        direction: direction,
                        button: settings[button: direction],
                        isListening: recorder.listeningFor == direction,
                        onRecord: { recorder.listen(for: direction) },
                        onCancel: recorder.cancel
                    )
                }
            } header: {
                Text("Mapping")
            } footer: {
                Text("Choose Set, then press any mouse button you want to use. Mapping a button already used by the other direction swaps the two.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.sideButtonsEnabled)

            Section("Behavior") {
                Picker(selection: $settings.navigationMethod) {
                    ForEach(NavigationMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                } label: {
                    Text("Send")
                    Text(settings.navigationMethod.explanation)
                }
                .pickerStyle(.radioGroup)

                LabeledContent {
                    HStack(spacing: 8) {
                        Picker("Trigger on", selection: $settings.triggerOnMouseDown) {
                            Text("Press").tag(true)
                            Text("Release").tag(false)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                } label: {
                    Text("Trigger on")
                    Text("Pressing feels quicker; releasing avoids repeats when a button chatters.")
                }
            }
            .disabled(!settings.sideButtonsEnabled)
        }
    }
}

private struct MappingRow: View {
    let direction: NavigationDirection
    let button: Int
    let isListening: Bool
    let onRecord: () -> Void
    let onCancel: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if isListening {
                    Text("Press a button…")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Button("Cancel", action: onCancel)
                        .controlSize(.small)
                } else {
                    Text("Button \(button + 1)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button("Set", action: onRecord)
                        .controlSize(.small)
                }
            }
        } label: {
            Text(direction.title)
        }
    }
}

private extension NavigationMethod {
    var title: String {
        switch self {
        case .swipe: "Swipe gesture"
        case .keyboard: "Keyboard shortcut"
        }
    }

    var explanation: String {
        switch self {
        case .swipe: "A two-finger swipe, the same gesture a trackpad sends. Works in most apps."
        case .keyboard: "Command-[ and Command-], for apps that ignore swipes."
        }
    }
}
