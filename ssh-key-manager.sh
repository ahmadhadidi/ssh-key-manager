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

# ─── TUI utilities ────────────────────────────────────────────────────────────

# Show a "Press any key to return to menu" bar at the bottom of the screen.
wait_user_acknowledge() {
    _term_size
    local msg="  Press any key to return to menu  "
    local pad
    pad=$(_repeat ' ' "$(( TERM_W - ${#msg} > 0 ? TERM_W - ${#msg} : 0 ))")
    printf '\e[%d;1H\e[7m%s%s\e[0m' "$TERM_H" "$msg" "$pad"
    _read_key
}

# Page through an array of lines.  Lines may contain ANSI codes.
# Call as:  show_paged line1 line2 line3 ...
show_paged() {
    local -a lines=("$@")
    local total=${#lines[@]}
    _term_size
    local page_size=$(( TERM_H - 4 ))
    (( page_size < 5 )) && page_size=5
    local i=0
    while (( i < total )); do
        local end=$(( i + page_size - 1 ))
        (( end >= total )) && end=$(( total - 1 ))
        local j
        for (( j=i; j<=end; j++ )); do
            printf '%s\n' "${lines[$j]}"
        done
        i=$(( i + page_size ))
        if (( i < total )); then
            printf '\e[90m-- %d/%d lines shown | Enter=more, Q=quit --\e[0m' "$i" "$total"
            _read_key
            printf '\n'
            [[ $KEY == 'q' || $KEY == 'Q' ]] && break
        fi
    done
}

# Return a label with the hotkey letter wrapped in bold+underline ANSI codes.
# format_menu_label "Generate & Install" "G"  →  "\e[1;4mG\e[0;37menerate & Install"
format_menu_label() {
    local label="$1" hotkey="${2:-}"
    if [[ -z $hotkey ]]; then
        printf '%s' "$label"
        return
    fi
    local lo="${hotkey,,}" up="${hotkey^^}"
    # Replace first occurrence (case-insensitive) of the hotkey letter
    printf '%s' "$label" | sed "s/[$lo$up]/\x1b[1;4m&\x1b[0;37m/1"
}

# Interactive combo-box.
# Args: [-s|--strict] [-p PROMPT] item1 item2 ...
#   -s / --strict  Enter only accepts a highlighted item or sole filter match; no free text.
# Sets _SELECT_RESULT (selected string) and _SELECT_CANCELLED (1=ESC).
# Returns 0 on selection, 1 on ESC/cancel.
select_from_list() {
    local strict=0 prompt="Select"
    while [[ ${1:-} == -* ]]; do
        case "$1" in
            -s|--strict) strict=1; shift ;;
            -p|--prompt) prompt="$2"; shift 2 ;;
            *) break ;;
        esac
    done

    local -a items=("$@")
    local item_count=${#items[@]}
    if (( item_count == 0 )); then
        _SELECT_RESULT=''
        _SELECT_CANCELLED=0
        return 1
    fi

    _term_size
    # Determine start row for the dropdown (below current cursor position + 3)
    local cur_row
    cur_row=$(tput lines 2>/dev/null || echo 24)
    # We'll place the combo at a fixed offset from top for simplicity
    local start_row=8
    local max_vis=$(( TERM_H - start_row - 2 ))
    (( max_vis < 1 )) && max_vis=1

    local sel=-1        # -1 = text input mode, >=0 = list item highlighted
    local view_off=0
    local filter=""
    local -a filtered=("${items[@]}")

    printf '\e[?25l'   # hide cursor

    while true; do
        # Re-filter
        filtered=()
        local it
        for it in "${items[@]}"; do
            [[ -z $filter || "${it,,}" == *"${filter,,}"* ]] && filtered+=("$it")
        done
        local fcount=${#filtered[@]}

        # Clamp sel
        (( sel >= fcount )) && sel=$(( fcount - 1 ))
        # Adjust viewport
        if (( sel >= 0 && sel < view_off )); then
            view_off=$sel
        elif (( sel >= 0 && sel >= view_off + max_vis )); then
            view_off=$(( sel - max_vis + 1 ))
        fi
        (( view_off < 0 )) && view_off=0

        local prompt_row=$(( start_row - 2 ))
        local input_row=$(( start_row - 1 ))
        local input_disp
        if [[ -n $filter ]]; then
            input_disp="$(printf '\e[37m%s\e[90m▌\e[0m' "$filter")"
        else
            input_disp="$(printf '\e[90m(type to filter or create new)\e[0m')"
        fi

        # Build frame
        local f
        f="$(printf '\e[%d;1H\e[K  \e[90m%s\e[0m' "$prompt_row" "$prompt")"
        f+="$(printf '\e[%d;1H\e[K  \e[36m›\e[0m %s' "$input_row" "$input_disp")"

        local i
        for (( i=0; i<max_vis; i++ )); do
            local idx=$(( view_off + i ))
            local r=$(( start_row + i ))
            f+="$(printf '\e[%d;1H\e[K' "$r")"
            if (( idx < fcount )); then
                if (( idx == sel )); then
                    f+="$(printf '  \e[1;36m▶ %s\e[0m' "${filtered[$idx]}")"
                else
                    f+="$(printf '  \e[37m  %s\e[0m' "${filtered[$idx]}")"
                fi
            fi
        done

        local up_ind="  " dn_ind="  "
        (( view_off > 0 )) && up_ind="▲ "
        (( view_off + max_vis < fcount )) && dn_ind="▼ "
        local hint="  ↑↓  navigate     Enter  select     type  filter / new name     Esc  cancel    ${up_ind}${dn_ind}"
        local hint_pad
        hint_pad=$(_repeat ' ' "$(( TERM_W - ${#hint} > 0 ? TERM_W - ${#hint} : 0 ))")
        f+="$(printf '\e[%d;1H\e[7m%s%s\e[0m' "$TERM_H" "$hint" "$hint_pad")"

        printf '%s' "$f"

        _read_key
        local k="$KEY"

        # Clear combo rows helper (used on exit)
        local clr="" ci
        for (( ci=prompt_row; ci<start_row+max_vis+1 && ci<TERM_H; ci++ )); do
            clr+="$(printf '\e[%d;1H\e[K' "$ci")"
        done

        case "$k" in
            "$KEY_UP")
                (( sel > 0 )) && (( sel-- )) || (( sel == 0 )) && sel=-1
                ;;
            "$KEY_DOWN")
                if (( sel == -1 && fcount > 0 )); then sel=0
                elif (( sel < fcount - 1 )); then (( sel++ ))
                fi
                ;;
            "$KEY_BACKSPACE"|"$KEY_BACKSPACE2")
                if (( ${#filter} > 0 )); then
                    filter="${filter%?}"
                    sel=-1
                fi
                ;;
            "$KEY_ENTER"|"$KEY_ENTER2")
                local chosen=""
                if (( sel >= 0 && sel < fcount )); then
                    chosen="${filtered[$sel]}"
                elif (( strict == 1 )); then
                    if (( fcount == 1 )); then chosen="${filtered[0]}"
                    else continue   # ignore — strict mode, no match
                    fi
                elif [[ -n $filter ]]; then
                    chosen="$filter"
                fi
                printf '%s\e[%d;1H\e[K\e[?25h' "$clr" "$TERM_H"
                if [[ -n $chosen ]]; then
                    printf '\e[%d;1H  \e[90m%s\e[0m  \e[36m%s\e[0m\n' \
                        "$prompt_row" "$prompt" "$chosen"
                else
                    printf '\e[%d;1H' "$prompt_row"
                fi
                _SELECT_RESULT="$chosen"
                _SELECT_CANCELLED=0
                return 0
                ;;
            "$KEY_ESC")
                printf '%s\e[%d;1H\e[K\e[%d;1H\e[?25h' "$clr" "$TERM_H" "$prompt_row"
                _SELECT_RESULT=""
                _SELECT_CANCELLED=1
                return 1
                ;;
            *)
                # Printable ASCII → append to filter
                if [[ ${#k} -eq 1 && $(printf '%d' "'$k") -ge 32 ]] 2>/dev/null; then
                    filter+="$k"
                    sel=-1
                fi
                ;;
        esac
    done

    printf '\e[?25h'
    _SELECT_RESULT=""
    _SELECT_CANCELLED=0
    return 1
}

# ─── SSH config parsing ───────────────────────────────────────────────────────

# Print "alias|hostname|user" for every non-wildcard Host block in ~/.ssh/config.
get_configured_ssh_hosts() {
    [[ -f "$SSH_CONFIG" ]] || return 0
    awk '
        /^Host[[:space:]]/ {
            if (alias != "" && alias != "*") print alias "|" hn "|" user
            alias=$2; hn=""; user=""
        }
        /^[[:space:]]*HostName[[:space:]]/ { hn=$2 }
        /^[[:space:]]*User[[:space:]]/     { user=$2 }
        END { if (alias != "" && alias != "*") print alias "|" hn "|" user }
    ' "$SSH_CONFIG"
}

# Print names of private key files in ~/.ssh (no .pub extension, excluding system files).
get_available_ssh_keys() {
    [[ -d "$SSH_DIR" ]] || return 0
    local exclude="config known_hosts known_hosts.old authorized_keys authorized_keys2 environment rc"
    local f
    for f in "$SSH_DIR"/*; do
        [[ -f "$f" ]] || continue
        local name; name=$(basename "$f")
        [[ $name == *.pub ]] && continue
        local skip=0
        local ex
        for ex in $exclude; do [[ ${name,,} == "$ex" ]] && skip=1 && break; done
        (( skip )) || printf '%s\n' "$name"
    done | sort
}

# Extract the full text of the Host block for a given alias (or empty string).
# Sets _HOST_BLOCK global.
_get_host_block() {
    local alias="$1"
    _HOST_BLOCK=""
    [[ -f "$SSH_CONFIG" ]] || return 0
    local esc; esc=$(_regex_escape "$alias")
    _HOST_BLOCK=$(perl -0777 -ne \
        "/(^Host[ \t]+${esc}\\b.*?)(?=^Host[ \t]|\\z)/ms and print \$1" \
        "$SSH_CONFIG" 2>/dev/null || true)
}

# Print IdentityFile values for a given host alias or IP address.
get_identity_files_for_host() {
    local target="$1"
    [[ -z $target || ! -f "$SSH_CONFIG" ]] && return 0

    _get_host_block "$target"
    local block="$_HOST_BLOCK"

    # If no alias match, search by HostName value
    if [[ -z $block ]]; then
        local esc; esc=$(_regex_escape "$target")
        block=$(awk -v tgt="$target" '
            /^Host[[:space:]]/ { alias=$2; in_block=1; block="" }
            in_block { block=block $0 "\n" }
            /^[[:space:]]*HostName[[:space:]]/ && in_block && $2==tgt {
                found=block
            }
            /^$/ && in_block { in_block=0 }
            END { if (found) printf "%s", found }
        ' "$SSH_CONFIG" 2>/dev/null || true)
    fi

    [[ -z $block ]] && return 0
    printf '%s\n' "$block" | \
        grep -E '^\s*IdentityFile\s+' | \
        sed -E 's/^\s*IdentityFile\s+//; s/^"(.*)"$/\1/; s/^\s+//; s/\s+$//'
}

# Print "alias|hostname|user" for hosts whose config block references KeyName as IdentityFile.
get_hosts_using_key() {
    local keyname="$1"
    [[ -f "$SSH_CONFIG" ]] || return 0
    local esc; esc=$(_regex_escape "$keyname")
    # Read all host blocks, grep for IdentityFile matching the key name
    while IFS='|' read -r alias hn user; do
        _get_host_block "$alias"
        if printf '%s\n' "$_HOST_BLOCK" | \
               grep -qE "IdentityFile\s+.*[/\\\\]?${esc}[[:space:]]*$"; then
            printf '%s|%s|%s\n' "$alias" "$hn" "$user"
        fi
    done < <(get_configured_ssh_hosts)
}

# Extract a single field value from a host block.
# _block_field "HostName" "$block"
_block_field() {
    local field="$1" block="$2"
    printf '%s\n' "$block" | \
        grep -m1 -iE "^\s*${field}\s+" | \
        sed -E "s/^\s*${field}\s+//i; s/\s+$//"
}

# Return HostName value from a named Host block (or empty).
get_ip_from_host_config() {
    local alias="$1"
    _get_host_block "$alias"
    _block_field "HostName" "$_HOST_BLOCK"
}

# Return User value from a named Host block (or empty).
get_user_from_host_config() {
    local alias="$1"
    _get_host_block "$alias"
    _block_field "User" "$_HOST_BLOCK"
}

# Return first IdentityFile value from a named Host block (or empty).
get_identity_file_from_host_config() {
    local alias="$1"
    _get_host_block "$alias"
    local raw
    raw=$(_block_field "IdentityFile" "$_HOST_BLOCK")
    # Expand ~ / $HOME
    raw="${raw/#\~/$HOME}"
    raw="${raw/#\$HOME/$HOME}"
    printf '%s' "$raw"
}
