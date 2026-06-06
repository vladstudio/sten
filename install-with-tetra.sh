#!/bin/bash
set -e

# Sten + Tetra combined installer.
#
# - Installs Sten (voice-to-text) and Tetra (text transforms) to /Applications
# - Seeds ~/.config/tetra/commands/ with AI Fix + a couple of safe demos
# - Walks the user through configuring an LLM provider (Groq/OpenAI/OpenRouter/Ollama/custom)
# - Verifies Tetra's HTTP server is reachable before finishing
#
# Usage:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vladstudio/sten/main/install-with-tetra.sh)"

PORT=24100
STEN_REPO="vladstudio/sten"
TETRA_REPO="vladstudio/tetra"
CONFIG_DIR="$HOME/.config/tetra"
COMMANDS_DIR="$CONFIG_DIR/commands"
CONFIG_FILE="$CONFIG_DIR/config.json"

# ─── Pretty output ──────────────────────────────────────────────────────────

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
dim()   { printf "\033[2m%s\033[0m\n" "$*"; }
green() { printf "\033[32m✓ %s\033[0m\n" "$*"; }
red()   { printf "\033[31m✗ %s\033[0m\n" "$*"; }
arrow() { printf "→ %s\n" "$*"; }

# Escape a string for use as a JSON string literal value (including surrounding quotes).
# API keys are ASCII alphanumeric, but we're paranoid.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  printf '"%s"' "$s"
}

# ─── Phase 1: welcome & checks ──────────────────────────────────────────────

echo
bold "Sten + Tetra installer"
echo
echo "This will install:"
echo "  • Sten  — voice-to-text (on-device)"
echo "  • Tetra — text transforms (AI grammar fix, etc.)"
echo "  • Starter commands and a working LLM config"
echo
echo "Press Enter to continue, or Ctrl+C to cancel."
read -r

if ! sw_vers -productVersion | grep -qE '^(14|1[5-9])'; then
  red "Requires macOS 14 or newer."
  exit 1
fi
if [ "$(uname -m)" != "arm64" ]; then
  red "Requires Apple Silicon (M1/M2/M3/M4)."
  exit 1
fi

# ─── Phase 2: install both apps ─────────────────────────────────────────────

install_app() {
  local name="$1" repo="$2"
  local app_path="/Applications/$name.app"
  local tmp; tmp=$(mktemp -d)

  echo
  arrow "Downloading $name"
  curl -fsSL "https://github.com/$repo/releases/latest/download/$name.zip" -o "$tmp/$name.zip"

  arrow "Extracting"
  ditto -xk "$tmp/$name.zip" "$tmp"
  if [ ! -d "$tmp/$name.app" ]; then
    red "Archive did not contain $name.app"
    exit 1
  fi

  pkill -x "$name" 2>/dev/null || true

  local sudo=""
  [ -w /Applications ] || sudo=sudo
  $sudo rm -rf "$app_path"
  $sudo ditto "$tmp/$name.app" "$app_path"
  xattr -dr com.apple.quarantine "$app_path" 2>/dev/null || true

  rm -rf "$tmp"
  green "$name installed"
}

install_app "Tetra" "$TETRA_REPO"
install_app "Sten"  "$STEN_REPO"

# ─── Phase 3: seed commands folder ──────────────────────────────────────────

mkdir -p "$COMMANDS_DIR"

echo
arrow "Seeding $COMMANDS_DIR"

if [ -f "$COMMANDS_DIR/Uppercase.sh" ]; then
  dim "  exists, skipping: Uppercase.sh"
else
  cat > "$COMMANDS_DIR/Uppercase.sh" <<'EOF'
#!/bin/bash
tr '[:lower:]' '[:upper:]'
EOF
  chmod 755 "$COMMANDS_DIR/Uppercase.sh"
  echo "  wrote Uppercase.sh"
fi

if [ -f "$COMMANDS_DIR/Trim.sh" ]; then
  dim "  exists, skipping: Trim.sh"
else
  cat > "$COMMANDS_DIR/Trim.sh" <<'EOF'
#!/bin/bash
sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
EOF
  chmod 755 "$COMMANDS_DIR/Trim.sh"
  echo "  wrote Trim.sh"
fi

# AI Fix.prompt.md is written after Phase 4, once we know the llm name.

# ─── Phase 4: interactive LLM configuration ─────────────────────────────────

mkdir -p "$CONFIG_DIR"

llm_name=""
base_url=""
model=""
api_key=""
overwrite=""

if [ -f "$CONFIG_FILE" ]; then
  echo
  dim "Found existing $CONFIG_FILE"
  printf "Overwrite it with a fresh config? [y/N] "
  read -r overwrite
fi

if [ ! -f "$CONFIG_FILE" ] || [ "$overwrite" = "y" ] || [ "$overwrite" = "Y" ]; then
  echo
  bold "Which AI provider would you like for the \"AI Fix\" transform?"
  echo "  1) Groq       — free, fast, recommended"
  echo "  2) OpenAI     — best quality, paid"
  echo "  3) OpenRouter — many models, paid"
  echo "  4) Ollama     — local, no account needed"
  echo "  5) Custom     — any OpenAI-compatible endpoint"
  echo "  6) Skip       — configure later"
  printf "Choice [1]: "
  read -r choice
  : "${choice:=1}"

  case "$choice" in
    1)
      llm_name="groq_llama"
      base_url="https://api.groq.com/openai/v1"
      model="llama-3.3-70b-versatile"
      echo
      arrow "Opening https://console.groq.com/keys in your browser..."
      open "https://console.groq.com/keys"
      echo "Sign in, click 'Create API Key', copy the key, and paste it below."
      while true; do
        read -s -p "API key: " api_key
        echo
        arrow "Testing key..."
        code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 \
                -H "Authorization: Bearer $api_key" \
                https://api.groq.com/openai/v1/models || echo "000")
        if [ "$code" = "200" ]; then
          green "Key works"
          break
        elif [ "$code" = "401" ] || [ "$code" = "403" ]; then
          red "Key rejected ($code). Try again (Ctrl+C to give up)."
        else
          red "Got HTTP $code — can't verify. Try again (Ctrl+C to give up)."
        fi
      done
      ;;

    2)
      llm_name="openai"
      base_url="https://api.openai.com/v1"
      model="gpt-4o-mini"
      echo
      arrow "Opening https://platform.openai.com/api-keys in your browser..."
      open "https://platform.openai.com/api-keys"
      echo "Sign in, click 'Create new secret key', copy it, and paste below."
      while true; do
        read -s -p "API key: " api_key
        echo
        arrow "Testing key..."
        code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 \
                -H "Authorization: Bearer $api_key" \
                https://api.openai.com/v1/models || echo "000")
        if [ "$code" = "200" ]; then
          green "Key works"
          break
        elif [ "$code" = "401" ] || [ "$code" = "403" ]; then
          red "Key rejected ($code). Try again (Ctrl+C to give up)."
        else
          red "Got HTTP $code — can't verify. Try again (Ctrl+C to give up)."
        fi
      done
      ;;

    3)
      llm_name="openrouter"
      base_url="https://openrouter.ai/api/v1"
      model="meta-llama/llama-3.3-70b-instruct"
      echo
      arrow "Opening https://openrouter.ai/keys in your browser..."
      open "https://openrouter.ai/keys"
      echo "Sign in, click 'Create Key', copy it, and paste below."
      while true; do
        read -s -p "API key: " api_key
        echo
        arrow "Testing key..."
        code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 \
                -H "Authorization: Bearer $api_key" \
                https://openrouter.ai/api/v1/auth/key || echo "000")
        if [ "$code" = "200" ]; then
          green "Key works"
          break
        elif [ "$code" = "401" ] || [ "$code" = "403" ]; then
          red "Key rejected ($code). Try again (Ctrl+C to give up)."
        else
          red "Got HTTP $code — can't verify. Try again (Ctrl+C to give up)."
        fi
      done
      ;;

    4)
      llm_name="local_gemma"
      base_url="http://localhost:11434/v1"
      model="gemma3:4b"
      echo
      arrow "Checking for Ollama at localhost:11434..."
      if curl -sS --max-time 2 http://localhost:11434/api/tags > /dev/null; then
        green "Ollama is running"
        echo "  Make sure you've pulled the model:  ollama pull $model"
      else
        red "Ollama not detected."
        echo "  Install it from https://ollama.com/download"
        echo "  Then run: ollama pull $model"
        echo "  (Tetra will start with this config but transforms will fail until Ollama is up.)"
      fi
      ;;

    5)
      llm_name="custom"
      echo
      printf "Base URL (e.g. http://localhost:8080/v1): "
      read -r base_url
      printf "Model name: "
      read -r model
      printf "API key (blank if none): "
      read -s api_key
      echo
      ;;

    6|*)
      llm_name="groq_llama"
      base_url="https://api.groq.com/openai/v1"
      model="llama-3.3-70b-versatile"
      api_key=""
      echo
      dim "Skipped — Tetra will start with a placeholder Groq config (no key)."
      dim "Edit $CONFIG_FILE later to add an API key."
      ;;
  esac

  # Build config.json
  if [ -n "$api_key" ]; then
    api_key_line=$'\n      '"\"apiKey\": $(json_escape "$api_key"),"
  else
    api_key_line=""
  fi

  arrow "Writing $CONFIG_FILE"
  cat > "$CONFIG_FILE" <<EOF
{
  "server": { "port": $PORT },
  "llms": {
    $(json_escape "$llm_name"): {
      "baseUrl": $(json_escape "$base_url"),
      "model": $(json_escape "$model"),$api_key_line
      "_note": "Edit this file to change providers or models."
    }
  }
}
EOF
  green "Config written"
else
  arrow "Keeping existing config"
  # Fall back to a generic llm name for AI Fix.prompt.md.
  # User can edit the frontmatter if theirs differs.
  llm_name="groq_llama"
fi

# Now write AI Fix.prompt.md using $llm_name.
if [ -f "$COMMANDS_DIR/AI Fix.prompt.md" ]; then
  dim "  exists, skipping: AI Fix.prompt.md"
else
  arrow "Writing AI Fix.prompt.md (llm: $llm_name)"
  cat > "$COMMANDS_DIR/AI Fix.prompt.md" <<EOF
---
llm: $llm_name
temperature: 0.3
---

Fix grammar, spelling, and misrecognized words in the provided speech-to-text transcription.
Keep the original language.
Remove filler words and mumbling.

{{#context}}
Context:
{{context}}
{{/context}}

Text:
{{text}}

OUTPUT ONLY THE CORRECTED TEXT.
EOF
  green "AI Fix.prompt.md written"
fi

# ─── Phase 5: launch & verify ───────────────────────────────────────────────

echo
arrow "Launching Tetra"
open -a Tetra
sleep 2

if curl -sS --max-time 3 "http://localhost:$PORT/commands" > /dev/null; then
  green "Tetra is responding at :$PORT"
else
  red "Tetra did not respond at :$PORT"
  echo "  Open Tetra from the menu bar and check its settings."
fi

arrow "Launching Sten"
open -a Sten

echo
bold "All done!"
echo
echo "  Press your Sten hotkey to speak. AI Fix will run automatically."
echo
echo "  • Sten menu → Commands… to toggle individual transforms"
echo "  • Edit $COMMANDS_DIR/ to add your own"
echo "  • Edit $CONFIG_FILE to change LLM providers"
echo
