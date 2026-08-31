# Lecture Local Classroom Assistant Design

## Product goal

Lecture is a macOS 26+ classroom assistant for in-person English lectures. Double-clicking `Lecture.app` starts a loopback-only local web application and opens the default browser. The app records the Mac microphone, produces local live English transcription and Simplified Chinese translation, retains course-organized history, and uses only the DeepSeek API for post-class correction, study summaries, and grounded questions.

## Approved visual direction

The browser interface uses the approved **Warm Terminal** direction: warm ivory surfaces, charcoal text, restrained clay-orange accents, serif display type, high-quality system sans-serif body type, Songti-style Chinese reading text, and monospaced technical/status labels. It must remain comfortable during long lectures and avoid generic SaaS cards, gradients, glows, and decorative motion.

## Runtime architecture

- A small native Swift/AppKit menu-bar application owns microphone capture, recording, speech recognition, translation, data storage, DeepSeek access, and the local HTTP/SSE server.
- The server binds only to `127.0.0.1`, chooses an available port, creates an ephemeral session token, and opens `http://127.0.0.1:<port>/?token=<token>`.
- The browser is a presentation and control surface. Closing it does not stop recording.
- The app stores its data below `~/Library/Application Support/Lecture/` and secrets in macOS Keychain.

## Recognition accuracy design

Scripta's five-second, no-context Whisper Base path is not retained. Lecture uses Apple's macOS 26 on-device Speech framework:

1. Live recognition uses `SpeechAnalyzer` plus `SpeechTranscriber` configured for English, progressive results, alternatives, audio time ranges, and transcription confidence.
2. Volatile text appears as a live draft; only final results become durable transcript segments.
3. Each segment stores start/end audio time and mean confidence. Low-confidence segments are visibly marked for review.
4. Each course owns a vocabulary list. Vocabulary is injected through `AnalysisContext.contextualStrings` for live recognition.
5. The raw recording remains the source of truth.
6. After class, a second fully local pass uses `DictationTranscriber` in time-indexed long-dictation mode with far-field and custom vocabulary hints. This reviewed English transcript is stored separately from the live transcript.
7. DeepSeek may correct punctuation and translation but cannot silently replace the English source. The UI retains live, reviewed, and AI-derived versions.
8. The setup/diagnostic view checks microphone level, installed speech assets, and translation language availability before class.

No local speech model can guarantee 100 percent accuracy. Acceptance is therefore based on measured word error rate using representative lecture audio and on preserving audio/time/confidence evidence for correction.

## Audio and translation

- Audio capture uses `AVAudioEngine`; recording is written locally in an efficient compressed Apple audio format with recoverable working data while recording.
- Live translation uses Apple's Translation framework with English source, Simplified Chinese target, and low-latency strategy.
- Failure to translate does not stop recording or English recognition.

## Data model

SQLite stores courses, lectures, transcript segments, markers, summary versions, and question threads. Audio is stored as files referenced from SQLite.

A course includes name, optional code, professor, semester, and vocabulary. A lecture includes lifecycle state, timestamps, duration, recording path, live transcript, reviewed transcript, translation versions, and processing errors. Transcript segments preserve stable identifiers, source kind, time range, text, confidence, finality, and low-confidence state.

## DeepSeek-only workflow

- The API key is stored under service `com.jiyuanyi.Lecture.DeepSeek` in login Keychain.
- The browser never receives the key. Logs, exports, source code, and SQLite never contain it.
- DeepSeek is used only for connectivity testing, post-class Chinese correction, structured study summaries, and grounded Q&A.
- Requests use the current official OpenAI-compatible DeepSeek endpoint and a single product-level model configuration, not a provider picker.
- Long transcripts are split at sentence/time boundaries. Each translated chunk retains source segment identifiers, then a reduce pass produces the complete summary.
- Q&A retrieves relevant local transcript chunks first and requires citations to lecture identifiers and audio timestamps. Missing evidence must be stated.
- Audio is never uploaded.

## Browser pages

1. **Live class**: course selector, start/stop, bilingual streaming transcript, confidence flags, audio level, recording duration, and quick markers.
2. **Course history**: course cards, creation/editing, lecture status, search, and safe deletion.
3. **Lecture detail**: audio player, timestamp navigation, live/reviewed English, live/corrected Chinese, markers, processing retry, and exports.
4. **Study summary**: overview, concepts, definitions, professor examples/emphasis, possible exam topics with disclaimer, unresolved questions, and bilingual glossary; versions are retained.
5. **DeepSeek Q&A**: current-lecture or whole-course scope, grounded answers, source citations, audio jumps, and chat history.
6. **Settings/diagnostics**: microphone test, speech/translation asset status, DeepSeek connection, Keychain replacement/removal, storage use, and export.

## Failure and recovery

- State and transcript segments are flushed frequently.
- On launch, incomplete lectures are surfaced as recoverable.
- DeepSeek failures leave local data intact and are retryable.
- Missing translation assets leave English and recording operational.
- Low disk space blocks or warns before recording.
- Destructive deletion requires explicit confirmation.

## Scope exclusions for v1

No system-audio capture, Zoom/Teams integration, accounts, cloud sync, remote/LAN access, video/screen capture, slide ingestion, speaker diarization, non-English source languages, alternative AI providers, Ollama, or a complex note editor.

## Verification

- Unit tests cover storage, request authentication, token redaction, chunking, retrieval, summary parsing, and state recovery.
- Native tests cover Keychain behavior with a test service, speech result mapping, and server routing.
- The built app must launch from Finder, open the browser, survive browser closure during recording, save/recover data, and show no provider other than DeepSeek.
- A representative audio fixture and transcript are used to calculate word error rate for both live-final and post-class review passes. The UI reports the measured result rather than claiming perfect accuracy.

