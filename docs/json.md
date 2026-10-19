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
  "version": "0.1.1",
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

`input` is `text`, `file` (a recording), `image`, or `visual` (a photo or a video),
or null when the model has no runner on this machine. Every
`options[].name` is accepted by both the verb (`--count 3`) and `run` (`--option
count=3`). Each entry also carries `emits` (the document kind its `--json` result is,
or null) and `accepts` (`[{kind, option}]`): a command whose `emits` matches another's
`accepts.kind` feeds it through that option, as a file or as `-` for stdin. See
[pipelines.md](pipelines.md).

`desertant doctor --json`:

```json
{
  "os": "macOS", "arch": "arm64",
  "coreml": true, "mlx": true, "litert": false, "ffmpeg": true,
  "cachePath": "/Users/you/Library/Caches/desert-ant-models",
  "cacheBytes": 1175608980,
  "downloaded": ["clear", "clips", "emo", "gist", "redact", "voz"],
  "runnable": ["clear", "clips", "emo", "gist", "redact"],
  "version": "0.1.1", "coreVersion": "3.1.0",
  "latest": "0.1.1", "updateAvailable": false, "updateCommand": "desertant update",
  "models": 18, "shipping": 12
}
```

`latest` is null when GitHub couldn't be reached. `ffmpeg` says whether ffmpeg is on PATH; on Linux, ffmpeg reads audio other than WAV, video, and images.

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
`CREDIT_CARD`, `IP_ADDRESS`, `URL`, and the rest of that set. On a Mac without a
Neural Engine, such as a virtual Mac, Redact finds no names, addresses, or cities, and
says so on stderr; emails, cards, and IBANs are still redacted.

`desertant gist "<text>" --json`: an array of topics, best first.

```json
[{"slug": "finance", "name": "Personal Finance & Investing", "score": 0.98}]
```

`desertant tongue "<text>" --json`: the language the text is written in.

```json
{
  "language": "de",
  "reliability": "confident",
  "tooCloseToCall": false,
  "candidates": [{"language": "de", "probability": 0.99}]
}
```

`language` is an ISO 639 code, and is left out when there was nothing to read. `reliability`
is `confident`, `likely`, `tentative`, or `empty`, judged from the text's length and
the lead over the runner-up rather than the probability alone. `tooCloseToCall` is
true when the top two are within 0.12 of each other. Pass `--top 2` to see both.

`desertant title "<text>" --json`: `{"title", "description"}`, on Apple silicon
builds.

`desertant moderator <image> --json`: the nudity score. On Linux, reading the image needs ffmpeg.

```json
{
  "input": "/work/photo.jpg",
  "nsfw": false,
  "score": 0.12,
  "threshold": 0.5,
  "policy": "standard",
  "quality": "accurate",
  "regions": {"nipples": 0.12, "genitals": 0.11, "buttocks": 0.06, "nude": 0.11, "sexAct": 0.05}
}
```

`score` is the highest region the policy counts, and `nsfw` is whether that score reaches
`threshold`. Under `allow-topless` a bare chest alone does not count. Regions are
decision scores in 0...1, not calibrated probabilities.

`desertant eye <photo> --json`: what the photo is, its scores, and what is in it. On
Linux, reading the photo needs ffmpeg.

```json
{
  "input": "trip/IMG_9641.HEIC",
  "model": "eye@v1.0.0",
  "width": 4032,
  "height": 3024,
  "kind": "photo",
  "scores": {"aesthetic": 0.71, "keeper": 0.0, "cover": 0.70},
  "sharpness": 1.0,
  "tags": {"cloud": 0.84, "hiking": 0.86, "mountain": 0.93, "people": 0.97, "photo": 0.99, "sharp": 1.0, "sky": 0.98},
  "faces": [{"box": {"x0": 0.24, "y0": 0.46, "x1": 0.25, "y1": 0.47}, "confidence": 0.41, "quality": 0.61,
             "pose": {"yaw": 5.3, "pitch": -1.9, "roll": -7.9},
             "tags": {"eyes_closed": 0.48, "happy": 0, "looking_at_camera": 0, "looking_away": 0.57, "smiling": 0.45, "surprised": 0}}],
  "people": [{"label": "person", "confidence": 0.45, "box": {"x0": 0.23, "y0": 0.44, "x1": 0.29, "y1": 0.54}}],
  "pets": []
}
```

`tags` holds every tag at or above the cutoff (0.5, or 0.9 under `--strict`), so a tag
that is missing scored below it; `--all-tags` holds every confidence. `kind` is the
most likely photo type. `scores` are percentiles in 0...1 against Eye's calibration
set. Boxes are in 0...1 of the upright image, from the top left. `rotation` (90, 180,
or 270) appears when the photo is turned clockwise by that much. `crop` appears with
`--crop`: `{"aspect": "1:1", "box": {...}, "file": "/work/IMG_0056_crop.jpeg"}`.
`embedding` (512 numbers) appears with `--embedding`. A part left out with `--parts`
leaves its keys out.

`desertant eye <video> --json`: the frames, the thumbnail, and the tags that hold.

```json
{
  "input": "/work/launch.mp4",
  "durationSec": 81.4,
  "every": 1,
  "kind": "screenshot",
  "tags": {"keeper": 0.63, "reference": 1, "screenshot": 0.62, "sharp": 1},
  "thumbnail": {"time": 7.5, "cover": 0.97, "crop": null, "file": "/work/launch_thumbnail.jpg"},
  "frames": [{"input": "/work/launch.mp4", "time": 0.5, "kind": "screenshot", "tags": {"reference": 0.91}}]
}
```

`tags` maps each tag to the share of frames it holds in. `frames` holds one photo
document per frame, each with its `time`. With `--has` or `--not`, `matches` lists the
stretches where every frame matches, as `[{"start", "end"}]` in seconds.

With `--has` or `--not` and several photos, the result is an array of the photo
documents that match. The questions return their own shapes:

- `--duplicates`: `{"photos": 15, "groups": [{"keep": "trip/IMG_3615.HEIC", "others": ["trip/IMG_3619.HEIC"]}]}`.
- `--best`: `{"best": "burst/IMG_0146.jpg", "photos": 5}`.
- `--sort` and `--similar-to`: an array of `{"input", "score"}`, highest first.

`voz`, `uhm`, `ear`, `who`, `clear`, `clips`, `moderator`, and `eye` take several paths, or a
folder, and `--recursive` looks inside its folders. One path returns the document
below. Several paths or a folder return an array of those documents, in the order the
files ran, each with its `input`. A file the model does not read is skipped, with a
note on stderr. A file that fails is left out, with its message on stderr, and the
exit code is 1 once the rest have run. `--output`, `--transcript`, and `--format` name
one file's document, so a batch refuses them. Each output lands beside its input, and
a second run of `clear` on the same folder also enhances the `talk_clear.mp4` files
the first run wrote.

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

With `--speakers`, each sentence carries `speaker`, numbered from 0 in the order the
speakers first speak, and a sentence two people share is split where the speaker
changes. The document adds `speakers` and `turns`, as `who` writes them below.


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

`desertant who <file> --json`: who spoke when.

```json
{
  "input": "/work/interview.mp4",
  "durationSec": 45.891,
  "loadSec": 0.17,
  "processingSec": 0.04,
  "speakerCount": 2,
  "speakers": [
    {"speaker": 0, "name": "Speaker 1", "seconds": 28.27, "share": 0.616, "turns": 4},
    {"speaker": 1, "name": "Speaker 2", "seconds": 11.84, "share": 0.258, "turns": 3}
  ],
  "turns": [{"start": 0.0, "end": 4.92, "speaker": 0}, {"start": 5.56, "end": 10.88, "speaker": 1}],
  "files": {}
}
```

Speakers are numbered from 0 in the order they first speak, and `speakers` lists the
most heard first. `name` is from `--names`, else `Speaker 1` and on. `share` is the
speaker's time against the whole recording. `turns` are joined across pauses up to
`--join` seconds (1 by default) and sorted by start; turns of two speakers can
overlap. With `--transcript`, `lines` lists the transcript as `[{"start", "end",
"speaker", "text"}]`. `files` maps the format written with `-o` to its path.

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

Clips come back best first. `file` is left out under `--select-only`. `transcript` is
the transcript file that was used, and is left out when Voz transcribed.

## Errors

Nothing is written to stdout on failure. The message is on stderr, prefixed
`Error:`, and the exit code is `1` for a runtime error or `64` for a usage error.
