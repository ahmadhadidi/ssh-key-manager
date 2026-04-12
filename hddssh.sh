#!/usr/bin/env bash
# hddssh.sh — SSH Key Manager TUI
#
# Usage:
#   bash hddssh.sh [OPTIONS]
#   bash <(curl -fsSL https://raw.githubusercontent.com/ahmadhadidi/ssh-key-manager/refs/heads/main/hddssh.sh) [OPTIONS]
#
# Options:
#   --user NAME           Default remote username        (default: default_non_root_username)
#   --subnet PREFIX       Default subnet prefix          (default: 192.168.0)
#   --comment-suffix STR  Default key comment suffix     (default: -[my-machine])
#   --password PASS       Default SSH password for sshpass
#   --verbose             Log debug info to /tmp/ssh-key-manager-debug.log

set -uo pipefail
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# ─── Defaults (overridable via CLI) ──────────────────────────────────────────
DEFAULT_USER="default_non_root_username"
DEFAULT_SUBNET_PREFIX="192.168.0"
DEFAULT_COMMENT_SUFFIX="-[my-machine]"
DEFAULT_PASSWORD=""
VERBOSE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)            DEFAULT_USER="$2";            shift 2 ;;
        --subnet)          DEFAULT_SUBNET_PREFIX="$2";   shift 2 ;;
        --comment-suffix)  DEFAULT_COMMENT_SUFFIX="$2";  shift 2 ;;
        --password)        DEFAULT_PASSWORD="$2";         shift 2 ;;
        --verbose)         VERBOSE=1;                     shift   ;;
        *) shift ;;
    esac
done

# ─── Constants ────────────────────────────────────────────────────────────────
SSH_DIR="$HOME/.ssh"
SSH_CONFIG="$HOME/.ssh/config"
P="  "

# ─── Script-scope globals ────────────────────────────────────────────────────
_LAST_SELECTED_ALIAS=""
KEY=""
_SELECT_RESULT=""
_SELECT_CANCELLED=0
_LOG_FILE="/tmp/ssh-key-manager-debug.log"
_STTY_SAVED=""   # global so _menu_cleanup can always access it
_HOST_BLOCK=""   # set by _get_host_block
_CONFIG_MISSING=0  # set to 1 when ~/.ssh/config does not exist

# ─── Library loader ──────────────────────────────────────────────────────────
_BASE_URL="https://raw.githubusercontent.com/ahmadhadidi/ssh-key-manager/refs/heads/main"

# Determine script directory (empty when run via bash <(curl ...))
_SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    _candidate="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
    # Only use local path if the lib/bash directory actually exists there
    [[ -d "${_candidate}/lib/bash" ]] && _SCRIPT_DIR="$_candidate"
fi

_source_lib() {
    local name="$1"
    local local_path="${_SCRIPT_DIR}/lib/bash/${name}.sh"
    if [[ -n "$_SCRIPT_DIR" && -f "$local_path" ]]; then
        # shellcheck source=/dev/null
        source "$local_path"
    else
        # shellcheck source=/dev/null
        source <(curl -fsSL "${_BASE_URL}/lib/bash/${name}.sh") || {
            printf 'Error: failed to load lib/bash/%s.sh from %s\n' "$name" "$_BASE_URL" >&2
            exit 1
        }
    fi
}

for _lib in tui ssh-config ssh-helpers prompts ssh-ops config-display menu menu-support menu-renderer; do
    _source_lib "$_lib"
done
unset _lib _source_lib _candidate _SCRIPT_DIR _BASE_URL

# ─── Entry point ─────────────────────────────────────────────────────────────
if (( VERBOSE )); then
    : > "$_LOG_FILE"
    printf '\e[33mVerbose mode: logging to %s\e[0m\n' "$_LOG_FILE"
    printf '\e[90mIn another terminal run:  tail -f %s\e[0m\n' "$_LOG_FILE"
    sleep 1
fi

show_main_menu
