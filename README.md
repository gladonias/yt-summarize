# yt-summarise

[![Version](https://img.shields.io/badge/version-1.1.1-blue)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A Bash script that downloads YouTube videos (or accepts local audio files), transcribes them with [Whisper](https://github.com/openai/whisper), and generates structured Markdown summaries using a local [Ollama](https://ollama.com) LLM. Output files include YAML frontmatter and are ready for use with Obsidian or any Markdown-based note system.

## How it works

1. Accepts a YouTube URL (from clipboard or as an argument) or a local audio/video file
2. Downloads and extracts audio via `yt-dlp`
3. Transcribes audio using OpenAI Whisper (with SRT timestamps)
4. Sends the transcript to a local Ollama model for summarisation
5. Auto-generates tags for the summary
6. Exports a structured Markdown file with frontmatter

## Requirements

| Tool | Purpose | Install |
|------|---------|---------|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | YouTube audio download | `brew install yt-dlp` / `sudo apt install yt-dlp` / `pip install yt-dlp` |
| [ffmpeg](https://ffmpeg.org/) | Audio conversion | `brew install ffmpeg` / `sudo apt install ffmpeg` / [ffmpeg.org](https://ffmpeg.org/download.html) |
| [Whisper](https://github.com/openai/whisper) | Speech-to-text transcription | `pip install openai-whisper` |
| [Ollama](https://ollama.com) | Local LLM inference | `brew install ollama` / [ollama.com](https://ollama.com/download) |
| [jq](https://jqlang.github.io/jq/) | JSON processing | `brew install jq` / `sudo apt install jq` / [jqlang.github.io](https://jqlang.github.io/jq/download/) |
| [curl](https://curl.se/) | HTTP requests | Pre-installed on most systems |

**Clipboard support** (optional, for reading URLs from clipboard when no argument is given):
- **macOS**: `pbpaste` (built-in)
- **Linux**: `xclip` or `xsel` (`sudo apt install xclip`)
- **Windows (Git Bash / WSL)**: Works via PowerShell automatically

## Installation

```bash
git clone https://codeberg.org/gadonias/yt-summarise.git
cd yt-summarise
chmod +x yt_summarise.sh
```

### Set up the prompt instructions

Copy the included prompt file to the default config location:

```bash
mkdir -p ~/.config/yt_summarise
cp prompt_instructions.txt ~/.config/yt_summarise/prompt_instructions.txt
```

### Pull an Ollama model

```bash
ollama pull gemma3:4b
```

You can use any Ollama model — configure it via the config file or `--model` flag.

## Usage

```bash
# Read YouTube URL from clipboard
./yt_summarise.sh

# Pass a YouTube URL directly
./yt_summarise.sh "https://www.youtube.com/watch?v=VIDEO_ID"

# Summarise a local audio/video file
./yt_summarise.sh /path/to/recording.mp3
```

### CLI options

```bash
./yt_summarise.sh --output-dir ~/Notes/Summaries "https://youtube.com/watch?v=..."
./yt_summarise.sh --prompt-file ./my_prompt.txt "https://youtube.com/watch?v=..."
./yt_summarise.sh --model llama3:8b "https://youtube.com/watch?v=..."
```

## Configuration

The script loads settings from `~/.config/yt_summarise/config` (if it exists). This is a shell file — just set variables:

```bash
# ~/.config/yt_summarise/config

# Where finished Markdown summaries are saved
OUTPUT_DIR="$HOME/Documents/Summaries"

# Path to your prompt instructions file
PROMPT_FILE="$HOME/.config/yt_summarise/prompt_instructions.txt"

# Ollama model to use (default: gemma3:4b)
OLLAMA_MODEL="gemma3:4b"

# Whisper model size: tiny | base | small | medium | large
WHISPER_MODEL="base"

# Ollama API endpoint
OLLAMA_URL="http://localhost:11434/api/generate"
```

CLI flags (`--output-dir`, `--prompt-file`, `--model`) take precedence over the config file.

## Platform notes

The script runs on **macOS**, **Linux**, and **Windows** (via Git Bash or WSL). OS-specific behaviour (clipboard, notifications, file opening) is detected automatically.

- **Notifications**: macOS uses `osascript`, Linux uses `notify-send` (install `libnotify`), Windows uses PowerShell toast (optional `BurntToast` module). Notifications are non-blocking — the script works fine without them.
- **Windows**: Run the script in Git Bash or WSL. All paths use `$HOME` which resolves correctly in both environments.

## Output

Each summary is saved as a Markdown file with YAML frontmatter:

```yaml
---
original_title: "Video Title"
source: "https://youtube.com/watch?v=..."
date: "2026-04-13"
ollama_model: "gemma3:4b"
whisper_model: "base"
tags: [topic-one, topic-two, topic-three]
---
```

The body includes an Introduction, numbered Key Takeaways with video timestamps, and a Conclusion. Edit `prompt_instructions.txt` to customise the output format.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a full version history.

## License

[MIT](LICENSE)
