#!/usr/bin/env bash

set -euo pipefail

if [[ $# -gt 2 ]]; then
  echo "Usage: $0 [target] [benchmark-filter-regex]" >&2
  echo "Example (whole target): $0 Basic" >&2
  echo "Example (filtered): $0 Basic '^Noop2$'" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

TARGET="${1:-Basic}"
FILTER="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BENCHMARKS_DIR="${REPO_ROOT}/Benchmarks"

SWIFT62_BIN="${SWIFT62_BIN:-/usr/local/share/toolchains/6.2.4/usr/bin/swift}"
SWIFT63_BIN="${SWIFT63_BIN:-/usr/local/share/toolchains/6.3.1/usr/bin/swift}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/benchmark-compare}"

mkdir -p "${OUTPUT_DIR}"

RUN_ID="$(date +%Y%m%d-%H%M%S)"
OUT62="${OUTPUT_DIR}/swift62-${TARGET}-${RUN_ID}.json"
OUT63="${OUTPUT_DIR}/swift63-${TARGET}-${RUN_ID}.json"
SCRATCH62="${OUTPUT_DIR}/scratch-62-${TARGET}-${RUN_ID}"
SCRATCH63="${OUTPUT_DIR}/scratch-63-${TARGET}-${RUN_ID}"

for swift_bin in "${SWIFT62_BIN}" "${SWIFT63_BIN}"; do
  if [[ ! -x "${swift_bin}" ]]; then
    echo "Swift binary not found or not executable: ${swift_bin}" >&2
    exit 1
  fi
done

run_benchmark() {
  local swift_bin="$1"
  local scratch_path="$2"
  local output_path="$3"
  local -a args

  (
    cd "${BENCHMARKS_DIR}"
    args=(
      package
      --scratch-path "${scratch_path}"
      benchmark
      --target "${TARGET}"
      --format jsonSmallerIsBetter
      --path stdout
      --no-progress
    )
    if [[ -n "${FILTER}" ]]; then
      args+=(--filter "${FILTER}")
    fi
    BENCHMARK_DISABLE_JEMALLOC=1 "${swift_bin}" "${args[@]}" > "${output_path}"
  )
}

if [[ -n "${FILTER}" ]]; then
  echo "Running ${TARGET} / ${FILTER} with Swift 6.2: ${SWIFT62_BIN}"
else
  echo "Running ${TARGET} with Swift 6.2: ${SWIFT62_BIN}"
fi
run_benchmark "${SWIFT62_BIN}" "${SCRATCH62}" "${OUT62}"

if [[ -n "${FILTER}" ]]; then
  echo "Running ${TARGET} / ${FILTER} with Swift 6.3: ${SWIFT63_BIN}"
else
  echo "Running ${TARGET} with Swift 6.3: ${SWIFT63_BIN}"
fi
run_benchmark "${SWIFT63_BIN}" "${SCRATCH63}" "${OUT63}"

echo
echo "Saved results:"
echo "  6.2 -> ${OUT62}"
echo "  6.3 -> ${OUT63}"
echo

python3 - "${OUT62}" "${OUT63}" <<'PY'
import json
import sys
from pathlib import Path

path62 = Path(sys.argv[1])
path63 = Path(sys.argv[2])

def load_metrics(path: Path):
    text = path.read_text()
    start = text.find("[")
    if start == -1:
        raise ValueError(f"No JSON payload found in {path}")
    return {item["name"]: item for item in json.loads(text[start:])}

data62 = load_metrics(path62)
data63 = load_metrics(path63)

names = sorted(set(data62) | set(data63))

rows = []
for name in names:
    a = data62.get(name)
    b = data63.get(name)
    av = a["value"] if a else None
    bv = b["value"] if b else None
    unit = a["unit"] if a else (b["unit"] if b else "")
    delta = None if av is None or bv is None else bv - av
    rows.append((name, av, bv, delta, unit))

interesting = [
    row for row in rows
    if any(token in row[0] for token in ("Time (wall clock)", "Object allocs", "Releases", "Retains"))
]

name_width = max(len("Metric"), max((len(row[0]) for row in interesting), default=0))

print(f'{"Metric":<{name_width}}  {"6.2":>12}  {"6.3":>12}  {"Delta":>12}  Unit')
for name, av, bv, delta, unit in interesting:
    avs = "-" if av is None else str(av)
    bvs = "-" if bv is None else str(bv)
    ds = "-" if delta is None else str(delta)
    print(f"{name:<{name_width}}  {avs:>12}  {bvs:>12}  {ds:>12}  {unit}")
PY
