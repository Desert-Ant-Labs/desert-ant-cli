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
  from stdin.
- `--select-only`: report the moments as timestamps and text, write nothing.
- `--output-dir clips/`: where the files go.
- `--force`: replace existing clip files instead of stepping aside.
- `--captions burn`: draw the captions into each clip. `--captions srt` writes `talk_clip-1.srt` beside each clip instead, and `off`, the default, writes no captions.
- `--json`: the report, in [json.md](json.md).

## Burned-in captions

To post a clip where people watch without sound, burn the captions into it:

```sh
da clips talk.mp4 --captions burn
da clips talk.mp4 --captions burn --caption-style box --caption-position top
```

The captions come from Voz's time on every word, moved onto the clip's own timeline, so a clip joined from two stretches of the recording shows the right words over each. They are cut short for a phone screen: at most two lines of up to 32 characters, at most 3.5s each, a new caption at the end of a sentence or after a pause. Burning re-encodes the video. A clip without captions is still cut without a re-encode.

| Option | Values | Default |
| --- | --- | --- |
| `--caption-position` | `bottom`, `center`, or `top`, inside margins that keep clear of a phone app's buttons | `bottom` |
| `--caption-align` | `left`, `center`, or `right` | `center` |
| `--caption-font` | A font family installed on the machine, or a `.ttf` or `.otf` file | Atkinson Hyperlegible |
| `--caption-size` | The text's height as a share of the frame's height, as `0.06` | 7% of the frame's short side |
| `--caption-weight` | `regular`, `medium`, `semibold`, `bold`, `black`, or 100 to 900 | `bold` |
| `--caption-color` | A name such as `white` or `yellow`, or a hex color such as `#ffcc00` | `white` |
| `--caption-style` | `outline`, `box` (a dark box behind each line), or `shadow` | `outline` |
| `--quality` | `low`, `medium`, or `high` | `high` |

Atkinson Hyperlegible ships with desertant in the `fonts` folder beside the binary, so a clip looks the same on macOS and Linux. On macOS, Core Text draws the captions and AVFoundation encodes the clip; `--quality medium` also caps the clip at 1080p. On Linux, libass draws them and ffmpeg encodes the clip with H.264, so burning needs an ffmpeg built with libass, as most distributions build it. A family name is found with Core Text on macOS and with fontconfig on Linux.

A recording with no picture has nothing to burn into, so `--captions burn` on audio writes an `.srt` beside each clip and says so on stderr.

## What it needs

At least three sentences of speech. A recording with no audio track fails within a
second, before any model is fetched. The first run downloads Voz and Clips into the
shared cache and prepares them for the Neural Engine, with progress on stderr; later
runs skip both.

## How it's built

The pipeline lives in `Sources/DesertAntCLI/Clipping/`. `ClipPipeline` orders the
three steps and writes the report; `Transcriber` and `MediaCutter` are the seams,
with Voz behind the first everywhere, and AVFoundation behind the second on Apple
platforms and ffmpeg on Linux.
