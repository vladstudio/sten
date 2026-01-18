import AppKit

enum UpdateChecker {
    static let repo = "vladstudio/sten"

    static func check(manual: Bool = false) {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            DispatchQueue.main.async {
                if latest.compare(current, options: .numeric) == .orderedDescending { promptUpdate(latest) }
                else if manual { showUpToDate() }
            }
        }.resume()
    }

    static func showUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.informativeText = "Sten \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") is the latest version."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static func promptUpdate(_ version: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Sten \(version) is available."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { runUpdate() }
    }

    static func runUpdate() {
        let script = "curl -fsSL https://raw.githubusercontent.com/\(repo)/main/install.sh | bash"
        NSAppleScript(source: "tell app \"Terminal\" to do script \"\(script)\"")?.executeAndReturnError(nil)
        NSApp.terminate(nil)
    }
}
