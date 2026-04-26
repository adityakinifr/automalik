#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/AutoMalikTeamSignedDerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/AutoMalik.app"
SIGNING_IDENTITY="8D1AF26CC49A3A27EDF925CD2FA82EFC2A318ABA"

xcodebuild \
  -project "$ROOT_DIR/AutoMalik.xcodeproj" \
  -scheme AutoMalik \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=UVD556ZKBG \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  build

killall AutoMalik 2>/dev/null || true
open "$APP_PATH"
