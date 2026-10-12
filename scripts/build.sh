#!/bin/bash
# Сборка без SwiftPM/Xcode (Command Line Tools). Использование: scripts/build.sh [core|app|all]
# Обход битой установки CLT 16.2: в usr/include/swift два modulemap с модулем SwiftBridging.
# Подменяем лишний файл пустым через VFS-overlay, систему не трогаем. С полным Xcode не нужно.
set -euo pipefail
cd "$(dirname "$0")/.."
B=build; mkdir -p $B/fix
CLT=/Library/Developer/CommandLineTools/usr/include/swift
FLAGS=(-module-cache-path "$PWD/build/module-cache" -target "$(uname -m)-apple-macos12.0" -O)
if [ -f "$CLT/bridging.modulemap" ] && [ -f "$CLT/module.modulemap" ] && grep -q SwiftBridging "$CLT/bridging.modulemap"; then
  : > $B/fix/empty.modulemap
  cat > $B/fix/overlay.yaml <<YAML
{"version":0,"case-sensitive":"false","roots":[{"type":"directory","name":"$CLT","contents":[{"type":"file","name":"bridging.modulemap","external-contents":"$PWD/$B/fix/empty.modulemap"}]}]}
YAML
  FLAGS+=(-vfsoverlay "$PWD/$B/fix/overlay.yaml")
fi
core() {
  swiftc "${FLAGS[@]}" -parse-as-library -module-name EasyTalkCore -emit-module -emit-module-path $B/EasyTalkCore.swiftmodule \
    -static -emit-library -o $B/libEasyTalkCore.a Sources/EasyTalkCore/*.swift
}
learning() {
  swiftc "${FLAGS[@]}" -parse-as-library -module-name EasyTalkLearning -I $B -L $B -lEasyTalkCore \
    -emit-module -emit-module-path $B/EasyTalkLearning.swiftmodule -static -emit-library -o $B/libEasyTalkLearning.a \
    ios/Shared/ConnectionSettings.swift ios/Shared/LearningStore.swift ios/Shared/InputHistory.swift ios/Shared/ContextExport.swift ios/Shared/ContextExportPrompt.swift ios/Shared/KeyboardPreferences.swift \
    ios/Shared/StudyPractice.swift ios/Shared/SecondSkillCards.swift ios/Shared/AnalysisPrompt.swift ios/Shared/AnalysisService.swift ios/Shared/StudyActionsPrompt.swift ios/Shared/StudyActionService.swift ios/Shared/SpeechPlayer.swift
}
app() {
  learning
  swiftc "${FLAGS[@]}" -I $B -L $B -lEasyTalkLearning -lEasyTalkCore -framework AppKit -framework SwiftUI -framework Carbon -framework Security Sources/EasyTalk/*.swift -o $B/easytalk
  APP=$B/easytalk.app; rm -rf $APP; mkdir -p $APP/Contents/MacOS
  cp $B/easytalk $APP/Contents/MacOS/easytalk; cp scripts/Info.plist $APP/Contents/Info.plist
  # Подпись: см. DEFERRED. Ad-hoc сбрасывает разрешение Accessibility при пересборке.
  codesign --force -s "${EASYTALK_SIGN_ID:--}" $APP 2>&1 | sed 's/^/codesign: /'
  echo "built $APP"
}
case "${1:-all}" in
  core) core;; app|all) core; app;;
esac
