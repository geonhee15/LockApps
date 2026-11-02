import SwiftUI
import AppKit

struct SettingsSheet: View {
    var settings: AppSettings
    var store: LockStore
    var ui: UIState
    @Environment(\.colorScheme) private var scheme

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("설정").font(.system(size: 18, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    ui.sheet = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Theme.chipFill(scheme)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            section("외관") {
                HStack(spacing: 6) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Button {
                            settings.appearance = mode
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: mode.icon).font(.system(size: 15, weight: .medium))
                                Text(mode.title).font(.system(size: 11.5, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(settings.appearance == mode ? Color.accentColor.opacity(scheme == .dark ? 0.35 : 0.18) : Theme.chipFill(scheme))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(settings.appearance == mode ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }

            section("백그라운드") {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        ProtectionActions.setBackgroundAgent(!settings.launchAtLogin, settings: settings, ui: ui)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("로그인 시 자동 실행 · 꺼져도 다시 실행").font(.system(size: 13, weight: .medium))
                                Text("launchd가 LockApps를 지켜봅니다. 로그인하면 자동으로 시작하고, 강제 종료되거나 멈춰도 몇 초 안에 다시 실행돼요. 적용을 누르면 자동으로 켜집니다.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            SwitchKnob(isOn: settings.launchAtLogin)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if settings.launchAtLoginNeedsApproval {
                        HStack(spacing: 8) {
                            Text("시스템 설정에서 LockApps의 백그라운드 실행을 허용해야 해요.")
                                .font(.system(size: 11)).foregroundStyle(.orange)
                            Spacer()
                            Button("시스템 설정 열기") { settings.openLoginItemsSettings() }
                                .controlSize(.small)
                        }
                    }
                    if let err = settings.launchAtLoginError {
                        Text(err).font(.system(size: 11)).foregroundStyle(.red)
                    }
                }
            }

            section("잠금") {
                VStack(alignment: .leading, spacing: 6) {
                    row("보호 상태", settings.protectionEnabled ? "켜짐" : "꺼짐")
                    row("잠근 앱", "\(store.count)개")
                    row("다시 잠기는 때", "앱을 완전히 종료한 뒤")
                    row("창을 닫으면", "Dock에서 사라지고 메뉴 막대에서 계속")
                    HStack {
                        Text("비밀번호 저장").font(.system(size: 12.5)).foregroundStyle(.secondary)
                        Spacer()
                        Text("PBKDF2-SHA256 해시 (원문 저장 안 함)").font(.system(size: 12))
                    }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([LockStore.fileURL])
                    } label: {
                        Label("잠금 데이터 폴더 열기", systemImage: "folder")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.link)
                    .padding(.top, 2)
                }
            }

            section("정보") {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LockApps \(version)").font(.system(size: 12.5, weight: .medium))
                        Text("geonhee15 · 맥에서 앱 잠그기").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://github.com/geonhee15/LockApps")!)
                    } label: {
                        Label("GitHub", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(22)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(radius: 12)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12.5)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 12.5, weight: .medium))
        }
    }
}

/// Drawn switch (NSSwitch does not render in offscreen snapshots; this one also fits the glass look).
private struct SwitchKnob: View {
    var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.35))
                .frame(width: 40, height: 24)
            Circle()
                .fill(.white)
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                .padding(2)
        }
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}
