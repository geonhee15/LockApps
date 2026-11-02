import SwiftUI

/// In-window card for setting, changing or removing an app's password.
struct PasswordSheet: View {
    enum Mode { case set, change, remove }

    let app: InstalledApp
    let mode: Mode
    var store: LockStore
    var ui: UIState

    @Environment(\.colorScheme) private var scheme
    @State private var current = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var shake = 0
    @FocusState private var focus: Field?

    private enum Field { case current, password, confirm }
    private static let minLength = 4

    private var title: String {
        switch mode {
        case .set: return "\(app.name) 잠그기"
        case .change: return "비밀번호 변경"
        case .remove: return "잠금 해제"
        }
    }

    private var subtitle: String {
        switch mode {
        case .set: return "이 앱을 열 때마다 아래 비밀번호를 묻습니다."
        case .change: return "현재 비밀번호를 확인한 뒤 새 비밀번호로 바꿉니다."
        case .remove: return "현재 비밀번호를 입력하면 \(app.name)의 잠금이 풀립니다."
        }
    }

    private var primaryTitle: String {
        switch mode {
        case .set: return "저장"
        case .change: return "변경"
        case .remove: return "잠금 해제"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: AppIconCache.icon(path: app.path, size: 128))
                    .resizable().interpolation(.high)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 10) {
                if mode != .set {
                    field("현재 비밀번호", text: $current, icon: "key.fill", focus: .current)
                }
                if mode != .remove {
                    field(mode == .set ? "비밀번호" : "새 비밀번호", text: $password, icon: "lock.fill", focus: .password)
                    field("비밀번호 확인", text: $confirm, icon: "checkmark.circle", focus: .confirm)
                }
            }
            .modifier(ShakeEffect(trigger: shake))

            HStack {
                Text(error ?? (mode == .remove ? " " : "\(Self.minLength)자 이상 · 잊어버리면 되찾을 수 없어요"))
                    .font(.system(size: 11.5, weight: error == nil ? .regular : .medium))
                    .foregroundStyle(error == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .lineLimit(2)
                Spacer()
            }
            .padding(.top, -8)

            HStack(spacing: 10) {
                Button("취소") { ui.sheet = nil }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    submit()
                } label: {
                    Text(primaryTitle)
                        .frame(minWidth: 70)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(mode == .remove ? .red : .accentColor)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(22)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                focus = mode == .set ? .password : .current
            }
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .set: return !password.isEmpty && !confirm.isEmpty
        case .change: return !current.isEmpty && !password.isEmpty && !confirm.isEmpty
        case .remove: return !current.isEmpty
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, icon: String, focus target: Field) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focus, equals: target)
                .onSubmit { advance(from: target) }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.fieldFill(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.cardStroke(scheme), lineWidth: 1))
    }

    private func advance(from field: Field) {
        switch (mode, field) {
        case (.change, .current): focus = .password
        case (_, .password): focus = .confirm
        default: if canSubmit { submit() }
        }
    }

    private func fail(_ message: String) {
        error = message
        shake += 1
    }

    private func submit() {
        guard canSubmit else { return }
        if mode != .set {
            guard store.verify(app.bundleID, password: current) else {
                current = ""
                focus = .current
                fail("현재 비밀번호가 맞지 않아요")
                return
            }
        }
        if mode == .remove {
            store.removeLock(app.bundleID)
            ui.flash("\(app.name) 잠금을 해제했어요")
            ui.sheet = nil
            return
        }
        guard password.count >= Self.minLength else {
            focus = .password
            fail("비밀번호는 \(Self.minLength)자 이상이어야 해요")
            return
        }
        guard password == confirm else {
            confirm = ""
            focus = .confirm
            fail("두 비밀번호가 서로 달라요")
            return
        }
        store.setLock(for: app, password: password)
        ui.flash(mode == .set ? "\(app.name)을(를) 잠갔어요" : "\(app.name) 비밀번호를 바꿨어요")
        ui.sheet = nil
    }
}

struct ShakeEffect: ViewModifier, Animatable {
    var trigger: Int
    var animatableData: CGFloat

    init(trigger: Int) {
        self.trigger = trigger
        animatableData = CGFloat(trigger)
    }

    func body(content: Content) -> some View {
        content.offset(x: sin(animatableData * .pi * 4) * 8)
            .animation(.easeInOut(duration: 0.4), value: trigger)
    }
}
