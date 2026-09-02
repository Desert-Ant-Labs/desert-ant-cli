# Pipelines

desertant commands compose by passing JSON documents through the shell, never the
media. Some of this ships today and some is planned; each section says which.

## Pipe the metadata, not the media

Unix pipes are right for text and JSON and wrong for a 2GB recording: piping bytes
makes every step buffer or remux, and the media frameworks want a seekable file. So
every media command takes a path and, under `--json`, emits a small document about
what it found or wrote: a transcript with times, a list of spans, clip ranges, an
output path. The media stays where it is.

Ships today: every command emits its document, and a command that reads one takes it
as a file or, with `-`, from stdin, so the steps chain in the shell:

```
desertant voz talk.mp4 --json | desertant clips talk.mp4 --transcript -
desertant clear talk.mp4 --json | jq -r .output
```

`desertant schema --json` says which documents fit where: each command lists what it
`emits` (`transcript`, `spans`, `clips`, `file`) and what it `accepts`, with the
option that takes it. An agent plans a chain from that alone. clips also takes SRT or
VTT written by anything else.

## Render once

Most of a pipeline is analysis: filler-word spans from uhm, a transcript from voz,
ranges from clips. Only the last step should touch pixels, and only once: one
composition with the original video track passed through unencoded, the enhanced
audio from clear muxed in, cut to the clip ranges minus the filler spans, exported in
a single pass. clear already renders video like this (a passthrough container with
the enhanced audio inside), so core has the pattern.

Two caveats. A passthrough cut lands on a keyframe, so a `--precise` option would
re-encode video when a cut has to land on the frame. And enhance, fillers, and
transcribe each decode audio; running fillers and transcribe on the one enhanced
audio file trims that to one extraction.

Ships today: `desertant voz` (the transcript) and `desertant uhm` (the filler
spans). Planned: a final `desertant export` that takes the documents and renders
once.

## Large files

Every step runs at bounded memory: clear streams the file chunk by chunk (an hour
uses the same RAM as ten seconds), Voz reads as it goes, and AVFoundation exports
stream. Nothing loads a whole recording into memory, which is why the media is passed
by path.

## A job file

Once the documents exist, a job file is a thin runner over the same steps that shares
their intermediates. The file would be JSON, which needs no new dependency and is
what agents write natively; YAML could layer on for people who prefer to hand-write
jobs. The job file comes after the commands, because a shell pipeline of composable
commands is already a spec and keeps every step testable on its own.
