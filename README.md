# Desert Ant CLI

![Swift](https://img.shields.io/badge/Swift-macOS%20%7C%20Linux-F05138?logo=swift&logoColor=white)
![Release](https://img.shields.io/github/v/release/Desert-Ant-Labs/desert-ant-cli?color=ADB49C&label=release)
![License](https://img.shields.io/badge/license-MIT-ADB49C)

Transcribe a recording, cut the best moments into clips, clean up the audio, redact
personal data from text, suggest emoji, or tag a topic, with [Desert Ant Labs](https://desertant.com)
models running on your own machine. Weights download once. Nothing leaves the device.

```
$ da voz talk.mp4 -t
0:00  We build small models that run on the device.
0:04  Nothing leaves the phone, and there is no cloud bill.
Transcribed 48 minutes of audio in 9.7s, 296x realtime.

$ da clips talk.mp4
 1  10:14 to 10:42  27s
    The one thing the meter can't sell you is inference that costs nothing.
    talk_clip-1.mp4
8 clips from 48 minutes in 41s.

$ da redact "Email Anna at anna@example.hu or call 555-0100"
Email [GIVEN_NAME_1] at [EMAIL_1] or call [PHONE_1]
```

`da` is short for `desertant`.

## Install

```
curl -fsSL https://raw.githubusercontent.com/Desert-Ant-Labs/desert-ant-cli/main/install.sh | sh
```

Or `brew install desert-ant-labs/tap/desertant`, or
`mise use -g "ubi:Desert-Ant-Labs/desert-ant-cli[exe=desertant]"`.

## Models

Each model has a page on [desertant.com](https://desertant.com/models/) with its
numbers, its limits, and a live demo. `da info <model>` prints the same card.

- **[Voz](https://desertant.com/models/voz/)** `da voz talk.mp4`  
  Transcribe a recording, with a time on every word, in 25 languages.
- **[Clips](https://desertant.com/models/clips/)** `da clips talk.mp4`  
  Cut a podcast, interview, or meeting into short clips and highlights.
- **[Clear](https://desertant.com/models/clear/)** `da clear talk.mp4`  
  Studio sound: noise and room echo out, loudness leveled.
- **[Uhm](https://desertant.com/models/uhm/)** `da uhm talk.mp4`  
  Find every "uh", "um", and "hmm", with the exact span to cut.
- **[Ear](https://desertant.com/models/ear/)** `da ear talk.mp4`  
  Name the language being spoken, from 99.
- **[Redact](https://desertant.com/models/redact/)** `da redact "<text>"`  
  Replace names, emails, and phone numbers in a text with labels.
- **[Emo](https://desertant.com/models/emo/)** `da emo "<text>"`  
  Suggest emoji for a word or a sentence.
- **[Gist](https://desertant.com/models/gist/)** `da gist "<text>"`  
  Tag a post or article with topics, from a set of 36.
- **[Title](https://desertant.com/models/title/)** `da title "<text>"`  
  Suggest a short factual title and a one- or two-sentence description for any text.

Redact, Emo, and Gist are multilingual. Voz, Uhm, and Title need Apple silicon, the
rest run on macOS and Linux, and `da models` lists what runs on your machine.

## Transcripts and captions

`da voz talk.mp4` prints the transcript, one sentence per line, and `-t` puts the time
in front of each. Caption and text files are one flag each, written beside the input:

```
da voz talk.mp4 --srt          talk.srt, captions
da voz talk.mp4 --vtt --txt    talk.vtt and talk.txt
da voz talk.mp4 -o notes.vtt   one file, the format from its extension
da voz talk.mp4 --format srt   SRT on stdout, for a pipe
```

Captions are cut the way broadcasters cut them: two lines of 42 characters, no more
than 7s on screen. `da docs voz` has the rest.

## Chain

Commands compose through their JSON. Transcribe once, then cut:

```
da voz talk.mp4 --json | da clips talk.mp4 --transcript -
```

`da schema --json` names which command's output feeds which, and `da docs pipelines`
covers the rest. desertant never overwrites a file: a second run writes
`talk_clear-2.mp4`, and `--force` is the only way around that.

## Coding agents

One command writes a skill for every agent installed on your machine, in the current
project: Claude Code and Pi get a skill file, Codex gets a section in `AGENTS.md`.

```
desertant setup
```

`desertant setup claude` does one agent, and `--global` writes where the agent looks for
every project. Or paste this into the agent and let the agent do both steps:

```
Install the Desert Ant CLI with: curl -fsSL https://raw.githubusercontent.com/Desert-Ant-Labs/desert-ant-cli/main/install.sh | sh
Then run `desertant setup` in this project.
```

Any other agent with a shell needs nothing more: every command returns JSON with
`--json`, reads stdin, and exits 0, 1, or 64, and `da schema --json` describes each
command and how they chain.

## Docs

`da docs` prints the docs offline. The same docs are in the repo, indexed by
`llms.txt`: [using desertant from an agent](docs/agents.md), the
[JSON contracts](docs/json.md), [files and the cache](docs/files.md),
[clips](docs/clips.md), [pipelines](docs/pipelines.md), and
[performance](docs/performance.md).

## License

MIT for the CLI. The models desertant runs are under the
[Desert Ant Labs source-available license](https://license.desertant.com/1.0).
