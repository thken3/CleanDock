import SwiftUI

/// Status mark that reads without colour: filled circle = active, diamond = needs attention, ring = idle.
struct StatusGlyph: View {
    let status: Status
    var size: CGFloat = 12

    var body: some View {
        switch status {
        case .active:
            Circle().fill(Color.green).frame(width: size, height: size)
        case .needsPermission:
            RoundedRectangle(cornerRadius: 2.5).strokeBorder(Color.orange, lineWidth: 1.6)
                .frame(width: size - 2, height: size - 2).rotationEffect(.degrees(45)).frame(width: size, height: size)
        default:
            Circle().strokeBorder(Color.secondary, lineWidth: 1.6).frame(width: size, height: size)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Preview") { PreviewView(state: state) }
                    section("General") { general }
                    section("Permissions") { permissions }
                    about
                }
                .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 14)
            }
        }
        .font(.system(size: 13))
        .frame(width: 600, height: 480)
    }

    private var header: some View {
        VStack(spacing: 11) {
            HStack {
                Text("Sharpen Dock icons").font(.system(size: 15, weight: .semibold))
                Spacer()
                Toggle("Sharpen Dock icons", isOn: Binding(get: { state.enabled }, set: { state.enabled = $0 }))
                    .toggleStyle(.switch).labelsHidden()
            }
            HStack(spacing: 9) {
                StatusGlyph(status: state.status)
                Text(state.statusText)
                Spacer()
                if state.status == .needsPermission || (!state.accessibility && state.enabled) {
                    Button("Open System Settings") { state.openSettingsPane("Privacy_Accessibility") }
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 15).padding(.bottom, 14)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased()).font(.system(size: 11)).kerning(0.6).foregroundStyle(.secondary)
            content()
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle("Launch at login", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
            Toggle("Show icon in menu bar", isOn: Binding(get: { state.showMenuBarIcon }, set: { state.setShowMenuBarIcon($0) }))
            Text("When the menu bar icon is off, launch Clean Dock again to open this window.")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 20)
        }
        .toggleStyle(.checkbox)
    }

    // MARK: Permissions

    private var permissions: some View {
        VStack(spacing: 0) {
            permissionRow("Accessibility", note: "required", detail: "Reads where your Dock icons are.",
                          state: state.accessibility ? .granted : .notGranted, pane: "Privacy_Accessibility")
            Divider()
            permissionRow("Finder automation", note: "optional",
                          detail: "Knows whether the Trash is full. Without it the Trash keeps its standard icon.",
                          state: state.finder, pane: "Privacy_Automation")
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    title("Folder access", note: "optional")
                    Text("Draws stacks such as Downloads. Without it that stack keeps its standard icon.").foregroundStyle(.secondary)
                }
                if state.folders.isEmpty {
                    Text("No folders in the Dock.").foregroundStyle(.secondary)
                }
                ForEach(Array(state.folders.enumerated()), id: \.offset) { _, folder in
                    HStack(spacing: 10) {
                        Text(folder.name)
                        Spacer()
                        stateLabel(folder.granted ? .granted : .notGranted)
                        Button("Open") { state.openSettingsPane("Privacy_FilesAndFolders") }.controlSize(.small)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    private func title(_ name: String, note: String) -> some View {
        Text("\(Text(name).fontWeight(.semibold))\(Text(" — \(note)").foregroundColor(.secondary))")
    }

    private func permissionRow(_ name: String, note: String, detail: String, state permission: PermissionState, pane: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                title(name, note: note)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            stateLabel(permission)
            Button("Open") { state.openSettingsPane(pane) }.controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func stateLabel(_ permission: PermissionState) -> some View {
        HStack(spacing: 6) {
            switch permission {
            case .granted: StatusGlyph(status: .active, size: 10)
            case .notGranted: StatusGlyph(status: .needsPermission, size: 10)
            case .notAsked: StatusGlyph(status: .noDock, size: 10)
            }
            Text(permission == .granted ? "Granted" : permission == .notGranted ? "Not granted" : "Not asked yet")
        }
        .fixedSize()
    }

    // MARK: About

    private var about: some View {
        VStack(spacing: 12) {
            Divider()
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Clean Dock \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").fontWeight(.semibold)
                    Text("Free and open source — MIT license. Clean Dock never captures your screen and never connects to the network.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Link("GitHub", destination: AppState.repository)
                Link("Report a problem", destination: AppState.repository.appendingPathComponent("issues/new"))
            }
        }
    }
}
