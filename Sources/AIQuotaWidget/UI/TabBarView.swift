import SwiftUI

/// 顶部 Cursor / Codex / Antigravity 三来源切换 Tab。
struct TabBarView: View {
    let selected: ProductTab
    let onSelect: (ProductTab) -> Void
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 4) {
            ForEach(settings.enabledTabs) { value in
                tab(value, title: settings.t(value.titleKey))
            }
        }
        .padding(2)
        .background(.white.opacity(0.12), in: Capsule())
    }

    private func tab(_ value: ProductTab, title: String) -> some View {
        Button {
            onSelect(value)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected == value ? .white : .white.opacity(0.6))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    selected == value ? AnyView(Capsule().fill(.white.opacity(0.25))) : AnyView(Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
