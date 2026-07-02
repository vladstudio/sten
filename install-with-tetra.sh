#!/bin/bash
set -eu

# Sten + Tetra combined installer.
#
# - Installs Sten (voice-to-text) and Tetra (text transforms) to /Applications
#   by fetching and reusing sten/install.sh (single source of truth for the
#   per-app install logic).
# - Walks the user through configuring an LLM provider (Groq/OpenAI/OpenRouter/Ollama/Custom).
# - Verifies Tetra's HTTP server is reachable before finishing.
#
# Usage:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vladstudio/sten/main/install-with-tetra.sh)"

PORT=24100
STEN_REPO="vladstudio/sten"
TETRA_REPO="vladstudio/tetra"
CONFIG_DIR="$HOME/.config/tetra"
COMMANDS_DIR="$CONFIG_DIR/commands"
CONFIG_FILE="$CONFIG_DIR/config.json"

# ─── Help ────────────────────────────────────────────────────────────────────

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<EOF
Sten + Tetra combined installer.

Installs:
  /Applications/Sten.app
  /Applications/Tetra.app
  ~/.config/tetra/config.json       (chmod 600)

Network endpoints contacted:
  https://github.com/vladstudio/sten/releases/latest/download/Sten.zip
  https://github.com/vladstudio/tetra/releases/latest/download/Tetra.zip
  https://raw.githubusercontent.com/vladstudio/sten/main/install.sh
  One of: api.groq.com / api.openai.com / openrouter.ai (for key verification)

After install, both apps launch and Tetra's HTTP server is verified at
http://localhost:$PORT.

EOF
  exit 0
fi

# ─── Pretty output ───────────────────────────────────────────────────────────

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
dim()   { printf "\033[2m%s\033[0m\n" "$*"; }
green() { printf "\033[32m✓ %s\033[0m\n" "$*"; }
red()   { printf "\033[31m✗ %s\033[0m\n" "$*"; }
arrow() { printf "\033[36m→\033[0m %s\n" "$*"; }

# Wrap a string as a JSON string literal (including surrounding quotes).
# Sufficient for ASCII API keys and URLs; not a full JSON validator.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  printf '"%s"' "$s"
}

# ─── Phase 1: welcome & sanity checks ────────────────────────────────────────

echo
bold "Sten + Tetra installer"
echo
echo "This will install:"
echo "  • Sten  — voice-to-text (on-device)"
echo "  • Tetra — text transforms (AI grammar fix, etc.)"
echo "  • A working LLM config for Fix Speech"
echo
echo "Press Enter to continue, or Ctrl+C to cancel."
read -r

major=$(sw_vers -productVersion | cut -d. -f1)
case "$major" in
  ''|*[!0-9]*) red "Could not determine macOS version."; exit 1 ;;
esac
if [ "$major" -lt 14 ]; then
  red "Requires macOS 14 or newer."
  exit 1
fi
if [ "$(uname -m)" != "arm64" ]; then
  red "Requires Apple Silicon (M1/M2/M3/M4)."
  exit 1
fi

# ─── Phase 2: install both apps via install.sh ──────────────────────────────
# install.sh is the single source of truth for the per-app install logic.
# We fetch it once and run it twice with different env vars.

INSTALL_SH_URL="https://raw.githubusercontent.com/$STEN_REPO/main/install.sh"
arrow "Fetching installer: $INSTALL_SH_URL"
INSTALL_SH=$(curl -fsSL "$INSTALL_SH_URL") || {
  red "Failed to download installer from $INSTALL_SH_URL"
  exit 1
}

install_app() {
  local name="$1" repo="$2"
  echo
  arrow "Installing $name"
  APP_NAME="$name" APP_REPO="$repo" APP_OPEN=0 bash -c "$INSTALL_SH"
}

install_app Tetra "$TETRA_REPO"
install_app Sten  "$STEN_REPO"

# ─── Phase 3: interactive LLM configuration ──────────────────────────────────

mkdir -p "$CONFIG_DIR"

llm_name=""
base_url=""
model=""
api_key=""
overwrite="n"

if [ -f "$CONFIG_FILE" ]; then
  echo
  dim "Found existing $CONFIG_FILE"
  printf "Overwrite it with a fresh config? [y/N] "
  read -r overwrite
  case "$overwrite" in
    [yY]*) overwrite=y ;;
    *)     overwrite=n ;;
  esac
fi

# Returns 0 if key works, 1 if rejected, 2 on network error.
# Uses curl -K (config file) to keep the key out of argv / ps output.
verify_api_key() {
  local key="$1" url="$2"
  local conf; conf=$(mktemp)
  chmod 600 "$conf"
  printf 'header = "Authorization: Bearer %s"\n' "$key" > "$conf"
  local code
  code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 -K "$conf" "$url" 2>/dev/null || echo "000")
  rm -f "$conf"
  case "$code" in
    200) return 0 ;;
    401|403) return 1 ;;
    *) return 2 ;;
  esac
}

# Prompts for an API key for the given provider, loops until verified.
prompt_and_verify_key() {
  local provider_name="$1" verify_url="$2" console_url="$3"
  echo
  arrow "Opening $console_url in your browser..."
  open "$console_url"
  echo "Sign in to $provider_name, create an API key, and paste it below."
  while true; do
    read -s -p "API key: " api_key
    echo
    arrow "Testing key..."
    local rc=0
    verify_api_key "$api_key" "$verify_url" || rc=$?
    case "$rc" in
      0) green "Key works"; return 0 ;;
      1) red "Key rejected. Try again (Ctrl+C to give up)." ;;
      2) red "Can't reach $provider_name right now. Try again (Ctrl+C to give up)." ;;
    esac
  done
}

if [ ! -f "$CONFIG_FILE" ] || [ "$overwrite" = "y" ]; then
  echo
  bold "Which AI provider would you like for the \"Fix Speech\" transform?"
  echo "  1) Groq       — llama-3.3-70b-versatile     (free, fast, recommended)"
  echo "  2) OpenAI     — gpt-4o-mini                  (best quality, paid)"
  echo "  3) OpenRouter — llama-3.3-70b-instruct       (many models, paid)"
  echo "  4) Gemini     — gemini-3.1-flash-lite        (Google, free tier)"
  echo "  5) Ollama     — gemma3:4b                    (local, no account needed)"
  echo "  6) Custom     —                              (any OpenAI-compatible endpoint)"
  echo "  7) Skip       —                              (configure later)"
  printf "Choice [1]: "
  read -r choice
  : "${choice:=1}"

  case "$choice" in
    1)
      llm_name="groq_llama"
      base_url="https://api.groq.com/openai/v1"
      model="llama-3.3-70b-versatile"
      prompt_and_verify_key "Groq" \
        "https://api.groq.com/openai/v1/models" \
        "https://console.groq.com/keys"
      ;;

    2)
      llm_name="openai"
      base_url="https://api.openai.com/v1"
      model="gpt-4o-mini"
      prompt_and_verify_key "OpenAI" \
        "https://api.openai.com/v1/models" \
        "https://platform.openai.com/api-keys"
      ;;

    3)
      llm_name="openrouter"
      base_url="https://openrouter.ai/api/v1"
      model="meta-llama/llama-3.3-70b-instruct"
      prompt_and_verify_key "OpenRouter" \
        "https://openrouter.ai/api/v1/auth/key" \
        "https://openrouter.ai/keys"
      ;;

    4)
      llm_name="gemini"
      base_url="https://generativelanguage.googleapis.com/v1beta/openai"
      model="gemini-3.1-flash-lite"
      prompt_and_verify_key "Gemini" \
        "https://generativelanguage.googleapis.com/v1beta/openai/models" \
        "https://aistudio.google.com/apikey"
      ;;

    5)
      llm_name="local_gemma"
      base_url="http://localhost:11434/v1"
      model="gemma3:4b"
      echo
      arrow "Checking for Ollama at localhost:11434..."
      if curl -sS --max-time 2 http://localhost:11434/api/tags > /dev/null 2>&1; then
        green "Ollama is running"
        echo "  Make sure you've pulled the model:  ollama pull $model"
      else
        red "Ollama not detected."
        echo "  Install it from https://ollama.com/download"
        echo "  Then run: ollama pull $model"
        echo "  (Tetra will start with this config but transforms will fail until Ollama is up.)"
      fi
      ;;

    6)
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

    7)
      llm_name="groq_llama"
      base_url="https://api.groq.com/openai/v1"
      model="llama-3.3-70b-versatile"
      api_key=""
      echo
      dim "Skipped — Tetra will start with a placeholder Groq config (no key)."
      dim "Edit $CONFIG_FILE later to add an API key."
      ;;

    *)
      red "Invalid choice: '$choice'"
      exit 1
      ;;
  esac

  arrow "Writing $CONFIG_FILE"
  cat > "$CONFIG_FILE" <<EOF
{
  "server": { "port": $PORT },
  "llms": {
    $(json_escape "$llm_name"): {
      "baseUrl": $(json_escape "$base_url"),
      "model": $(json_escape "$model"),
      "apiKey": $(json_escape "$api_key"),
      "_note": "Edit this file to change providers or models."
    }
  }
}
EOF
  chmod 600 "$CONFIG_FILE"
  green "Config written"
else
  arrow "Keeping existing config"
fi

# ─── Phase 4: launch & verify ────────────────────────────────────────────────

echo
arrow "Launching Tetra"
echo "  (grant the accessibility prompt if it appears)"
open -a Tetra

attempts=15
tetra_ok=""
for i in $(seq 1 $attempts); do
  if curl -sS --max-time 1 "http://localhost:$PORT/commands" > /dev/null 2>&1; then
    green "Tetra is responding at :$PORT"
    tetra_ok=1
    break
  fi
  sleep 1
done

if [ -z "$tetra_ok" ]; then
  red "Tetra did not respond at :$PORT after $attempts seconds"
  echo "  On first run, this usually means macOS is waiting for you to grant"
  echo "  Accessibility permission. Open Tetra from the menu bar and check."
fi

arrow "Launching Sten"
open -a Sten

echo
bold "All done!"
echo
echo "  Press your Sten hotkey to speak. Fix Speech will run automatically."
echo
echo "  • Sten menu → Fix with Tetra (enabled by default)"
echo "  • Sten creates Fix Speech.prompt.md in $COMMANDS_DIR on first use — edit it to tweak the prompt"
echo "  • Edit $CONFIG_FILE to change LLM providers"
echo
