import SwiftUI
import AppKit

final class ModifierSettingsModel: ObservableObject {
    @Published var metaControl: Bool
    @Published var metaOption: Bool
    @Published var metaCommand: Bool
    @Published var metaShift: Bool

    @Published var layoutControl: Bool
    @Published var layoutOption: Bool
    @Published var layoutCommand: Bool
    @Published var layoutShift: Bool

    @Published var focusControl: Bool
    @Published var focusOption: Bool
    @Published var focusCommand: Bool
    @Published var focusShift: Bool

    private let originalMeta: NSEvent.ModifierFlags
    private let originalScrollLayout: NSEvent.ModifierFlags
    private let originalScrollFocus: NSEvent.ModifierFlags

    init(meta: NSEvent.ModifierFlags, scrollLayout: NSEvent.ModifierFlags, scrollFocus: NSEvent.ModifierFlags) {
        self.originalMeta = meta
        self.originalScrollLayout = scrollLayout
        self.originalScrollFocus = scrollFocus

        metaControl = meta.contains(.control)
        metaOption  = meta.contains(.option)
        metaCommand = meta.contains(.command)
        metaShift   = meta.contains(.shift)

        layoutControl = scrollLayout.contains(.control)
        layoutOption  = scrollLayout.contains(.option)
        layoutCommand = scrollLayout.contains(.command)
        layoutShift   = scrollLayout.contains(.shift)

        focusControl = scrollFocus.contains(.control)
        focusOption  = scrollFocus.contains(.option)
        focusCommand = scrollFocus.contains(.command)
        focusShift   = scrollFocus.contains(.shift)
    }

    var currentMeta: NSEvent.ModifierFlags {
        flags(metaControl, metaOption, metaCommand, metaShift)
    }

    var currentScrollLayout: NSEvent.ModifierFlags {
        flags(layoutControl, layoutOption, layoutCommand, layoutShift)
    }

    var currentScrollFocus: NSEvent.ModifierFlags {
        flags(focusControl, focusOption, focusCommand, focusShift)
    }

    var hasChanges: Bool {
        currentMeta != originalMeta ||
        currentScrollLayout != originalScrollLayout ||
        currentScrollFocus != originalScrollFocus
    }

    var anyEmpty: Bool {
        currentMeta.isEmpty || currentScrollLayout.isEmpty || currentScrollFocus.isEmpty
    }

    var metaHasCommand: Bool { metaCommand }

    private func flags(_ c: Bool, _ o: Bool, _ cmd: Bool, _ s: Bool) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if c   { f.insert(.control) }
        if o   { f.insert(.option) }
        if cmd { f.insert(.command) }
        if s   { f.insert(.shift) }
        return f
    }
}

struct ModifierSettingsView: View {
    @ObservedObject var model: ModifierSettingsModel
    var onCancel: () -> Void
    var onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Keyboard Meta") {
                modifierGrid(
                    control: $model.metaControl,
                    option:  $model.metaOption,
                    command: $model.metaCommand,
                    shift:   $model.metaShift,
                    isEmpty: model.currentMeta.isEmpty
                )
                if model.metaHasCommand {
                    Label("Command はワークスペース操作と競合します", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            GroupBox("Scroll: Layout") {
                modifierGrid(
                    control: $model.layoutControl,
                    option:  $model.layoutOption,
                    command: $model.layoutCommand,
                    shift:   $model.layoutShift,
                    isEmpty: model.currentScrollLayout.isEmpty
                )
            }

            GroupBox("Scroll: Focus") {
                modifierGrid(
                    control: $model.focusControl,
                    option:  $model.focusOption,
                    command: $model.focusCommand,
                    shift:   $model.focusShift,
                    isEmpty: model.currentScrollFocus.isEmpty
                )
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Restart to Apply") {
                    ConfigStore.save(
                        meta: model.currentMeta,
                        scrollLayout: model.currentScrollLayout,
                        scrollFocus: model.currentScrollFocus
                    )
                    onApply()
                }
                .disabled(!model.hasChanges || model.anyEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    @ViewBuilder
    private func modifierGrid(
        control: Binding<Bool>,
        option:  Binding<Bool>,
        command: Binding<Bool>,
        shift:   Binding<Bool>,
        isEmpty: Bool
    ) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                Toggle("Control (⌃)", isOn: control)
                Toggle("Option (⌥)",  isOn: option)
            }
            GridRow {
                Toggle("Command (⌘)", isOn: command)
                Toggle("Shift (⇧)",   isOn: shift)
            }
        }
        .padding(.vertical, 4)
        if isEmpty {
            Text("最低1つ選択してください")
                .font(.caption)
                .foregroundColor(.red)
        }
    }
}
