import SwiftUI
import HotKey
import AppKit

struct AppLauncherSettingsView: View {
    @ObservedObject var manager = AppLauncherManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("launcher_settings.desc"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Shortcuts List
            VStack(alignment: .leading, spacing: 0) {
                if manager.shortcuts.isEmpty {
                    Text(L10n.t("launcher_settings.empty"))
                        .foregroundColor(.secondary)
                        .padding(20)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 0) {
                        ForEach(manager.shortcuts) { shortcut in
                            AppShortcutRow(shortcut: shortcut)
                            Divider()
                                .gridCellColumns(4)
                        }
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Add Button
            HStack {
                Button(action: addApplication) {
                    Label(L10n.t("launcher_settings.add_app"), systemImage: "plus")
                }
                .controlSize(.large)
                
                Spacer()
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func addApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        if panel.runModal() == .OK, let url = panel.url {
            let appName = url.deletingPathExtension().lastPathComponent
            // Default to no key, user must record one
            // Using a dummy key initially or make key optional in struct?
            // Since struct has let key: Key, we need a default. Let's use F1 as placeholder or make it optional?
            // Making it optional would require changing the struct.
            // Let's use a dummy key and handle "none" state in UI.
            // Or better, let's update AppShortcut to make key optional?
            // No, HotKey library needs a key.
            // Let's assume we don't enable it until a key is set.
            // But for now, let's just initialize with a default harmless key or ask user to record immediately?
            // Let's initialize with a default harmless key (e.g. F19 or something rare) and disabled.
            // But easier to just update the struct to have optional key?
            // No, let's just use F1 for now and user changes it.
            
            let shortcut = AppShortcut(
                appName: appName,
                appPath: url.path,
                key: .f1, // Default, user should change
                modifiers: [],
                isEnabled: false // Disabled by default until configured? Or enabled with dummy?
                // Better: AppShortcut should probably allow 'nil' key if we want 'pending' state.
                // But let's stick to existing struct and maybe use a special 'unassigned' state logic.
                // Actually, let's just set it to something valid but unlikely, and disable it.
            )
            manager.addShortcut(shortcut)
        }
    }
}

struct AppShortcutRow: View {
    let shortcut: AppShortcut
    @ObservedObject var manager = AppLauncherManager.shared
    @State private var isHovering = false
    
    var body: some View {
        GridRow(alignment: .center) {
            // Icon
            Image(nsImage: NSWorkspace.shared.icon(forFile: shortcut.appPath))
                .resizable()
                .frame(width: 32, height: 32)
            
            // Name
            Text(shortcut.appName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)

            // Recorder
            AppShortcutRecorderView(shortcut: shortcut)
                .frame(width: 140)
            
            // Delete Button
            Button(action: {
                manager.removeShortcut(id: shortcut.id)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: 20, height: 20)
        }
        .padding(.horizontal, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 3)
        .background(Color(NSColor.controlBackgroundColor))
        .onHover { hover in
            isHovering = hover
        }
    }
}

struct AppShortcutRecorderView: View {
    let shortcut: AppShortcut
    @ObservedObject var manager = AppLauncherManager.shared
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
                    Text(L10n.t("launcher_settings.type"))
                        .foregroundColor(.blue)
                } else {
                    if shortcut.isEnabled {
                        Text(shortcut.modifiers.displayString + shortcut.key.displayString)
                            .fontWeight(.medium)
                    } else {
                        Text(L10n.t("launcher_settings.record_hotkey"))
                            .foregroundColor(.secondary)
                            .italic()
                    }
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
    
    func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if isRecording {
                if event.keyCode == 53 { // ESC
                    stopRecording()
                    return nil
                }
                // Check for valid key
                if let key = Key(carbonKeyCode: UInt32(event.keyCode)) {
                    // Update shortcut
                    // We need to update the shortcut in the manager
                    let newShortcut = AppShortcut(
                        id: shortcut.id,
                        appName: shortcut.appName,
                        appPath: shortcut.appPath,
                        key: key,
                        modifiers: event.modifierFlags,
                        isEnabled: true
                    )
                    
                    // Find index and update
                    if let index = manager.shortcuts.firstIndex(where: { $0.id == shortcut.id }) {
                        manager.shortcuts[index] = newShortcut
                    }
                    
                    stopRecording()
                    return nil
                }
            }
            return event
        }
    }
    
    func stopRecording() {
        isRecording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
