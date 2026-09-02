# Desert Ant CLI

![Swift](https://img.shields.io/badge/Swift-macOS%20%7C%20Linux-F05138?logo=swift&logoColor=white)
![Release](https://img.shields.io/github/v/release/Desert-Ant-Labs/desert-ant-cli?color=ADB49C&label=release)
![License](https://img.shields.io/badge/license-MIT-ADB49C)

Transcribe a recording, cut it into clips, clean up the audio, redact personal data
from a text, suggest emoji, or tag a topic, with [Desert Ant Labs](https://desertant.com)
models running on your own machine. Weights download once. Nothing leaves the device.

The command is `desertant`; `da` is the short alias.

```
$ da voz talk.mp4 -t
0:00  We build small models that run on the device.
0:04  Nothing leaves the phone, and there is no cloud bill.
48 minutes of audio in 9.7s, 296x realtime.

$ da clips talk.mp4
 1  10:14 to 10:42  27s
    The one thing the meter can't sell you is inference that costs nothing.
    talk_clip-1.mp4
8 clips from 48 minutes in 41s.

$ da redact "Email Anna at anna@example.hu or call 555-0100"
Email [GIVEN_NAME_1] at [EMAIL_1] or call [PHONE_1]
```

Type `da` for the list of commands. Coding agents get the same tool: every command
returns JSON with `--json`, reads stdin, and exits 0, 1, or 64, and `da schema --json`
describes each command and how they chain.

## Models

Every model has a page on [desertant.com](https://desertant.com/models/) with its
numbers, its limits, and a live demo. `da info <model>` prints the same card.

- **[Voz](https://desertant.com/models/voz/)** `da voz talk.mp4`  
  On-device speech recognition: transcripts with word-level timestamps, 25 languages.
- **[Clips](https://desertant.com/models/clips/)** `da clips talk.mp4`  
  Short clips and highlights from talking video and audio: podcasts, interviews, meetings. On-device.
- **[Clear](https://desertant.com/models/clear/)** `da clear talk.mp4`  
  On-device speech enhancement: denoise, dereverb, and loudness-normalize.
- **[Uhm](https://desertant.com/models/uhm/)** `da uhm talk.mp4`  
  On-device filler-word detection: frame-precise "uh"/"um"/"hmm" spans.
- **[Ear](https://desertant.com/models/ear/)** `da ear talk.mp4`  
  On-device spoken language identification across 99 languages.
- **[Redact](https://desertant.com/models/redact/)** `da redact "<text>"`  
  Multilingual on-device PII detection and redaction.
- **[Emo](https://desertant.com/models/emo/)** `da emo "<text>"`  
  Multilingual on-device emoji suggestion.
- **[Gist](https://desertant.com/models/gist/)** `da gist "<text>"`  
  Multilingual on-device content topic tagging across a 36-topic taxonomy.
- **[Title](https://desertant.com/models/title/)** `da title "<text>"`  
  On-device titles and descriptions: a short factual title and a one- to two-sentence description for any passage of text.

Voz, Uhm, and Title need Apple silicon. The rest run on macOS and Linux. `da models`
lists what runs on your machine; `da models --all` lists the full catalog.

## Transcripts and captions

`da voz talk.mp4` prints the transcript, one sentence per line; `-t` puts the time
in front of each. The files are one flag each, written beside the input:

```
da voz talk.mp4 --srt          talk.srt, captions
da voz talk.mp4 --vtt --txt    talk.vtt and talk.txt
da voz talk.mp4 -o notes.vtt   one file, the format from its extension
da voz talk.mp4 --format srt   SRT on stdout, for a pipe
```

Captions are cut the way broadcasters cut them: two lines of 42 characters at most,
at most 7s on screen, breaking at the end of a sentence first. `da docs voz` has the
rest.

## Install

### The script

```
curl -fsSL https://raw.githubusercontent.com/Desert-Ant-Labs/desert-ant-cli/main/install.sh | sh
```

Downloads the release for your machine, checks it against the release's checksums,
puts it in `~/.local/share/desertant`, and symlinks `desertant` and `da` into
`~/.local/bin`. `DESERTANT_BIN` and `DESERTANT_HOME` change those two directories.
`desertant update` runs the script again later.

### Homebrew

```
brew install desert-ant-labs/tap/desertant
```

`brew upgrade desertant` moves to the next release.

### mise

```
mise use -g "ubi:Desert-Ant-Labs/desert-ant-cli[exe=desertant]"
```

All three install the same release: macOS on Apple silicon, and Linux on x86_64 and
arm64.

## Chain

Commands compose through their JSON. Transcribe once, then cut:

```
da voz talk.mp4 --json | da clips talk.mp4 --transcript -
```

`da schema --json` names which command's output feeds which. `da docs pipelines` covers
the rest.

A command that writes a file never replaces one: a taken name steps aside
(`talk_clear-2.mp4`), the output can never be the input, and `--force` is the only way
to overwrite.

## Coding agents

One command sets up every agent it finds on your machine, in the current project:

```
desertant setup
```

Claude Code gets `.claude/skills/desertant/SKILL.md`, Pi gets
`.pi/skills/desertant/SKILL.md`, and Codex gets a marked section in `AGENTS.md`.
`desertant setup claude` does one agent; `--global` writes where the agent looks for
every project. Or paste this into the agent and let it do both steps:

```
Install the Desert Ant CLI with: curl -fsSL https://raw.githubusercontent.com/Desert-Ant-Labs/desert-ant-cli/main/install.sh | sh
Then run `desertant setup` in this project.
```

Works in the Claude Code terminal, VS Code extension, and desktop app, and in the
Codex CLI and app. Any other agent with a shell needs nothing more than `--json`,
stdin, the exit codes, and `da schema --json`. The Claude chat app has no shell, so
desertant doesn't reach it yet; an MCP server over the same catalog is the planned
route.

## Docs

`da docs` prints docs offline. The docs also live in the repo, indexed by
`llms.txt`: [using desertant from an agent](docs/agents.md), the
[JSON contracts](docs/json.md), [files and the cache](docs/files.md),
[clips](docs/clips.md), [pipelines](docs/pipelines.md), and
[performance](docs/performance.md). 

Adapters for Claude Code, Codex, and Pi live in
`integrations/`.

## License

MIT for the CLI. The models desertant runs are under the
[Desert Ant Labs source-available license](https://license.desertant.com/1.0).
