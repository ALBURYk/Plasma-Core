#!/usr/bin/env bash
set -euo pipefail

export FLUTTER_HOME="${FLUTTER_HOME:-$HOME/flutter}"
export PATH="$FLUTTER_HOME/bin:$PATH"

if ! command -v flutter >/dev/null 2>&1; then
  git clone https://github.com/flutter/flutter.git --branch stable --depth 1 "$FLUTTER_HOME"
fi

flutter config --enable-web
flutter pub get
flutter build web --release --base-href /
