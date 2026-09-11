import SwiftUI
import MetalKit

struct MetalPreview: NSViewRepresentable {
    let renderer: FoldRenderer
    func makeNSView(context: Context) -> MTKView { renderer.makeView() }
    func updateNSView(_ view: MTKView, context: Context) { view.needsDisplay = true }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    private func t(_ key: String) -> String { model.language.text(key) }
    private let accent = Color(red: 0.66, green: 0.84, blue: 0.98)

    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("foldglass").font(.system(size: 32, weight: .semibold, design: .rounded)).tracking(-1.1)
                    Text(t("tagline")).foregroundStyle(.secondary).font(.system(size: 13))
                }
                Spacer()
                HStack(spacing: 9) {
                    Circle().fill(model.sensorError == nil && model.angle != nil ? accent : .orange).frame(width: 6, height: 6)
                    Text(model.angle.map { "\(Int($0))°" } ?? "...").font(.system(size: 19, weight: .medium, design: .monospaced))
                    Text(t("lid")).foregroundStyle(.secondary).font(.system(size: 11))
                }.padding(.horizontal, 15).padding(.vertical, 11)
                    .background(.white.opacity(0.045), in: Capsule())
                Toggle(t("enabled"), isOn: $model.enabled).toggleStyle(.switch).labelsHidden().padding(.leading, 5).padding(.top, 10)
                    .accessibilityLabel(t("effect_enabled"))
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    ZStack(alignment: .top) {
                        MetalPreview(renderer: model.previewRenderer)
                            .aspectRatio(1600.0 / 1040, contentMode: .fit)
                        RoundedRectangle(cornerRadius: 3).fill(.black).frame(width: 42, height: 9)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(6)
                    .background(Color(white: 0.025), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 12)
                    HStack {
                        Text(model.previewIsDesktop ? t("your_snapshot") : t("test_screen"))
                            .foregroundStyle(.secondary).font(.system(size: 11))
                        Spacer()
                        Button(model.playing ? t("stop") : t("play")) {
                            if model.playing { model.stopPreview() } else { model.playPreview() }
                        }.buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 12, weight: .medium))
                    }
                    VStack(spacing: 8) {
                        HStack {
                            Text(t("preview_angle")).font(.system(size: 12))
                            Spacer()
                            Text("\(Int(model.previewAngle))°").monospacedDigit().foregroundStyle(accent)
                        }
                        Slider(value: Binding(get: { model.previewAngle }, set: { model.stopPreview(); model.previewAngle = $0 }), in: 12...max(110, model.settings.startAngle))
                            .accessibilityLabel(t("preview_angle"))
                        HStack {
                            Text(t("closed"))
                            Spacer()
                            Text(t("open"))
                        }.font(.system(size: 10)).foregroundStyle(.tertiary)
                    }.padding(.top, 4)
                }.frame(width: 470)

                VStack(alignment: .leading, spacing: 22) {
                    Text(t("effect_settings")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 7) {
                        control(t("start_angle"), value: $model.settings.startAngle, range: FoldSettings.startAngleRange, suffix: "°", help: t("start_help"))
                        Button(t("calibrate_angle")) { model.calibrateStartAngle() }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
                            .help(t("calibrate_help"))
                            .disabled(model.angle == nil || model.sensorError != nil)
                    }
                    control(t("frosted_glass"), value: $model.settings.blur, range: 0...96, suffix: "", help: t("blur_help"))
                    control(t("dimming"), value: $model.settings.darkness, range: 0.4...2, suffix: "×", help: t("dimming_help"), decimals: 2)
                    control(t("stretch"), value: $model.settings.projection, range: 0...1, suffix: "%", help: t("stretch_help"), percent: true)
                    Button(t("reset_effect")) { model.resetSettings() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
            }

            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Circle().fill(model.permission && model.sensorError == nil ? accent : .orange).frame(width: 5, height: 5)
                        Text(model.status).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    }
                    Text(model.permission ? t("demo_help") : t("capture_help"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if model.permission {
                    Button(t("refresh_snapshot")) { model.capturePreview() }.disabled(model.capturing || model.effectVisible)
                    Button(t("desktop_demo")) { model.demoDesktop() }
                        .buttonStyle(PrimaryButtonStyle(color: accent))
                        .disabled(model.capturing || !model.enabled)
                } else {
                    Button(t("grant_screen_access")) { model.requestPermission() }
                        .buttonStyle(PrimaryButtonStyle(color: accent))
                }
            }.controlSize(.large)
            HStack(alignment: .top, spacing: 20) {
                LoginItemRow(item: model.loginItem, language: model.language)
                Picker(t("language"), selection: $model.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.name).tag(language)
                    }
                }.frame(width: 180).controlSize(.small)
            }
            HStack {
                Text(t("privacy_footer"))
                Spacer()
                Button(t("reference")) { NSWorkspace.shared.open(URL(string: "https://www.apple.com/iphone-duo/")!) }.buttonStyle(.plain)
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 816)
        .background(LinearGradient(colors: [Color(red: 0.105, green: 0.12, blue: 0.145), Color(red: 0.065, green: 0.07, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.dark)
        .tint(accent)
        .environment(\.locale, model.language.locale)
    }

    private func control(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String, help: String, decimals: Int = 0, percent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(name).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(String(format: "%.*f%@", locale: model.language.locale, decimals, value.wrappedValue * (percent ? 100 : 1), suffix))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(accent)
            }
            Slider(value: value, in: range).accessibilityLabel(name)
            Text(help).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
        }
    }
}

private struct LoginItemRow: View {
    @ObservedObject var item: LoginItem
    let language: AppLanguage
    private func t(_ key: String) -> String { language.text(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(t("launch_at_login"), isOn: Binding(get: { item.isEnabled }, set: { item.setEnabled($0) }))
                    .toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
                Spacer()
                if item.status == .requiresApproval {
                    Button(t("allow_in_settings")) { item.openSettings() }.font(.system(size: 11))
                } else {
                    Text(t("background_help")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if let error = item.error {
                Text(error.text(in: language)).foregroundStyle(.orange).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            } else if item.status == .requiresApproval {
                Text(t("login_approval")).foregroundStyle(.orange).font(.system(size: 11))
            }
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(white: 0.06))
            .padding(.horizontal, 15).padding(.vertical, 11)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 9))
    }
}
