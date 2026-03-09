import AppKit
import SwiftUI

struct InspectorPanelSection<Content: View>: View {
    let title: LocalizedStringResource?
    @ViewBuilder let content: () -> Content

    init(_ title: LocalizedStringResource? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06))
        )
    }
}

struct PythonDependencyInstallSheet: View {
    let guide: PythonDependencyInstallGuide
    let dismissAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Install pymobiledevice3")
                        .font(.title3.weight(.semibold))

                    Text(
                        "Physical-device simulation needs pymobiledevice3 in the exact Python interpreter selected for the helper."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Resolved Python")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SelectableCodeRow(text: guide.resolvedPythonPath)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Install Command")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SelectableCodeRow(text: guide.installCommand)
            }

            Text("Run the command in Terminal, then return here and retry the physical-device location action.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Copy Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(guide.installCommand, forType: .string)
                }
                .buttonStyle(.borderedProminent)

                Button("Close") {
                    dismissAction()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

struct SelectableCodeRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }
}

enum StatusTone {
    case neutral
    case active
    case good
    case error

    var foregroundColor: Color {
        switch self {
        case .neutral:
            return .secondary
        case .active:
            return .blue
        case .good:
            return .green
        case .error:
            return .red
        }
    }

    var backgroundColor: Color {
        switch self {
        case .neutral:
            return Color.secondary.opacity(0.12)
        case .active:
            return Color.blue.opacity(0.14)
        case .good:
            return Color.green.opacity(0.14)
        case .error:
            return Color.red.opacity(0.14)
        }
    }
}

struct StatusRow: View {
    let title: LocalizedStringResource
    let value: UserFacingText
    let tone: StatusTone

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            StatusRowValue(value: value, tone: tone)
        }
    }
}

struct StatusRowValue: View {
    let value: UserFacingText
    let tone: StatusTone

    var body: some View {
        Text(value)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tone.backgroundColor)
            )
    }
}

struct CopiedPopup: View {
    var body: some View {
        Text("Copied")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.96))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            )
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }
}

struct USBOnboardingSheet: View {
    @State private var suppressFuturePrompts = false

    let guide: USBSetupGuide?
    let continueAction: (Bool) -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.9), Color.cyan.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Physical Device Setup")
                        .font(.title3.weight(.semibold))
                    Text(
                        "Before simulating location on a physical iPhone, confirm the device and host are ready."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SimpleSecurityRow(
                    icon: "iphone.gen3.badge.exclamationmark",
                    text: "Enable Developer Mode on the iPhone in Settings > Privacy & Security > Developer Mode."
                )
                SimpleSecurityRow(
                    icon: "hammer",
                    text:
                        "Install Xcode and open it once so Apple's developer tools finish setup and `xcrun` can access device and simulator tooling."
                )
                SimpleSecurityRow(
                    icon: "terminal",
                    text: "Install Python 3 on this Mac so `python3` resolves from your shell."
                )
                SimpleSecurityRow(
                    icon: "shippingbox",
                    text: "Install pymobiledevice3 into the same Python interpreter used by the device helper."
                )
                SimpleSecurityRow(
                    icon: "wifi",
                    text:
                        "For Wi-Fi discovery, connect once over USB first, accept pairing, then keep the iPhone unlocked on the same local network."
                )
                SimpleSecurityRow(
                    icon: "checkmark.shield",
                    text:
                        "macOS will ask for your administrator password in a separate system dialog when the physical-device tunnel starts."
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Developer Tools")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SelectableCodeRow(text: "xcode-select --install")
                SelectableCodeRow(text: "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer")
            }

            Text(
                "`xcrun` is not guaranteed to be usable on a clean macOS install. If macOS reports missing developer tools, install them with `xcode-select --install`. If full Xcode is already installed but the active developer directory is wrong, run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, then launch Xcode once to finish setup."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Resolved Python")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SelectableCodeRow(
                    text: guide?.pythonStatusText ?? String(localized: TeleportStrings.selectUSBDeviceToResolvePython))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Install Command")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SelectableCodeRow(text: guide?.pythonInstallCommand ?? "python3 -m pip install pymobiledevice3")
            }

            Text(
                "Run the install command in Terminal if needed, then continue. You can copy the command directly from this sheet."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Toggle("Don't show this again", isOn: $suppressFuturePrompts)
                .toggleStyle(.checkbox)

            HStack {
                Button(String(localized: TeleportStrings.cancel), role: .cancel) {
                    cancelAction()
                }

                Button("Copy Install Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        guide?.pythonInstallCommand ?? "python3 -m pip install pymobiledevice3",
                        forType: .string
                    )
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Continue") {
                    continueAction(suppressFuturePrompts)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

struct SimpleSecurityRow: View {
    let icon: String
    let text: LocalizedStringResource

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 18)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
