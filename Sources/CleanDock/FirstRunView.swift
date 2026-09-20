import SwiftUI

/// Shown on first launch, and whenever Accessibility is missing at launch. Three steps; the second one
/// finishes by itself as soon as the permission is granted.
struct FirstRunView: View {
    @ObservedObject var state: AppState
    let close: () -> Void
    @State private var step = 1
    @State private var launchAtLogin = true

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 1: what
                case 2: grant
                default: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 26).padding(.top, 22)
            Divider()
            footer
        }
        .font(.system(size: 13))
        .frame(width: 560, height: 440)
        .onChange(of: state.accessibility) { _, granted in
            if granted, step == 2 { step = 3 }
        }
    }

    private var what: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your Dock icons can be sharp").font(.system(size: 19, weight: .semibold))
                    Text("On a non-Retina display the Dock smears small icons. Clean Dock draws a properly downscaled copy on top, and leaves the Dock itself untouched.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            PreviewView(state: state)
        }
    }

    private var grant: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Grant Accessibility").font(.system(size: 19, weight: .semibold))
            Text("Clean Dock reads where your Dock icons are. It cannot see your screen, your windows or what you type.")
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") { state.openSettingsPane("Privacy_Accessibility") }
                .buttonStyle(.borderedProminent)
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Waiting for permission")
                    Text("This step finishes by itself. You do not need to come back here.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
            Text("Turn on Clean Dock under Privacy & Security → Accessibility.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 430, alignment: .leading)
    }

    private var done: some View {
        let active = state.status == .active
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26)).foregroundStyle(active ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(active ? "Your Dock is sharp now" : "Clean Dock is ready").font(.system(size: 19, weight: .semibold))
                    Text(active ? "Sharp icons follow the Dock live, including bounce, drag and badges."
                                : state.accessibility ? "Clean Dock switches on by itself when your Dock is on a non-Retina display."
                                                      : "Clean Dock switches on by itself once it has the Accessibility permission.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Toggle("Launch at login", isOn: $launchAtLogin).toggleStyle(.checkbox)
            Text("Clean Dock has no Dock icon. It lives in the menu bar, where you can turn it off or open its settings.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Image(systemName: "dock.rectangle").font(.system(size: 15))
                Text("Look for this in your menu bar").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
        }
        .frame(maxWidth: 440, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { index in
                    Circle().fill(index == step ? Color.primary.opacity(0.65) : Color.primary.opacity(0.18)).frame(width: 6, height: 6)
                }
            }
            Spacer()
            if step == 2 { Button("Back") { step = 1 } }
            Button(step == 1 ? "Continue" : step == 2 ? "Skip for now" : "Done") {
                switch step {
                case 1: step = state.accessibility ? 3 : 2
                case 2: step = 3
                default:
                    state.setLaunchAtLogin(launchAtLogin)
                    close()
                }
            }
            .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 26).padding(.top, 14).padding(.bottom, 18)
    }
}
