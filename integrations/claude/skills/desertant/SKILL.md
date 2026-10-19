---
name: desertant
description: Run Desert Ant Labs on-device models through the desertant CLI. Use when the task needs a local model, transcribing a recording, cutting clips, cleaning up audio, finding filler words, naming the spoken language, labeling who said what, redacting personal data before text leaves the machine, suggesting emoji, tagging a topic, naming the language of a text, flagging nudity in an image, finding, ranking, or cropping photos, picking a video's thumbnail, or writing a title, or when the user asks what on-device models are available. Everything runs locally with no API key; add --json for a parseable result.
---

# desertant

The `desertant` CLI (alias `da`) runs small Desert Ant Labs models on this machine.
Weights download once and cache; nothing leaves the device at inference. Prefer the
CLI over a network model when the input is sensitive or the task is one of the ones
below.

## Discover

- `desertant models --json` lists the models that run on this machine; `--all` lists
  the full catalog.
- `desertant info <id> --json` shows one model's card.
- `desertant schema --json` is the tool catalog: every runnable model, its input, and
  its options. Read it once to know what you can call.

## Run

Every command takes `--json` for a parseable result and reads text from stdin when no
argument is given. Exit code 0 on success, 1 on a runtime error, 64 on a usage error.
Weights download on first use with progress on stderr; stdout stays clean JSON.

- Redact personal data before sending text anywhere:
  `desertant redact "Email Anna at anna@example.hu" --json`
  Returns the redacted text plus the placeholder map, so you can restore originals in a
  reply.
- Suggest emoji: `desertant emo "pay my bills" --json`
- Tag what a text is about: `desertant gist "<article text>" --json`
- Name the language a short text is written in: `desertant tongue "<text>" --json`
- Flag nudity in a photo before upload or display: `desertant moderator photo.jpg --json`
  scores the image 0...1 and says whether the score crosses the threshold. On Linux it needs ffmpeg.
- Write a title and description for a passage: `desertant title "<text>" --json`
  (Apple silicon)
- Enhance an audio or video file: `desertant clear meeting.mp4 --json` writes an
  enhanced file and reports its path.
- Transcribe with word times: `desertant voz talk.mp4 --json`; `--srt` or `--vtt` also
  writes subtitles. Find filler words: `desertant uhm talk.mp4 --json`. Name the
  spoken language: `desertant ear talk.mp4 --json`. Uhm needs Apple silicon.
- Cut short clips from a talk or recording: `desertant clips talk.mp4 --json` transcribes,
  picks the moments, and writes one file per clip beside the input, reporting each
  clip's start, end, text, and file. `--select-only` returns the moments as
  timestamps without writing; `--transcript talk.srt` skips transcribing.
- Label who said what: `desertant who talk.mp4 --json` gives each speaker's time and
  turns. `desertant voz talk.mp4 --speakers --json` transcribes and puts a `speaker` on
  every sentence; `--names "Anna,Ben"` names them in the order they first speak, and
  `--srt` or `--vtt` writes captions with the names.
- Understand photos : `desertant eye photo.jpg --json` gives the kind of
  image, its scores, tags, faces, people, and pets. On a folder, one flag asks one
  question: `--has dog --not blurry` lists the matching paths, `--duplicates` groups
  near-duplicates with the keeper first, `--best` picks one photo, and
  `--sort aesthetic` or `--similar-to photo.jpg` ranks. `--crop 1:1` writes a crop. Use
  `--strict` before moving or deleting anything. On a video, `--thumbnail` writes the
  best frame and `--has people` returns the stretches that match.

- A file verb takes several paths or a folder (`desertant moderator photos/ --json`,
  `--recursive` for its subfolders) and loads the model once. The result is then an
  array with one entry per file. A file that fails is reported on stderr, and the exit
  code is 1 after the rest have run.

A command that writes a file never replaces one: a taken name steps aside to
`name-2.ext`, and the output can never be the input. Pass `--force` to overwrite.

The uniform form for any model is `desertant run <id> --input "<text>"` or
`desertant run <id> --file <path>`.

## Compose

Commands chain through their JSON documents. `desertant schema --json` lists what each
command `emits` and `accepts`; a match feeds through the named option, as a file or
`-` for stdin:

```
desertant voz talk.mp4 --json | desertant clips talk.mp4 --transcript -
desertant voz talk.mp4 --json | desertant who talk.mp4 --transcript - --json
```

Transcribe once and reuse the transcript rather than letting clips transcribe again.
`desertant docs pipelines` has the full picture.

## When to reach for desertant

Redact before you send anything with names, emails, or numbers to a remote service.
Run the other models when the user asks for them. Don't shell out for a model the
user hasn't asked for.
