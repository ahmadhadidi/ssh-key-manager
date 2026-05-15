# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A terminal-based SSH key manager with an interactive TUI (Text User Interface). It automates ED25519 key generation, deployment to remote machines, SSH config management, connection testing, and key rotation/cleanup.

Two parallel implementations exist:
- `sshhdd.sh` — macOS (bash 3.2), entry point (~47 lines); logic lives in `lib/bash/`
- `sshhdd.ps1` — Windows (PowerShell 5+), entry point (~47 lines); logic lives in `lib/ps/`

Implementation details are in the sub-directory CLAUDE.md files (loaded automatically when editing files in those directories):
- Bash: `lib/bash/CLAUDE.md` — architecture, module breakdown, bash 3.2 rules, implementation notes
- PowerShell: `lib/ps/CLAUDE.md` — architecture, module breakdown, PS-specific notes

## Running

**Bash:**
```bash
bash sshhdd.sh
bash sshhdd.sh --user myuser --subnet 192.168.0 --comment-suffix "-[prod]" --password "mypass"
```

**PowerShell:**
```powershell
. .\sshhdd.ps1
& ./sshhdd.ps1 -DefaultUserName "root" -DefaultSubnetPrefix "192.168.0"
```

There is no build step, test framework, or linter. Both scripts run directly with no dependencies beyond Bash/PowerShell and OpenSSH (`ssh`, `ssh-keygen`). `sshpass` is optional for password-based remote auth.

## Bash vs PowerShell parity

When modifying behavior, changes typically need to be mirrored in the counterpart lib files. Bash uses `stty`/`read` for terminal I/O; PowerShell uses `Host.UI.RawUI.ReadKey()` and `[Console]::Write()`. Config parsing in Bash uses `perl`/`awk`/`sed`; PowerShell uses `[regex]` class methods.
