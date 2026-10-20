# Flows

Run several models on a file in one command: clean up a recording, transcribe it, cut captioned clips, and save notes, all on this machine. A flow file lists the steps in YAML, and desertant ships templates you can run as they are or copy and edit.

## Templates

1. List the templates:

   ```sh
   da flow templates
   ```

2. Run one on your file:

   ```sh
   da flow run transcript-and-captions talk.mp4
   ```

3. Read the paths it prints. The files are beside the input: `talk.txt`, `talk.srt`, and `talk.vtt`.

| Template | What it does |
| --- | --- |
| `studio-sound` | Takes the noise and echo out of a recording and levels the voice. A video keeps its picture. |
| `transcript-and-captions` | Transcribes a recording into text, SRT, and WebVTT. |
| `who-said-what` | Transcribes a recording and names the speaker of each line. |
| `meeting-notes` | Names each speaker, replaces personal data with placeholders, and tags the main topic. |
| `podcast-clips` | Cleans up the sound, then cuts the moments worth sharing into clips with captions burned in. |
| `filler-words` | Lists each uh, um, and hmm with its time. Runs on macOS. |
| `photo-keepers` | Copies the photos worth keeping into a Keepers folder: no blurry or accidental shots, one of each near-duplicate. |
| `find-receipts` | Copies the receipts among your photos into a Receipts folder. |
| `redact-a-document` | Replaces the personal data in a text with placeholders and prints it. |

`da flow show <template>` prints a template's YAML, and `da flow new <template>` copies it to `<template>.flow` in the current folder to edit.

## Running a flow

`da flow run` takes a flow file or a template's name, then the files to run it on:

```sh
da flow run podcast-clips episode.mp4
da flow run meeting-notes standup.m4a --set who.names="Anna,Ben"
da flow run photo-keepers ~/Pictures/trip --apply
echo "Call Anna at 555-0100" | da flow run redact-a-document
```

The paths fill the flow's input step, its first step. A step that takes a list, `photos` or `files`, gets every path in one run, and a folder gives it every file inside. Any other input step runs the flow once per file, and each model loads once for all of them. A `text` step reads a file's text, or stdin when you pass no file. `--recursive` also takes the files in a folder's subfolders.

What a flow saves goes beside the first input, or into `--output-dir`. A taken name steps aside to `talk-2.srt` unless you pass `--force`, and the input itself is never written over.

`--set step.setting=value` changes one step's setting for this run, as `--set clips.count=3` or `--set clips.style=box`. `da schema --json` lists each step's settings and their defaults.

The `rename` and `copy` steps change your own files, so they wait for `--apply`. Without it they print each file they would copy, move, or rename, and change nothing.

Under `--json`, a run prints one document: each step's status and time, what each view and table step shows, and the files it wrote. When the flow runs once per file, the result is an array. [json.md](json.md) has the shape.

The exit code is 1 when a step fails. A step whose input brought nothing, such as the `no` side of an `if` that every item passed, is skipped and isn't a failure.

## Flow files

A flow file is YAML: `flow: 1`, a title, and a list of steps. Each step has a `type`, and can have an `id`, `uses` to say where its inputs come from, and `with` for its settings.

```yaml
flow: 1
title: Podcast clips
summary: Cut captioned clips from a video podcast or a talk.
steps:
  - type: audio
  - type: clear
    with:
      loudness: podcast
  - type: voz
  - type: clips
    with:
      captions: burn
      count: 5
  - type: folder
```

A step without an `id` is called by its type, as `voz` above. When two steps have the same type, give all but one of them an `id`.

`uses` maps a step's inputs to outputs of earlier steps, as `step.output`:

```yaml
  - id: notes
    type: template
    uses:
      a: redact.text
      b: gist.top
    with:
      template: "# Notes\n\n{{date}}, about {{b}}\n\n{{a}}"
```

An input left out of `uses` takes the output of the same name from the nearest step before it, so `voz` above transcribes `clear`'s audio. If no earlier step has an output of that name, a required input takes the nearest output of the same type. When that step has several outputs of the type, the input takes the one `da schema --json` lists first for the step, if that one fits. If it doesn't fit, `da flow check` asks you to name one in `uses`.

`uses` can only name earlier steps. `da flow check` reads a file, prints how every input is wired, and names any step that doesn't run on this machine. `da flow new` writes every id and every wire out in full, and lists each step's settings.

## Lists

Some outputs are lists that go on item by item: the photos of a `photos` step, a transcript's sentences, the clips of a `clips` step. A step after one that takes a single item runs once per item. A step that takes a whole list, as `folder`, `table`, `join`, `list`, and `duplicates` do, gets every item at once.

An `if` step sends each item down `yes` or `no` and leaves a gap on the other side, so the two sides stay in step with the list they came from. `merge` joins them back together. An item that fails leaves a gap too, and the step fails only when every item does.

## Steps

`da schema --json` lists every step with its inputs, outputs, settings, and each setting's default.

| Step | What it does | Settings |
| --- | --- | --- |
| `audio` | An audio or video file. | `file` |
| `image` | A photo. | `file` |
| `photos` | Several photos, as a list. | `files` |
| `files` | Files, or every file in some folders, as a list. | `files`, `folders` |
| `watch` | The files in a folder, sorted into photos, recordings, texts, and files. | `folder`, `files` |
| `text` | Text from a file, stdin, or the flow. Also as lines, sentences, and paragraphs. | `text` |
| `textlist` | Several texts, one item each. | `items` |
| `voz` | Transcribes speech, with a time on every word. | |
| `who` | Tells the speakers apart. With voz's words, labels each line. | `names` |
| `clear` | Studio sound: noise and echo out, the voice leveled. | `loudness`: podcast, spotify, youtube, broadcast, or off |
| `clips` | Cuts the moments worth sharing into clips. | `count`, `captions`, and the caption settings below |
| `captions` | SRT and WebVTT from voz's words, with speaker names from who's turns. | |
| `uhm` | The uh, um, and hmm in a recording, with times. macOS only. | |
| `ear` | The language spoken in a recording. | |
| `redact` | Personal data replaced with placeholders. | `confidence` |
| `gist` | The topics of a text, from 36. | `limit` |
| `emo` | Emoji that fit a text. | `limit` |
| `tongue` | The language of a short text. | |
| `eye` | What a photo shows, its kind, quality, faces, and framing. | |
| `moderator` | Whether a photo is safe to show. | `threshold` |
| `duplicates` | The photos to keep from sets of near-duplicates, and the rest. | |
| `readtext` | The text in a photo, read with Apple's Vision. macOS only. | `fast` |
| `if` | Sends each value down yes or no. | `op`, `operand` |
| `merge` | Joins the two sides of an if back together. | |
| `list` | Sorts, slices, or counts a list. | `op`, `n` |
| `best` | The item with the highest score. | |
| `template` | Text with `{{a}}`, `{{b}}`, `{{c}}`, `{{date}}`, `{{time}}`, and `{{b\|lang}}` filled in. | `template` |
| `join` | A list joined into one text. | `separator`: newline, space, comma, or paragraph |
| `convert` | A photo, recording, text, or table saved in another format. | `to` |
| `view` | Prints a value. | |
| `table` | Prints lists side by side, or one list of records with a column per field. | `columns` |
| `folder` | Saves a value as files. | `folder`, `name` |
| `rename` | New names for files from a pattern. Needs `--apply`. | `pattern`, `mode`: copy or rename, `folder` |
| `copy` | Copies or moves files into a folder. Needs `--apply`. | `mode`: copy or move, `folder`, `subfolder` |

An `if` checks with `op`: `equals`, `notEquals`, `oneOf` (a comma-separated `operand`), `contains`, `above`, `below`, `truthy`, `falsy`, or `empty`. An `if` checks the value itself, or its `test` input when one is wired, as a photo against Eye's `type`. A `list` takes `op`: `desc` or `asc` (sorted by its `by` input when wired), `sort`, `most`, `firstN`, `lastN`, `item`, `count`, `unique`, `reverse`, or `compact`.

The eye step gives `subject`, `scenes`, `type`, `animal`, `people`, `pets`, `keeper`, `reason`, `aesthetic`, `cover`, `sharp`, `blur`, `sensitive`, `faces`, `smile`, `eyesOpen`, `looking`, `expression`, `shot`, `crop`, and `detail`, the document `da eye --json` writes. `reason` is `keeper`, or why a photo isn't worth keeping: blurry, taken by accident, nothing special, and so on.

The clips step takes the caption settings `da clips` takes, without the `caption-` in front: `captions` (burn, srt, or off), `position`, `align`, `font`, `size`, `weight`, `color`, `style`, `lines`, `words`, and `quality`. `quality` is `high` unless you set it, in the file or with `--set clips.quality=medium`, and every level keeps the source's size and frame rate. [clips.md](clips.md) explains each setting.

## Saved files

A `folder` step saves text as `.txt`, captions as `.srt` or `.vtt`, text with Markdown in it as `.md`, a list of records as `.csv`, and anything else as `.json`, named by its `name` setting. `{{name}}` in it is the first input's name without its extension, so `"{{name}}_notes"` saves `standup_notes.md` beside `standup.m4a`. Audio, video, and photos keep their own names, as `talk_clear.wav` or `talk_clear_clip-1.mp4`. A bare `folder` setting, as `Receipts`, is a folder beside the input or inside `--output-dir`.

A file a step makes along the way, as clear's clean audio, is kept only when a `folder` or `view` step takes it. A `view` of such a file saves it beside the input, or into `--output-dir`, and prints the path of the saved copy.

## Limits

- Steps run one after another, in file order. Each model loads once per command.
- A text splits into sentences at a period, question mark, or exclamation mark before a capital, a digit, or a line break, the same way on macOS and Linux. An abbreviation such as "Dr." before a name ends a sentence.
- A flow file holds at most 8MB and a million values.
- `da flow check` names any step type desertant doesn't have, and `da flow run` refuses a file that uses one.
- `watch` reads the files in its folder once, and doesn't wait for new ones.
- `uhm` and `readtext` run on macOS only. On Linux, every step that reads audio other than WAV, video, or photos needs ffmpeg, and burned-in captions need an ffmpeg built with libass.
- Eye is in closed beta, so the `eye` and `duplicates` steps need `HF_TOKEN` set to a Hugging Face token with access to [desert-ant-labs/eye](https://huggingface.co/desert-ant-labs/eye).
