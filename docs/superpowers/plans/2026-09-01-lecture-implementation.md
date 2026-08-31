# Lecture Classroom Assistant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver an installed macOS 26 application that opens a local Warm Terminal web UI, records and locally transcribes in-person English lectures, saves history, and uses only DeepSeek for post-class AI workflows.

**Architecture:** A Swift/AppKit menu-bar executable embeds a static web application and exposes a token-protected loopback HTTP/SSE API. Native services own SpeechAnalyzer, DictationTranscriber, AVAudioEngine, TranslationSession, SQLite, Keychain, and DeepSeek networking.

**Tech Stack:** Swift 6.3, AppKit, Speech, AVFoundation, Translation, Security, Network, SQLite3, XCTest, HTML/CSS/JavaScript.

**Spec:** `docs/superpowers/specs/2026-09-01-lecture-design.md`

## Global Constraints

- Minimum platform is macOS 26.0 on Apple Silicon.
- Bind web access to 127.0.0.1 and require an ephemeral token.
- DeepSeek is the only cloud AI provider; never persist or expose its API key outside Keychain.
- Audio never leaves the Mac.
- Preserve raw/live/reviewed/AI-derived transcript versions.
- Implement the approved Warm Terminal UI without generic gradients, glows, or SaaS decoration.

---

### Task 1: Package skeleton, domain models, paths, and test harness

**Files:** `Package.swift`, `Sources/LectureCore/*`, `Tests/LectureCoreTests/*`

- [ ] Write failing tests for safe application paths, course/lecture/segment Codable round trips, lecture state transitions, and secret redaction.
- [ ] Run `swift test` and verify the missing interfaces fail.
- [ ] Implement focused domain and path modules.
- [ ] Run tests and commit.

### Task 2: SQLite history and recovery repository

**Files:** `Sources/LectureCore/Storage/*`, `Tests/LectureCoreTests/StorageTests.swift`

- [ ] Write failing CRUD, cascade, version-retention, search, and incomplete-lecture recovery tests using a temporary database.
- [ ] Implement schema migrations and parameter-bound SQLite operations.
- [ ] Verify tests and commit.

### Task 3: Token-protected loopback server and embedded Warm Terminal UI

**Files:** `Sources/LectureServer/*`, `Sources/LectureApp/Resources/Web/*`, `Tests/LectureServerTests/*`

- [ ] Write failing route tests for session-token authentication, static assets, course/lecture JSON, mutations, and SSE events.
- [ ] Implement a small Network.framework HTTP server bound to 127.0.0.1.
- [ ] Implement the approved responsive UI and functional navigation/forms/history/player shells.
- [ ] Verify route, build, and browser rendering; commit.

### Task 4: Keychain and DeepSeek-only client

**Files:** `Sources/LectureCore/Security/*`, `Sources/LectureCore/DeepSeek/*`, tests

- [ ] Write failing Keychain save/load/delete tests under an isolated test service and URLProtocol request-shape/redaction tests.
- [ ] Implement Keychain storage, connectivity test, chunk-safe translation correction, structured summary parsing, and grounded Q&A request construction.
- [ ] Verify that source and built resources contain no provider names other than DeepSeek in user-facing product copy; commit.

### Task 5: Local speech, confidence, vocabulary, recording, and review pass

**Files:** `Sources/LectureSpeech/*`, tests

- [ ] Write failing pure mapping tests for AttributedString confidence/time ranges, low-confidence classification, vocabulary normalization, and final-versus-volatile handling.
- [ ] Implement SpeechAnalyzer live transcription with progressive final results and AnalysisContext vocabulary.
- [ ] Implement DictationTranscriber time-indexed long/far-field review from saved audio.
- [ ] Implement AVAudioEngine recording, level metering, frequent checkpoints, and recovery metadata.
- [ ] Verify compilation and available speech assets; commit.

### Task 6: Apple live translation and lecture orchestration

**Files:** `Sources/LectureCore/Translation/*`, `Sources/LectureApp/LectureCoordinator.swift`, tests

- [ ] Write failing coordinator tests with fake speech/translation/recording/DeepSeek services.
- [ ] Implement state machine: start, checkpoint, mark, stop, review, correct, summarize, retry, recover.
- [ ] Implement low-latency English-to-Simplified-Chinese translation without blocking English capture.
- [ ] Verify tests and commit.

### Task 7: Native app shell, packaging, installation, and end-to-end verification

**Files:** `Sources/LectureApp/*`, `scripts/build-app.sh`, `scripts/install.sh`, `README.md`

- [ ] Write launcher smoke tests for port/token URL formation and lifecycle behavior.
- [ ] Implement AppKit menu-bar shell, browser opening, permission prompts, and clean shutdown.
- [ ] Package `Lecture.app`, include usage descriptions, sign ad hoc, install into `/Applications`, and store the supplied key in Keychain without printing it.
- [ ] Launch and verify API/UI, course creation, simulated transcript persistence, DeepSeek connection, recovery, and browser reopen.
- [ ] Run full tests, inspect the rendered UI at desktop/mobile widths, commit, and push the branch.

## Plan self-review

Every approved feature maps to one of Tasks 1-7. The design deliberately treats actual classroom microphone accuracy as an empirical acceptance item; code tests validate mapping and lifecycle while a representative audio fixture validates WER. All secret-bearing paths require redaction and Keychain-only storage.

