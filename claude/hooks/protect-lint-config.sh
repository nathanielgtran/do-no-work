#!/bin/bash
# PreToolUse (Edit|Write|MultiEdit): ask before changing lint, format or type-check config.
# Agents tend to disable rules to pass; the prompt asks for the code fix first.
set -uo pipefail

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -n "$FILE" ] || exit 0
BASE=$(basename "$FILE")

# All text the call would add or remove, for section sniffing.
edit_text() {
  printf '%s' "$INPUT" | jq -r '
    .tool_input
    | [.old_string, .new_string, .content, (.edits[]? | .old_string, .new_string)]
    | map(select(. != null)) | join("\n")'
}

is_plain_config() {
  case "$BASE" in
    .eslintrc*|eslint.config.*|.golangci.*|ruff.toml|.ruff.toml) return 0 ;;
    .prettierrc*|biome.json|.markdownlint*|.pre-commit-config.yaml) return 0 ;;
    aiq-lint-baseline.json|*baseline*.json) return 0 ;;
  esac
  return 1
}

touches_tool_sections() {
  edit_text | grep -qE '\[tool\.(ruff|mypy|pyright)'
}

touches_strict_keys() {
  edit_text | grep -qiE 'strict|noImplicit|noUnchecked|exactOptional|useUnknown|noFallthrough'
}

needs_ask() {
  is_plain_config && return 0
  case "$BASE" in
    pyproject.toml) touches_tool_sections ;;
    tsconfig*.json) touches_strict_keys ;;
    *) return 1 ;;
  esac
}

needs_ask || exit 0
jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:"lint/type config change: fix the code instead, or confirm"}}'
