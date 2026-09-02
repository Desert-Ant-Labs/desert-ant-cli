# Agent integrations

Adapters that hand the `desertant` CLI to a coding agent. All three teach the agent
the same thing: call `desertant ... --json`, and read `desertant schema --json` to
know what is callable. Install the CLI first (see the root README), then add the
adapter for your agent.

## Claude Code

Install `claude/` as a plugin, or drop `claude/skills/desertant/` into a project's
`.claude/skills/`. Claude loads the skill and reaches for the CLI when a task needs a
local model: transcription, clips, audio cleanup, redaction, and the rest.

## Codex

Add the contents of `codex/AGENTS.md` to a project's `AGENTS.md`. Codex reads it and
runs the CLI through its shell.

## Pi

`pi install git:github.com/Desert-Ant-Labs/desert-ant-cli/integrations/pi`, or from the
published package. Pi loads the skill and calls the CLI with its bash tool.

## Any other agent

The CLI needs no adapter: `--json` output, stdin input, stable exit codes (0 success,
1 runtime error, 64 usage error), and `desertant schema --json` as an introspectable
catalog. An `mcp` subcommand serving the same catalog over MCP is planned.
