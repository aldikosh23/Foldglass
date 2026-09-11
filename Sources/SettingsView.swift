import SwiftUI
import MetalKit

struct MetalPreview: NSViewRepresentable {
    let renderer: FoldRenderer
    func makeNSView(context: Context) -> MTKView { renderer.makeView() }
    func updateNSView(_ view: MTKView, context: Context) { view.needsDisplay = true }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    private let accent = Color(red: 0.66, green: 0.84, blue: 0.98)

    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("foldglass").font(.system(size: 32, weight: .semibold, design: .rounded)).tracking(-1.1)
                    Text("экран следует за крышкой").foregroundStyle(.secondary).font(.system(size: 13))
                }
                Spacer()
                HStack(spacing: 9) {
                    Circle().fill(model.sensorError == nil && model.angle != nil ? accent : .orange).frame(width: 6, height: 6)
                    Text(model.angle.map { "\(Int($0))°" } ?? "...").font(.system(size: 19, weight: .medium, design: .monospaced))
                    Text("крышка").foregroundStyle(.secondary).font(.system(size: 11))
                }.padding(.horizontal, 15).padding(.vertical, 11)
                    .background(.white.opacity(0.045), in: Capsule())
                Toggle("включён", isOn: $model.enabled).toggleStyle(.switch).labelsHidden().padding(.leading, 5).padding(.top, 10)
                    .accessibilityLabel("эффект включён")
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
                        Text(model.previewIsDesktop ? "снимок твоего экрана" : "тестовый экран")
                            .foregroundStyle(.secondary).font(.system(size: 11))
                        Spacer()
                        Button(model.playing ? "остановить" : "проиграть") {
                            if model.playing { model.stopPreview() } else { model.playPreview() }
                        }.buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 12, weight: .medium))
                    }
                    VStack(spacing: 8) {
                        HStack {
                            Text("предпросмотр угла").font(.system(size: 12))
                            Spacer()
                            Text("\(Int(model.previewAngle))°").monospacedDigit().foregroundStyle(accent)
                        }
                        Slider(value: Binding(get: { model.previewAngle }, set: { model.stopPreview(); model.previewAngle = $0 }), in: 12...max(110, model.settings.startAngle))
                            .accessibilityLabel("угол предпросмотра")
                        HStack {
                            Text("закрыт")
                            Spacer()
                            Text("открыт")
                        }.font(.system(size: 10)).foregroundStyle(.tertiary)
                    }.padding(.top, 4)
                }.frame(width: 470)

                VStack(alignment: .leading, spacing: 22) {
                    Text("характер эффекта").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    control("начало", value: $model.settings.startAngle, range: 65...115, suffix: "°", help: "эффект появится ниже этого угла")
                    control("матовое стекло", value: $model.settings.blur, range: 0...96, suffix: "", help: "размытие от верхнего края")
                    control("затемнение", value: $model.settings.darkness, range: 0.4...2, suffix: "×", help: "насколько быстро экран гаснет", decimals: 2)
                    control("растяжение", value: $model.settings.projection, range: 0...1, suffix: "%", help: "компенсация наклона крышки", percent: true)
                    Button("вернуть исходный эффект") { model.resetSettings() }
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
                    Text(model.permission ? "демо длится 6 секунд. клик прервёт эффект." : "нужен один снимок рабочего стола для анимации.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if model.permission {
                    Button("обновить снимок") { model.capturePreview() }.disabled(model.capturing || model.effectVisible)
                    Button("демо на экране") { model.demoDesktop() }
                        .buttonStyle(PrimaryButtonStyle(color: accent))
                        .disabled(model.capturing || !model.enabled)
                } else {
                    Button("дать доступ к экрану") { model.requestPermission() }
                        .buttonStyle(PrimaryButtonStyle(color: accent))
                }
            }.controlSize(.large)
            LoginItemRow(item: model.loginItem)
            HStack {
                Text("снимок хранится только в памяти. окно можно закрыть - foldglass останется в строке меню.")
                Spacer()
                Button("референс") { NSWorkspace.shared.open(URL(string: "https://www.apple.com/iphone-duo/")!) }.buttonStyle(.plain)
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 816)
        .background(LinearGradient(colors: [Color(red: 0.105, green: 0.12, blue: 0.145), Color(red: 0.065, green: 0.07, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.dark)
        .tint(accent)
    }

    private func control(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String, help: String, decimals: Int = 0, percent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(name).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(String(format: "%.*f%@", decimals, value.wrappedValue * (percent ? 100 : 1), suffix))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(accent)
            }
            Slider(value: value, in: range).accessibilityLabel(name)
            Text(help).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
        }
    }
}

private struct LoginItemRow: View {
    @ObservedObject var item: LoginItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("запускать при входе в macos", isOn: Binding(get: { item.isEnabled }, set: { item.setEnabled($0) }))
                    .toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
                Spacer()
                if item.status == .requiresApproval {
                    Button("разрешить в настройках") { item.openSettings() }.font(.system(size: 11))
                } else {
                    Text("в фоне, без окна настроек").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if let error = item.error {
                Text(error).foregroundStyle(.orange).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            } else if item.status == .requiresApproval {
                Text("macos ожидает разрешение на автозапуск").foregroundStyle(.orange).font(.system(size: 11))
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
