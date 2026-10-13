#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
printf '%s\n' '开始 Xcode 编译检查。这不会登录华体或创建跑步记录。'
xcodebuild -project 'Huati.xcodeproj' -scheme 'Huati' -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath "$PWD/Exports/DerivedData" CODE_SIGNING_ALLOWED=NO build
DEVICE_ID="${1:-}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(xcrun simctl list devices available --json | /usr/bin/python3 -c 'import json,sys,re; items=json.load(sys.stdin)["devices"]; print(next((d["udid"] for runtime,devices in items.items() if re.search(r"iOS-(\d+)",runtime) and int(re.search(r"iOS-(\d+)",runtime).group(1))>=17 for d in devices if "iPhone" in d["name"] and d.get("isAvailable")), ""))')"
fi
if [[ -z "$DEVICE_ID" ]]; then
  printf '%s\n' '编译完成。请在 Xcode 下载 iOS 17 或更新的 iPhone 模拟器，随后再次运行本脚本以执行 XCTest。'
  exit 0
fi
xcodebuild -project 'Huati.xcodeproj' -scheme 'Huati' -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath "$PWD/Exports/DerivedData" CODE_SIGNING_ALLOWED=NO test
printf '%s\n' '原生编译和 XCTest 检查完成。'
