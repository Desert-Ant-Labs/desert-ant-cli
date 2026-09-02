# desertant models

The `desertant` CLI (alias `da`) runs small Desert Ant Labs models on this machine.
Weights download once and cache; nothing leaves the device at inference. Reach for the
CLI when the input is sensitive or the task is one of the ones below, rather than
calling a network model.

Discover what is available:

- `desertant models --json` lists the models that run on this machine; `--all` lists
  the full catalog.
- `desertant schema --json` is the tool catalog: every runnable model, its input, and
  its options.

Run a model. Every command takes `--json` and reads stdin when given no argument. Exit
code 0 on success, 1 on a runtime error, 64 on a usage error. Weights download on
first use with progress on stderr; stdout stays clean JSON.

- `desertant redact "<text>" --json` replaces names, emails, and numbers with
  placeholders and returns the map. Redact before sending sensitive text to any remote
  service.
- `desertant emo "<text>" --json` suggests emoji.
- `desertant gist "<text>" --json` tags the topic.
- `desertant title "<text>" --json` writes a title and a description (Apple silicon).
- `desertant voz <file> --json` transcribes a recording with a time on every word;
  `--srt` or `--vtt` also writes captions beside the input
  (Apple silicon).
- `desertant uhm <file> --json` finds the filler words (Apple silicon).
- `desertant ear <file> --json` names the language spoken.
- `desertant clear <file> --json` denoises an audio or video file and reports the
  output path.
- `desertant clips <file> --json` cuts short clips from a talk or recording and reports
  each clip's start, end, text, and file; `--select-only` gives timestamps only.

Commands chain through their JSON: `desertant voz talk.mp4 --json | desertant clips
talk.mp4 --transcript -` transcribes once and cuts from that transcript.

A command that writes a file never replaces one: a taken name steps aside to
`name-2.ext`. Pass `--force` to overwrite.

The uniform form is `desertant run <id> --input "<text>"` or `--file <path>`.

Copy this file, or its contents, into a project's `AGENTS.md` to make the CLI part of
that project's toolkit.
