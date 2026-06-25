#!/usr/bin/env bash
#
# bench_malloc.sh — build scripts/bench_malloc.c once and run it twice:
# under the system allocator and under jemalloc. Uses runtime injection
# (DYLD_INSERT_LIBRARIES on macOS, LD_PRELOAD on Linux), so there's no
# link-time difference between the two runs.
#
# Pre-requisites:
#   - macOS: `brew install jemalloc` (or override JEMALLOC_LIB)
#   - Linux: jemalloc installed (e.g. `apt install libjemalloc2`)
#
# Usage:
#   ./scripts/bench_malloc.sh
#
# Env overrides:
#   JEMALLOC_LIB   path to libjemalloc.{dylib,so}; auto-detected if unset.
#   CC             compiler; defaults to cc.
#   CFLAGS         extra cflags; defaults to "-O2 -Wall -Wextra".

set -euo pipefail

# Use clang explicitly — `cc` is aliased to other things in many shells.
CC="${CC:-$(command -v clang || command -v gcc || echo cc)}"
CFLAGS="${CFLAGS:--O2 -Wall -Wextra}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/bench_malloc.c"
BIN="$(mktemp -t bench_malloc.XXXXXX)"
trap 'rm -f "$BIN"' EXIT

step() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
fail() { printf '\033[31m## %s\033[0m\n' "$*" >&2; exit 1; }

# --- locate jemalloc ---
if [[ -z "${JEMALLOC_LIB:-}" ]]; then
    case "$(uname -s)" in
        Darwin)
            for cand in \
                /opt/homebrew/opt/jemalloc/lib/libjemalloc.2.dylib \
                /opt/homebrew/opt/jemalloc/lib/libjemalloc.dylib \
                /usr/local/opt/jemalloc/lib/libjemalloc.2.dylib \
                /usr/local/opt/jemalloc/lib/libjemalloc.dylib; do
                if [[ -f "$cand" ]]; then JEMALLOC_LIB="$cand"; break; fi
            done
            ;;
        Linux)
            for cand in \
                /usr/lib/x86_64-linux-gnu/libjemalloc.so.2 \
                /usr/lib/aarch64-linux-gnu/libjemalloc.so.2 \
                /usr/lib64/libjemalloc.so.2 \
                /usr/lib/libjemalloc.so.2 \
                /usr/lib/x86_64-linux-gnu/libjemalloc.so \
                /usr/lib/libjemalloc.so; do
                if [[ -f "$cand" ]]; then JEMALLOC_LIB="$cand"; break; fi
            done
            ;;
    esac
fi
[[ -n "${JEMALLOC_LIB:-}" && -f "$JEMALLOC_LIB" ]] \
    || fail "jemalloc dylib not found — set JEMALLOC_LIB=/path/to/libjemalloc.{dylib,so}"

# --- build ---
step "Compiling $SRC"
# shellcheck disable=SC2086
"$CC" $CFLAGS -o "$BIN" "$SRC"

# --- run system allocator ---
step "Run 1 — system allocator"
BENCH_LABEL="system" "$BIN"

# --- run with jemalloc injected ---
step "Run 2 — jemalloc (injected: $JEMALLOC_LIB)"
case "$(uname -s)" in
    Darwin)
        BENCH_LABEL="jemalloc" \
            DYLD_INSERT_LIBRARIES="$JEMALLOC_LIB" \
            DYLD_FORCE_FLAT_NAMESPACE=1 \
            "$BIN"
        ;;
    Linux)
        BENCH_LABEL="jemalloc" \
            LD_PRELOAD="$JEMALLOC_LIB" \
            "$BIN"
        ;;
    *)
        fail "Unsupported platform: $(uname -s)"
        ;;
esac
