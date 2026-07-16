#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/release.sh <version> [commit-message]

Example:
  scripts/release.sh 1.2.2 "feat: show recent request token usage"
  scripts/release.sh v1.2.2

What it does:
  1. Verifies the working tree has no staged changes.
  2. Runs swift test.
  3. Stages all non-ignored changes.
  4. Creates one commit.
  5. Creates an annotated release tag.
  6. Pushes main and the tag.
  7. Watches the GitHub Release workflow if gh is available.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 64
fi

version="$1"
tag="$version"
if [[ "$tag" != v* ]]; then
  tag="v$tag"
fi

message="${2:-release: $tag}"
branch="$(git branch --show-current)"

if [[ "$branch" != "main" ]]; then
  echo "Refusing to release from '$branch'. Switch to main first." >&2
  exit 1
fi

if ! git diff --cached --quiet; then
  echo "Refusing to continue: staged changes already exist. Commit or unstage them first." >&2
  exit 1
fi

if git rev-parse "$tag" >/dev/null 2>&1; then
  echo "Tag already exists: $tag" >&2
  exit 1
fi

echo "Running tests..."
swift test

echo "Staging changes..."
git add -A

if git diff --cached --quiet; then
  echo "No changes to commit." >&2
  exit 1
fi

echo "Creating commit: $message"
git commit -m "$message"

echo "Creating tag: $tag"
git tag -a "$tag" -m "$tag"

echo "Pushing main and $tag..."
git push origin main "$tag"

if command -v gh >/dev/null 2>&1; then
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  if [[ -n "$repo" ]]; then
    echo "Waiting for Release workflow..."
    sleep 3
    run_id="$(gh run list --repo "$repo" --workflow Release --limit 1 --json databaseId,headBranch,event \
      --jq 'map(select(.event == "push"))[0].databaseId // empty')"
    if [[ -n "$run_id" ]]; then
      gh run watch "$run_id" --repo "$repo" --exit-status
      release_url="$(gh release view "$tag" --repo "$repo" --json url --jq .url)"
      echo "Release published: $release_url"
    else
      echo "No Release workflow run found yet. Check GitHub Actions manually." >&2
    fi
  fi
else
  echo "gh CLI not found; check GitHub Actions manually."
fi
