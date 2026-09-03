# Transcripts and captions

Transcribe a recording with a time on every word, and get the transcript or the
captions in the format the next tool wants.

```
da voz talk.mp4
```

Prints the transcript, one sentence per line, and ends with the measured line:
"Voz loaded in 1.1s. Transcribed 2 minutes of audio in 0.5s, 270x realtime". The first figure is
the model coming up, once per run; the realtime factor is the recognizer alone. Voz runs on Apple silicon; 25 languages.

## Timestamps

```
da voz talk.mp4 -t
```

```
0:00  For five years we've built on-device first at Detail and now at Subwave.
0:06  Because going local let us ship the best product experience we could.
1:04  That's why we're starting Desert Ant Labs.
```

Each sentence carries the time it starts, as `m:ss` or `h:mm:ss`.

## Files

Each flag writes the input's name with that extension, beside the input:

- `--srt`: captions, `talk.srt`.
- `--vtt`: captions, `talk.vtt`.
- `--txt`: the transcript, `talk.txt`, one sentence per line.

Mix them as you like. A taken name steps aside (`talk-2.srt`); `--force` replaces.
`-o path` writes one file at that path instead, in the format its extension names
(`srt`, `vtt`, `txt`, or `json`). The command prints every path it wrote.

## Pipes

`--format srt|vtt|txt|json` puts that format on stdout:

```
da voz talk.mp4 --format srt > captions.srt
da voz talk.mp4 --json | da clips talk.mp4 --transcript -
```

`--json` is the document: `text`, `words` and `sentences` with times, `captions`
(the cues), and `files` (what was written). `clips --transcript` reads it, and reads
SRT and VTT from anywhere.

## How captions are cut

Captions follow the rules broadcasters use, so they fit a caption box and stay
readable:

- At most 2 lines of at most 42 characters.
- At most 7s on screen, at least 1s.
- A cue breaks at the end of a sentence first, then at a comma or clause, then at
  the widest pause between words; a wrapped cue balances its two lines.
- Cues never overlap, and a gap under 0.3s between two cues is closed.

The transcript (`--txt`, `--format txt`, and the screen) is sentences, not cues.
