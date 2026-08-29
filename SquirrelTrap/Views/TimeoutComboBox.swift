import AppKit
import SwiftUI

/// A native combo box (free-form text entry + dropdown of presets) for picking
/// the auto-dismiss timeout — SwiftUI has no built-in equivalent to NSComboBox.
struct TimeoutComboBox: NSViewRepresentable {
    @Binding var value: Double
    let options: [Double]

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.addItems(withObjectValues: options.map(Self.string(for:)))
        comboBox.stringValue = Self.string(for: value)
        comboBox.font = .systemFont(ofSize: 12)
        comboBox.completes = false
        comboBox.delegate = context.coordinator
        return comboBox
    }

    func updateNSView(_ nsView: NSComboBox, context: Context) {
        let stringValue = Self.string(for: value)
        if nsView.stringValue != stringValue {
            nsView.stringValue = stringValue
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    private static func string(for value: Double) -> String {
        String(Int(value))
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        let value: Binding<Double>

        init(value: Binding<Double>) {
            self.value = value
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox,
                  let number = Double(comboBox.stringValue) else { return }
            apply(number)
        }

        /// Reads the selected item, never `stringValue`.
        ///
        /// AppKit sends this notification BEFORE it copies the chosen item into
        /// the text field, so `stringValue` here is still the value being
        /// replaced. Committing from it wrote the old number straight back:
        /// picking 3 seconds stored 7, and updateNSView then dutifully restored
        /// "7" in the field, so the setting appeared to refuse every choice
        /// made from the dropdown. Typing a number worked, which is what made
        /// it look like the preference itself was ignored rather than unsaved.
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox,
                  let selected = comboBox.objectValueOfSelectedItem as? String,
                  let number = Double(selected) else { return }
            apply(number)
        }

        // Values are clamped rather than rejected, so a stray "0" or a huge
        // number can't produce a broken (zero/negative or absurdly long) Timer
        // interval.
        private func apply(_ number: Double) {
            value.wrappedValue = min(max(number, 1), 300)
        }
    }
}
