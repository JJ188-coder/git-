// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Lecture",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LectureCore", targets: ["LectureCore"]),
        .library(name: "LectureServer", targets: ["LectureServer"]),
        .library(name: "LectureSpeech", targets: ["LectureSpeech"]),
        .executable(name: "Lecture", targets: ["LectureApp"]),
    ],
    targets: [
        .target(
            name: "LectureCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Security"),
                .linkedFramework("Translation"),
            ]
        ),
        .target(
            name: "LectureServer",
            dependencies: ["LectureCore"],
            linkerSettings: [.linkedFramework("Network")]
        ),
        .target(
            name: "LectureSpeech",
            dependencies: ["LectureCore"],
            linkerSettings: [
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CryptoKit"),
            ]
        ),
        .executableTarget(
            name: "LectureApp",
            dependencies: ["LectureCore", "LectureServer", "LectureSpeech"],
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("Translation"),
            ]
        ),
        .executableTarget(
            name: "LectureTests",
            dependencies: ["LectureCore", "LectureServer", "LectureSpeech"],
            path: "Tests",
            exclude: ["ServerSmoke", "KeyImportSmoke", "DeepSeekSmoke", "SpeechFileSmoke"],
            sources: ["main.swift", "LectureSpeechTests/LectureSpeechTestSuite.swift"]
        ),
        .executableTarget(
            name: "LectureServerSmoke",
            dependencies: ["LectureCore", "LectureServer"],
            path: "Tests/ServerSmoke"
        ),
        .executableTarget(
            name: "LectureKeyImportSmoke",
            dependencies: ["LectureCore"],
            path: "Tests/KeyImportSmoke"
        ),
        .executableTarget(
            name: "LectureDeepSeekSmoke",
            dependencies: ["LectureCore"],
            path: "Tests/DeepSeekSmoke"
        ),
        .executableTarget(
            name: "LectureSpeechFileSmoke",
            dependencies: ["LectureCore", "LectureSpeech"],
            path: "Tests/SpeechFileSmoke"
        ),
    ],
    swiftLanguageModes: [.v5]
)
