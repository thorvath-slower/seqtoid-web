#!/usr/bin/env bash
# CZID-392: single source of versioning truth for known-good builds.
#
# Computes a SemVer 2.0.0 version string + an OCI-safe image tag from git, identically for local
# and GitHub Actions builds (only the build-context field differs). See BUILD-VERSIONING-DESIGN.md.
#
#   v<MAJOR>.<MINOR>.<PATCH>[-dev.<n>]+g<sha>.d<ts>.b<ctx>[.r<runid>][.dirty]
#     └── release identity (annotated git tag `vX.Y.Z`, or v0.0.0 until first tag)
#                            └── build metadata (ignored for SemVer precedence; unique per build)
#
# OCI tags may not contain '+', so the image tag replaces '+' -> '_'. The true SemVer is always
# recoverable from the org.opencontainers.image.version label stamped on the image.
#
# Output: writes `key=value` lines (version, tag, sha, release, semver) to $GITHUB_OUTPUT when set,
# and always echoes a human summary to stderr. Safe to source or run.
set -euo pipefail

# --- release identity: newest vX.Y.Z annotated tag, else v0.0.0; dev.<commits-since> between tags ---
REL="$(git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null || echo v0.0.0)"
SHA="$(git rev-parse --short=10 HEAD)"
N="$(git rev-list "${REL}..HEAD" --count 2>/dev/null || echo 0)"
BASE="$REL"
if [ "$N" -gt 0 ]; then
  BASE="${REL}-dev.${N}"
fi

# --- build metadata (unique per build) ---
TS="$(date -u +%Y%m%dT%H%MZ)"                         # no ':' -> SemVer-legal
if [ -n "${GITHUB_ACTIONS:-}" ]; then CTX="gha"; else CTX="local"; fi
META="g${SHA}.d${TS}.b${CTX}"
if [ -n "${GITHUB_RUN_ID:-}" ]; then META="${META}.r${GITHUB_RUN_ID}"; fi
if ! git diff --quiet 2>/dev/null; then META="${META}.dirty"; fi

SEMVER="${BASE}+${META}"
TAG="${SEMVER//+/_}"                                  # OCI-safe image tag

{
  echo "release=$REL"
  echo "semver=$SEMVER"
  echo "version=$SEMVER"
  echo "tag=$TAG"
  echo "sha=$SHA"
} > "${GITHUB_OUTPUT:-/dev/null}"

echo "compute-version: semver=$SEMVER  image-tag=$TAG  release=$REL  sha=$SHA" >&2
# Also print to stdout for local callers that capture it.
echo "$SEMVER $TAG"
