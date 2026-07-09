# zcode-config

This folder holds machine-wide ZCode configuration files, backed up to GitHub.

## Files

- `ZCODE.md` — global rules (engineering, git workflow, auto-sync policy, OCR defaults)
- `AGENTS.md` — mirror of ZCODE.md

## How to restore on a new machine

```bash
mkdir -p ~/.zcode
cp ZCODE.md AGENTS.md ~/.zcode/
```

## Update flow

1. Edit `~/.zcode/ZCODE.md` (the live file ZCode reads)
2. Copy it here: `cp ~/.zcode/ZCODE.md zcode-config/ZCODE.md`
3. Commit and push — ZCode auto-syncs per its own rules
