import SwiftUI

struct RootView: View {
    var scanner: AppScanner
    var store: LockStore
    var settings: AppSettings
    var engine: LockEngine
    @Bindable var ui: UIState
    @Environment(\.colorScheme) private var scheme

    private var filteredApps: [InstalledApp] {
        let query = ui.search.trimmingCharacters(in: .whitespaces)
        return scanner.apps.filter { app in
            if ui.filter == .locked, !store.isLocked(app.bundleID) { return false }
            guard !query.isEmpty else { return true }
            return app.name.localizedCaseInsensitiveContains(query) || app.bundleID.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            if RenderMode.flat {
                SimulatedWallpaper().ignoresSafeArea()
            } else {
                VisualEffectBackdrop(material: .popover, blending: .behindWindow)
                    .ignoresSafeArea()
            }
            LinearGradient(
                colors: scheme == .dark
                    ? [Color.white.opacity(0.06), Color.clear, Color.black.opacity(0.18)]
                    : [Color.white.opacity(0.55), Color.white.opacity(0.15), Color.clear],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                    .padding(.top, 36)
                    .padding(.horizontal, 22)
                controls
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                appList
                bottomBar
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
            }
            .ignoresSafeArea()

            if RenderMode.flat {
                FakeTrafficLights()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 14)
                    .padding(.leading, 14)
                    .ignoresSafeArea()
            }

            overlaySheet
        }
        .frame(minWidth: 520, minHeight: 580)
        .animation(.spring(duration: 0.28, bounce: 0.12), value: ui.sheet)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.62, blue: 1.0), Color(red: 0.20, green: 0.27, blue: 0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: Color(red: 0.2, green: 0.3, blue: 0.9).opacity(0.35), radius: 10, y: 5)
                Image(systemName: "lock.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text("LockApps")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("고른 앱을 열 때 비밀번호를 묻습니다")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()

            statusPill

            Button {
                ui.sheet = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glass(radius: 17, interactive: true)
            .help("설정")
        }
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(settings.protectionEnabled ? Theme.protectedGreen : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
                .shadow(color: settings.protectionEnabled ? Theme.protectedGreen.opacity(0.8) : .clear, radius: 4)
            Text(settings.protectionEnabled ? "보호 중" : "꺼짐")
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .glass(radius: 15)
    }

    // MARK: Search + filter

    private var controls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("앱 이름이나 번들 ID로 검색", text: $ui.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                if !ui.search.isEmpty {
                    Button {
                        ui.search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .glass(radius: 18, interactive: true)

            HStack(spacing: 2) {
                ForEach(ListFilter.allCases) { f in
                    let count = f == .all ? scanner.apps.count : store.count
                    Button {
                        ui.filter = f
                    } label: {
                        HStack(spacing: 5) {
                            Text(f.title)
                            Text("\(count)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ui.filter == f ? .white.opacity(0.9) : .secondary)
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .background(
                            Capsule().fill(ui.filter == f ? Color.accentColor : Color.clear)
                        )
                        .foregroundStyle(ui.filter == f ? .white : .primary)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(4)
            .glass(radius: 18)
        }
    }

    // MARK: List

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if scanner.isScanning && scanner.apps.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("설치된 앱을 찾는 중…").font(.system(size: 12.5)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else if filteredApps.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredApps) { app in
                        AppRow(app: app, isLocked: store.isLocked(app.bundleID)) { action in
                            switch action {
                            case .lock: ui.sheet = .setPassword(app)
                            case .change: ui.sheet = .changePassword(app)
                            case .remove: ui.sheet = .removeLock(app)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.automatic)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: ui.filter == .locked ? "lock.open" : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(ui.filter == .locked && ui.search.isEmpty ? "아직 잠근 앱이 없어요" : "검색 결과가 없어요")
                .font(.system(size: 14, weight: .semibold))
            Text(ui.filter == .locked && ui.search.isEmpty
                 ? "전체 목록에서 앱 옆의 \"잠금\"을 눌러 비밀번호를 정하세요."
                 : "다른 이름이나 번들 ID로 찾아보세요.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    // MARK: Bottom bar

    private var statusTitle: String {
        if settings.protectionEnabled { return "보호 중 · 잠근 앱 \(store.count)개" }
        return store.count == 0 ? "잠근 앱이 없어요" : "잠근 앱 \(store.count)개 · 아직 적용 안 됨"
    }

    private var statusSubtitle: String {
        if let toast = ui.toast { return toast }
        if settings.protectionEnabled {
            return engine.heldCount > 0 ? "비밀번호를 기다리는 앱 \(engine.heldCount)개" : "저장한 잠금은 바로 적용돼요 · 창을 닫아도 메뉴 막대에서 계속 지킵니다"
        }
        return store.count == 0 ? "앱을 골라 비밀번호를 정한 뒤 적용을 누르세요" : "적용을 누르면 지금부터 비밀번호를 묻습니다"
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            Image(systemName: settings.protectionEnabled ? "checkmark.shield.fill" : "shield.slash")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(settings.protectionEnabled ? Theme.protectedGreen : .secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(statusSubtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            if settings.protectionEnabled {
                Button("보호 끄기") {
                    ProtectionActions.turnOff(settings: settings, ui: ui)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button {
                    ProtectionActions.apply(settings: settings, ui: ui)
                } label: {
                    Label("적용", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 13.5, weight: .semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.count == 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .glass(radius: 22)
        .animation(.easeOut(duration: 0.2), value: ui.toast)
    }

    // MARK: Overlay sheets

    @ViewBuilder
    private var overlaySheet: some View {
        if let sheet = ui.sheet {
            ZStack {
                Color.black.opacity(scheme == .dark ? 0.45 : 0.22)
                    .ignoresSafeArea()
                    .onTapGesture { ui.sheet = nil }
                Group {
                    switch sheet {
                    case .setPassword(let app):
                        PasswordSheet(app: app, mode: .set, store: store, ui: ui)
                    case .changePassword(let app):
                        PasswordSheet(app: app, mode: .change, store: store, ui: ui)
                    case .removeLock(let app):
                        PasswordSheet(app: app, mode: .remove, store: store, ui: ui)
                    case .settings:
                        SettingsSheet(settings: settings, store: store, ui: ui)
                    }
                }
                .frame(width: 400)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(scheme == .dark ? Color(white: 0.08).opacity(0.72) : Color.white.opacity(0.55))
                )
                .glass(radius: 26)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
            .transition(.opacity)
        }
    }
}
