# Files and the cache

desertant writes outputs beside the input, never over an existing file, and keeps
model weights in a cache shared with other Desert Ant apps.

## Outputs never replace files

A command that writes a file follows one rule, in `Destination.swift`, whichever
command it is:

- The output can never be the input. `desertant clear talk.wav --output talk.wav`
  fails before anything runs.
- A name that exists steps aside: `talk_clear.mp4` is taken, so the next run writes
  `talk_clear-2.mp4`, then `-3`. The Finder and the Clipper app do the same, so a
  batch never stops and nothing is lost.
- `--force` replaces in place, and is the only way to overwrite.

The JSON result carries the path actually written (`output`, or each clip's `file`),
so a script reads it rather than predicting the name.

Default names sit beside the input and keep its container: `talk.mp4` becomes
`talk_clear.mp4` for clear, and `talk_clip-1.mp4`, `talk_clip-2.mp4` for clips
(`--output-dir` moves them); a `.mov` gives `.mov` clips, a `.wav` gives `.wav` clips.
Clips are cut without re-encoding, so a video clip starts on a keyframe. The one
exception is mp3, which Apple platforms cannot write: an mp3 input comes out as m4a,
and the command says so. `--output` with another extension picks another container.

## The model cache

Weights download on first use into the platform cache, `~/Library/Caches/desert-ant-models`
on macOS, under `desert-ant-labs/<model>/<revision>/`. Every Desert Ant app built on
desert-ant-core reads and writes the same directory, so a model one app fetched is
ready for the others, and the revision in the path lets two apps pinned to different
releases each keep their copy.

- `desertant cache` shows the path, its size, and what is downloaded; `--path` prints
  only the directory.
- `desertant pull <id>` fetches a model before you need it, for an offline session.
- `desertant cache --clean --force` deletes every downloaded model, including the
  other apps' copies; they download again on their next run.

Downloads are verified against the release's checksums, so an interrupted download is
never mistaken for a complete one.
