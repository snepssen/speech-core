#!/usr/bin/env bash
# Release speech-core and carry it into every app that depends on it.
#
#   scripts/release.sh 0.6.0 [--dry-run]
#
# Tests here, then the tag. Then, for each app checked out beside this
# repository that ecosystem.json says uses speech-core: update the dependency,
# run that app's own checks, and commit and push the new Package.resolved if
# they pass: one release, every app updated, none of them broken by it. A bump
# whose checks fail is reverted and reported, and that app stays on the
# version it had. The work is site-core's workshop script, which voice-core
# releases with too.
set -euo pipefail
cd "$(dirname "$0")/.."
WORKSHOP="../site-core/workshop"
[ -x "$WORKSHOP" ] || { echo "error: needs site-core checked out beside speech-core" >&2; exit 1; }
exec "$WORKSHOP" release speech-core "${1:?version, like 0.6.0}" ${2:+"$2"}
