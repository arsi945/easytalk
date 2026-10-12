// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "easytalk",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "easytalk", targets: ["EasyTalk"]),
    ],
    targets: [
        // Платформонезависимое ядро: ответ AI, проверка правок, учёба, идиомы.
        .target(name: "EasyTalkCore"),
        .target(name: "EasyTalkLearning", dependencies: ["EasyTalkCore"], path: "ios/Shared",
            exclude: ["DocumentProxyBridge.h", "DocumentProxyBridge.m", "EasyTalkTheme.swift", "EasyTalkBridging.h"],
            sources: ["ConnectionSettings.swift", "LearningStore.swift", "InputHistory.swift", "ContextExport.swift", "ContextExportPrompt.swift", "KeyboardPreferences.swift", "StudyPractice.swift", "SecondSkillCards.swift", "AnalysisService.swift", "AnalysisPrompt.swift", "StudyActionService.swift", "StudyActionsPrompt.swift", "SpeechPlayer.swift"]),
        // macOS-приложение (AppKit + SwiftUI): панель, Службы, вставка.
        .executableTarget(name: "EasyTalk", dependencies: ["EasyTalkCore", "EasyTalkLearning"]),
    ]
)
