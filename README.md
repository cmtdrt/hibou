# Hibou is a tiny [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) chat that lives in the macOS menu bar.

Click the owl, type or paste a message, press Return: Claude's reply appears in the popup. Click outside to close it. The conversation is kept until you start a new one.

## Requirements

- macOS 14 (Sonoma) or later
- [Claude Code](https://docs.claude.com/en/docs/claude-code/setup) installed and logged in

## Installation

```bash
git clone https://github.com/cmtdrt/hibou.git
cd hibou
./scripts/build.sh --install
```

The script builds the app, copies it to `/Applications` and launches it. The owl appears in the menu bar.

## Permissions

Hibou does not ask for confirmation in the middle of a reply, so it offers two modes:

- **Read-only** (default)
- **Can edit files**

Claude Code permission rules (`~/.claude/settings.json`) still apply.

## Updating

```bash
git pull
./scripts/build.sh --install
```

The script quits Hibou, replaces the app in `/Applications` and relaunches it. Your conversation and settings are kept.
