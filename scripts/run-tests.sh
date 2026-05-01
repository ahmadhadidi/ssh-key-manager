#!/usr/bin/env bash
# scripts/run-tests.sh — run the pytest suite (requires pexpect)
#
# Usage:
#   bash scripts/run-tests.sh [pytest-args...]
set -uo pipefail
cd "$(dirname "$0")/.."

if ! command -v pytest &>/dev/null && ! command -v python3 &>/dev/null; then
    printf '  \e[90mpython3/pytest not found — skipping tests\e[0m\n'
    exit 0
fi

_pytest() {
    if command -v pytest &>/dev/null; then
        pytest "$@"
    else
        python3 -m pytest "$@"
    fi
}

printf '  Running pytest...\n\n'
if _pytest "$@"; then
    printf '\n  \e[32mAll tests passed.\e[0m\n'
else
    printf '\n  \e[31mTests failed.\e[0m\n'
    exit 1
fi
