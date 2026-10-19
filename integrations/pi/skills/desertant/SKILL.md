---
name: desertant
description: Run Desert Ant Labs on-device models through the desertant CLI. Use for transcribing a recording, cutting clips, cleaning up audio, finding filler words, naming the spoken language, labeling who said what, redacting personal data before text leaves the machine, suggesting emoji, tagging a topic, naming the language of a text, flagging nudity in an image, finding, ranking, or cropping photos, picking a video's thumbnail, or writing a title. Local, no API key; add --json for a parseable result.
---

# desertant

The `desertant` CLI (alias `da`) runs small Desert Ant Labs models on this machine.
Weights download once and cache; nothing leaves the device at inference. Call it with
the bash tool.

Discover:

- `desertant models --json` lists the models that run on this machine; `--all` lists
  the full catalog.
- `desertant schema --json` is the tool catalog: every runnable model, its input, and
  its options.

Run. Every command takes `--json` and reads stdin when given no argument. Exit code 0
on success, 1 on a runtime error, 64 on a usage error. Weights download on first use
with progress on stderr; stdout stays clean JSON.

- `desertant redact "<text>" --json` replaces personal data with placeholders and
  returns the map. Redact before sending sensitive text to any remote service.
- `desertant emo "<text>" --json` suggests emoji.
- `desertant gist "<text>" --json` tags the topic.
- `desertant tongue "<text>" --json` names the language the text is written in.
- `desertant moderator <image> --json` scores an image for nudity and says whether the
  score crosses the threshold. On Linux it needs ffmpeg.
- `desertant title "<text>" --json` writes a title and a description (Apple silicon).
- `desertant voz <file> --json` transcribes a recording with a time on every word;
  `--srt` or `--vtt` also writes captions beside the input.
- `desertant uhm <file> --json` finds the filler words (Apple silicon).
- `desertant ear <file> --json` names the language spoken.
- `desertant clear <file> --json` denoises an audio or video file and reports the
  output path.
- `desertant clips <file> --json` cuts short clips from a talk or recording and reports
  each clip's start, end, text, and file; `--select-only` gives timestamps only.
- `desertant who <file> --json` labels who spoke when: each speaker's time and turns.
  `desertant voz <file> --speakers --json` transcribes and labels each sentence with its
  speaker; `--names "Anna,Ben"` names them in the order they first speak.
- `desertant eye <photo> --json` names what a photo is, scores it, and lists its tags,
  faces, people, and pets. On a folder, `--has dog --not blurry` lists
  the matches, `--duplicates` groups near-duplicates, `--best` picks one, and
  `--sort aesthetic` ranks. `--crop 1:1` writes a crop. On a video, `--thumbnail`
  writes the best frame and `--has people` gives the stretches that match.

- A file verb takes several paths or a folder (`desertant moderator photos/ --json`,
  `--recursive` for its subfolders) and loads the model once. The result is then an
  array with one entry per file. A file that fails is reported on stderr, and the exit
  code is 1 after the rest have run.

Commands chain through their JSON: `desertant voz talk.mp4 --json | desertant clips
talk.mp4 --transcript -` transcribes once and cuts from that transcript.

A command that writes a file never replaces one: a taken name steps aside to
`name-2.ext`. Pass `--force` to overwrite.

The uniform form is `desertant run <id> --input "<text>"` or `--file <path>`.
