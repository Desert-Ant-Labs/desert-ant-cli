# JSON contracts

What every command writes to stdout under `--json`. Keys are stable within a major
version; a new key may appear, an existing one won't change meaning or type. Numbers
are JSON numbers, seconds are seconds, paths are absolute. Examples are real output.

## Discovery

`desertant models --json`: an array, one entry per model that runs on this machine,
A-Z by id. `--all` adds the rest of the catalog; `--group audio|text|vision` filters.

```json
[
  {
    "id": "emo",
    "name": "Emo",
    "tagline": "Faster than you can type.",
    "summary": "Multilingual on-device emoji suggestion.",
    "category": "Emoji suggestions",
    "group": "text",
    "lifecycle": "stable",
    "runtime": ["coreml", "litert"],
    "platforms": ["apple", "linux", "windows"],
    "ships": true,
    "runnableHere": true
  }
]
```

`group` is `audio`, `text`, or `vision`. `ships` is true when any SDK is live.
`platforms` is where core's Swift SDK runs, from the manifest; `runnableHere` is
whether this CLI runs the model on this machine.

`desertant search <query> --json`: an array of `{id, name, tagline, summary}`.

`desertant home --json`: the verbs that run on this machine, in the order the help
lists them.

```json
[{"command": "emo", "input": "\"<text>\"", "does": "Suggest emoji for a line of text."}]
```

`desertant info <id> --json`: one object. Everything in a `models` entry plus:

```json
{
  "languages": 22,
  "variants": [],
  "weightsRepo": "desert-ant-labs/emo",
  "weightsRevision": "v0.7.0",
  "weightsURL": "https://huggingface.co/desert-ant-labs/emo",
  "demo": "https://desertant.com/models/emo/",
  "sdks": {"swift": "Emo", "kotlin": "ai.desertant:emo", "js": "@desert-ant-labs/emo"},
  "runnableHere": true,
  "downloaded": true
}
```

`downloaded` is null when the model has no runner on this machine.

`desertant schema --json`: the tool catalog.

```json
{
  "tool": "desertant",
  "version": "0.1.0",
  "coreVersion": "3.1.0",
  "invocation": "desertant <verb> <input> [--json]  |  desertant run <id> --input <text> | --file <path> [--option k=v]",
  "globalFlags": [{"flag": "--json", "help": "Machine-readable JSON output."}],
  "exitCodes": [{"code": 0, "meaning": "success"}, {"code": 1, "meaning": "runtime error, message on stderr"}, {"code": 64, "meaning": "usage error, message on stderr"}],
  "models": [
    {
      "id": "clips",
      "verb": "clips",
      "summary": "Short clips and highlights from talking video and audio: podcasts, interviews, meetings. On-device.",
      "input": "file",
      "runnableHere": true,
      "options": [{"name": "count", "help": "How many clips to look for. Default: the model sizes it to the recording."}]
    }
  ]
}
```

`input` is `text` or `file`, or null when the model has no runner on this machine. Every
`options[].name` is accepted by both the verb (`--count 3`) and `run` (`--option
count=3`). Each entry also carries `emits` (the document kind its `--json` result is,
or null) and `accepts` (`[{kind, option}]`): a command whose `emits` matches another's
`accepts.kind` feeds it through that option, as a file or as `-` for stdin. See
[pipelines.md](pipelines.md).

`desertant doctor --json`:

```json
{
  "os": "macOS", "arch": "arm64",
  "coreml": true, "mlx": true, "litert": false,
  "cachePath": "/Users/you/Library/Caches/desert-ant-models",
  "cacheBytes": 1175608980,
  "downloaded": ["clear", "clips", "emo", "gist", "redact", "voz"],
  "runnable": ["clear", "clips", "emo", "gist", "redact"],
  "version": "0.1.0", "coreVersion": "3.1.0",
  "latest": "0.1.0", "updateAvailable": false, "updateCommand": "desertant update",
  "models": 18, "shipping": 12
}
```

`latest` is null when GitHub couldn't be reached.

## Weights

`desertant pull <id> --json`: `{"model": "emo", "downloaded": true}`.

`desertant cache --json`: `{"path", "sizeBytes", "size", "downloaded": [ids]}`;
`--clean --force --json` returns `{"cleaned": true}`.

`desertant update --check --json`: `{"current", "latest", "updateAvailable",
"installedVia", "updateCommand"}`.

## Models

`desertant emo "<text>" --json`: an array, best first.

```json
[{"emoji": "💰", "confidence": 0.63}, {"emoji": "📅", "confidence": 0.20}]
```

`desertant redact "<text>" --json`: the redacted text and every replacement.

```json
{
  "redacted": "Email [GIVEN_NAME_1] at [EMAIL_1]",
  "items": [
    {"label": "GIVEN_NAME", "original": "Anna", "placeholder": "[GIVEN_NAME_1]", "confidence": 1},
    {"label": "EMAIL", "original": "anna@example.hu", "placeholder": "[EMAIL_1]", "confidence": 1}
  ]
}
```

To restore originals in a reply, replace each `placeholder` with its `original`.
Labels are the Redact SDK's: `GIVEN_NAME`, `SURNAME`, `EMAIL`, `PHONE`,
`CREDIT_CARD`, `IP_ADDRESS`, `URL`, and the rest of that set.

`desertant gist "<text>" --json`: an array of topics, best first.

```json
[{"slug": "finance", "name": "Personal Finance & Investing", "score": 0.98}]
```

`desertant title "<text>" --json`: `{"title", "description"}`, on Apple silicon
builds.

`desertant voz <file> --json`: the transcript document. `clips --transcript` reads
this file as is.

```json
{
  "input": "/work/talk.mp4",
  "text": "We build small models that run on the device. ...",
  "durationSec": 2880.0,
  "loadSec": 1.1,
  "processingSec": 9.7,
  "words": [{"start": 0.0, "end": 0.32, "text": "We"}],
  "sentences": [{"start": 0.0, "end": 5.27, "text": "We build small models that run on the device."}],
  "captions": [{"start": 0.0, "end": 2.6, "text": "We build small models
that run on the device."}],
  "files": {"srt": "/work/talk.srt"}
}
```

`captions` are the cues SRT and VTT are written from (a newline inside `text` is a line break). `files` maps each extension written to its path, empty when none was.

`desertant uhm <file> --json`: the filler words, in order.

```json
{
  "input": "/work/talk.mp4",
  "durationSec": 2880.0,
  "fillers": [{"start": 4.21, "end": 4.52, "durationSec": 0.31, "type": "um", "confidence": 0.94}]
}
```

`desertant ear <file> --json`: the language spoken.

```json
{
  "input": "/work/talk.mp4",
  "language": "en",
  "confidence": 0.99,
  "candidates": [{"language": "en", "probability": 0.99}]
}
```

`language` is an ISO code, or null when there was nothing to listen to. Candidates
under 0.01 are left out.

`desertant clear <file> --json`: where the enhanced file landed.

```json
{
  "input": "/work/talk.mp4",
  "output": "/work/talk_clear.mp4",
  "durationSec": 2880.0,
  "processingSec": 17.1
}
```

`output` is the path actually written, which may have stepped aside to
`talk_clear-2.mp4`.

`desertant clips <file> --json`: the report.

```json
{
  "input": "/work/talk.mp4",
  "transcript": null,
  "sentences": 212,
  "materialSec": 2880.0,
  "transcribeSec": 9.7,
  "selectSec": 1.1,
  "cutSec": 3.4,
  "clips": [
    {
      "id": 1,
      "start": 614.2,
      "end": 641.8,
      "durationSec": 27.6,
      "score": 0.85,
      "text": "The sentence or run of sentences the clip covers.",
      "file": "/work/talk_clip-1.mp4"
    }
  ]
}
```

Clips come back best first. `file` is null under `--select-only`. `transcript` is
the transcript file that was used, or null when Voz transcribed.

## Errors

Nothing is written to stdout on failure. The message is on stderr, prefixed
`Error:`, and the exit code is `1` for a runtime error or `64` for a usage error.
