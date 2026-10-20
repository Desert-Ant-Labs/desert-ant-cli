---
name: desertant
description: Run Desert Ant Labs on-device models through the desertant CLI, one at a time or chained in a flow. Use when the task needs a local model, transcribing a recording, writing captions, labeling who said what, cleaning up audio, cutting clips with burned-in captions, finding filler words, naming the spoken language, redacting personal data before text leaves the machine, suggesting emoji, tagging a topic, naming the language of a text, flagging nudity in an image, finding, ranking, sorting, or cropping photos, picking a video's thumbnail, writing a title, or running several of these on a file in one command, such as meeting notes or podcast clips. Also when the user asks what on-device models are available. Everything runs locally with no API key; add --json for a parseable result.
---

# desertant

The `desertant` CLI (alias `da`) runs small Desert Ant Labs models on this machine. Weights download once and cache, and nothing leaves the device when a model runs. Prefer the CLI over a network model when the input is sensitive or the task is one of the ones below.

## Discover

- `desertant schema --json` is the tool catalog: every model, whether it runs here, its input, and its options, plus `flowSteps`, every step a flow file can use. Read it once per session instead of guessing flags.
- `desertant models --json` lists the models that run on this machine, and `--all` the full catalog. `desertant info <id> --json` is one model's card.
- `desertant flow templates --json` lists the flows that ship.
- `desertant docs <page>` prints a page offline: `agents`, `json` (the shape of every result), `flows`, `clips`, `voz`, `who`, `eye`, `pipelines`, `files`.

## Run a model

Every command takes `--json` for one JSON value on stdout, and a text model reads stdin when given no argument. Exit code 0 is success, 1 a runtime error, 64 a usage error, with the message on stderr. Weights download on first use with progress on stderr, so stdout stays clean JSON.

- Redact personal data before sending text anywhere: `desertant redact "Email Anna at anna@example.hu" --json` returns the redacted text and the placeholder map, so you can restore the originals in a reply.
- Suggest emoji: `desertant emo "pay my bills" --json`.
- Tag what a text is about, from 36 topics: `desertant gist "<article text>" --json`.
- Name the language a short text is written in: `desertant tongue "<text>" --json`.
- Write a title and a description for a passage: `desertant title "<text>" --json`. Apple silicon only.
- Transcribe with a time on every word: `desertant voz talk.mp4 --json`. `--srt`, `--vtt`, and `--txt` also write those files beside the input.
- Label who said what: `desertant voz talk.mp4 --speakers --json` puts a `speaker` on every sentence, and `--names "Anna,Ben"` names them in the order they first speak. `desertant who talk.mp4 --json` alone gives each speaker's time and turns.
- Clean up a recording's sound, studio sound: `desertant clear meeting.mp4 --json` writes `meeting_clear.mp4` and reports the path.
- Find each uh, um, and hmm: `desertant uhm talk.mp4 --json`. Apple silicon only.
- Name the language spoken: `desertant ear talk.mp4 --json`.
- Cut the moments worth sharing into clips: `desertant clips talk.mp4 --json` transcribes, picks the moments, and writes one file per clip beside the input, with each clip's start, end, text, and file. `--count 5` sets how many to look for, `--select-only` returns the moments without writing files, and `--transcript talk.srt` (or `-` with `voz --json` on stdin) skips transcribing.
- Burn captions into the clips: `desertant clips talk.mp4 --captions burn --json`. The look: `--caption-style outline|box|shadow`, `--caption-position bottom|center|top`, `--caption-align left|center|right`, `--caption-color yellow` or `#ffcc00`, `--caption-weight bold`, `--caption-size 0.06` (a share of the frame's height), `--caption-font "<family or .ttf>"`, and `--quality low|medium|high`. `--captions srt` writes an `.srt` beside each clip instead. On audio there is no picture, so burn writes the `.srt` and says so in `notes`.
- Flag nudity in a photo before upload or display: `desertant moderator photo.jpg --json` scores it 0 to 1 and says whether the score crosses the threshold.
- Read photos: `desertant eye photo.jpg --json` gives the kind of image, its scores, tags, faces, people, and pets. On a folder, one flag asks one question: `--has dog --not blurry` lists the matches, `--duplicates` groups near-duplicates with the keeper first, `--best` picks one, and `--sort aesthetic` or `--similar-to photo.jpg` ranks. `--crop 1:1` writes a crop. On a video, `--thumbnail` writes the best frame and `--has people` returns the stretches that match. Use `--strict` before moving or deleting anything. Eye is in closed beta and needs `HF_TOKEN`.

A file command takes several paths or a folder (`--recursive` for its subfolders) and loads the model once. The result is then an array with one entry per file. A file that fails is reported on stderr, and the exit code is 1 after the rest have run.

The uniform form for any model is `desertant run <id> --input "<text>"` or `desertant run <id> --file <path> --option key=value`.

## Run a flow

A flow runs several models on a file in one command. Reach for one when the user wants a chain, such as notes from a meeting or captioned clips from a podcast. The flows that ship:

- `studio-sound`: clean up a recording's sound. A video keeps its picture.
- `transcript-and-captions`: a transcript as text, SRT, and WebVTT.
- `who-said-what`: a transcript with each speaker's name.
- `meeting-notes`: who said what, with personal data replaced and the main topic tagged.
- `podcast-clips`: clean sound, then clips with captions burned in.
- `filler-words`: each uh, um, and hmm with its time. macOS only.
- `photo-keepers`: copy the photos worth keeping, one of each near-duplicate, into a Keepers folder.
- `find-receipts`: copy the receipts among some photos into a Receipts folder.
- `redact-a-document`: a text with its personal data replaced.

```
desertant flow run meeting-notes standup.m4a --json
desertant flow run podcast-clips episode.mp4 --set clips.count=3 --set clips.style=box --json
echo "Call Anna at 555-0100" | desertant flow run redact-a-document --json
desertant flow run find-receipts ~/Pictures/trip --json
```

The paths fill the flow's first step. A photos or files step takes every path, folders included, in one run; any other step runs the flow once per file, and the result is then an array. `--set step.setting=value` changes one step's setting for this run, `--output-dir` chooses where files go (default: beside the first input), and `--recursive` takes subfolders. The result lists each step's `status` (`done`, `skipped`, or `failed` with a `note`), what each view and table step shows in `outputs`, and every file written in `files`. Report the paths in `files` to the user.

Steps that rename, copy, or move the user's files print a plan and change nothing until `--apply`. Run without it first, show the user the plan, and pass `--apply` only when they ask for the files to change.

## Write a flow

When no template fits, write a flow file. Read `flowSteps` in `desertant schema --json` for each step's inputs, outputs, and settings, then write YAML:

```yaml
flow: 1
title: Clips and captions
steps:
  - type: audio
  - type: voz
  - type: clips
    with:
      captions: burn
      position: top
      count: 3
  - id: clipfiles
    type: folder
    uses:
      value: clips.files
    with:
      folder: Clips
  - type: captions
  - id: srt
    type: folder
    uses:
      value: captions.srt
    with:
      name: "{{name}}"
```

- Each step has a `type`. Give it an `id` when two steps share a type; otherwise the type is its id.
- `uses` maps an input to an earlier step's output as `step.output`. An input left out takes the output of the same name from the nearest step before it, else the nearest output of the same type. Name the wire in `uses` whenever that would be ambiguous.
- `with` holds the step's settings. The clips step takes the caption options without the `caption-` prefix: `captions`, `style`, `position`, `align`, `color`, `weight`, `size`, `font`, `quality`, `count`.
- Run `desertant flow check flow.yml --json` before running it. It shows how every input is wired, and `problems` names any step that cannot run here; the exit code is then 1.
- `desertant flow new <template> flow.yml` writes a template out in full, every wire and setting listed, as a starting point.

`flowSteps` lists every step type desertant has; `flow check` names any other type a file uses, and `flow run` refuses the file. `desertant docs flows` has every step and rule.

## Compose without a flow

Commands also chain through their JSON. `desertant schema --json` lists what each command `emits` and `accepts`; a match feeds through the named option, as a file or `-` for stdin:

```
desertant voz talk.mp4 --json | desertant clips talk.mp4 --transcript - --captions burn
desertant voz talk.mp4 --json | desertant who talk.mp4 --transcript - --json
```

Transcribe once and reuse the transcript rather than letting another command transcribe again.

## Files

A command that writes a file never replaces one: a taken name steps aside to `name-2.ext`, and the output is never the input. Read the paths from the JSON result instead of predicting them. Pass `--force` only when the user asks to overwrite.

## When to reach for desertant

Redact before you send anything with names, emails, or numbers to a remote service. Run the other models and flows when the user asks for what they do. Don't run a model the user hasn't asked for, and don't pass `--apply` or `--force` on your own judgment.
