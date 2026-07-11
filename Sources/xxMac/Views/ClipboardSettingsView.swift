import SwiftUI
import HotKey
import AppKit

struct ClipboardSettingsView: View {
    @ObservedObject var clipboardManager = ClipboardManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsSection(title: L10n.t("clipboard.section_history")) {
                Toggle(isOn: $clipboardManager.settings.clipboardMonitoringEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("clipboard.enable"))
                        Text(L10n.t("clipboard.enable_desc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Stepper(value: Binding(
                    get: { clipboardManager.settings.maxHistoryItems },
                    set: { clipboardManager.settings.maxHistoryItems = $0 }
                ), in: 100...10000, step: 100) {
                    HStack {
                        Text(L10n.t("clipboard.max_history_items"))
                        Spacer()
                        Text(L10n.f("clipboard.items_format", clipboardManager.settings.maxHistoryItems))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            settingsSection(title: L10n.t("clipboard.section_plain")) {
                Picker(L10n.t("clipboard.cache_duration"), selection: $clipboardManager.settings.textCacheDurationDays) {
                    Text(L10n.t("clipboard.days_1")).tag(1)
                    Text(L10n.t("clipboard.days_3")).tag(3)
                    Text(L10n.t("clipboard.days_7")).tag(7)
                    Text(L10n.t("clipboard.days_14")).tag(14)
                    Text(L10n.t("clipboard.days_30")).tag(30)
                    Text(L10n.t("clipboard.days_90")).tag(90)
                }
                
                HStack {
                    Spacer()
                    Button(L10n.t("clipboard.clear_history")) {
                        clipboardManager.clearPlainTextHistory()
                    }
                }
            }
            .disabled(!clipboardManager.settings.clipboardMonitoringEnabled)
            
            settingsSection(title: L10n.t("clipboard.section_images")) {
                Toggle(L10n.t("clipboard.save_images"), isOn: $clipboardManager.settings.manageImages)
                
                if clipboardManager.settings.manageImages {
                    Picker(L10n.t("clipboard.cache_duration"), selection: $clipboardManager.settings.imageCacheDurationDays) {
                        Text(L10n.t("clipboard.days_1")).tag(1)
                        Text(L10n.t("clipboard.days_3")).tag(3)
                        Text(L10n.t("clipboard.days_7")).tag(7)
                        Text(L10n.t("clipboard.days_14")).tag(14)
                        Text(L10n.t("clipboard.days_30")).tag(30)
                    }
                    
                    HStack {
                        Text(L10n.t("clipboard.max_image_size"))
                        Slider(value: Binding(
                            get: { Double(clipboardManager.settings.maxImageSizeMB) },
                            set: { clipboardManager.settings.maxImageSizeMB = Int($0) }
                        ), in: 10...1000, step: 10)
                        Text(L10n.f("clipboard.max_size_format", clipboardManager.settings.maxImageSizeMB))
                            .frame(width: 60, alignment: .trailing)
                    }

                    Stepper(value: Binding(
                        get: { clipboardManager.settings.maxImageStorageSizeMB },
                        set: { clipboardManager.settings.maxImageStorageSizeMB = $0 }
                    ), in: 100...5000, step: 50) {
                        HStack {
                            Text(L10n.t("clipboard.max_image_storage"))
                            Spacer()
                            Text(L10n.f("clipboard.max_size_format", clipboardManager.settings.maxImageStorageSizeMB))
                                .foregroundColor(.secondary)
                        }
                    }

                    Stepper(value: Binding(
                        get: { clipboardManager.settings.thumbnailGenerationThresholdMB },
                        set: { clipboardManager.settings.thumbnailGenerationThresholdMB = $0 }
                    ), in: 1...100, step: 1) {
                        HStack {
                            Text(L10n.t("clipboard.thumbnail_threshold"))
                            Spacer()
                            Text(L10n.f("clipboard.max_size_format", clipboardManager.settings.thumbnailGenerationThresholdMB))
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $clipboardManager.settings.imageOCREnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("clipboard.ocr_enable"))
                            Text(L10n.t("clipboard.ocr_enable_desc"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if clipboardManager.settings.imageOCREnabled {
                        Stepper(value: Binding(
                            get: { clipboardManager.settings.maxOCRImageSizeMB },
                            set: { clipboardManager.settings.maxOCRImageSizeMB = $0 }
                        ), in: 1...100, step: 1) {
                            HStack {
                                Text(L10n.t("clipboard.ocr_max_image_size"))
                                Spacer()
                                Text(L10n.f("clipboard.max_size_format", clipboardManager.settings.maxOCRImageSizeMB))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    HStack {
                        Spacer()
                        Button(L10n.t("clipboard.clear_history")) {
                            clipboardManager.clearImageHistory()
                        }
                    }
                }
            }
            .disabled(!clipboardManager.settings.clipboardMonitoringEnabled)
            
            settingsSection(title: L10n.t("clipboard.section_shortcuts")) {
                HStack {
                    Text(L10n.t("clipboard.toggle_history"))
                    Spacer()
                    ClipboardHotKeyRecorder()
                        .frame(width: 140)
                    
                    if clipboardManager.settings.hotKey != nil {
                        Button(action: {
                            clipboardManager.settings.hotKey = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.leading, 4)
                    }
                }
            }

            Spacer()
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

struct ClipboardHotKeyRecorder: View {
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @State private var isRecording = false
    @State private var monitor: Any?
    
    var body: some View {
        Button(action: {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }) {
            HStack {
                Spacer()
            if isRecording {
                    Text(L10n.t("clipboard.type_hotkey"))
                        .foregroundColor(.blue)
                } else if let hotKey = clipboardManager.settings.hotKey {
                    Text(hotKey.modifiers.displayString + hotKey.key.displayString)
                        .fontWeight(.medium)
                } else {
                    Text(L10n.t("clipboard.none"))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isRecording ? Color.blue.opacity(0.1) : Color(NSColor.textBackgroundColor))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isRecording ? Color.blue : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Ignore if only modifiers are pressed
            // We need to check if a non-modifier key is pressed
            // Modifier flags check is insufficient because modifiers can be pressed alone
            // We check keyCode. Modifiers have specific keyCodes but Key(carbonKeyCode:) handles standard keys.
            
            // Allow only if it's not a modifier key event (modifier key events have no characters usually or specific key codes)
            // But easier: check if Key(carbonKeyCode) returns a valid key and it's not just a modifier.
            // HotKey library Key enum doesn't include bare modifiers like 'command', 'shift'.
            
            if let key = Key(carbonKeyCode: UInt32(event.keyCode)) {
                 // Capture modifiers
                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                
                // Save configuration
                _ = clipboardManager.setHotKey(HotKeyConfiguration(key: key, modifiers: modifiers))
                
                stopRecording()
                return nil // Consume event
            }
            
            return event
        }
    }
    
    private func stopRecording() {
        isRecording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
