# Clips

Cut short clips from a talk, a podcast, or a meeting recording, on this machine.

```
desertant clips talk.mp4
```

Voz transcribes the recording with a time on every word, Clips reads the sentences
and picks the moments worth sharing, ranked best first and never overlapping, and one
file per clip lands beside the input, in the input's container: `talk_clip-1.mp4`,
`talk_clip-2.mp4`, or `.wav` clips from a `.wav`. The cut copies the tracks rather
than re-encoding them, so a video clip starts on a keyframe. The run ends with a line you can quote: "8 clips from 48
minutes in 41s".

## Options

- `--count 5`: how many clips to look for. Without it the model sizes the search to
  the recording. The count sets the search budget rather than trimming a longer
  list, so `--count 5` isn't the first five of `--count 10`.
- `--transcript talk.srt`: use a transcript instead of transcribing. SRT, VTT, or
  JSON as `[{"start": 1.0, "end": 4.5, "text": "..."}]` in seconds; `-` reads one
  from stdin. On Linux, where Voz doesn't run, clips runs from a transcript.
- `--select-only`: report the moments as timestamps and text, write nothing.
- `--output-dir clips/`: where the files go.
- `--force`: replace existing clip files instead of stepping aside.
- `--json`: the report, in [json.md](json.md).

## What it needs

At least three sentences of speech. A recording with no audio track fails within a
second, before any model is fetched. The first run downloads Voz and Clips into the
shared cache and prepares them for the Neural Engine, with progress on stderr; later
runs skip both.

## How it's built

The pipeline lives in `Sources/DesertAntCLI/Clipping/`. `ClipPipeline` orders the
three steps and writes the report; `Transcriber` and `MediaCutter` are the seams,
with Voz and AVFoundation behind them on Apple platforms. Another platform brings its
own recognizer and cutter by conforming to those two protocols, and `--transcript`
already works everywhere.
