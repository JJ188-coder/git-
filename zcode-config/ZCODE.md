# AGENTS.md

Global Codex guidance for this machine. Apply project-specific instructions on top of this file when they exist.

## UI/UX Skill Routing

When working on frontend, visual design, landing pages, dashboards, or product UI:

- Use **hue** when extracting or generating a brand or design language from a URL, screenshot, brand, or visual reference.
- Use **ui-ux-pro-max** when the task needs UI/UX patterns, design options, color palettes, font pairings, dashboard patterns, landing patterns, or structured design recommendations.
- Use **design-taste-frontend** when implementing or improving frontend pages and removing AI-template visual quality.
- Use **gpt-taste** when a GPT or Codex-specific taste critique is useful.
- Use **impeccable** for critique, polish, layout, typesetting, hardening, design audit, and final shipping review.
- Use **horseshoe-design** only when the requested visual direction explicitly involves horseshoe geometry, U-shaped layouts, protective enclosure, curved magnetic composition, or that generated design language.

Do not activate every design skill at once. Choose the smallest relevant set.
For major UI work, first produce a short design read, then implement, then audit.
Avoid generic SaaS templates, default gradients, overused card grids, stock hero structures, and unmotivated animations.

## Image & Video OCR (Default Behavior)

A local high-accuracy OCR engine is installed and available globally. Use it by default whenever images or videos containing text are involved.

- **Tool**: PP-OCRv6 (2025 latest) + CoreML acceleration on Apple Silicon
- **Location**: `/Users/jiyuanyi/Documents/OCR图片识别/`
- **Image command**: `ocr <image>` (on PATH via `~/.local/bin/ocr`)
- **Video command**: `video_ocr <video>` (on PATH via `~/.local/bin/video_ocr`)
- **Accuracy**: Chinese/English/digits ≈ 99% confidence in benchmarks
- **Speed**: ~2.5s per image; video ~1.5s per frame at 1fps sampling
- **Languages**: 80+ including Chinese, English, Japanese, Korean, Arabic, etc.

### When to Auto-Use OCR

Run `ocr` (for images) or `video_ocr` (for videos) automatically, without asking the user, when any of these is true:

- The user references an image file (`.png`, `.jpg`, `.jpeg`, `.bmp`, `.tiff`, `.webp`, `.gif`) or video file (`.mp4`, `.mov`, `.avi`, `.mkv`, `.webm`, `.flv`, `.wmv`, `.m4v`) and asks what is in it, asks to read/extract text from it, or asks to "look at" / "看看" / "识别" / "看下" a picture or video.
- The user pastes or provides a screenshot, photo, or video that clearly contains text, and the question is about the text content.
- A task requires reading text from an image or video to proceed (e.g., parsing a receipt, reading a form, extracting code from a screenshot, reading subtitles/text from a video, reading a label).
- The user asks to "OCR" or "识别图片/视频" or "read the image/video" or "图片/视频里的字".

### Image OCR Usage

```bash
# Single image (most common)
ocr path/to/image.png

# Multiple images / glob / directory
ocr img1.jpg img2.png
ocr *.png
ocr ./screenshots/

# JSON output for programmatic parsing
ocr image.png --json

# Skip orientation classification for speed (when text is upright)
ocr image.png --no-cls

# Save visualization with bounding boxes
ocr image.png --save ./output/

# Choose model size: tiny (fastest) / small / medium (default) / server (most accurate)
ocr image.png --model server

# From stdin
cat image.png | ocr -
```

### Video OCR Usage

```bash
# Basic: extract text from a video (samples 1 frame per second by default)
video_ocr video.mp4

# Higher sampling rate for fast-changing text
video_ocr video.mp4 --fps 2

# Only OCR a specific time range
video_ocr video.mp4 --start 10 --end 60

# JSON output with timestamps
video_ocr video.mp4 --json

# Save extracted frames
video_ocr video.mp4 --save-frames ./frames/

# Faster model for long videos
video_ocr video.mp4 --model tiny --no-cls

# Adjust dedup aggressiveness (lower = more aggressive dedup)
video_ocr video.mp4 --similarity 0.7
```

### Output Format

Image (human-readable):
```
📷 image.png
   ⏱ 耗时 2.5s  |  识别到 2 行
   ────────────────────────────────────────────────────────────
   [1] 你好世界 Hello World 2026   (置信度 0.999)
   [2] OCR 识别测试 中文英文数字混合   (置信度 0.978)
```

Video (human-readable, with timestamps and frame-level dedup):
```
🎬 test_video.mp4
   ════════════════════════════════════════════════════════════════

   [1] ⏱ 00:00.00
       第一段：欢迎使用 OCR   (置信度 0.977)

   [2] ⏱ 00:02.00
       第二段：视频文字识别   (置信度 1.000)
```

JSON: array of `{image/segments, elapsed/timestamp, lines: [{text, score, box}]}`.

### Behavior Rules

- When the user mentions an image or video with text but does NOT specify how to read it, default to `ocr <image>` or `video_ocr <video>` and report the extracted text. Do not ask "do you want me to OCR it?" — just do it.
- Detect file type by extension: images → `ocr`, videos → `video_ocr`.
- If the file path is relative, resolve it relative to the current working directory.
- If the OCR result is low confidence (< 0.5) or empty, mention that the media may be unclear, rotated, or contain no detectable text, and suggest `--no-cls` or a different `--model`.
- For batch image processing, prefer `--json` and parse programmatically.
- For long videos, suggest `--fps 0.5` (one frame every 2 seconds) to speed up processing, or `--model tiny` for a quick pass.
- After OCR, summarize the recognized text in plain language and proceed with whatever the user actually wanted done with that text (translate, summarize, search, format, etc.).
- Do not install alternative OCR libraries (Tesseract, EasyOCR, PaddleOCR) or video tools (ffmpeg) unless the installed tool is clearly insufficient for the task. Reuse the installed tools first.

## General Engineering Rules

These rules bias toward caution and clarity over speed for non-trivial work.

### 1. Reuse Existing Resources First

Before implementing from scratch:

- Search available plugins that can directly solve or meaningfully assist with the task.
- Search installed skills that match the task.
- Prefer using a suitable plugin or skill before writing custom code.
- Only build from scratch when no suitable resource exists or the existing option is clearly not a fit.
- Whenever a plugin or skill is selected automatically, explicitly tell the user which plugin or skill is being used before or while using it.

### 2. Translate User Language Into Product Requirements

- Assume the user may describe requests in non-technical, incomplete, emotional, or everyday language rather than precise engineering terms.
- Interpret the user's request first as a product goal: what outcome they want, what problem they are trying to solve, what the successful experience should feel like, and what constraint is implicit in their wording.
- Do not judge wording quality, technical accuracy, or tone. Focus on extracting intent and helping the user succeed.
- When the request is vague, infer the most likely product requirement and state that interpretation in simple language while proceeding when the risk is low.
- When a decision has meaningful product or technical tradeoffs, pause briefly and explain the options in non-technical language before continuing.
- Prefer explanations, plans, and status updates that a non-technical user can follow without specialized vocabulary unless technical detail is specifically helpful.

### 3. Think Before Coding

- State important assumptions.
- If there are multiple plausible interpretations, surface them instead of silently picking one.
- If a simpler path exists, mention it.
- If uncertainty is material, pause and clarify before making risky changes.

### 4. Keep It Simple

- Write the minimum code needed to solve the actual request.
- Do not add speculative abstractions, flexibility, or configuration.
- Do not implement error handling for scenarios that are not realistically in scope.
- If a solution feels overbuilt, simplify it.

### 5. Make Precise Changes

- Change only what is needed for the current request.
- Do not refactor unrelated code, comments, or formatting.
- Follow the existing local style unless the user asks otherwise.
- Remove imports, variables, and functions that become unused because of your own change.
- Do not clean up unrelated dead code unless the user asks.

### 6. Work Toward Verifiable Outcomes

- Turn requests into concrete checks whenever possible.
- For bug fixes, prefer reproducing the bug and then verifying the fix.
- For refactors, preserve behavior and verify existing tests still pass.
- For multi-step work, briefly define the success checks before diving in.

### 7. Handle Edge Cases

- Consider null, empty collections, missing fields, 0, negative numbers, and out-of-range values when they are plausible inputs.
- Do not assume input is always valid unless that guarantee is explicit and enforced.

### 8. Do Not Invent APIs

- Only use APIs, functions, config keys, and libraries that actually exist in the current environment.
- If an API is uncertain, confirm it from source or documentation before using it.
- Do not assume a library version or language feature is available without checking when it matters.

### 9. Confirm Current State Before Editing

- Read the current file contents before changing them.
- Confirm the function, class, selector, config key, or command you plan to change really exists where you expect.
- Check impact before removing shared code or changing shared signatures.
- If the likely blast radius is unclear, inspect first and ask only if the risk remains material.

## CodeGraph

If `codegraph_*` tools are available for the current project, prefer them for structural questions such as:

- where a symbol is defined
- who calls a function
- what a change will impact
- how data or control flows from one place to another

Prefer plain text search only for literal strings, comments, logs, or after you already know the exact file you need to inspect.

## Codex Git Workflow For Code Changes

### Goal

From now on, any task that changes code must be done on a dedicated branch. Never make code changes directly on `main`. `main` should only receive changes that have already been checked, tested, and reviewed.

This workflow is designed to:

- ensure every code change goes through an isolated branch
- preserve Git and GitHub history without adding unnecessary token overhead
- keep the review gate right before merging back to `main`, instead of making the development phase too heavy
- retain all task branches by default instead of deleting them automatically
- **keep every session's file changes automatically backed up to the configured remote**

### Auto-Sync Default Policy

By default, any session that produces file changes inside a Git repository with a configured remote MUST push those changes to the remote before reporting task completion. This applies to all file types, not only code:

- source code, scripts, configs, build files
- documentation, notes, READMEs, markdown
- assets, designs, data files committed to the repo
- any other tracked file

Push timing:

- Push the task branch to the remote **immediately after creating it**, before doing the actual edits, so the branch exists remotely even if the session is interrupted.
- Push **again at the end of each task** so the latest commits are always remotely backed up.
- If multiple commits are made within one task, batch-push them at the end is sufficient; per-commit push is not required.

Failure handling:

- If push fails (network, auth, no remote, permissions), stop and report it to the user. Do not silently skip the push and pretend the task is complete.
- If the repository has no remote configured, state that clearly at the end of the task instead of pushing.

The review gate before merging back to `main` is unchanged: a PR with review is still required. Auto-sync only applies to pushing the **task branch**, never to auto-merging into `main`.

### Default Repository (Fallback When CWD Is Not a Git Repo)

When a session needs to save file changes but the current working directory is **not** inside a Git repository with a configured remote, use the machine-wide default repository as fallback:

- **Default repo path**: `/Users/jiyuanyi/ZCodeProject/git-repo`
- **Default remote URL (SSH)**: `git@github.com:JJ188-coder/git-.git`
- **SSH key**: `~/.ssh/id_ed25519` (already added to GitHub, passphraseless, ready to use)
- **GitHub username**: `JJ188-coder`
- **Git identity**: `user.name=JJ188-coder`, `user.email=jij673944@gmail.com`

Behavior when fallback is needed:

1. `cd` into `/Users/jiyuanyi/ZCodeProject/git-repo` before running any git command.
2. If the user's task produced files **outside** this repo (e.g. on Desktop, in a random project folder), either:
   - Move/copy those files into the default repo and commit them there, OR
   - Ask the user: "这个文件在 X，要不要我挪到默认 git 仓库再同步？或者给当前目录单独 init + 配 remote？"
3. Never silently skip pushing just because CWD is not a repo. Always either use the fallback repo or explicitly ask the user.
4. If the default repo itself is unavailable (deleted, moved, corrupted), stop and report it.

### New Project = New GitHub Repo

When the user starts a **new project** (a distinct body of work with its own folder, not a one-off file), do NOT keep stuffing it into the default `git-repo`. Instead, create a dedicated GitHub repository for that project.

Definition of "new project" (any of these):

- The user explicitly says "新项目" / "new project" / "做个 X" / "build X" where X is a self-contained deliverable
- A new top-level folder is being created under `/Users/jiyuanyi/ZCodeProject/` (or another workspace root) for a coherent body of work
- The work is expected to produce multiple related files (code + docs + assets) that don't belong together with previous work
- The user gives the project a name (e.g. "做个天气预报网站", "写个股票分析工具")

Definition of "NOT a new project" (use default repo instead):

- One-off notes, todos, scratch files
- Quick scripts or snippets with no project structure
- Edits to existing files in already-configured repos
- Exploration / debugging / reading tasks

Procedure for a new project:

1. **Confirm the name with the user** if not obvious. Suggest a concise English repo name in `kebab-case` (e.g. `weather-app`, `stock-analyzer`). Chinese project names should be translated or romanized for the GitHub repo name; the in-repo README can keep the Chinese name.
2. **Pick the local path**: `/Users/jiyuanyi/ZCodeProject/<repo-name>/` by default. Ask the user if they want a different location.
3. **Create the GitHub repo first** using the GitHub CLI if available (`gh repo create JJ188-coder/<repo-name> --private --source=. --remote=origin`), or instruct the user to create it manually at https://github.com/new and give you the SSH URL.
4. **Initialize locally**:
   ```bash
   mkdir -p /Users/jiyuanyi/ZCodeProject/<repo-name>
   cd /Users/jiyuanyi/ZCodeProject/<repo-name>
   git init
   git remote add origin git@github.com:JJ188-coder/<repo-name>.git
   ```
5. **Create an initial commit** (README + .gitignore at minimum) and push to `main` to establish the repo.
6. **From this point on**, all subsequent edits for this project MUST go to this new repo, not the default `git-repo`. The new repo becomes the project's canonical remote.
7. **Update the project list** (see "Known Project Repos" section below) so future sessions know this repo exists.

Failure handling:

- If `gh` CLI is not installed, fall back to manual repo creation (ask the user to create it on github.com and paste the SSH URL).
- If the user declines creating a new repo, respect that and use the default repo for this one task, but remind them that mixing projects in one repo gets messy over time.
- If a repo with the same name already exists on GitHub, suggest a suffix (`-v2`, `-2026`, etc.) or ask for a new name.

### Known Project Repos

Maintain a mental/written list of project-specific repos so future sessions know which repo to use for which project:

- `git-repo` (`git@github.com:JJ188-coder/git-.git`) - default/fallback for one-off files and this config backup
- `zcode-config` (folder inside `git-repo`) - this ZCODE.md / AGENTS.md backup, not a separate repo

When a new project repo is created, append it to this list (both in ZCODE.md here and in the backup copy at `git-repo/zcode-config/ZCODE.md`).

Decision tree when a session starts a file-changing task:

```
Is the task a new project (per definition above)?
├── Yes  → Create new GitHub repo per procedure above. Use it for this and all future tasks for this project.
└── No   → Is CWD already inside a git repo with remote?
         ├── Yes  → Use that repo.
         └── No   → Is the file location clearly associated with an existing project repo?
                  ├── Yes  → cd into that project repo and commit there.
                  └── No   → Use the default `git-repo` as fallback, OR ask the user which project repo to use.
```

### Trigger Rules

The branch workflow is required for any task that does one or more of the following:

- adds code
- deletes code
- modifies existing code
- changes configuration, scripts, components, interfaces, or styles that affect runtime behavior
- changes project structure, build behavior, dependency declarations, or automation scripts
- **creates, edits, or deletes any other tracked file** (docs, markdown, notes, assets) in a repo with a configured remote

A new branch is **not** required by default for:

- reading code only
- explanation, analysis, investigation, discussion, or planning
- checking logs, errors, or command output
- giving suggestions without actually editing files

The decision is based on whether the task will create a real file change in the working repository, not on task size or file type.

### Default Workflow

1. First decide whether the task will change code or logic-related files.
2. If yes, check whether the current directory is a Git repository, what branch is active, and whether the working tree is clean.
3. If the current branch is `main`, create and switch to a new task branch before making any changes.
4. If the repository has a GitHub or other remote configured, push the new branch early so it is safely stored remotely.
5. Complete the changes, self-checks, and necessary tests on the task branch.
6. Only when preparing to write the changes back to `main`, create or update a PR and enter the review gate.
7. Merge the task branch back into `main` only after review has passed.
8. Keep the local branch, remote branch, and PR record after merge unless the user explicitly asks to delete them.

### Branch Strategy

- Use one branch per code task, not one branch per tiny edit.
- Use the default naming format `codex/YYYY-MM-DD-short-task-name`.
- If the current branch is already the correct task branch for the requested work, it may be reused.
- Do not make direct code changes on `main`.

### GitHub And Remote Strategy

- If a remote is configured, push the task branch soon after creating it.
- If no remote is configured, continue with the local Git branch workflow and clearly state that there is no remote backup.
- Do not require a PR at the very start of every task.
- Use the PR as the required review gate before writing back to `main`.
- Use a normal merge into `main` by default after review passes.
- Do not automatically delete local branches, remote branches, or PRs unless the user explicitly asks for deletion.

### Communication Rules

To reduce unnecessary token usage, do not repeatedly report Git details throughout the whole development process. Only report at these key checkpoints:

- **Before code changes begin:** Report the current branch and, if currently on `main`, the name of the branch that will be created.
- **After branch creation:** Report that the task branch has been created and checked out.
- **After remote push:** Report that the remote branch has been pushed, or state that work is staying local if no remote exists.
- **Before merge:** Report review status, merge target, and whether a PR is being created or updated.
- **After merge:** Report that the changes have been written back to `main` and that the branch and PR were retained.

Outside these checkpoints, avoid unnecessary Git status narration.

### Review Gate

Before writing any code changes back to `main`, complete all of the following:

- necessary self-checks
- necessary tests or verification
- a short summary of the changes
- a created or updated PR, or explicit user confirmation to proceed with the current review flow

Do not merge unreviewed or unconfirmed changes into `main`.

### Prohibited Actions

- Do not make code changes directly on `main`.
- Do not skip the branch workflow and modify the main line directly.
- Do not skip review or the PR gate and merge straight into `main`.
- Do not continue dangerous Git operations when the repository state is abnormal.
- Do not auto-delete branches or PRs after merge unless the user explicitly requests it.

### Exception Handling

Stop before the next risky step and explain the situation if any of the following is true:

- the current directory is not a Git repository
- the working tree has uncommitted changes that make branch switching or merging risky
- the target branch name already exists and should not be reused
- no remote is configured, push fails, or permissions are missing
- PR creation fails
- merge conflicts exist, or `main` has changed and needs to be resynced

In these situations, explain the risk and the recommended next step before continuing.

### Default Interpretation

When the user asks to "change code", "fix a bug", "add a feature", "remove some logic", or "refactor something", interpret that as:

- a code task that must enter the Git branch workflow
- first check Git status and the current branch
- if currently on `main`, create a new branch before editing files
- if GitHub is available, push the branch remotely early
- only enter the PR and review gate when preparing to merge back into `main`

When the user asks to "explain this", "analyze the error", "investigate first", or "review the code" without requesting edits yet, do not create a new branch unless the work later turns into real file changes.

### Branch Visualization (Post-Completion)

After completing work on a task branch (after merge back to `main` or at final report when no remote exists), generate a visualized branch tree to make the commit topology easy to scan:

- The primary tool is: `git log --oneline --graph --all --decorate`
- For very long branch histories, use: `git log --oneline --graph --all --decorate --branches=<current-branch> --max-count=15`
- Output the result in a fenced code block so it renders as monospace ASCII art in the final answer.
- The visualization keeps branch history scannable at a glance and serves as the spatial "mind map" of what was built and how commits relate.
- Clean the visualization from Practice Log / temporary sections before final delivery if they would distract from the real changes.
