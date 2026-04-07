// Re-exports shared UpdateChecker with Sten-specific defaults
import MacAppKit

enum StenUpdater {
    static func check(manual: Bool = false) {
        UpdateChecker.check(repo: "vladstudio/sten", appName: "Sten", manual: manual)
    }
}
