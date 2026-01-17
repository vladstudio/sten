import Carbon

final class InputSourceObserver {
    static let shared = InputSourceObserver()

    private let mapping: [String: String] = [
        "com.apple.keylayout.US": "en", "com.apple.keylayout.USInternational-PC": "en", "com.apple.keylayout.British": "en", "com.apple.keylayout.Australian": "en", "com.apple.keylayout.ABC": "en", "com.apple.keylayout.USExtended": "en",
        "com.apple.keylayout.Spanish": "es", "com.apple.keylayout.Spanish-ISO": "es", "com.apple.keylayout.LatinAmerican": "es",
        "com.apple.keylayout.French": "fr", "com.apple.keylayout.French-PC": "fr", "com.apple.keylayout.ABC-AZERTY": "fr", "com.apple.keylayout.Canadian-CSA": "fr",
        "com.apple.keylayout.German": "de", "com.apple.keylayout.ABC-QWERTZ": "de", "com.apple.keylayout.Austrian": "de", "com.apple.keylayout.Swiss": "de",
        "com.apple.keylayout.Italian": "it", "com.apple.keylayout.Italian-Pro": "it",
        "com.apple.keylayout.Portuguese": "pt", "com.apple.keylayout.Brazilian": "pt", "com.apple.keylayout.Brazilian-Pro": "pt",
        "com.apple.keylayout.Dutch": "nl", "com.apple.keylayout.Belgian": "nl",
        "com.apple.keylayout.Russian": "ru", "com.apple.keylayout.RussianWin": "ru", "com.apple.keylayout.Russian-Phonetic": "ru",
        "com.apple.keylayout.Ukrainian": "uk", "com.apple.keylayout.Ukrainian-PC": "uk",
        "com.apple.inputmethod.SCIM.ITABC": "zh", "com.apple.inputmethod.TCIM.Pinyin": "zh", "com.apple.inputmethod.SCIM.Pinyin": "zh",
        "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese": "ja", "com.apple.inputmethod.Kotoeri.Japanese": "ja",
        "com.apple.inputmethod.Korean.2SetKorean": "ko", "com.apple.inputmethod.Korean.390Sebulshik": "ko",
        "com.apple.keylayout.Arabic": "ar", "com.apple.keylayout.Arabic-PC": "ar",
        "com.apple.keylayout.Hindi": "hi", "com.apple.inputmethod.Hindi": "hi",
        "com.apple.keylayout.Turkish": "tr", "com.apple.keylayout.Turkish-QWERTY-PC": "tr",
        "com.apple.keylayout.Polish": "pl", "com.apple.keylayout.Polish-Pro": "pl",
        "com.apple.keylayout.Vietnamese": "vi", "com.apple.keylayout.Thai": "th", "com.apple.keylayout.Indonesian": "id",
        "com.apple.keylayout.Greek": "el", "com.apple.keylayout.Hebrew": "he", "com.apple.keylayout.Czech": "cs",
        "com.apple.keylayout.Hungarian": "hu", "com.apple.keylayout.Romanian": "ro", "com.apple.keylayout.Swedish": "sv",
        "com.apple.keylayout.Norwegian": "no", "com.apple.keylayout.Danish": "da", "com.apple.keylayout.Finnish": "fi"
    ]

    var currentLanguage: String { mapping[currentInputSourceID] ?? "auto" }
    var onChange: (() -> Void)?

    private var currentInputSourceID: String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    }

    func start() {
        stop()
        CFNotificationCenterAddObserver(CFNotificationCenterGetDistributedCenter(), Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
            Unmanaged<InputSourceObserver>.fromOpaque(observer!).takeUnretainedValue().onChange?()
        }, kTISNotifySelectedKeyboardInputSourceChanged, nil, .deliverImmediately)
    }

    func stop() {
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDistributedCenter(), Unmanaged.passUnretained(self).toOpaque(), CFNotificationName(kTISNotifySelectedKeyboardInputSourceChanged), nil)
    }
}
