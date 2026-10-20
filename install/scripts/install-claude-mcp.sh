#!/usr/bin/env bash
set -euo pipefail

# Add the MCP servers of ~/.claude/mcp-servers.json to Claude Code's user
# config (~/.claude.json, which also holds state, so it is not in the repo).
# Keys stay out of the repo: they are ${VARS} that Claude Code reads from the
# environment.

servers="$HOME/.claude/mcp-servers.json"
config="$HOME/.claude.json"

[ -f "$servers" ] || exit 0
[ -f "$config" ] || printf '{}\n' > "$config"

tmp="$(mktemp)"
jq --slurpfile s "$servers" '.mcpServers = ((.mcpServers // {}) + $s[0])' \
  "$config" > "$tmp"
mv "$tmp" "$config"
chmod 600 "$config"
printf 'Claude Code MCP servers: %s\n' "$(jq -r '.mcpServers | keys | join(", ")' "$config")"
