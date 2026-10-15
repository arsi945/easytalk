#!/bin/bash
# Host-side checks only. UIKit type checking still requires Xcode and the iOS SDK.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ios-check
FLAGS=(-module-cache-path "$PWD/build/ios-check/module-cache")
CLT=/Library/Developer/CommandLineTools/usr/include/swift
if [ -f "$CLT/bridging.modulemap" ] && [ -f "$CLT/module.modulemap" ]; then
  : > build/ios-check/empty.modulemap
  python3 - <<'PY'
import json, pathlib
p = pathlib.Path("build/ios-check").resolve()
overlay = {"version": 0, "roots": [{"type": "file",
    "name": "/Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap",
    "external-contents": str(p / "empty.modulemap")}]}
(p / "overlay.yaml").write_text(json.dumps(overlay))
PY
  FLAGS+=(-vfsoverlay "$PWD/build/ios-check/overlay.yaml")
fi
plutil -lint ios/EasyTalk.xcodeproj/project.pbxproj ios/EasyTalk/Info.plist ios/Keyboard/Info.plist
swiftc -frontend -parse "${FLAGS[@]}" ios/EasyTalk/AppDelegate.swift ios/Keyboard/KeyboardViewController.swift
swiftc "${FLAGS[@]}" Sources/EasyTalkCore/Contracts.swift Sources/EasyTalkCore/Learning.swift Sources/EasyTalkCore/StudyContent.swift Sources/EasyTalkCore/IdiomCatalog.swift Sources/EasyTalkCore/CursorNavigation.swift Sources/EasyTalkCore/TypingRules.swift Sources/EasyTalkCore/WordSuggestions.swift Sources/EasyTalkCore/DocumentReader.swift \
  ios/Shared/ConnectionSettings.swift ios/Shared/SharedStorage.swift ios/Shared/LearningStore.swift ios/Shared/InputHistory.swift ios/Shared/ContextExport.swift ios/Shared/ContextExportPrompt.swift ios/Shared/KeyboardPreferences.swift ios/Shared/StudyPractice.swift ios/Shared/SecondSkillCards.swift ios/Shared/AnalysisPrompt.swift \
  ios/Shared/AnalysisService.swift ios/Shared/StudyActionsPrompt.swift ios/Shared/StudyActionService.swift ios/Tests/LearningTests.swift \
  -o build/ios-learning-tests
build/ios-learning-tests "$@"
