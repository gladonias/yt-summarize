#!/usr/bin/env bash
# =============================================================================
# yt_summarise.sh
#
# PURPOSE:
#   Accepts a YouTube URL (from clipboard or argument) or a local audio file,
#   downloads/extracts the audio, transcribes it with Whisper, summarises the
#   transcript with a local Ollama model, and exports a structured Markdown
#   file to your Documents folder.
#
# COMPATIBILITY:
#   macOS, Linux, Windows (Git Bash / WSL)
#
# DEPENDENCIES:
#   - yt-dlp, ffmpeg, openai-whisper, ollama, jq, curl
#   See README.md for installation instructions per platform.
#
# USAGE:
#   ./yt_summarise.sh                  # reads YouTube URL from clipboard
#   ./yt_summarise.sh <youtube_url>    # pass URL directly
#   ./yt_summarise.sh <audio_file>     # pass a local audio file path
#   ./yt_summarise.sh --output-dir DIR --model MODEL <input>
# =============================================================================

set -euo pipefail   # exit on error, unset variable, or pipe failure

# =============================================================================
# OS DETECTION
# =============================================================================
detect_os() {
    case "$(uname -s)" in
        Darwin*)  echo "macos" ;;
        Linux*)   echo "linux" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)        echo "unknown" ;;
    esac
}
OS="$(detect_os)"

# =============================================================================
# DEFAULT SETTINGS
# =============================================================================

OUTPUT_DIR="$HOME/Documents/Summaries"
PROMPT_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/yt_summarise/prompt_instructions.txt"
OLLAMA_MODEL="gemma3:4b"
OLLAMA_URL="http://localhost:11434/api/generate"
OLLAMA_HEALTH_URL="http://localhost:11434/"
WHISPER_MODEL="base"

# =============================================================================
# LOAD CONFIG FILE (if it exists) — overrides defaults above
# =============================================================================
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/yt_summarise/config"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# =============================================================================
# PARSE CLI FLAGS — override config and defaults
# =============================================================================
CLI_OUTPUT_DIR=""
CLI_PROMPT_FILE=""
CLI_MODEL=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            CLI_OUTPUT_DIR="$2"; shift 2 ;;
        --prompt-file)
            CLI_PROMPT_FILE="$2"; shift 2 ;;
        --model)
            CLI_MODEL="$2"; shift 2 ;;
        *)
            POSITIONAL_ARGS+=("$1"); shift ;;
    esac
done

[[ -n "$CLI_OUTPUT_DIR" ]]  && OUTPUT_DIR="$CLI_OUTPUT_DIR"
[[ -n "$CLI_PROMPT_FILE" ]] && PROMPT_FILE="$CLI_PROMPT_FILE"
[[ -n "$CLI_MODEL" ]]       && OLLAMA_MODEL="$CLI_MODEL"

# Restore positional arguments
set -- "${POSITIONAL_ARGS[@]+"${POSITIONAL_ARGS[@]}"}"

# Temporary working directory — cleaned up automatically on exit
TEMP_DIR=$(mktemp -d)

# =============================================================================
# CLEANUP — runs automatically when the script exits (success or failure)
# =============================================================================
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Cross-platform desktop notification
notify() {
    local title="$1"
    local message="$2"
    case "$OS" in
        macos)   osascript -e "display notification \"$message\" with title \"$title\" sound name \"Glass\"" 2>/dev/null || true ;;
        linux)   notify-send "$title" "$message" 2>/dev/null || true ;;
        windows)
            # Escape single quotes for PowerShell single-quoted strings ('' = literal ')
            local _ps_title="${title//\'/\'\'}"
            local _ps_msg="${message//\'/\'\'}"
            powershell.exe -Command "[void](New-BurntToastNotification -Text '$_ps_title','$_ps_msg')" 2>/dev/null || true
            ;;
    esac
    echo "[INFO] $title: $message"
}

# Print an error message, send a notification, and exit
die() {
    echo "[ERROR] $1" >&2
    case "$OS" in
        macos)   osascript -e "display notification \"$1\" with title \"yt_summarise — Error\" sound name \"Basso\"" 2>/dev/null || true ;;
        linux)   notify-send "yt_summarise — Error" "$1" 2>/dev/null || true ;;
        windows)
            # Escape single quotes for PowerShell single-quoted strings ('' = literal ')
            local _ps_msg="${1//\'/\'\'}"
            powershell.exe -Command "[void](New-BurntToastNotification -Text 'yt_summarise — Error','$_ps_msg')" 2>/dev/null || true
            ;;
    esac
    exit 1
}

# Check that a required command exists on PATH
require() {
    command -v "$1" &>/dev/null || die "Required tool not found: '$1'. See README.md for installation instructions."
}

# Cross-platform clipboard paste
clipboard_paste() {
    case "$OS" in
        macos)   pbpaste 2>/dev/null ;;
        linux)
            if command -v xclip &>/dev/null; then
                xclip -selection clipboard -o 2>/dev/null
            elif command -v xsel &>/dev/null; then
                xsel --clipboard --output 2>/dev/null
            else
                echo ""
            fi
            ;;
        windows) powershell.exe -Command "Get-Clipboard" 2>/dev/null | tr -d '\r' ;;
        *)       echo "" ;;
    esac
}

# Cross-platform file opener
open_file() {
    case "$OS" in
        macos)   open "$1" ;;
        linux)   xdg-open "$1" 2>/dev/null ;;
        windows) start "" "$1" 2>/dev/null ;;
    esac
}

# =============================================================================
# DEPENDENCY CHECKS
# =============================================================================
require yt-dlp
require ffmpeg
require whisper
require curl
require jq

# Check Ollama is actually running by hitting the root health endpoint
curl -sf "$OLLAMA_HEALTH_URL" -o /dev/null --max-time 3 \
    || die "Ollama is not running. Start it with: ollama serve"

# Ensure the output directory exists, create it if not
mkdir -p "$OUTPUT_DIR"

# Ensure the prompt instructions file exists
[[ -f "$PROMPT_FILE" ]] \
    || die "Prompt instructions file not found at: $PROMPT_FILE\nSee README.md for setup instructions."

# =============================================================================
# DETERMINE INPUT SOURCE
# =============================================================================

INPUT=""
IS_YOUTUBE=false
IS_LOCAL_FILE=false

if [[ $# -ge 1 ]]; then
    # An argument was passed — could be a URL or a local file path
    INPUT="$1"
else
    # No argument — read from system clipboard
    INPUT=$(clipboard_paste || true)
fi

[[ -z "$INPUT" ]] && die "No input provided and clipboard is empty. Copy a YouTube URL first."

# Detect whether input is a YouTube URL or a local file
if echo "$INPUT" | grep -qE '(youtube\.com|youtu\.be)'; then
    IS_YOUTUBE=true
    notify "yt_summarise" "YouTube URL detected. Starting..."
elif [[ -f "$INPUT" ]]; then
    IS_LOCAL_FILE=true
    notify "yt_summarise" "Local audio file detected: $(basename "$INPUT")"
else
    die "Input doesn't look like a YouTube URL or an existing file.\nClipboard contents: $INPUT"
fi

# =============================================================================
# STEP 1 — GET VIDEO TITLE AND AUDIO
# =============================================================================

VIDEO_TITLE="Unknown Title"
VIDEO_URL=""
AUDIO_FILE="$TEMP_DIR/audio.mp3"

if $IS_YOUTUBE; then
    VIDEO_URL="$INPUT"

    echo "[INFO] Fetching video title..."
    VIDEO_TITLE=$(yt-dlp --get-title "$VIDEO_URL" 2>/dev/null || echo "Unknown Title")
    echo "[INFO] Title: $VIDEO_TITLE"

    notify "yt_summarise" "Downloading audio for: $VIDEO_TITLE"
    echo "[INFO] Downloading and extracting audio from YouTube..."

    yt-dlp \
        --extract-audio \
        --audio-format mp3 \
        --audio-quality 0 \
        --output "$TEMP_DIR/audio.%(ext)s" \
        "$VIDEO_URL" \
        || die "yt-dlp failed to download audio. Check the URL and your internet connection."

else
    # Local file path — extract title from filename, convert to mp3 for Whisper
    VIDEO_TITLE=$(basename "$INPUT" | sed 's/\.[^.]*$//')
    VIDEO_URL="Local file: $INPUT"

    echo "[INFO] Converting local audio file to mp3..."
    ffmpeg -i "$INPUT" -q:a 0 -map a "$AUDIO_FILE" -y -loglevel error \
        || die "ffmpeg failed to convert the audio file. Is the file a valid audio/video format?"
fi

[[ -f "$AUDIO_FILE" ]] \
    || die "Audio file was not created at $AUDIO_FILE. Something went wrong during extraction."

# =============================================================================
# STEP 2 — TRANSCRIBE WITH WHISPER
# =============================================================================

notify "yt_summarise" "Transcribing audio — this may take a few minutes..."
echo "[INFO] Running Whisper transcription (model: $WHISPER_MODEL)..."
echo "[INFO] Note: On first run Whisper will download the model (~140MB for base). Subsequent runs are instant."

# Run Whisper — outputs both .txt and .srt files
# SRT includes timestamps needed for locating content in the video
whisper "$AUDIO_FILE" \
    --model "$WHISPER_MODEL" \
    --output_format all \
    --output_dir "$TEMP_DIR" \
    --language en \
    2>&1 | tail -5   # show last few lines so you can see progress in terminal

# Use the SRT file as the transcript so the model can see timestamps
TRANSCRIPT_FILE="$TEMP_DIR/audio.srt"
[[ -f "$TRANSCRIPT_FILE" ]] \
    || die "Whisper did not produce a transcript file. Check that Whisper is installed correctly: whisper --help"

# Also keep plain text version for word count
PLAIN_TRANSCRIPT_FILE="$TEMP_DIR/audio.txt"
TRANSCRIPT=$(cat "$TRANSCRIPT_FILE")
[[ -z "$TRANSCRIPT" ]] && die "Transcript is empty — the audio may be silent or too short."

WORD_COUNT=$(cat "$PLAIN_TRANSCRIPT_FILE" 2>/dev/null | wc -w | tr -d ' ' || wc -w <<< "$TRANSCRIPT" | tr -d ' ')
echo "[INFO] Transcription complete ($WORD_COUNT words)."

# =============================================================================
# STEP 3 — BUILD THE PROMPT
# =============================================================================

# Load your custom prompt instructions from the external file
USER_INSTRUCTIONS=$(cat "$PROMPT_FILE")

# Combine instructions with the transcript into a single prompt.
# jq --arg treats every value as a literal string — no shell evaluation
# of backticks, $() or backslashes that may appear in the transcript.
FULL_PROMPT=$(jq -rn \
    --arg instructions "$USER_INSTRUCTIONS" \
    --arg title        "$VIDEO_TITLE" \
    --arg url          "$VIDEO_URL" \
    --arg transcript   "$TRANSCRIPT" \
    '$instructions
     + "\n\n---\n\nVIDEO TITLE: " + $title
     + "\nVIDEO URL: "             + $url
     + "\n\nTRANSCRIPT:\n"         + $transcript
     + "\n\n---\n\nNow produce the structured Markdown summary as instructed above."')

# =============================================================================
# STEP 4 — SUMMARISE WITH OLLAMA
# =============================================================================

notify "yt_summarise" "Summarising with $OLLAMA_MODEL — almost done..."
echo "[INFO] Calling Ollama (model: $OLLAMA_MODEL)..."
echo "[INFO] This typically takes 1-3 minutes on M1 with gemma3:4b..."

# Build the JSON payload safely using jq to handle special characters
PAYLOAD=$(jq -n \
    --arg model "$OLLAMA_MODEL" \
    --arg prompt "$FULL_PROMPT" \
    '{model: $model, prompt: $prompt, stream: false}')

# Call Ollama — timeout set to 5 minutes for longer transcripts
OLLAMA_RESPONSE=$(curl -sf \
    --max-time 300 \
    -X POST "$OLLAMA_URL" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD") \
    || die "Ollama API call failed. Is the model pulled? Run: ollama pull $OLLAMA_MODEL"

# Extract the response text from Ollama's JSON output
SUMMARY=$(echo "$OLLAMA_RESPONSE" | jq -r '.response') \
    || die "Failed to parse Ollama's response. The model may have timed out."

[[ -z "$SUMMARY" || "$SUMMARY" == "null" ]] \
    && die "Ollama returned an empty summary. Try running: ollama run $OLLAMA_MODEL 'test' to check the model works."

# Strip follow-up questions from the bottom — removes trailing offer-to-help lines
SUMMARY=$(echo "$SUMMARY" | awk '
{
    lines[NR] = $0
}
END {
    last = NR
    while (last > 0) {
        l = tolower(lines[last])
        if (l ~ /would you like|let me know|feel free|do you want|do you need|should i |shall i |is there anything|i can (also|further|refine)|i hope this|happy to|if you (have|need|want)|don.t hesitate/) {
            last--
        } else if (lines[last] ~ /^[[:space:]]*$/) {
            last--
        } else {
            break
        }
    }
    for (i=1; i<=last; i++) print lines[i]
}
')

echo "[INFO] Summarisation complete."

# Remove any code fences the model added despite instructions
SUMMARY=$(echo "$SUMMARY" | sed '/^```/d')

# Strip preamble — remove any lines before the first ## heading
# This catches "Here's a summary...", "Sure! Here is...", etc.
SUMMARY=$(echo "$SUMMARY" | awk '
BEGIN { found=0 }
/^## / { found=1 }
found { print }
')

# =============================================================================
# GENERATE DYNAMIC TAGS WITH OLLAMA
# =============================================================================

echo "[INFO] Generating tags..."

TAGS_PROMPT="Based on this video title and summary, output ONLY 3 to 4 lowercase tags describing the content. Use hyphens for multi-word tags. Output them on a single line separated by commas, with absolutely nothing else — no explanation, no punctuation before or after.

Example output:
productivity, note-taking, knowledge-management, obsidian

VIDEO TITLE: ${VIDEO_TITLE}

SUMMARY:
${SUMMARY:0:500}"

TAGS_PAYLOAD=$(jq -n --arg model "$OLLAMA_MODEL" --arg prompt "$TAGS_PROMPT" '{model: $model, prompt: $prompt, stream: false}')

TAGS_RESPONSE=$(curl -sf --max-time 60 -X POST "$OLLAMA_URL" -H "Content-Type: application/json" -d "$TAGS_PAYLOAD") || true

if [[ -n "$TAGS_RESPONSE" ]]; then
    RAW_TAGS=$(echo "$TAGS_RESPONSE" | jq -r '.response' 2>/dev/null || echo "")
    # Clean to lowercase, keep only letters/digits/hyphens/commas, build YAML array
    YAML_TAGS=$(echo "$RAW_TAGS" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:],- ' | awk -F',' '{
        out="["
        for(i=1;i<=NF;i++){
            gsub(/^[[:space:]]+|[[:space:]]+$/,"",$i)
            if($i!="" && length($i)<=30){
                if(out!="[") out=out", "
                out=out $i
            }
        }
        print out"]"
    }')
else
    YAML_TAGS="[video, summary, ai-generated]"
fi

echo "[INFO] Tags: $YAML_TAGS"

# =============================================================================
# STEP 5 — BUILD AND EXPORT THE MARKDOWN FILE
# =============================================================================

# Sanitise the title for use as a filename — strip problematic characters
SAFE_TITLE=$(echo "$VIDEO_TITLE" \
    | tr -cd '[:alnum:] ._-' \
    | cut -c1-80 \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

OUTPUT_FILE="$OUTPUT_DIR/${SAFE_TITLE}.md"

echo "[INFO] Writing Markdown file to: $OUTPUT_FILE"

cat > "$OUTPUT_FILE" <<EOF
---
original_title: "${VIDEO_TITLE}"
source: "${VIDEO_URL}"
date: "$(date +"%Y-%m-%d")"
ollama_model: "${OLLAMA_MODEL}"
whisper_model: "${WHISPER_MODEL}"
tags: ${YAML_TAGS}
---

# ${VIDEO_TITLE}

${SUMMARY}

---
*This summary was generated automatically using Whisper (${WHISPER_MODEL}) for transcription and ${OLLAMA_MODEL} via Ollama for summarisation.*
EOF

# Send final success notification
notify "yt_summarise — Done!" "Summary saved: $(basename "$OUTPUT_FILE")"
echo "[INFO] All done. File saved to: $OUTPUT_FILE"

# Optional: open the finished file in your default Markdown app automatically
# Uncomment the line below to enable this
# open_file "$OUTPUT_FILE"