# <img width="34" height="29" alt="image" src="https://github.com/user-attachments/assets/c5986644-d13c-40e6-905b-62ef381c89e2" /> Hibou is a tiny [claude code](https://docs.claude.com/en/docs/claude-code/overview) chat that lives in the macOS menu bar.

<p align="center">
  <img width="29%" alt="image" src="https://github.com/user-attachments/assets/0cc3621c-2b4d-41fe-a8fe-85475b597f97" />
  &nbsp;&nbsp;
  <img width="29%" alt="image" src="https://github.com/user-attachments/assets/4a17b35d-8709-4fbd-9009-ef3318e2df73" />
  &nbsp;&nbsp;
  <img width="29%" alt="image" src="https://github.com/user-attachments/assets/874fce7b-3e1e-4192-921e-6b5e78393e92" />
</p>

Open hibou, type or paste a message, press Enter: Claude's reply appears in the popup. Click outside to close it. The conversation is kept until you start a new one.

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

Hibou does not ask for confirmation in the middle of a reply, so it pre-approves these permissions:

- **Web search**
- **Edit files**
- **Terminal commands**
- **Connectors** (MCP servers)

All of them are allowed by default and can be turned off in the settings. Claude Code permission rules (`~/.claude/settings.json`) still apply.

## Updating

```bash
git pull
./scripts/build.sh --install
```

The script quits Hibou, replaces the app in `/Applications` and relaunches it. Your conversation and settings are kept.
