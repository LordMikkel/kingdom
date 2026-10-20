#!/usr/bin/env sh
set -eu

file="$HOME/.local/share/zed/extensions/work/cspell/node_modules/@vlabo/cspell-lsp/dist/cspell-lsp.js"

if [ ! -f "$file" ]; then
  printf 'cspell-lsp file not found: %s\n' "$file" >&2
  exit 1
fi

tmp="$(mktemp)"
sed \
  -e 's/const severity = DiagnosticSeverity\.Information;/const severity = DiagnosticSeverity.Warning;/' \
  -e 's/const severityFlaggedWords = DiagnosticSeverity\.Information;/const severityFlaggedWords = DiagnosticSeverity.Warning;/' \
  "$file" > "$tmp"

if cmp -s "$file" "$tmp"; then
  rm "$tmp"
  printf 'cspell-lsp is already patched for Warning diagnostics.\n'
  exit 0
fi

mv "$tmp" "$file"
printf 'Patched cspell-lsp diagnostics to Warning. Restart Zed or the cspell language server.\n'
