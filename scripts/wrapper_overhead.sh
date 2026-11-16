#!/usr/bin/env bash
#
# wrapper_overhead.sh — show the irreducible cost of "being a wrapper" in
# isolation, with no header / no counters / no enable check / nothing.
#
# Builds two artifacts:
#   - bin/wrapper_overhead              the hot-loop bench
#   - bin/wrapper_passthrough.{dylib,so}  a do-nothing tail-call interposer
#
# Runs the bench twice:
#   1. Plain  — user code → libc malloc.
#   2. Wrapped — user code → tail-call wrapper → libc malloc.
#
# Whatever ns delta you see is the price of the extra function-call layer
# alone. Anything you'd build on top (header, counters, enable check)
# stacks on top of that.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$(mktemp -d -t wrapper_overhead.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

CC="${CC:-$(command -v clang || command -v gcc || echo cc)}"
CFLAGS="${CFLAGS:--O2 -Wall -Wextra}"

step() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
fail() { printf '\033[31m## %s\033[0m\n' "$*" >&2; exit 1; }

# --- Build ---
step "Building bench harness + pass-through wrapper"
"$CC" $CFLAGS -o "$BUILD_DIR/wrapper_overhead" "$SCRIPT_DIR/wrapper_overhead.c"

# Collect injection env vars in a bash array so they pass cleanly to `env`.
declare -a INJECT_ENV=()
case "$(uname -s)" in
    Darwin)
        WRAPPER_LIB="$BUILD_DIR/libwrapper_passthrough.dylib"
        "$CC" $CFLAGS -dynamiclib -o "$WRAPPER_LIB" \
            "$SCRIPT_DIR/wrapper_overhead_passthrough.c"
        INJECT_ENV+=("DYLD_INSERT_LIBRARIES=$WRAPPER_LIB" "DYLD_FORCE_FLAT_NAMESPACE=1")
        ;;
    Linux)
        WRAPPER_LIB="$BUILD_DIR/libwrapper_passthrough.so"
        "$CC" $CFLAGS -fPIC -shared -o "$WRAPPER_LIB" \
            "$SCRIPT_DIR/wrapper_overhead_passthrough.c" -ldl
        INJECT_ENV+=("LD_PRELOAD=$WRAPPER_LIB")
        ;;
    *)
        fail "Unsupported platform: $(uname -s)"
        ;;
esac

# --- Run plain ---
step "Run 1 — plain (no wrapper)"
BENCH_LABEL="plain" "$BUILD_DIR/wrapper_overhead"

# --- Run wrapped ---
step "Run 2 — pass-through wrapper preloaded ($(basename "$WRAPPER_LIB"))"
env BENCH_LABEL="wrapped" "${INJECT_ENV[@]}" "$BUILD_DIR/wrapper_overhead"

# --- Run full interposer (optional) ---
# If the caller points us at the real malloc-interposer dylib, do a third run
# with counting enabled. Delta from run #2 is the real bookkeeping cost.
if [[ -n "${INTERPOSER_DYLIB:-}" ]]; then
    if [[ ! -f "$INTERPOSER_DYLIB" ]]; then
        fail "INTERPOSER_DYLIB=$INTERPOSER_DYLIB does not exist"
    fi

    declare -a FULL_INJECT=()
    case "$(uname -s)" in
        Darwin)
            FULL_INJECT+=("DYLD_INSERT_LIBRARIES=$INTERPOSER_DYLIB"
                          "DYLD_FORCE_FLAT_NAMESPACE=1")
            ;;
        Linux)
            FULL_INJECT+=("LD_PRELOAD=$INTERPOSER_DYLIB")
            ;;
    esac

    step "Run 3 — full malloc-interposer preloaded, counting ON"
    env BENCH_LABEL="full-interposer" "${FULL_INJECT[@]}" "$BUILD_DIR/wrapper_overhead"
fi

cat <<'EOF'

Reading the output:
  delta(plain → wrapped)     = cost of the wrapper layer alone (no logic).
  delta(wrapped → full)      = cost of header + magic check + enable check
                               + TLS pointer + counter writes (the
                               "bookkeeping" on top of the wrapper).
  delta(plain → full)        = total interposer overhead vs. raw libc.

If only runs 1 and 2 appear, set INTERPOSER_DYLIB=<path> to enable run 3.
EOF
