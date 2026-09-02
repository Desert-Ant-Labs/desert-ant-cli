# Using desertant from an agent

desertant is a command-line tool a coding agent runs through its shell. There is no
server, no API key, and no session: each call is one process that reads its input,
runs a model on this machine, and writes one result.

## Find out what you can call

```
desertant schema --json
```

The catalog of every shipping model: its id, whether it runs on this machine, whether
it takes text or a file, and its options with a line of help each. The schema is
built from the same code the commands run, so a model, option, or exit code listed
there exists. Read it once per session rather than guessing flags.

`desertant home --json` is the short form: the verbs that run on this machine, each
with its input kind and a line of help. The bare `desertant` shows a person the same
list.

`desertant models --json` lists the models that run on this machine; `--all` lists
the full catalog, including models with no runner on this machine. `desertant info
<id> --json` is one model's card with `runnableHere` and `downloaded`.

`desertant setup` writes your own setup: a skill for Claude Code or Pi, a marked
section in `AGENTS.md` for Codex, in the current project (`--global` for the user).
`desertant docs skill` and `desertant docs codex` print the same text.

The docs are inside the binary. `desertant docs --json` lists the pages;
`desertant docs json --json` returns a page as `{name, title, markdown}`. Read
`docs json` for the exact shape of each result before parsing one.

## Call a model

A model runs by its verb or through `run`; both do the same thing:

```
desertant redact "Email Anna at anna@example.hu" --json
desertant run redact --input "Email Anna at anna@example.hu" --json
desertant clear meeting.mp4 --json
desertant run clear --file meeting.mp4 --option output=clean.mp4 --json
```

A text model reads its text from the argument, or from stdin when no argument is
given, so a long passage can be piped in. A file model takes a path and never reads
media from stdin. `clips --transcript -` reads a transcript document from stdin, so
`voz --json` pipes into `clips`; see [pipelines.md](pipelines.md).

## What comes back

stdout carries the result and nothing else. Under `--json` stdout is one JSON value,
whose shape per command is in [json.md](json.md); numbers are numbers, lists are
lists, and paths are absolute. Without `--json`, stdout is text for a person.

stderr carries everything that isn't the result: progress while weights download or
a long file runs, and the error message when a call fails. Progress draws only when
stderr is a terminal, so captured stderr holds only messages.

Exit codes: `0` success, `1` a runtime error (the message on stderr says what), `64`
a usage error (an unknown model, a bad flag). Check the code before parsing stdout.

`--quiet` drops notes and progress. `--no-color` is implied by `--json` and by a
pipe, so you never need to strip escape codes.

## Updates

`desertant` checks for a newer release once a day and prints a line when there is
one. No other command touches the network unless asked. Set
`DESERTANT_NO_UPDATE_CHECK=1` in CI and agent loops. `desertant update --check` asks
now.

## First runs

The first call to a model downloads its weights (once, into a shared cache) and the
first load on a machine prepares the model for the Neural Engine. Both show progress
on stderr and both happen once; the second call is fast. `desertant pull <id>` does
the download ahead of time, and `desertant doctor --json` reports what is downloaded
and runnable.

## Files

A command that writes a file never replaces one. The output can never be the input
(the call fails), and a name that exists steps aside to `name-2.ext`. The JSON result
always carries the path that was actually written, so read `output` (or each clip's
`file`) rather than predicting the name. Pass `--force` only when the user has asked
to overwrite. Details in [files.md](files.md).

## When to reach for desertant

Redact before sending text with names, emails, or numbers to any remote service; the
placeholder map in the result restores the originals afterward. Run the other models
when the task asks for them. Don't run a model the user hasn't asked for, and don't
pass `--force` on your own judgment.
