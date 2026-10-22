#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${1:-$SOURCE_DIR/../Build}"
mkdir -p "$OUTPUT_DIR"
APP="$OUTPUT_DIR/Text.app"
BUILD_DIR="$(mktemp -d -t text-native-build)"
trap 'rm -rf "$BUILD_DIR"' EXIT
SDK_PATH="$(xcrun --show-sdk-path)"
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]; then SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SOURCE_DIR/Info.plist" "$APP/Contents/Info.plist"
for ARCH in arm64 x86_64; do
 xcrun swiftc -O -whole-module-optimization -swift-version 5 -sdk "$SDK_PATH" -target "$ARCH-apple-macosx13.0" -module-cache-path "$BUILD_DIR/module-cache" "$SOURCE_DIR/Core.swift" "$SOURCE_DIR/State.swift" "$SOURCE_DIR/Results.swift" "$SOURCE_DIR/Preferences.swift" "$SOURCE_DIR/App.swift" "$SOURCE_DIR/Tests.swift" "$SOURCE_DIR/main.swift" -framework AppKit -framework Carbon -framework ImageIO -framework UniformTypeIdentifiers -framework Security -framework ServiceManagement -framework NaturalLanguage -o "$BUILD_DIR/Text-$ARCH"
done
lipo -create "$BUILD_DIR/Text-arm64" "$BUILD_DIR/Text-x86_64" -output "$APP/Contents/MacOS/Text"
if [ -f "$SOURCE_DIR/Resources/AppIcon.icns" ]; then cp "$SOURCE_DIR/Resources/"* "$APP/Contents/Resources/"; fi
if [ -n "${TEXT_SIGNING_IDENTITY:-}" ] && [ -n "${TEXT_SIGNING_KEYCHAIN:-}" ]; then
 python3 - "$APP" "$TEXT_SIGNING_IDENTITY" "$TEXT_SIGNING_KEYCHAIN" <<'PY_SIGN'
import subprocess,sys,shlex,os
from pathlib import Path
app,identity,keychain=sys.argv[1:]
password_file=os.environ.get('TEXT_SIGNING_PASSWORD_FILE')
if password_file:
 unlock=subprocess.run(['security','unlock-keychain','-p',Path(password_file).read_text(),keychain],capture_output=True,text=True)
 if unlock.returncode:
  print(unlock.stderr,file=sys.stderr)
  raise SystemExit('Local signing keychain unlock failed.')
original=shlex.split(subprocess.check_output(['security','list-keychains','-d','user'],text=True))
try:
 subprocess.run(['security','list-keychains','-d','user','-s']+original+([keychain] if keychain not in original else []),check=True)
 subprocess.run(['codesign','--force','--deep','--sign',identity,'--keychain',keychain,'--timestamp=none',app],check=True)
finally:
 subprocess.run(['security','list-keychains','-d','user','-s']+original,check=True)
PY_SIGN
else
 codesign --force --deep --sign - "$APP"
 echo "注意：未配置固定签名，使用临时签名；升级可能重新请求钥匙串授权。"
fi
codesign --verify --strict --deep "$APP"
echo "已生成 $APP"
