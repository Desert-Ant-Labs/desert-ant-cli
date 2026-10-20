# Clips

Cut short clips from a talk, a podcast, or a meeting recording, on this machine, with the captions burned in if you want them.

```
desertant clips talk.mp4
```

Voz transcribes the recording with a time on every word, and Clips reads the sentences and picks the moments worth sharing, ranked best first and never overlapping. desertant writes one file per clip beside the input, in the input's container: `talk_clip-1.mp4`, `talk_clip-2.mp4`, or `.wav` clips from a `.wav`. The cut copies the tracks rather than re-encoding them, so a video clip starts on a keyframe. The run ends with a line you can quote, such as "8 clips from 48 minutes in 41s".

## Options

- `--count 5` looks for five clips. Without it, the model sizes the search to the recording. The count sets the search budget rather than trimming a longer list, so `--count 5` isn't the first five of `--count 10`.
- `--transcript talk.srt` uses a transcript instead of transcribing: SRT, VTT, or JSON as `[{"start": 1.0, "end": 4.5, "text": "..."}]` in seconds. `-` reads one from stdin.
- `--select-only` reports the moments as timestamps and text, and writes nothing.
- `--output-dir clips/` puts the files in that folder.
- `--force` replaces existing clip files instead of stepping aside to new names.
- `--captions burn` draws the captions into each clip. `--captions srt` writes `talk_clip-1.srt` beside each clip instead, and `off`, the default, writes no captions.
- `--json` prints the report, described in [json.md](json.md).

## Burned-in captions

To post a clip where people watch without sound, burn the captions into it:

```sh
da clips talk.mp4 --captions burn
da clips talk.mp4 --captions burn --caption-style box --caption-position top
```

The captions come from Voz's time on every word, moved onto the clip's own timeline, so a clip joined from two stretches of the recording shows the right words over each. Burning re-encodes the video. A clip without captions is still cut without a re-encode.

| Option | Values | Default |
| --- | --- | --- |
| `--caption-position` | `bottom`, `center`, or `top`, inside margins that keep clear of a phone app's buttons | `bottom` |
| `--caption-align` | `left`, `center`, or `right` | `center` |
| `--caption-font` | A font family installed on the machine, or a `.ttf` or `.otf` file | Inclusive Sans |
| `--caption-size` | The text's height as a share of the frame's height, as `0.06` | 7% of the frame's short side |
| `--caption-weight` | `regular`, `medium`, `semibold`, `bold`, `black`, or 100 to 900 | `bold` |
| `--caption-color` | A name such as `white` or `yellow`, or a hex color such as `#ffcc00` | `white` |
| `--caption-style` | `outline`, `box` (a dark box behind each line), or `shadow` | `outline` |
| `--caption-lines` | Lines on screen at once, `1` or `2` | Set by the clip's shape |
| `--caption-words` | The most words in one caption | Set by the clip's shape |
| `--quality` | How much a clip with burned captions is compressed: `high`, `medium`, or `low` | `high` |

Inclusive Sans ships with desertant in the `fonts` folder beside the binary, so a clip looks the same on macOS and Linux. On macOS, Core Text draws the captions and AVFoundation encodes the clip. On Linux, libass draws them and ffmpeg encodes the clip with H.264, so burning needs an ffmpeg built with libass, as most distributions build it. A family name is found with Core Text on macOS and with fontconfig on Linux. Inclusive Sans has the Latin letters of most European languages and of Vietnamese. Captions in Greek, Cyrillic, and other scripts use a system font for those letters.

## Caption shapes

The captions follow the clip's shape, which the clip's width over its height decides:

| Shape | Width over height | Lines | Characters a line | Longest on screen |
| --- | --- | --- | --- | --- |
| Vertical | under 0.8 | 1, of up to 5 words | 20 | 1.5s |
| Square | 0.8 to 1.25 | 2 | 26 | 2.5s |
| Landscape | over 1.25 | 2 | 42 | 5s |

A line never holds more than fits across the frame at the chosen size, so a 1080x1080 clip takes 25 characters a line at the default size. A new caption starts at the end of a sentence, after a pause, which on a vertical clip is any silence over 0.4s and otherwise over 0.7s, or when a caption has been up for its longest. `--caption-lines` and `--caption-words` change the shape's lines and words.

## Caption timing

A caption stays up after its last word for the silence that follows, for at most 0.5s. When the next caption starts less than 0.5s later, the first stays up until it appears, so the screen doesn't flicker. After a longer silence the screen clears 0.5s after the speech, until the next words. Every caption is up for at least 0.8s, never past the start of the next one. An `.srt` from `--captions srt` keeps the broadcast rules [voz.md](voz.md) describes, since players lay those out themselves.

## Quality

Every quality keeps the source's size and frame rate. `high`, the default, is as close to the source as a re-encode gets: Apple's highest quality export on macOS, which wrote 10.5Mbps for a 1080p clip at 30fps, and H.264 at CRF 18 on Linux. `medium` and `low` make smaller files. On macOS they write H.264 at 0.05 and 0.025 bits a pixel, 3.1Mbps and 1.6Mbps for 1080p at 30fps, and on Linux at CRF 23 and CRF 28.

## Audio

A recording with no picture has nothing to burn into, so `--captions burn` on audio writes an `.srt` beside each clip and says so on stderr.

## Requirements

Clips needs at least three sentences of speech. A recording with no audio track fails within a second, before any model is fetched. The first run downloads Voz and Clips into the shared cache and prepares them for the Neural Engine, with progress on stderr, and later runs skip both.

## Pipeline

The pipeline is in `Sources/DesertAntCLI/Clipping/`. `ClipPipeline` orders the three steps and writes the report. `Transcriber` and `MediaCutter` are the seams: Voz behind the first everywhere, and AVFoundation behind the second on Apple platforms and ffmpeg on Linux. `Burn.swift` holds the caption shapes, timing, and both renderers.
