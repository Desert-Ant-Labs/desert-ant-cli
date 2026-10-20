# Pipelines

desertant commands compose by passing JSON documents through the shell, never the media. Some of this ships today and some is planned; each section says which.

## JSON through pipes, media by path

Unix pipes are right for text and JSON and wrong for a 2GB recording: piping bytes makes every step buffer or remux, and the media frameworks want a seekable file. So every media command takes a path and, under `--json`, emits a small document about what it found or wrote: a transcript with times, a list of spans, clip ranges, an output path. The media stays where it is.

Every command emits its document today, and a command that reads one takes it as a file or, with `-`, from stdin, so the steps chain in the shell:

```
desertant voz talk.mp4 --json | desertant clips talk.mp4 --transcript -
desertant voz talk.mp4 --json | desertant who talk.mp4 --transcript - --format vtt
desertant clear talk.mp4 --json | jq -r .output
```

`desertant schema --json` says which documents fit where: each command lists what it `emits` (`transcript`, `speakers`, `spans`, `clips`, `file`) and what it `accepts`, with the option that takes it. An agent plans a chain from that alone. clips also takes SRT or VTT written by anything else.

## One render

Most of a pipeline is analysis: filler-word spans from uhm, a transcript from voz, ranges from clips. Only the last step should touch pixels, and only once: one composition with the original video track passed through unencoded, the enhanced audio from clear muxed in, cut to the clip ranges minus the filler spans, exported in a single pass. clear already renders video like this (a passthrough container with the enhanced audio inside), so core has the pattern.

A passthrough cut starts on a keyframe, so a `--precise` option would re-encode video when a cut has to start on the exact frame. And enhance, fillers, and transcribe each decode audio; running fillers and transcribe on the one enhanced audio file trims that to one extraction.

`desertant voz` (the transcript), `desertant who` (the speakers' turns), and `desertant uhm` (the filler spans) ship today. A final `desertant export` that renders once from the documents is planned.

## Large files

Every step runs at bounded memory: clear streams the file chunk by chunk (an hour uses the same RAM as ten seconds), Voz reads as it goes, and AVFoundation exports stream. Nothing loads a whole recording into memory, which is why the media is passed by path.

## Flows

A flow file runs a chain like the ones above in one command, and keeps what each step makes for the next: the transcript stays in memory, and clean audio and cut clips stay in a scratch folder until a step saves them. Each model loads once, even when the flow runs over a folder of files.

```sh
da flow run podcast-clips episode.mp4
```

The file is YAML that a person or an agent writes: a list of steps, each with a type, the outputs it uses, and its settings. desertant ships templates for the common chains, and `da schema --json` lists every step type for an agent that writes its own. [flows.md](flows.md) has the format.

`da flow run`, `templates`, `show`, `new`, and `check` ship today, with the steps for audio, text, photos, and logic.
