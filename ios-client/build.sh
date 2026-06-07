#!/bin/bash
# ==========================================
#  🏗️ Build GPS Tracker iOS App
#  Chạy trên macOS có Xcode
#  Usage:
#    ./build.sh                  # Build dev + install sim
#    ./build.sh ipa              # Export IPA (ad-hoc)
#    ./build.sh release          # Release build
#    ./build.sh clean            # Xoá Build/
# ==========================================

set -e

SCHEME="GPSTracker"
CONFIG="${2:-Debug}"
PROJECT=$(ls *.xcworkspace 2>/dev/null || ls *.xcodeproj 2>/dev/null || echo "")

if [[ -z "$PROJECT" ]]; then
  echo "❌ Không tìm thấy Xcode project!"
  echo "   Tạo bằng: xcodegen generate  (cần brew install xcodegen)"
  exit 1
fi

echo "═══════════════════════════════════════"
echo "  🏗️  Build GPS Tracker iOS App"
echo "  📦 Project: $PROJECT"
echo "  ⚙️  Config: $CONFIG"
echo "═══════════════════════════════════════"

case "$1" in
  clean)
    echo "🧹 Cleaning..."
    rm -rf Build/
    xcodebuild clean -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG"
    echo "✅ Clean done!"
    exit 0
    ;;

  ipa)
    echo "📱 Exporting IPA (ad-hoc)..."
    
    # Build archive
    echo "🛠️ Building archive..."
    xcodebuild archive \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration "$CONFIG" \
      -destination "generic/platform=iOS" \
      -archivePath Build/GPSTracker.xcarchive \
      | xcpretty || xcodebuild archive \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration "$CONFIG" \
      -destination "generic/platform=iOS" \
      -archivePath Build/GPSTracker.xcarchive

    # Export IPA
    echo "📦 Exporting IPA..."
    mkdir -p Build
    cat > Build/ExportOptions.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>ad-hoc</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
EOF

    xcodebuild -exportArchive \
      -archivePath Build/GPSTracker.xcarchive \
      -exportPath Build/ \
      -exportOptionsPlist Build/ExportOptions.plist \
      | xcpretty || xcodebuild -exportArchive \
      -archivePath Build/GPSTracker.xcarchive \
      -exportPath Build/ \
      -exportOptionsPlist Build/ExportOptions.plist

    IPA_FILE=$(ls Build/*.ipa 2>/dev/null | head -1)
    if [[ -n "$IPA_FILE" ]]; then
      echo "✅ IPA exported: $IPA_FILE"
      echo "   Size: $(du -h "$IPA_FILE" | cut -f1)"
      open -R "$IPA_FILE" 2>/dev/null || true
    else
      echo "❌ Không tìm thấy file IPA!"
      exit 1
    fi
    ;;

  install|dev|"")
    echo "📱 Building and launching on simulator..."
    
    # Get booted simulator or boot one
    SIM=$(xcrun simctl list devices booted 2>/dev/null | grep -v "unavailable" | grep -v "^$" | grep -v "==" | head -1 | sed 's/.*(\(.*\))/\1/')
    if [[ -z "$SIM" ]]; then
      echo "📱 Booting iPhone 15 Pro simulator..."
      SIM=$(xcrun simctl create "GPS Sim" "iPhone 15 Pro" 2>/dev/null || echo "")
      xcrun simctl boot "$SIM" 2>/dev/null || true
      sleep 2
    fi
    
    if [[ -n "$SIM" ]]; then
      DEST="-destination \"platform=iOS Simulator,id=$SIM\""
    else
      DEST="-destination \"platform=iOS Simulator,name=iPhone 15 Pro\""
    fi
    
    eval xcodebuild run \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration "$CONFIG" \
      $DEST \
      | xcpretty || eval xcodebuild run \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration "$CONFIG" \
      $DEST
    
    echo "✅ App installed on simulator!"
    ;;

  release)
    echo "🏭 Building Release..."
    bash "$0" ipa Release
    ;;

  *)
    echo "Usage:"
    echo "  $0              → Build + run simulator"
    echo "  $0 install      → Build + run simulator"
    echo "  $0 ipa          → Export IPA (ad-hoc)"
    echo "  $0 release      → Build Release + IPA"
    echo "  $0 clean        → Xoá Build/"
    exit 1
    ;;
esac
