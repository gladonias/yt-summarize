# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [1.1.1] — 2026-04-22

### Fixed
- **Prompt injection via shell expansion**: `FULL_PROMPT` was assembled by interpolating `$TRANSCRIPT` and related variables inside a double-quoted Bash string. Any backticks, `$()`, or backslash sequences present in transcript content could be evaluated by the shell before reaching Ollama. The prompt is now assembled entirely through `jq -rn --arg`, which treats all values as literal strings with no shell evaluation.

---

## [1.1.0] — 2026-04-13

### Added
- Cross-platform OS detection (`macos` / `linux` / `windows`)
- Cross-platform clipboard support: `pbpaste` (macOS), `xclip`/`xsel` (Linux), PowerShell `Get-Clipboard` (Windows)
- Cross-platform desktop notifications: `osascript` (macOS), `notify-send` (Linux), PowerShell BurntToast (Windows)
- Cross-platform file opener function: `open` / `xdg-open` / `start`
- Config file support: settings loaded from `~/.config/yt_summarise/config` at runtime
- CLI flags: `--output-dir`, `--prompt-file`, `--model` — override config or defaults per invocation
- Portable default paths using `$XDG_CONFIG_HOME` and `$HOME/Documents/Summaries`
- README platform notes section documenting OS-specific behaviour

### Changed
- Default `OUTPUT_DIR` changed from a hardcoded iCloud/Obsidian path to `$HOME/Documents/Summaries`
- `mktemp -d /tmp/yt_summarise_XXXXXX` replaced with `mktemp -d` (OS picks temp location)
- All references to `SETUP_GUIDE_MACOS.md` replaced with `README.md`
- Script header updated to reflect cross-platform compatibility

---

## [1.0.0] — 2026-04-13

### Added
- Initial release of `yt_summarise.sh`
- YouTube URL input from clipboard or command-line argument
- Local audio/video file input support
- Audio extraction via `yt-dlp` and `ffmpeg`
- Transcription via OpenAI Whisper (configurable model size)
- Summarisation via local Ollama LLM (configurable model)
- Auto-generated tags via a second Ollama pass
- Structured Markdown output with YAML frontmatter (title, source URL, date, models, tags)
- SRT timestamps preserved in transcript so the LLM can reference video timecodes
- LLM output cleanup: strips preamble, postamble, and code fences
- External prompt instructions file (`prompt_instructions.txt`) for customising summary format
- Automatic temp directory cleanup on exit
- `README.md` with requirements, installation, usage, and configuration docs
- MIT licence
