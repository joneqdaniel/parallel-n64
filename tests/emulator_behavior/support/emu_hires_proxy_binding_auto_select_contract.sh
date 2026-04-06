#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-proxy-auto-select-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

INDEX_PATH="$TMP_DIR/index.json"
OUTPUT_PATH="$TMP_DIR/bindings.json"

cat >"$INDEX_PATH" <<'JSON'
{
  "imported_index": {
    "canonical_records": [
      {
        "sampled_object_id": "sampled-deterministic",
        "runtime_ready": true,
        "sampled_low32": "11111111",
        "sampled_entry_pcrc": "aaaabbbb",
        "sampled_sparse_pcrc": "ccccdddd",
        "linked_policy_keys": ["legacy-low32-11111111-fs258"],
        "upload_low32s": [{"value": "11111111"}],
        "transport_candidates": [
          {
            "replacement_id": "repl-deterministic",
            "source": {
              "legacy_checksum64": "aaaabbbb11111111",
              "legacy_texture_crc": "11111111",
              "legacy_palette_crc": "aaaabbbb",
              "legacy_formatsize": 258,
              "legacy_storage": "htc",
              "legacy_source_path": "/tmp/deterministic.htc"
            },
            "replacement_asset": {
              "width": 16,
              "height": 16
            }
          }
        ]
      },
      {
        "sampled_object_id": "sampled-runtime-ready",
        "runtime_ready": true,
        "sampled_low32": "22222222",
        "sampled_entry_pcrc": "11112222",
        "sampled_sparse_pcrc": "33334444",
        "linked_policy_keys": [],
        "upload_low32s": [{"value": "22222222"}],
        "transport_candidates": [
          {
            "replacement_id": "repl-runtime-ready",
            "source": {
              "legacy_checksum64": "1111222222222222",
              "legacy_texture_crc": "22222222",
              "legacy_palette_crc": "11112222",
              "legacy_formatsize": 258,
              "legacy_storage": "htc",
              "legacy_source_path": "/tmp/runtime-ready.htc"
            },
            "replacement_asset": {
              "width": 8,
              "height": 8
            }
          }
        ]
      },
      {
        "sampled_object_id": "sampled-ambiguous",
        "runtime_ready": true,
        "sampled_low32": "33333333",
        "sampled_entry_pcrc": "55556666",
        "sampled_sparse_pcrc": "77778888",
        "linked_policy_keys": ["legacy-low32-33333333-fs258"],
        "upload_low32s": [{"value": "33333333"}],
        "transport_candidates": [
          {
            "replacement_id": "repl-ambiguous-a",
            "source": {
              "legacy_checksum64": "5555666633333333",
              "legacy_texture_crc": "33333333",
              "legacy_palette_crc": "55556666",
              "legacy_formatsize": 258,
              "legacy_storage": "htc",
              "legacy_source_path": "/tmp/ambiguous-a.htc"
            },
            "replacement_asset": {
              "width": 32,
              "height": 16
            }
          },
          {
            "replacement_id": "repl-ambiguous-b",
            "source": {
              "legacy_checksum64": "7777888833333333",
              "legacy_texture_crc": "33333333",
              "legacy_palette_crc": "77778888",
              "legacy_formatsize": 258,
              "legacy_storage": "htc",
              "legacy_source_path": "/tmp/ambiguous-b.htc"
            },
            "replacement_asset": {
              "width": 64,
              "height": 16
            }
          }
        ]
      }
    ],
    "legacy_transport_aliases": [
      {
        "policy_key": "legacy-low32-11111111-fs258",
        "status": "deterministic"
      },
      {
        "policy_key": "legacy-low32-33333333-fs258",
        "status": "manual-review-required"
      }
    ]
  }
}
JSON

python3 "$ROOT_DIR/tools/hires_pack_emit_proxy_bindings.py" \
  --input "$INDEX_PATH" \
  --auto-select-deterministic-singletons \
  --output "$OUTPUT_PATH"

python3 - "$OUTPUT_PATH" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
bindings = {item["policy_key"]: item for item in payload["bindings"]}
unresolved = {item["policy_key"]: item for item in payload["unresolved_transport_cases"]}

if payload["binding_count"] != 2:
    raise SystemExit(f"expected 2 bindings, got {payload['binding_count']}")
if payload["unresolved_count"] != 1:
    raise SystemExit(f"expected 1 unresolved case, got {payload['unresolved_count']}")

deterministic = bindings.get("sampled-deterministic")
if not deterministic:
    raise SystemExit("missing deterministic singleton binding")
if deterministic.get("selection_reason") != "deterministic-singleton-source-policy":
    raise SystemExit(f"unexpected deterministic selection reason: {deterministic.get('selection_reason')}")

runtime_ready = bindings.get("sampled-runtime-ready")
if not runtime_ready:
    raise SystemExit("missing runtime-ready singleton binding")
if runtime_ready.get("selection_reason") != "runtime-ready-singleton":
    raise SystemExit(f"unexpected runtime-ready selection reason: {runtime_ready.get('selection_reason')}")

ambiguous = unresolved.get("sampled-ambiguous")
if not ambiguous:
    raise SystemExit("missing unresolved ambiguous proxy")
if ambiguous.get("reason") != "proxy-transport-selection-required":
    raise SystemExit(f"unexpected unresolved reason: {ambiguous.get('reason')}")
PY

echo "emu_hires_proxy_binding_auto_select_contract: PASS"
