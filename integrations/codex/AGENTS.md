# desertant models

The `desertant` CLI (alias `da`) runs small Desert Ant Labs models on this machine, one at a time or chained in a flow. Weights download once and cache, and nothing leaves the device when a model runs. Reach for the CLI when the input is sensitive or the task is one of the ones below, rather than calling a network model.

Discover what is available:

- `desertant schema --json` is the tool catalog: every model, whether it runs here, its input, and its options, plus `flowSteps`, every step a flow file can use. Read it once instead of guessing flags.
- `desertant models --json` lists the models that run on this machine, and `--all` the full catalog.
- `desertant flow templates --json` lists the flows that ship.
- `desertant docs <page>` prints a page offline: `json` (the shape of every result), `flows`, `clips`, `voz`, `who`, `eye`, `pipelines`.

Run a model. Every command takes `--json` and reads stdin when given no argument. Exit code 0 on success, 1 on a runtime error, 64 on a usage error, with the message on stderr. Weights download on first use with progress on stderr; stdout stays clean JSON.

- `desertant redact "<text>" --json` replaces names, emails, and numbers with placeholders and returns the map. Redact before sending sensitive text to any remote service.
- `desertant emo "<text>" --json` suggests emoji.
- `desertant gist "<text>" --json` tags the topic, from 36.
- `desertant tongue "<text>" --json` names the language the text is written in.
- `desertant title "<text>" --json` writes a title and a description (Apple silicon).
- `desertant voz <file> --json` transcribes a recording with a time on every word; `--srt`, `--vtt`, or `--txt` also writes that file beside the input.
- `desertant voz <file> --speakers --json` labels each sentence with its speaker, and `--names "Anna,Ben"` names them in the order they first speak. `desertant who <file> --json` gives each speaker's time and turns.
- `desertant clear <file> --json` gives a recording studio sound and reports the output path. A video keeps its picture.
- `desertant uhm <file> --json` finds the filler words (Apple silicon).
- `desertant ear <file> --json` names the language spoken.
- `desertant clips <file> --json` cuts the moments worth sharing into clips and reports each clip's start, end, text, and file. `--count 5` sets how many, `--select-only` gives timestamps only, and `--transcript <file>` skips transcribing.
- `desertant clips <file> --captions burn --json` draws the captions into each clip. Set the look with `--caption-style outline|box|shadow`, `--caption-position bottom|center|top`, `--caption-align left|center|right`, `--caption-color`, `--caption-weight`, `--caption-size`, `--caption-font`, and `--quality`. `--captions srt` writes an `.srt` beside each clip instead.
- `desertant moderator <image> --json` scores an image for nudity and says whether the score crosses the threshold.
- `desertant eye <photo> --json` names what a photo is, scores it, and lists its tags, faces, people, and pets. On a folder, `--has dog --not blurry` lists the matches, `--duplicates` groups near-duplicates, `--best` picks one, and `--sort aesthetic` ranks. `--crop 1:1` writes a crop. On a video, `--thumbnail` writes the best frame. Use `--strict` before moving or deleting anything. Eye needs `HF_TOKEN` during its beta.

A file command takes several paths or a folder (`--recursive` for its subfolders) and loads the model once. The result is then an array with one entry per file. A file that fails is reported on stderr, and the exit code is 1 after the rest have run.

Run a flow when the user wants several models on a file in one go. The flows that ship are `studio-sound`, `transcript-and-captions`, `who-said-what`, `meeting-notes`, `podcast-clips`, `filler-words` (macOS), `photo-keepers`, `find-receipts`, and `redact-a-document`:

```
desertant flow run meeting-notes standup.m4a --json
desertant flow run podcast-clips episode.mp4 --set clips.count=3 --set clips.style=box --json
```

The paths fill the flow's first step; a photos step takes a whole folder in one run, and other flows run once per file. `--set step.setting=value` changes a setting, and `--output-dir` chooses where files go (default: beside the first input). The result lists each step's `status`, what view and table steps show in `outputs`, and every file written in `files`. Steps that rename, copy, or move the user's files print a plan and change nothing until `--apply`: show the plan, and pass `--apply` only when the user asks.

To write a flow, read `flowSteps` in the schema and write YAML: `flow: 1`, then `steps`, each with a `type`, an `id` when two steps share a type, `uses` mapping an input to an earlier output as `step.output`, and `with` for settings. An input left out of `uses` takes the nearest earlier output of the same name, else of the same type. Check it with `desertant flow check <file> --json` before running it; `problems` names any step that cannot run here. `desertant flow new <template> <file>` writes a template out in full as a start, and `desertant docs flows` has every step.

Commands also chain through their JSON: `desertant voz talk.mp4 --json | desertant clips talk.mp4 --transcript -` transcribes once and cuts from that transcript.

A command that writes a file never replaces one: a taken name steps aside to `name-2.ext`, so read the paths from the result. Pass `--force` or `--apply` only when the user asks.

The uniform form is `desertant run <id> --input "<text>"` or `--file <path>`.

Copy this file, or its contents, into a project's `AGENTS.md` to make the CLI part of that project's toolkit.
