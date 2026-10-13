#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"

TEAM_ID="${1:-${DEVELOPMENT_TEAM:-}}"
EXPORT_METHOD="${2:-debugging}"
if [[ -z "$TEAM_ID" ]]; then
  printf '%s\n' '请先在 Xcode 的 Signing & Capabilities 中选择自己的 Team。' '直接安装到自己的 iPhone：连接手机，在 Xcode 选择设备并点击运行。' '已具备付费开发者签名时，可在终端运行：' './Build-iOS.command 十位TeamID debugging' '或：./Build-iOS.command 十位TeamID release-testing'
  open 'Huati.xcodeproj'
  exit 0
fi
if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  printf '%s\n' 'Team ID 需为 10 位大写字母或数字；不要输入账号密码。' >&2
  exit 1
fi
if [[ "$EXPORT_METHOD" != 'debugging' && "$EXPORT_METHOD" != 'release-testing' ]]; then
  printf '%s\n' '导出方式仅支持 debugging 或 release-testing，使用 Xcode 16 或更新版本。' >&2
  exit 1
fi
if ! xcrun --find xcodebuild >/dev/null 2>&1; then
  printf '%s\n' '请安装 Xcode，并在 Xcode → Settings → Locations 中选择 Command Line Tools。' >&2
  exit 1
fi
mkdir -p 'Exports'
OPTIONS="$PWD/Exports/ExportOptions.plist"
cat > "$OPTIONS" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>$EXPORT_METHOD</string>
<key>teamID</key><string>$TEAM_ID</string>
<key>signingStyle</key><string>automatic</string>
<key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
XML
xcodebuild -project 'Huati.xcodeproj' -scheme 'Huati' -configuration Release -destination 'generic/platform=iOS' -archivePath "$PWD/Exports/Huati.xcarchive" -allowProvisioningUpdates "DEVELOPMENT_TEAM=$TEAM_ID" archive
xcodebuild -exportArchive -archivePath "$PWD/Exports/Huati.xcarchive" -exportPath "$PWD/Exports/IPA" -exportOptionsPlist "$OPTIONS" -allowProvisioningUpdates
printf '%s\n' '签名导出完成，IPA 在 Exports/IPA 文件夹。仅已获签名配置授权的设备能安装。'
open 'Exports/IPA'
