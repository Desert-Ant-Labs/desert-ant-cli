# Releasing

`VERSION` at the root holds the version. `CORE_REF` names the desert-ant-core ref the
CLI follows: `main` to track core day to day, or a tag like `v3.1.0` or a commit to
pin a release. CI, the release workflow, `Tools/sync-manifest`, and `Tools/check` all
read it through `Tools/core-ref`, so the vendored manifest, the checked-out core, and
the guard that compares them never disagree. Set it to a tag before cutting a
release. `Tools/embed` compiles the manifest, version, and docs into the binary.

```
Tools/release 0.2.0
git push --follow-tags
Tools/publish-formula      # once the release workflow is green
```

`Tools/release` syncs the manifest from the sibling `desert-ant-core` checkout, writes
the version to `VERSION` and the formula, re-embeds, runs `Tools/check` (build, tests,
manifest in sync, voice), commits, and tags `v0.2.0`. The push triggers
`.github/workflows/release.yml`, which builds `desertant` for macOS arm64 and Linux
x86_64 and arm64, attaches the tarballs and a `checksums.txt` to the GitHub release,
and renders `Formula/desertant.rb` with the real checksums.

## How people install and update

Every path below pulls the same release assets, so there's one thing to publish.

- The script: `curl -fsSL https://raw.githubusercontent.com/Desert-Ant-Labs/desert-ant-cli/main/install.sh | sh`.
  Updates with `desertant update`, which runs the script again.
- Homebrew: `brew install desert-ant-labs/tap/desertant`, updates with `brew upgrade`.
  The formula lives in `Desert-Ant-Labs/homebrew-tap`, beside the Clipper cask. After
  the release workflow is green, `Tools/publish-formula` downloads the rendered
  formula from the release and pushes it to the tap from your machine, the way the
  cask is published.
- mise: `mise use -g "ubi:Desert-Ant-Labs/desert-ant-cli[exe=desertant]"`, updates
  with `mise upgrade`. mise needs nothing beyond the release assets.

`desertant update --check` and `desertant doctor` report a newer release whichever
way the CLI was installed, and `desertant update` knows which command applies.

## When core ships a new model

Discovery reads the bundled manifest, so a new model becomes visible in the CLI with
the next release: `Tools/release` syncs the manifest as its first step. Running the
model needs an adapter (see `AGENTS.md`), which can land in the same release or a
later one; until then `info` says the model has no runner on this platform.

## What a release tarball holds

`desertant`, plus what the binary needs beside it: `mlx.metallib` on macOS (MLX looks
for it next to the binary; Title runs on it) and `libLiteRt.so` on Linux. The script
and the formula keep them together in a private directory (`~/.local/share/desertant`,
Homebrew's `libexec`) and symlink `desertant` and `da` into `bin`.

## Linux

The Linux binaries need `libLiteRt.so` beside them. The release workflow vendors it
the same way desert-ant-core does and ships it inside the tarball, with an rpath of
`$ORIGIN`, so the installed binary finds it without any system setup. The models
themselves are tested on Linux in desert-ant-core's CI; this repo's `ci.yml` covers
what only this repo can break there: it runs `Tools/check`, packages the binary, and
runs `doctor`, `models`, `schema`, and `docs` from the tarball on every push.

A Windows build is not set up. The starting point is a `windows-latest` job modeled
on core's, which vendors LiteRT from the win_amd64 wheel.
