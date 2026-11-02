import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "keyboard.badge.ellipsis").font(.system(size: 36)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("KeyFlip").font(.largeTitle.bold())
                    Text("Two taps. The text you meant to type.").foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.running ? "ACTIVE" : "PAUSED")
                    .font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(model.running ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                    .clipShape(Capsule())
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    shortcut("⌥", title: "Option · Change keyboard layout", example: "ghbdtn  ↔  привет")
                    Divider()
                    shortcut("⌃", title: "Left Control · Invert letter case", example: "Hello  ↔  hELLO")
                }.padding(8)
            }
            Text("Tap either Option key alone to convert layout, or left Control alone to invert case. Selected text takes priority; otherwise, KeyFlip changes the word before the cursor. Normal keyboard shortcuts keep working.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            GroupBox("Keyboard layouts") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("English", selection: $model.englishID) {
                        ForEach(model.availableLayouts.filter { $0.language == "en" }) { Text($0.name).tag($0.id) }
                    }.onChange(of: model.englishID) { _ in model.saveLayouts() }
                    Picker("Russian", selection: $model.russianID) {
                        ForEach(model.availableLayouts.filter { $0.language == "ru" }) { Text($0.name).tag($0.id) }
                    }.onChange(of: model.russianID) { _ in model.saveLayouts() }
                    HStack {
                        Button("Keyboard Settings…") { model.openSettings("com.apple.Keyboard-Settings.extension") }
                        Button("Refresh") { model.refreshLayouts() }
                    }
                    if !model.availableLayouts.contains(where: { $0.language == "en" }) || !model.availableLayouts.contains(where: { $0.language == "ru" }) {
                        Text("Add U.S. (or ABC) and Russian under Keyboard → Text Input → Edit.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }.padding(8)
            }

            GroupBox("macOS permissions") {
                VStack(spacing: 12) {
                    permission("Accessibility", granted: model.accessibilityGranted, request: model.requestAccessibility,
                               pane: "com.apple.preference.security?Privacy_Accessibility")
                    permission("Input Monitoring", granted: model.monitoringGranted, request: model.requestMonitoring,
                               pane: "com.apple.preference.security?Privacy_ListenEvent")
                    Text("Access lets KeyFlip read the active text field, remember the word you are typing (in memory only), and replace your text. If macOS asks you to quit and reopen, do so after enabling access.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(8)
            }
            Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
            GroupBox("Test conversion") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Editor", selection: $model.testApplicationPID) {
                        Text("Last active: \(model.editorName)").tag(pid_t(0))
                        ForEach(model.testApplications, id: \.processIdentifier) { app in
                            Text(app.localizedName ?? "App \(app.processIdentifier)").tag(app.processIdentifier)
                        }
                    }
                    HStack {
                        Button("Convert layout") { model.applyInEditor(.layout) }
                        Button("Invert case") { model.applyInEditor(.invertCase) }
                        Spacer()
                        Text(model.currentLayoutName).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(model.shortcutStatus).font(.caption).foregroundStyle(.secondary)
                }.padding(6)
            }
            HStack(alignment: .top) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text(model.status).font(.callout).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.frame(minHeight: 36, alignment: .topLeading)
            HStack {
                Text("Works offline. Typed text is never saved.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.enabled ? "Pause" : "Resume") { model.toggleEnabled() }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }.padding(28).frame(width: 550)
    }

    private func shortcut(_ symbol: String, title: String, example: String) -> some View {
        HStack(spacing: 16) {
            Text(symbol).font(.system(size: 26, weight: .medium)).frame(width: 48, height: 42)
                .background(Color.secondary.opacity(0.09)).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.medium)
                Text(example).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func permission(_ name: String, granted: Bool, request: @escaping () -> Void, pane: String) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle").foregroundStyle(granted ? .green : .secondary)
            Text(name)
            Spacer()
            if granted { Text("Allowed").font(.caption).foregroundStyle(.secondary) }
            else { Button("Grant Access", action: request) }
            Button("Open Settings") { model.openSettings(pane) }
        }
    }
}
