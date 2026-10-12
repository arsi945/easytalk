#!/bin/bash
# Source snapshot with checksums. Build caches and credentials are not project sources.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/archive_project.py "${1:-snapshot}"
