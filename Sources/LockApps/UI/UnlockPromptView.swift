import SwiftUI

/// The password card shown over a frosted copy of the screen when a locked app opens.
struct UnlockPromptView: View {
    @Bindable var model: UnlockPromptModel
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            if RenderMode.flat {
                SimulatedWallpaper().ignoresSafeArea()
            } else {
                VisualEffectBackdrop(material: .fullScreenUI, blending: .behindWindow)
                    .ignoresSafeArea()
            }
            Color.black.opacity(scheme == .dark ? 0.35 : 0.18)
                .ignoresSafeArea()

            card
                .frame(width: 380)
                .modifier(Shake(trigger: model.shake))
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
        .onChange(of: model.bundleID) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
    }

    private var card: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: model.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.locked))
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                    .offset(x: 6, y: 6)
            }
            .padding(.top, 6)

            VStack(spacing: 5) {
                Text(model.appName)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("이 앱은 LockApps로 잠겨 있어요.\n비밀번호를 입력하면 열립니다.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                SecureField("비밀번호", text: $model.password)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                    .onSubmit { model.onSubmit?() }
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.fieldFill(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(model.errorText == nil ? Theme.cardStroke(scheme) : Color.red.opacity(0.6), lineWidth: 1)
            )

            Text(model.errorText ?? " ")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .opacity(model.errorText == nil ? 0 : 1)
                .padding(.top, -8)

            HStack(spacing: 10) {
                Button {
                    model.onCancel?()
                } label: {
                    Text("취소 · 앱 닫기")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)

                Button {
                    model.onSubmit?()
                } label: {
                    Label("잠금 해제", systemImage: "lock.open.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(model.password.isEmpty)
            }
            .padding(.top, -4)

            Text("LockApps")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.tertiary)
        }
        .padding(26)
        .glass(radius: 30)
    }
}

/// Horizontal shake on wrong password.
private struct Shake: ViewModifier, Animatable {
    var trigger: Int
    var animatableData: CGFloat

    init(trigger: Int) {
        self.trigger = trigger
        animatableData = CGFloat(trigger)
    }

    func body(content: Content) -> some View {
        content.offset(x: sin(animatableData * .pi * 4) * 9)
            .animation(.easeInOut(duration: 0.4), value: trigger)
    }
}
