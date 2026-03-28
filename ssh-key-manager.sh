#!/usr/bin/env bash
# ssh-key-manager.sh — SSH Key Manager TUI for Linux
# Bash port of generate_key_test.ps1
#
# Usage:
#   bash ssh-key-manager.sh [OPTIONS]
#
# Options:
#   --user NAME           Default remote username        (default: default_non_root_username)
#   --subnet PREFIX       Default subnet prefix          (default: 192.168.0)
#   --comment-suffix STR  Default key comment suffix     (default: -[my-machine])
#   --password PASS       Default SSH password for sshpass

set -uo pipefail
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# ─── Defaults (overridable via CLI) ──────────────────────────────────────────
DEFAULT_USER="default_non_root_username"
DEFAULT_SUBNET_PREFIX="192.168.0"
DEFAULT_COMMENT_SUFFIX="-[my-machine]"
DEFAULT_PASSWORD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)            DEFAULT_USER="$2";            shift 2 ;;
        --subnet)          DEFAULT_SUBNET_PREFIX="$2";   shift 2 ;;
        --comment-suffix)  DEFAULT_COMMENT_SUFFIX="$2";  shift 2 ;;
        --password)        DEFAULT_PASSWORD="$2";         shift 2 ;;
        *) shift ;;
    esac
done

# ─── Constants ────────────────────────────────────────────────────────────────
SSH_DIR="$HOME/.ssh"
SSH_CONFIG="$HOME/.ssh/config"
P="  "   # 2-space left-pad for all user-facing output

# ─── Script-scope globals ────────────────────────────────────────────────────
_LAST_SELECTED_ALIAS=""   # set by read_remote_host_address when config entry chosen
KEY=""                     # set by _read_key / _read_key_nb
_SELECT_RESULT=""          # set by select_from_list
_SELECT_CANCELLED=0        # 1 if select_from_list exited via ESC

# ─── Terminal helpers ─────────────────────────────────────────────────────────

_term_size() {
    TERM_W=$(tput cols  2>/dev/null || echo 80)
    TERM_H=$(tput lines 2>/dev/null || echo 24)
}

# Escape a string for literal use inside a basic/extended regex pattern.
_regex_escape() {
    printf '%s' "$1" | sed 's/[.^$*+?{}|\\()\[\]]/\\&/g'
}

# Repeat a character N times.  _repeat "─" 40
_repeat() {
    local char="$1" n="$2"
    printf '%*s' "$n" '' | tr ' ' "$char"
}

# Integer max/min helpers.
_max() { (( $1 >= $2 )) && printf '%d' "$1" || printf '%d' "$2"; }
_min() { (( $1 <= $2 )) && printf '%d' "$1" || printf '%d' "$2"; }

# Read one keypress (blocking).  Sets global KEY.
# Handles arrow keys and other multi-byte escape sequences.
_read_key() {
    local k s1 s2 s3
    local _st
    _st=$(stty -g 2>/dev/null) || true
    stty -echo -icanon min 1 time 0 2>/dev/null || true
    IFS= read -r -n1 k 2>/dev/null || k=''
    if [[ $k == $'\x1b' ]]; then
        IFS= read -r -n1 -t 0.05 s1 2>/dev/null || s1=''
        IFS= read -r -n1 -t 0.05 s2 2>/dev/null || s2=''
        # PgUp ESC[5~ / PgDn ESC[6~ have a trailing '~' as 4th byte
        if [[ ${s2:-} =~ ^[0-9]$ ]]; then
            IFS= read -r -n1 -t 0.05 s3 2>/dev/null || s3=''
        else
            s3=''
        fi
        k="${k}${s1}${s2}${s3}"
    fi
    stty "$_st" 2>/dev/null || true
    KEY="$k"
}

# Non-blocking read: waits up to ~50 ms.  Returns 0 if key read, 1 on timeout.
# Sets global KEY on success.
_read_key_nb() {
    local k s1 s2 s3
    local _st
    _st=$(stty -g 2>/dev/null) || true
    stty -echo -icanon min 0 time 0 2>/dev/null || true
    IFS= read -r -n1 -t 0.05 k 2>/dev/null || {
        stty "$_st" 2>/dev/null || true
        KEY=''
        return 1
    }
    if [[ $k == $'\x1b' ]]; then
        IFS= read -r -n1 -t 0.05 s1 2>/dev/null || s1=''
        IFS= read -r -n1 -t 0.05 s2 2>/dev/null || s2=''
        if [[ ${s2:-} =~ ^[0-9]$ ]]; then
            IFS= read -r -n1 -t 0.05 s3 2>/dev/null || s3=''
        else
            s3=''
        fi
        k="${k}${s1}${s2}${s3}"
    fi
    stty "$_st" 2>/dev/null || true
    KEY="$k"
    return 0
}

# Key constants (used throughout as case-match values)
readonly KEY_UP=$'\x1b[A'
readonly KEY_DOWN=$'\x1b[B'
readonly KEY_HOME=$'\x1b[H'
readonly KEY_END=$'\x1b[F'
readonly KEY_PGUP=$'\x1b[5~'
readonly KEY_PGDN=$'\x1b[6~'
readonly KEY_HOME2=$'\x1bOH'    # alternate Home (some terminals)
readonly KEY_END2=$'\x1bOF'     # alternate End
readonly KEY_F1_A=$'\x1bOP'     # F1 variant A
readonly KEY_F1_B=$'\x1b[11~'   # F1 variant B
readonly KEY_F10=$'\x1b[21~'    # F10
readonly KEY_ENTER=$'\r'
readonly KEY_ENTER2=$'\n'
readonly KEY_ESC=$'\x1b'
readonly KEY_BACKSPACE=$'\x7f'
readonly KEY_BACKSPACE2=$'\x08' # Ctrl-H (some terminals)
