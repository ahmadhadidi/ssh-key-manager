#!/usr/bin/env bash
# scripts/check.sh — syntax-check all lib files (bash + PS) without staging
#
# Usage:
#   bash scripts/check.sh
set -uo pipefail
cd "$(dirname "$0")/.."

failed=0

# ── Bash ──────────────────────────────────────────────────────────────────────
for f in lib/bash/*.sh; do
    [[ -f $f ]] || continue
    if bash -n "$f" 2>/tmp/check-bash-err; then
        printf '  \e[32m✓\e[0m  %s\n' "$f"
    else
        printf '  \e[31m✗\e[0m  %s\n' "$f"
        sed 's/^/      /' /tmp/check-bash-err
        failed=1
    fi
done

# ── PowerShell ────────────────────────────────────────────────────────────────
if command -v pwsh &>/dev/null; then
    for f in lib/ps/*.ps1; do
        [[ -f $f ]] || continue
        errs=$(pwsh -NoProfile -Command "
            \$errors = \$null
            \$null = [System.Management.Automation.Language.Parser]::ParseFile(
                '$f', [ref]\$null, [ref]\$errors)
            \$errors | ForEach-Object { \$_.Message }
        " 2>/dev/null)
        if [[ -z "$errs" ]]; then
            printf '  \e[32m✓\e[0m  %s\n' "$f"
        else
            printf '  \e[31m✗\e[0m  %s\n' "$f"
            printf '%s\n' "$errs" | sed 's/^/      /'
            failed=1
        fi
    done
else
    printf '  \e[90mpwsh not found — skipping PS syntax check\e[0m\n'
fi

# ── Result ────────────────────────────────────────────────────────────────────
if (( failed )); then
    printf '\n  \e[31mSyntax errors found.\e[0m\n\n'
    exit 1
else
    printf '\n  \e[32mAll files OK.\e[0m\n'
fi
