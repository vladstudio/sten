# Sten

<img src="icons/Sten.png" width="128" alt="Sten icon">

A lightweight macOS menu bar app for voice-to-text transcription. Press a hotkey, speak, press a hotkey again, and your words are typed into the active application.

**Privacy-first**: All transcription runs on-device using [FluidAudio](https://github.com/FluidInference/FluidAudio).

### Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon chip

## Install

[Download Sten.zip](https://github.com/vladstudio/sten/releases/latest/download/Sten.zip), unzip, and move to Applications.

Or via terminal:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vladstudio/sten/main/install.sh)"
```

## Usage

1. Launch the app — it appears in the menu bar
2. Complete the onboarding wizard (permissions + hotkey setup)
3. Press your hotkey to start recording
4. Press your hotkey again to stop recording
5. Transcribed text is typed into the active app

### Text Transforms

Sten uses [Tetra](https://github.com/vladstudio/tetra) for text transforms. Tetra commands in `~/.config/tetra/commands/` appear in Sten's menu bar — enable the ones you want to run on transcribed text.

When **Include Context** is enabled in the menu, Sten passes the `STEN_CONTEXT` environment variable (up to 1000 characters from the active app's focused input) to Tetra commands, which they can use for context-aware corrections.

## Build

```bash
./build.sh
```

This builds the app and installs it to `/Applications/Sten.app`.

## License

MIT
