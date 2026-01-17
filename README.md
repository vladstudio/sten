# Sten

<img src="icons/Sten.png" width="128" alt="Sten icon">

A lightweight macOS menu bar app for voice-to-text transcription. Press a hotkey, speak, and your words are typed into the active application.

**Privacy-first**: All transcription runs on-device using [FluidAudio](https://github.com/FluidInference/FluidAudio).

## Requirements

- macOS 14 (Sonoma) or later
- Microphone permission
- Accessibility permission (for text injection and global hotkey)

## Installation

```bash
./build.sh
```

This builds the app and installs it to `/Applications/Sten.app`.

## Usage

1. Launch the app — it appears in the menu bar
2. Complete the onboarding wizard (permissions + hotkey setup)
3. Press your hotkey to start recording
4. Speak — recording stops on silence
5. Transcribed text is typed into the active app

### Text Transforms

Place shell scripts in `~/.sten/transforms/` to process transcribed text before injection. Enable them from the menu bar.

## Menu Bar Icons

| Icon | State |
|------|-------|
| Idle | Ready to record |
| Listening | Recording audio |
| Thinking | Transcribing |
| Warning | Missing permissions |

## Building Manually

```bash
swift build -c release
```

## License

MIT
