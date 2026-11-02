import SwiftUI

enum AppRowAction { case lock, change, remove }

struct AppRow: View {
    let app: InstalledApp
    let isLocked: Bool
    var onAction: (AppRowAction) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIconCache.icon(path: app.path, size: 64))
                .resizable()
                .interpolation(.high)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 13.5, weight: .medium))
                        .lineLimit(1)
                    if app.isSystem {
                        Text("시스템")
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Capsule().fill(Theme.chipFill(scheme)))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(app.bundleID)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)

            if isLocked {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold))
                    Text("잠김").font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Capsule().fill(Theme.locked))

                Menu {
                    Button {
                        onAction(.change)
                    } label: {
                        Label("비밀번호 변경…", systemImage: "key")
                    }
                    Button(role: .destructive) {
                        onAction(.remove)
                    } label: {
                        Label("잠금 해제…", systemImage: "lock.open")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.chipFill(scheme)))
            } else {
                Button {
                    onAction(.lock)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "lock").font(.system(size: 11, weight: .semibold))
                        Text("잠금").font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(Capsule().fill(hovering ? Color.accentColor : Theme.chipFill(scheme)))
                    .foregroundStyle(hovering ? .white : .primary)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(hovering ? Theme.hoverFill(scheme) : Color.clear)
        )
        .card(radius: Theme.rowRadius)
        .contentShape(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { onAction(isLocked ? .change : .lock) }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
