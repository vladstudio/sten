# Sten

<img src="icons/Sten.png" width="128" alt="Sten icon">

A lightweight macOS menu bar app for voice-to-text transcription. Press a hotkey, speak, press a hotkey again, and your words are typed into the active application.

**Privacy-first**: All transcription runs on-device using [FluidAudio](https://github.com/FluidInference/FluidAudio).

### Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon chip

## Install

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vladstudio/sten/main/install.sh)"
```

- Verifies macOS 14+ on Apple Silicon
- Downloads the latest release from GitHub
- Installs to `/Applications` (replaces existing version)
- Removes quarantine flag so the unsigned app can run
- Opens the app

## Usage

1. Launch the app — it appears in the menu bar
2. Complete the onboarding wizard (permissions + hotkey setup)
3. Press your hotkey to start recording
4. Press your hotkey again to stop recording
5. Transcribed text is typed into the active app

### Text Transforms

Place shell scripts in `~/.sten/transforms/` to process transcribed text before injection. Enable them from the menu bar.

## Build

```bash
./build.sh
```

This builds the app and installs it to `/Applications/Sten.app`.

## License

MIT
