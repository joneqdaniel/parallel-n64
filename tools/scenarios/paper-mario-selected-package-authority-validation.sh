#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/paper-mario-phrb-authority-validation.sh" \
  --summary-title "Selected-Package Authority Validation" \
  --expected-source-mode "phrb-only" \
  --min-native-sampled-count 1 \
  "$@"
