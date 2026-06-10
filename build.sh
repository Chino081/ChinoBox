#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLUTTER="$SCRIPT_DIR/../flutter/bin/flutter"
DIST="$SCRIPT_DIR/dist"
WIN_RELEASE="$SCRIPT_DIR/build/windows/x64/runner/Release"
# Proxy (set MOVIESBOX_BUILD_PROXY to enable, e.g. http://user:pass@host:port)
PROXY="${MOVIESBOX_BUILD_PROXY:-}"

# Parse args
BUILD_ANDROID=true
BUILD_WINDOWS=true
for arg in "$@"; do
  case "$arg" in
    --android) BUILD_WINDOWS=false ;;
    --windows) BUILD_ANDROID=false ;;
    --no-proxy) PROXY="" ;;
    --help|-h)
      echo "Usage: ./build.sh [OPTIONS]"
      echo "  --android   Build Android only"
      echo "  --windows   Build Windows only"
      echo "  --no-proxy  Disable proxy"
      exit 0
      ;;
  esac
done

# Use JDK 21 for Android (Gradle doesn't support JDK 25)
export JAVA_HOME="C:/Program Files/Zulu/zulu-21"
export PATH="$JAVA_HOME/bin:$PATH"

# Apply proxy for network access
if [ -n "$PROXY" ]; then
  export http_proxy="$PROXY"
  export https_proxy="$PROXY"
  export all_proxy="$PROXY"

  PROXY_ADDR="${PROXY#*://}"
  PROXY_AUTH=""
  if [[ "$PROXY_ADDR" == *"@"* ]]; then
    PROXY_AUTH="${PROXY_ADDR%@*}"
    PROXY_ADDR="${PROXY_ADDR#*@}"
  fi
  PROXY_HOST="${PROXY_ADDR%%:*}"
  PROXY_PORT="${PROXY_ADDR##*:}"

  if [ -n "$PROXY_HOST" ] && [ -n "$PROXY_PORT" ] && [ "$PROXY_HOST" != "$PROXY_PORT" ]; then
    GRADLE_PROXY_OPTS="-Dhttp.proxyHost=$PROXY_HOST -Dhttp.proxyPort=$PROXY_PORT -Dhttps.proxyHost=$PROXY_HOST -Dhttps.proxyPort=$PROXY_PORT"
    if [ -n "$PROXY_AUTH" ]; then
      PROXY_USER="${PROXY_AUTH%%:*}"
      PROXY_PASS="${PROXY_AUTH#*:}"
      GRADLE_PROXY_OPTS="$GRADLE_PROXY_OPTS -Dhttp.proxyUser=$PROXY_USER -Dhttp.proxyPassword=$PROXY_PASS -Dhttps.proxyUser=$PROXY_USER -Dhttps.proxyPassword=$PROXY_PASS"
    fi
    export GRADLE_OPTS="${GRADLE_OPTS:-} $GRADLE_PROXY_OPTS"
    echo "[proxy] enabled for $PROXY_HOST:$PROXY_PORT"
  else
    echo "[proxy] enabled"
  fi
fi

mkdir -p "$DIST"

# Extract version from pubspec.yaml
VERSION=$(grep '^version:' "$SCRIPT_DIR/pubspec.yaml" | awk '{print $2}')
echo "[build] version $VERSION"

# ── Android ──────────────────────────────────────────────────────────
if $BUILD_ANDROID; then
  echo ""
  echo "══════════════════════════════════════"
  echo "  Building Android APK (release)"
  echo "══════════════════════════════════════"
  "$FLUTTER" build apk --release

  APK_DIR="$SCRIPT_DIR/build/app/outputs/flutter-apk"
  OK=true
  for pair in \
    "app-arm64-v8a-release.apk:ChinoBox-android-arm64-v8a-release.apk" \
    "app-x86_64-release.apk:ChinoBox-android-x86_64-release.apk" \
    "app-release.apk:ChinoBox-android-universal-release.apk"; do
    SRC="${pair%%:*}"
    DST="${pair##*:}"
    if [ -f "$APK_DIR/$SRC" ]; then
      cp "$APK_DIR/$SRC" "$DIST/$DST"
      SIZE=$(du -h "$DIST/$DST" | cut -f1)
      echo "[done] $DST ($SIZE)"
    else
      echo "[error] $SRC not found"
      OK=false
    fi
  done
  $OK || exit 1
fi

# ── Windows ──────────────────────────────────────────────────────────
if $BUILD_WINDOWS; then
  echo ""
  echo "══════════════════════════════════════"
  echo "  Building Windows (release)"
  echo "══════════════════════════════════════"
  "$FLUTTER" build windows --release

  if [ -f "$WIN_RELEASE/ChinoBox.exe" ]; then
    ZIP="$DIST/ChinoBox-windows-x64-release.zip"
    rm -f "$ZIP"
    WIN_SRC="$(cygpath -w "$WIN_RELEASE")"
    WIN_ZIP="$(cygpath -w "$ZIP")"
    powershell -Command "Compress-Archive -Path '$WIN_SRC\\*' -DestinationPath '$WIN_ZIP' -Force"
    SIZE=$(du -h "$ZIP" | cut -f1)
    echo "[done] ChinoBox-windows-x64-release.zip ($SIZE)"
  else
    echo "[error] ChinoBox.exe not found"
    exit 1
  fi
fi

echo ""
echo "══════════════════════════════════════"
echo "  All builds complete!"
echo "══════════════════════════════════════"
ls -lh "$DIST"/*.apk "$DIST"/*.zip 2>/dev/null
