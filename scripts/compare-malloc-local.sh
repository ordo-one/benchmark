#!/usr/bin/env bash
#
# compare-malloc-local.sh — compare malloc counts between the legacy jemalloc
# path (Swift 6.2 → Package@swift-6.2.swift) and the new custom interposer
# (Swift 6.3 → Package.swift) using THIS repo's local
# `MallocInterposerBenchmarks` target.
#
# These benchmarks have predictable per-iteration allocation counts, so any
# drift between the two code paths is a regression. For "real workload"
# comparison against swift-nio, see compare-malloc.sh instead.
#
# Mechanism:
#   1. Runs `swift package benchmark baseline update <name>` once per
#      toolchain via swiftly. SwiftPM picks the right Package*.swift
#      manifest for each toolchain automatically.
#   2. Calls `baseline compare` for the two recorded baselines.
#
# Pre-requisites:
#   - swiftly with both toolchains installed.
#
# Usage:
#   ./scripts/compare-malloc-local.sh [filter ...]
#
# Each positional arg becomes a `--filter` regex. With no args every
# benchmark in the target runs.
#
# Env overrides:
#   TOOLCHAIN_OLD   default 6.2.2
#   TOOLCHAIN_NEW   default 6.3-snapshot-2026-02-27
#   FRESH=1         use timestamp-suffixed scratch dirs (fresh build, no
#                   cache reuse). Use this when a previous hung/zombie
#                   process is holding a SwiftPM lock on .build-X and you
#                   can't kill it. Trade-off: full rebuild each run.
#   KEEP_FRESH=1    when FRESH=1, don't auto-delete the scratch dirs at
#                   exit (default is to clean up on success).

set -euo pipefail

PB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_DIR="${PB_DIR}/Benchmarks"
TARGET="MallocInterposerBenchmarks"
TOOLCHAIN_OLD="${TOOLCHAIN_OLD:-6.2.4}"
TOOLCHAIN_NEW="${TOOLCHAIN_NEW:-6.3}"
BASELINE_OLD="jemalloc-${TOOLCHAIN_OLD}"
BASELINE_NEW="interposer-${TOOLCHAIN_NEW}"

# Per-toolchain scratch paths so each toolchain has its own .build cache.
# Without this, switching toolchains hits "module compiled with Swift X
# cannot be imported by Y" errors on the cached Benchmark.swiftmodule.
#
# If FRESH=1 is set, append a timestamp suffix so this run can't collide
# with a SwiftPM lock held by a previous (possibly hung) process. Trade-off:
# no cache reuse — every run rebuilds from scratch.
SCRATCH_SUFFIX=""
if [[ "${FRESH:-0}" == "1" ]]; then
  SCRATCH_SUFFIX="-fresh-$(date +%s)"
fi
SCRATCH_OLD="${BENCH_DIR}/.build-${TOOLCHAIN_OLD}${SCRATCH_SUFFIX}"
SCRATCH_NEW="${BENCH_DIR}/.build-${TOOLCHAIN_NEW}${SCRATCH_SUFFIX}"

step() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!! %s\033[0m\n' "$*" >&2; }
fail() {
  printf '\033[31m## %s\033[0m\n' "$*" >&2
  exit 1
}

[[ -d "$BENCH_DIR/Benchmarks/MallocInterposer" ]] ||
  fail "MallocInterposer benchmark dir missing — expected $BENCH_DIR/Benchmarks/MallocInterposer"
command -v swiftly >/dev/null || fail "swiftly required"

# When FRESH=1, clean the throwaway scratch dirs on successful exit so they
# don't accumulate. KEEP_FRESH=1 disables this if the user wants to inspect.
if [[ "${FRESH:-0}" == "1" && "${KEEP_FRESH:-0}" != "1" ]]; then
  cleanup_fresh() {
    local rc=$?
    if ((rc == 0)); then
      rm -rf "$SCRATCH_OLD" "$SCRATCH_NEW" 2>/dev/null || true
    else
      warn "Run failed (exit $rc); leaving fresh scratch dirs for inspection:"
      warn "  $SCRATCH_OLD"
      warn "  $SCRATCH_NEW"
    fi
  }
  trap cleanup_fresh EXIT
fi

cd "$BENCH_DIR"

# Forward any positional args as --filter regexes.
declare -a FILTER_ARGS=()
for f in "$@"; do
  FILTER_ARGS+=(--filter "$f")
done

run_jemalloc() {
  step "Run 1: Swift $TOOLCHAIN_OLD (jemalloc) → baseline '$BASELINE_OLD'  [scratch: $SCRATCH_OLD]"
  swiftly run +"$TOOLCHAIN_OLD" \
    swift package \
    --scratch-path "$SCRATCH_OLD" \
    --allow-writing-to-package-directory benchmark \
    baseline update "$BASELINE_OLD" \
    --target "$TARGET" \
    --quiet --no-progress \
    "${FILTER_ARGS[@]}"
}

run_interposer() {
  step "Run 2: Swift $TOOLCHAIN_NEW (interposer) → baseline '$BASELINE_NEW'  [scratch: $SCRATCH_NEW]"
  swiftly run +"$TOOLCHAIN_NEW" \
    swift package \
    --scratch-path "$SCRATCH_NEW" \
    --allow-writing-to-package-directory benchmark \
    baseline update "$BASELINE_NEW" \
    --target "$TARGET" \
    --quiet --no-progress \
    "${FILTER_ARGS[@]}"
}

run_jemalloc
run_interposer

step "Comparison: $BASELINE_OLD  vs  $BASELINE_NEW"
swiftly run +"$TOOLCHAIN_NEW" \
  swift package \
  --scratch-path "$SCRATCH_NEW" \
  benchmark baseline compare "$BASELINE_OLD" "$BASELINE_NEW" \
  --target "$TARGET"
