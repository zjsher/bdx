#!/bin/bash
# release.sh — bump plugin version, stage changes, regenerate changelog.
#
# Usage:
#   ./scripts/release.sh current
#   ./scripts/release.sh patch|minor|major
#   ./scripts/release.sh set <version>
#
# Finds every Claude and Codex plugin.json (supports multi-plugin repos),
# verifies their versions are in lockstep, bumps each version consistently,
# stages all changes with `git add .`, then runs
# `lazy-changelog --prepend CHANGELOG.md`. Commit + tag + push is left to the
# caller so you can review the changelog first.

set -euo pipefail

MODE="${1:-}"
TARGET="${2:-}"

case "$MODE" in
  current|patch|minor|major|set) ;;
  *) echo "usage: $0 current|patch|minor|major|set <version>" >&2; exit 2 ;;
esac

if [ "$MODE" = "set" ] && [ -z "$TARGET" ]; then
  echo "error: 'set' requires a version argument" >&2; exit 2
fi

# Locate Claude and Codex plugin manifests (one per plugin in a multi-plugin
# repo). Both roots are required so a release cannot silently update only one
# plugin format.
# Using while-read instead of mapfile for bash 3.2 compat (macOS default).
MANIFESTS=()
for root in .claude-plugin .codex-plugin; do
  if [ ! -d "$root" ]; then
    echo "error: required plugin manifest root not found: $root/" >&2
    exit 1
  fi
  found=0
  while IFS= read -r line; do
    MANIFESTS+=("$line")
    found=1
  done < <(find "$root" -maxdepth 2 -name 'plugin.json' -type f | sort)
  if [ "$found" -eq 0 ]; then
    echo "error: no plugin.json found under $root/" >&2
    exit 1
  fi
done
if [ "${#MANIFESTS[@]}" -eq 0 ]; then
  echo "error: no Claude or Codex plugin manifests found" >&2; exit 1
fi

# Current version (authoritative: first manifest). Refuse to release if any
# manifest has drifted so the two plugin catalogs never publish mismatched
# versions.
CURRENT=$(jq -r .version "${MANIFESTS[0]}")
if [ -z "$CURRENT" ] || [ "$CURRENT" = "null" ]; then
  echo "error: ${MANIFESTS[0]} has no .version field" >&2; exit 1
fi
for m in "${MANIFESTS[@]:1}"; do
  version=$(jq -r .version "$m")
  if [ -z "$version" ] || [ "$version" = "null" ]; then
    echo "error: $m has no .version field" >&2
    exit 1
  fi
  if [ "$version" != "$CURRENT" ]; then
    echo "error: plugin manifest versions are out of sync:" >&2
    echo "  ${MANIFESTS[0]}: $CURRENT" >&2
    echo "  $m: $version" >&2
    exit 1
  fi
done

if [ "$MODE" = "current" ]; then
  echo "$CURRENT"
  exit 0
fi

bump() {
  local cur="$1" part="$2" major minor patch
  IFS='.' read -r major minor patch <<< "$cur"
  case "$part" in
    patch) echo "$major.$minor.$((patch + 1))" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    major) echo "$((major + 1)).0.0" ;;
  esac
}

if [ "$MODE" = "set" ]; then
  NEW="$TARGET"
else
  NEW=$(bump "$CURRENT" "$MODE")
fi

echo "Bumping $CURRENT → $NEW across ${#MANIFESTS[@]} manifest(s):"
for m in "${MANIFESTS[@]}"; do
  echo "  $m"
  tmp=$(mktemp)
  jq --arg v "$NEW" '.version = $v' "$m" > "$tmp"
  mv "$tmp" "$m"
done

echo
echo "git add ."
git add .

echo "lazy-changelog generate --prepend CHANGELOG.md"
lazy-changelog generate --prepend CHANGELOG.md

echo
echo "Done. Next steps:"
echo "  git commit -m 'release v$NEW' && \\"
echo "  git tag v$NEW && \\"
echo "  git push && git push --tags"
