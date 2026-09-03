import SwiftUI

struct ScrollingPane: View {
    @ObservedObject var settings: AppSettings

    private var isHoldToStart: Bool { settings.scrollMode == .holdToStart }

    var body: some View {
        SettingsForm {
            Section("Autoscroll") {
                Picker(selection: $settings.scrollMode) {
                    ForEach(ScrollMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    Text("Middle-click")
                    Text(settings.scrollMode.explanation)
                }
                .pickerStyle(.radioGroup)

                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(value: holdDelayMs, in: delayRange, step: delayStep)
                        Text("\(settings.holdToStartDelayMs) ms")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .trailing)
                    }
                    .frame(maxWidth: 300)
                } label: {
                    Text("Hold duration")
                    Text("How long to hold the middle button before scrolling latches.")
                }
                .disabled(!isHoldToStart)

                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(value: scrollSpeed, in: speedRange, step: speedStep)
                        Text("\(settings.scrollSpeedPercent)%")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .trailing)
                    }
                    .frame(maxWidth: 300)
                } label: {
                    Text("Speed")
                    Text("How fast a given distance from the anchor scrolls.")
                }
            }

            Section("Direction") {
                Toggle(isOn: $settings.reverseScrollDirectionVertical) {
                    Text("Reverse vertical")
                    Text("Drag down to scroll up instead of down.")
                }

                Toggle(isOn: $settings.reverseScrollDirectionHorizontal) {
                    Text("Reverse horizontal")
                    Text("Drag right to scroll left instead of right.")
                }
            }

            Section("Indicator") {
                LabeledContent("Appearance") {
                    Picker("Appearance", selection: $settings.darkMode) {
                        Text("Light").tag(false)
                        Text("Dark").tag(true)
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                LabeledContent("Size") {
                    Picker("Size", selection: $settings.markerSize) {
                        ForEach(AppSettings.markerSizes, id: \.self) { size in
                            Text("\(size) px").tag(size)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                ScrollIndicatorPreview(darkMode: settings.darkMode, size: settings.markerSize)
            }
        }
    }

    private var delayRange: ClosedRange<Double> {
        Double(AppSettings.holdToStartDelayRange.lowerBound)...Double(AppSettings.holdToStartDelayRange.upperBound)
    }

    private var delayStep: Double {
        Double(AppSettings.holdToStartDelayStep)
    }

    private var holdDelayMs: Binding<Double> {
        Binding(
            get: { Double(settings.holdToStartDelayMs) },
            set: { settings.holdToStartDelayMs = Int($0.rounded()) }
        )
    }

    private var speedRange: ClosedRange<Double> {
        Double(AppSettings.scrollSpeedRange.lowerBound)...Double(AppSettings.scrollSpeedRange.upperBound)
    }

    private var speedStep: Double {
        Double(AppSettings.scrollSpeedStep)
    }

    private var scrollSpeed: Binding<Double> {
        Binding(
            get: { Double(settings.scrollSpeedPercent) },
            set: { settings.scrollSpeedPercent = Int($0.rounded()) }
        )
    }
}

private extension ScrollMode {
    var title: String {
        switch self {
        case .holdToScroll: "Hold to scroll"
        case .holdToStart: "Hold to start"
        }
    }

    var explanation: String {
        switch self {
        case .holdToScroll: "Scroll while the middle button is held, and stop when you release it."
        case .holdToStart: "Hold briefly to latch scrolling, then click any button to stop."
        }
    }
}
