#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-gates-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"
BUNDLE_DIR="$TMP_DIR/bundle"
TRACE_DIR="$BUNDLE_DIR/traces"
PASS_OUTPUT_DIR="$TMP_DIR/out-pass"
CANONICAL_PASS_OUTPUT_DIR="$TMP_DIR/out-canonical-pass"
FAIL_OUTPUT_DIR="$TMP_DIR/out-fail"
MINIMUM_FAIL_OUTPUT_DIR="$TMP_DIR/out-minimum-fail"
CLASS_FAIL_OUTPUT_DIR="$TMP_DIR/out-class-fail"

mkdir -p "$TRACE_DIR"

python3 - "$CACHE_PATH" "$TRACE_DIR/hires-evidence.json" <<'PY'
import gzip
import json
import struct
import sys
from pathlib import Path

cache_path = Path(sys.argv[1])
evidence_path = Path(sys.argv[2])

TXCACHE_FORMAT_VERSION = 0x08000000
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401
GL_RGBA8 = 0x8058

texture_crc = 0x11111111
palette_crc = 0xAAAABBBB
checksum64 = (palette_crc << 32) | texture_crc
formatsize = 258
payload = bytes([
    0x10, 0x20, 0x30, 0xFF,
    0x40, 0x50, 0x60, 0xFF,
    0x70, 0x80, 0x90, 0xFF,
    0xA0, 0xB0, 0xC0, 0xFF,
])

with gzip.open(cache_path, "wb") as fp:
    fp.write(struct.pack("<i", TXCACHE_FORMAT_VERSION))
    fp.write(struct.pack("<i", 0))
    fp.write(struct.pack("<Q", checksum64))
    fp.write(struct.pack("<IIIHHB", 2, 2, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, 1))
    fp.write(struct.pack("<H", formatsize))
    fp.write(struct.pack("<I", len(payload)))
    fp.write(payload)

evidence = {
    "ci_palette_probe": {
        "families": [
            {
                "low32": f"{texture_crc:08x}",
                "fs": str(formatsize),
                "mode": "loadtile",
                "wh": "2x2",
                "pcrc": f"{palette_crc:08x}",
                "active_pool": "compatibility"
            }
        ],
        "usages": [],
        "emulated_tmem": []
    },
    "sampled_object_probe": {
        "top_groups": [
            {
                "fields": {
                    "draw_class": "texrect",
                    "cycle": "1cycle",
                    "fmt": "2",
                    "siz": "1",
                    "off": "0",
                    "stride": "2",
                    "wh": "2x2",
                    "fs": str(formatsize),
                    "sampled_low32": f"{texture_crc:08x}",
                    "sampled_entry_pcrc": f"{palette_crc:08x}",
                    "sampled_sparse_pcrc": f"{palette_crc:08x}",
                    "sampled_entry_count": "1",
                    "sampled_used_count": "1"
                },
                "upload_low32s": [
                    {"value": f"{texture_crc:08x}"}
                ],
                "upload_pcrcs": [
                    {"value": f"{palette_crc:08x}"}
                ]
            }
        ]
    }
}
evidence_path.write_text(json.dumps(evidence, indent=2) + "\n")
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$BUNDLE_DIR" \
  --output-dir "$PASS_OUTPUT_DIR" \
  --stdout-format json \
  --expect-context-class context-enriched \
  --require-promotable \
  --max-total-ms 10000 \
  --max-binary-package-bytes 65536 \
  > "$TMP_DIR/pass.json"

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --all-families \
  --output-dir "$CANONICAL_PASS_OUTPUT_DIR" \
  --stdout-format json \
  --expect-context-class zero-context \
  --minimum-outcome canonical-package-only \
  > "$TMP_DIR/canonical-pass.json"

WRONG_RUNTIME_CLASS="$(
  python3 - "$TMP_DIR/canonical-pass.json" <<'PY'
import json
import sys
from pathlib import Path

actual = json.loads(Path(sys.argv[1]).read_text()).get("package_manifest_runtime_ready_record_class")
choices = ["none", "compat-only", "mixed-native-and-compat", "native-sampled-only"]
for choice in choices:
    if choice != actual:
        print(choice)
        break
PY
)"

set +e
python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --output-dir "$FAIL_OUTPUT_DIR" \
  --stdout-format json \
  --require-promotable \
  --max-total-ms 0.001 \
  > "$TMP_DIR/fail.json" \
  2> "$TMP_DIR/fail.stderr"
status=$?
set -e

if [[ $status -eq 0 ]]; then
  echo "expected gated failure run to exit non-zero" >&2
  exit 1
fi

set +e
python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --low32 33333333 \
  --formatsize 258 \
  --output-dir "$MINIMUM_FAIL_OUTPUT_DIR" \
  --stdout-format json \
  --minimum-outcome partial-runtime-package \
  > "$TMP_DIR/minimum-fail.json" \
  2> "$TMP_DIR/minimum-fail.stderr"
minimum_status=$?
set -e

if [[ $minimum_status -eq 0 ]]; then
  echo "expected minimum-outcome failure run to exit non-zero" >&2
  exit 1
fi

set +e
python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --all-families \
  --output-dir "$CLASS_FAIL_OUTPUT_DIR" \
  --stdout-format json \
  --expect-runtime-ready-class "$WRONG_RUNTIME_CLASS" \
  > "$TMP_DIR/class-fail.json" \
  2> "$TMP_DIR/class-fail.stderr"
class_status=$?
set -e

if [[ $class_status -eq 0 ]]; then
  echo "expected runtime-ready-class failure run to exit non-zero" >&2
  exit 1
fi

python3 - "$TMP_DIR" <<'PY'
import json
import sys
from pathlib import Path

tmp_dir = Path(sys.argv[1])
pass_report = json.loads((tmp_dir / "pass.json").read_text())
canonical_pass_report = json.loads((tmp_dir / "canonical-pass.json").read_text())
fail_report = json.loads((tmp_dir / "fail.json").read_text())
fail_stderr = (tmp_dir / "fail.stderr").read_text()
fail_summary = Path(fail_report["summary_path"]).read_text()
minimum_fail_report = json.loads((tmp_dir / "minimum-fail.json").read_text())
minimum_fail_stderr = (tmp_dir / "minimum-fail.stderr").read_text()
minimum_fail_summary = Path(minimum_fail_report["summary_path"]).read_text()
class_fail_report = json.loads((tmp_dir / "class-fail.json").read_text())
class_fail_stderr = (tmp_dir / "class-fail.stderr").read_text()
class_fail_summary = Path(class_fail_report["summary_path"]).read_text()

if not pass_report.get("gate_success", False) or pass_report.get("gate_failures"):
    raise SystemExit(f"expected passing gate report, got {pass_report!r}")
if pass_report.get("minimum_outcome") is not None or not pass_report.get("require_promotable"):
    raise SystemExit(f"expected require-promotable pass metadata, got {pass_report!r}")
if pass_report.get("context_bundle_class") != "context-enriched":
    raise SystemExit(f"expected context-enriched pass report, got {pass_report!r}")

if canonical_pass_report["conversion_outcome"] != "promotable-runtime-package":
    raise SystemExit(f"expected promotable-runtime-package pass, got {canonical_pass_report!r}")
if canonical_pass_report.get("minimum_outcome") != "canonical-package-only" or canonical_pass_report.get("require_promotable"):
    raise SystemExit(f"unexpected canonical minimum-outcome metadata: {canonical_pass_report!r}")
if not canonical_pass_report.get("gate_success", False) or canonical_pass_report.get("gate_failures"):
    raise SystemExit(f"expected canonical minimum-outcome pass, got {canonical_pass_report!r}")
if canonical_pass_report.get("context_bundle_class") != "zero-context":
    raise SystemExit(f"expected zero-context canonical report, got {canonical_pass_report!r}")

codes = [item["code"] for item in (fail_report.get("gate_failures") or [])]
if codes != ["max-total-ms"]:
    raise SystemExit(f"unexpected gate failure codes: {codes!r}")
if fail_report.get("gate_success", True):
    raise SystemExit(f"expected failing gate report, got {fail_report!r}")
if "Conversion gates failed:" not in fail_stderr:
    raise SystemExit(f"expected stderr gate summary, got {fail_stderr!r}")
if "`max-total-ms`" not in fail_summary:
    raise SystemExit(f"expected markdown gate summary, got {fail_summary!r}")
if fail_report.get("minimum_outcome") is not None or not fail_report.get("require_promotable"):
    raise SystemExit(f"expected require-promotable fail metadata, got {fail_report!r}")

minimum_codes = [item["code"] for item in (minimum_fail_report.get("gate_failures") or [])]
if minimum_codes != ["minimum-outcome"]:
    raise SystemExit(f"unexpected minimum-outcome failure codes: {minimum_codes!r}")
if minimum_fail_report.get("gate_success", True):
    raise SystemExit(f"expected minimum-outcome failure report, got {minimum_fail_report!r}")
if "expected outcome >= partial-runtime-package, got canonical-package-only" not in minimum_fail_stderr:
    raise SystemExit(f"unexpected minimum-outcome stderr: {minimum_fail_stderr!r}")
if "`minimum-outcome`" not in minimum_fail_summary:
    raise SystemExit(f"expected minimum-outcome summary entry, got {minimum_fail_summary!r}")

class_codes = [item["code"] for item in (class_fail_report.get("gate_failures") or [])]
if class_codes != ["expect-runtime-ready-class"]:
    raise SystemExit(f"unexpected runtime-ready-class failure codes: {class_codes!r}")
if class_fail_report.get("gate_success", True):
    raise SystemExit(f"expected runtime-ready-class failure report, got {class_fail_report!r}")
if "expected runtime-ready class" not in class_fail_stderr:
    raise SystemExit(f"unexpected runtime-ready-class stderr: {class_fail_stderr!r}")
if "`expect-runtime-ready-class`" not in class_fail_summary:
    raise SystemExit(f"expected runtime-ready-class summary entry, got {class_fail_summary!r}")
PY

echo "emu_hts2phrb_gates: PASS"
