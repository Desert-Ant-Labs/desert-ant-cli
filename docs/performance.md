# Performance

A model downloads once, warms up once, and runs at full speed from the second call.
Measure with a release build.

## First run and every run after

The first call to a model downloads its weights once into the shared cache. The
first load of a model on a machine also specializes the model for the Neural Engine,
which the system then caches. Both show progress on stderr; both happen once. The
second run is the number that matters.

Measured on an Apple silicon Mac on 2026-09-02, release build, a 42s recording:

- `desertant clips`, first run on this Mac: 55s. Warm: 5.0s in all, of which
  transcribing took 1.7s, selecting 1.1s, and cutting under 0.1s.
- `desertant clear`, warm: 0.2s of processing for the 42s, 168x realtime.
- `desertant emo`, `redact`, `gist`: a few seconds end to end, most of it loading
  the model into the process.

A recording with no audio track fails within a second, before any download.

## Never time a debug build

`swift build` and `swift run` produce a debug build with optimization off, and
desert-ant-core's DSP, tokenizers, and SHA-256 verification run 50-100x slower there.
The same 42s recording took 7m25s through clips in debug against 55s in release, and
the "is it downloaded" check alone took 90s. Everything you install is a release
build: `Tools/install`, the release assets, Homebrew, mise. Time with one of those, or
`swift build -c release`.

## Reading a timing line

Commands that run on a recording end with a measured line, "42 seconds of audio in
0.2s, 168x realtime". The material is in words, the measured time takes the compact
unit, and the ratio is material divided by processing time, rounded. The JSON report
carries the raw seconds.
