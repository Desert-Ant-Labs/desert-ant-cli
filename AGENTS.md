# desert-ant-cli, for agents working on this repo

A Swift command-line tool that runs Desert Ant Labs models, built on desert-ant-core.
The binary is `desertant` (alias `da`).

## Layout

- `manifest.json` and `VERSION` at the root are the vendored catalog and the version.
  `Tools/embed` compiles them into `Sources/DesertAntCLI/Generated/Embedded.swift` so
  the binary is one file; never edit that file by hand. `Sources/DesertAntCLI/Discovery/`
  reads the catalog from it. All discovery is manifest-driven; don't hand-copy a fact
  the manifest already states.
- `Sources/DesertAntCLI/Run/` is the per-model layer: `ModelRunner.swift` (the
  protocol), `Registry.swift` (the id-to-runner map), `Adapters/` (one file per
  model), `Execute.swift` (input, download, run), and the `run` command plus the
  ergonomic verbs. A runner declares its `options` once; `schema`, `run --option`, and
  the verbs all read that list.
- `Sources/DesertAntCLI/Terminal/` is the brand look: color over ANSI, tables. Painting
  is off when output is piped, `NO_COLOR` is set, `--no-color` is passed, or `--json` is
  on.
- `Sources/DesertAntCLI/Clipping/` is the clips pipeline: `ClipPipeline` orders
  transcribe, select, cut; `Transcriber` and `MediaCutter` are the platform seams
  (Voz and AVFoundation behind them on Apple, a transcript file anywhere). The
  pipeline shares the CLI's `Output`, `Progress`, and `Destination` on purpose; if the
  pipeline ever moves to a package, those three are the only ties to cut.
- `Sources/DesertAntCLI/IO/Destination.swift` is the one file-writing policy: never
  the input, never over an existing file unless `--force`, else step aside to
  `name-2.ext`. Every command that writes goes through it.
- `Sources/DesertAntCLI/Schema/` emits the agent tool catalog.
- `integrations/` holds the Claude, Codex, and Pi adapters.

## How a model reaches the CLI

Discovery is driven entirely by `manifest.json`, vendored from the core ref in
`CORE_REF` and compiled into the binary, so a new model in core is discoverable with
no code change once `Tools/sync-manifest` runs. Running a model takes one adapter
file under `Run/Adapters/`, listed in `Registry.swift`; the adapter declares its
options, and `schema`, the verbs, and `info` read them from it.

## Docs

`llms.txt` is the index; `docs/` holds the pages, each written for a person and for
an agent. `Tools/embed` compiles them into the binary for `desertant docs`, so a docs
edit needs a re-embed (`Tools/check` re-embeds and fails if the generated file was
stale). `docs/json.md` is a contract: when a command's `Encodable` result changes,
change that page in the same commit, and never change an existing key's meaning or
type within a major version. `docs/pipelines.md` marks what ships and what is
planned; move a section when it lands.

## Two build rules

Title runs on MLX behind core's `MLX` package trait. A trait request in a manifest
is unconditional, so `Package.swift` turns it on from `DESERTANT_MLX=1` at manifest
time; `Tools/check`, `Tools/install`, and `Tools/package` set it on macOS, Linux
never does, and the Title code is compiled behind `#if TITLE`. A plain `swift build`
without the variable resolves a different graph and rebuilds the world, so on a Mac
use the tools.

Core's `Tools/dal.sh` moves to core's root when sourced. Only ever source it inside a
subshell that hands back a value (see how `Tools/check` finds LiteRT); sourcing
`dal.sh` in the main shell once made CI build and test core instead of this repo.

## Adding a model

1. Add its product to `Package.swift` (gate Apple-only models behind `#if canImport`).
2. Write `Run/Adapters/<Name>Runner.swift`: id, input kind, options, and a `run` that
   emits a typed `Encodable` under `--json` and a plain line otherwise. Numbers stay
   numbers in JSON; never stringify a confidence.
3. List it in `Registry.swift`, and add a verb in `Verbs.swift` if the model earns one.

Discovery, `info`, `pull`, and `schema` pick the model up with no further work. The
tests assert every runner has a live-Swift manifest entry and unique option names.

## Voice

Follow `brand/VOICE.md` and the root `dal/CLAUDE.md` for every user-facing string:
first line describes, no em or en dashes, US spelling, units against the number,
sentence case, no label-colon openers. Emoji are model output, never prose. Prose
uses contractions; an error or status message uses the full form ("could not reach
GitHub", "did not decode"), which reads better when something has gone wrong.

## Commands

`mise run check` is what CI runs: embed is current, build, tests, manifest in sync
with the sibling core checkout, no dashes. Also `build`, `test`, `sync-manifest`,
`install`, and `release` (see `RELEASING.md`).

Never judge speed from a debug build. `swift build` and `swift run` are `-Onone`, and
core's DSP, tokenizers, and SHA-256 verification run 50-100x slower there: a 42s
recording took 7m through `clips` in debug and 55s in release, and the "is it
downloaded" check alone took 90s. Time things with `swift build -c release` or the
installed binary from `Tools/install`. The first load of a model on a machine also
specializes the model for the Neural Engine; the second run is the real number.
