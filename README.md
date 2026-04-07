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

Place shell scripts in `~/.sten/transforms/` to process transcribed text before injection. Enable them from the menu bar.

Scripts receive transcribed text on stdin and should output the processed text on stdout. When **Include Context** is enabled in the menu, the `STEN_CONTEXT` environment variable contains text from the active app's focused input (up to 1000 characters), which transforms can use for context-aware corrections.

Example transform using a local LLM (Ollama) for grammar correction with context:

```ruby
#!/usr/bin/env ruby
require 'json'; require 'net/http'; require 'uri'

CUSTOM_WORDS = "MyApp, GitHub"
PROMPT = "You are given a speech-to-text transcription. Correct grammar, spelling, " \
  "and misrecognized words based on context. Correct these special words or their " \
  "misspellings to exact spellings: <text>#{CUSTOM_WORDS}</text>. " \
  "Consider nearby text: <text>#{ENV['STEN_CONTEXT']}</text>. " \
  "OUTPUT ONLY THE CORRECTED TEXT. Transcription: "

text = STDIN.read
exit 1 if text.empty?
begin
  uri = URI("http://localhost:11434/api/generate")
  body = { model: "qwen3.5:2b", prompt: PROMPT + text, stream: false,
           options: { num_predict: 1024 }, think: false }.to_json
  response = Net::HTTP.post(uri, body, 'Content-Type' => 'application/json')
  result = JSON.parse(response.body)['response']&.strip
  puts result || text
rescue Errno::ECONNREFUSED
  puts text
end
```

## Build

```bash
./build.sh
```

This builds the app and installs it to `/Applications/Sten.app`.

## License

MIT
