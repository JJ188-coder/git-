# SDD ledger — plan: docs/superpowers/plans/2026-09-01-lecture-implementation.md

## Completed

- Task 1 complete — package, domain models, paths, executable test harness (`8ef0fc0`).
- Task 2 complete — SQLite history, cascades, recovery query (`8ef0fc0`).
- Task 3 complete — loopback-only token HTTP server and Warm Terminal browser UI.
- Task 4 complete — Keychain-only DeepSeek client, JSON mode, chunking, summaries, grounded Q&A.
- Task 5 complete — native live SpeechAnalyzer, confidence/time mapping, vocabulary, AAC recording, checkpoints, offline far-field DictationTranscriber (`3a14a22`).
- Task 6 complete — Apple low-latency translation and lecture lifecycle coordinator.
- Task 7 complete — AppKit menu bar shell, packaging, ad-hoc signing, install and launch at `/Applications/Lecture.app`.

## Verification evidence

- `swift run LectureTests`: 9 groups pass.
- `swift build -c release --product Lecture`: pass without warnings.
- `codesign --verify --deep --strict /Applications/Lecture.app`: pass.
- App process is running and listens only on `127.0.0.1` with an ephemeral port.
- Static page/API smoke: tokenless 401; token/cookie page and health 200; all three embedded assets served.
- DeepSeek key exists in macOS Keychain under `com.jiyuanyi.Lecture.DeepSeek`; source and resources contain no supplied secret.
- Real classroom WER measurement remains empirical and requires representative user audio plus a human reference transcript; no unsupported accuracy claim is made.
