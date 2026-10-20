# Releasing

`VERSION` at the root holds the version. `CORE_REF` names the desert-ant-core ref the
CLI follows: `main` to track core day to day, or a tag like `v3.1.0` or a commit to
pin a release. CI, the release workflow, `Tools/sync-manifest`, and `Tools/check` all
read it through `Tools/core-ref`, so the vendored manifest, the checked-out core, and
the guard that compares them never disagree. Set it to a tag before cutting a
release. `Tools/embed` compiles the manifest, version, and docs into the binary.

```
$EDITOR release-notes/0.2.0.md
Tools/release 0.2.0
git push --follow-tags
Tools/publish-formula      # once the release workflow is green
```

`release-notes/<version>.md` is the GitHub release body, and `Tools/release` refuses to tag without it. The first line names the desert-ant-core version the release follows, since the CLI keeps its own version numbers. Then list what changed for someone running the CLI, one line each, and end with how to update. Follow `brand/VOICE.md`.

`Tools/release` syncs the manifest from the sibling `desert-ant-core` checkout, writes
the version to `VERSION` and the formula, re-embeds, runs `Tools/check` (build, tests,
manifest in sync, voice), commits, and tags `v0.2.0`. The push triggers
`.github/workflows/release.yml`, which builds `desertant` for macOS arm64 and Linux
x86_64 and arm64, installs each tarball into clean systems and runs `Tools/smoke`
against it (`verify.yml`), and only then attaches the tarballs and a `checksums.txt`
to the GitHub release and renders `Formula/desertant.rb` with the real checksums.

## How people install and update

Every path below pulls the same release assets, so there's one thing to publish.

- The script: `curl -fsSL https://raw.githubusercontent.com/Desert-Ant-Labs/desert-ant-cli/main/install.sh | sh`.
  Updates with `desertant update`, which runs the script again.
- Homebrew: `brew install desert-ant-labs/tap/desertant`, updates with `brew upgrade`.
  The formula lives in `Desert-Ant-Labs/homebrew-tap`, beside the Clipper cask. After
  the release workflow is green, `Tools/publish-formula` downloads the rendered
  formula from the release and pushes it to the tap from your machine, the way the
  cask is published.
- mise: `mise use -g "ubi:Desert-Ant-Labs/desert-ant-cli[extract_all=true]"`, updates
  with `mise upgrade`. `extract_all` keeps the whole tarball together; without it mise
  installs the executable alone, and Tongue, Title, and every Linux model stop working.

`desertant update --check` and `desertant doctor` report a newer release whichever
way the CLI was installed, and `desertant update` knows which command applies.

## When core ships a new model

Discovery reads the bundled manifest, so a new model becomes visible in the CLI with
the next release: `Tools/release` syncs the manifest as its first step. Running the
model needs an adapter (see `AGENTS.md`), which can land in the same release or a
later one; until then `info` says the model has no runner on this platform.

## What a release tarball holds

`desertant` and what the binary needs beside it: the SwiftPM resource bundles
(Tongue's weights among them), `fonts/` with the caption font and its license,
`THIRD_PARTY_NOTICES.md`, `mlx.metallib` on macOS (Title runs on MLX, which looks for
it next to the binary), and `libLiteRt.so` on Linux.
The script and the formula keep them together in a private directory
(`~/.local/share/desertant`, Homebrew's `libexec`) and symlink `desertant` and `da`
into `bin`.

## Linux

The Linux binary links the Swift runtime and Foundation statically, so a machine needs
no Swift toolchain. At run time it needs glibc 2.35 or later, libcurl, and
`libLiteRt.so`, which it finds beside itself through an rpath of `$ORIGIN`. The glibc
floor comes from the build image, `swift:6.2-jammy` (`Tools/linux.Dockerfile`).
`install.sh` refuses an older glibc or a musl system with a message instead of
installing a binary that cannot start.

The binary links against upstream curl, built in the image for linking only. Debian's
libcurl tags its symbols with versions that Fedora, openSUSE, and Arch don't have, and
their loader would print a warning on every run.

ffmpeg is optional. Core reads and writes WAV in Swift, and ffmpeg reads other audio,
video, and images.

An Amazon Linux 2 build image would lower the floor, and doesn't work. On arm64 the
linker refuses LiteRT, which needs glibc 2.34. On x86_64 the binary stops with a
libcurl error on Ubuntu 22.04 and Rocky 9, whose curl is older than the one that
image's Foundation expects.

`Tools/linux` runs any command in the build image, from a Mac or a Linux host, with
this repo and core mounted. CI and the release workflow build through it too.

```
Tools/linux Tools/check                    # the commit gate on Linux
Tools/linux Tools/package linux-arm64      # dist/desertant-linux-arm64.tar.gz
Tools/linux-matrix                         # install that tarball into each distribution and smoke-test it
Tools/linux-matrix --ffmpeg ubuntu:24.04   # the same, with ffmpeg installed
Tools/smoke path/to/desertant              # one binary, end to end
```

`--arch x86_64` builds and tests the other architecture, under emulation on Apple
silicon. `Tools/smoke` runs every model the platform supports, the file handling, and
the errors a person sees. It fails on any log line on stderr except TFLite's
"Created TensorFlow Lite XNNPACK delegate", which LiteRT has no setting to turn off.
CI and the release workflow run the same scripts through `verify.yml`.

A Windows build is not set up. The starting point is a `windows-latest` job modeled
on core's, which vendors LiteRT from the win_amd64 wheel.
