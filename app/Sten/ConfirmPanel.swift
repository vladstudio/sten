import AppKit

final class ConfirmPanel: NSPanel {
    var onConfirm: (() -> Void)?

    init(message: String, confirmTitle: String) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        title = "Sten"
        isFloatingPanel = true
        level = .floating

        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 13)
        label.alignment = .center

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(close))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1B}"

        let confirm = NSButton(title: confirmTitle, target: self, action: #selector(confirmAction))
        confirm.bezelStyle = .rounded
        confirm.hasDestructiveAction = true

        let btnRow = NSStackView(views: [cancel, confirm])
        btnRow.spacing = 8

        let stack = NSStackView(views: [label, btnRow])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        contentView = stack
        center()
    }

    @objc private func confirmAction() { close(); onConfirm?() }
    override var canBecomeKey: Bool { true }
}
