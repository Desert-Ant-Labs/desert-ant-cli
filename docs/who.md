# Speakers

Label who said what in a podcast, interview, or meeting recording: each speaker's time, their turns, and with a transcript, the speaker of every line.

```
da who interview.mp4
```

```
2 speakers in 46 seconds
Speaker 1      28s   62%
Speaker 2      12s   26%

0:00 to 0:05  Speaker 1  4.9s
0:06 to 0:11  Speaker 2  5.3s
0:12 to 0:15  Speaker 1  3.1s
Who labeled 46 seconds in 0.03s, 1377x realtime.
```

Who numbers the speakers in the order they first speak. Who labels voices and doesn't know the people, so `--names "Sam,Dan"` names them in that order. The share is each speaker's time against the whole recording, so silence and music make the shares add up to less than 100%. Who takes audio or video, and labeled a 15-minute recording in 1.5s on an M4 Max. On Linux, ffmpeg reads any file that isn't WAV.

## Who said what

```
da voz interview.mp4 --speakers --names "Sam,Dan"
```

```
Sam
0:00  Welcome back to the show.
0:01  Today we are talking about small models that run on your phone.

Dan
0:05  Thanks for having me.
0:07  I have been building on device features for about five years now.
```

Voz transcribes, Who labels the speakers, and each word goes to the speaker heard while it's spoken. A sentence two people share splits where the speaker changes. The caption and text files carry the speakers too:

- `--srt`: the speaker's name in front of a cue when the speaker changes, `Sam: Welcome back to the show.`
- `--vtt`: a voice tag on every cue, `<v Sam>Welcome back to the show.`, which players can show or style.
- `--txt`: a paragraph per turn, the name in front.

Who downloads on the first `--speakers` run.

## A transcript you already have

```
da voz interview.mp4 --json > interview.json
da who interview.mp4 --transcript interview.json --format vtt > interview.vtt
```

`--transcript` takes the `--json` of voz, an `.srt`, or a `.vtt`, and `-` reads it from stdin. A Voz document carries every word's time, so a line splits where the speaker changes. An SRT or VTT from elsewhere is labeled cue by cue: each cue goes to the speaker heard most during it.

## Formats

`--format` puts one format on stdout, and `-o path` writes one file in the format its extension names:

- `rttm`: one `SPEAKER` line per turn, the format diarization tools score and exchange.
- `json`: the document in [json.md](json.md).
- `srt`, `vtt`, `txt`: the transcript with speakers, with `--transcript`.

A taken name steps aside (`interview-2.rttm`); `--force` replaces.

## Turns

Who splits a turn wherever a speaker pauses, so `who` joins a speaker's turns across pauses up to 1s. Another speaker talking in between keeps two turns apart, so a short "yes" stays on the page. `--join 0` keeps every turn as Who found it, and `--join 3` joins across longer pauses. The RTTM and JSON turns are the joined ones; the times and shares count every turn.

`--min-share 0.05` leaves out a speaker heard for less than 5% of the recording, such as a laugh or a jingle that got a number of its own. The other speakers are numbered again in the order they first speak.

## Limits

- Who is built for conversations of up to four speakers. A recording with more voices is labeled with its four most present ones.
- A speaker's number holds within one recording. Speaker 1 in two files can be two different people.
- Two voices that sound alike can come out as one speaker.
