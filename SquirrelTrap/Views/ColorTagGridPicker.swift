import SwiftUI

/// The 4x4 preset color-swatch grid, shared between IntentRowView's per-item
/// picker and Preferences' Default Color picker so both stay visually
/// identical and only need updating in one place. Tapping the already-
/// selected swatch clears it (passes nil to onSelect).
struct ColorTagGridPicker: View {
    let selected: TodoColorTag?
    let onSelect: (TodoColorTag?) -> Void

    private static let columns = Array(repeating: GridItem(.fixed(28), spacing: 6), count: 4)

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: 6) {
            ForEach(TodoColorTag.allCases, id: \.self) { tag in
                Button {
                    onSelect(selected == tag ? nil : tag)
                } label: {
                    Circle()
                        .fill(tag.color)
                        .frame(width: 24, height: 24)
                        .overlay {
                            if selected == tag {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }
}
