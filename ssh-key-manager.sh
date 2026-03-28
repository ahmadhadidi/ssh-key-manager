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

# ─── Input / prompt functions ─────────────────────────────────────────────────

# Prompt with color.  Result printed to stdout.
read_colored_input() {
    local prompt="${1:-Input}" color="${2:-cyan}"
    local code
    case "${color,,}" in
        cyan)    code=36 ;;
        yellow)  code=33 ;;
        green)   code=32 ;;
        red)     code=31 ;;
        gray)    code=90 ;;
        *)       code=37 ;;
    esac
    printf '\e[%dm%s \e[0m' "$code" "$prompt" >&2
    local val
    read -r val || val=''
    printf '%s' "$val"
}

# Show a prompt with a default value pre-filled and editable (char-by-char).
# Returns the edited value (or default on Enter).  ESC sets _SELECT_CANCELLED=1 and returns "".
read_host_with_default() {
    local prompt="${1:-Value:}" default="${2:-}"
    printf '  \e[36m%s\e[0m  ' "$prompt" >&2
    printf '%s' "$default" >&2
    printf '\e[?25h' >&2   # show cursor

    local buf="$default"
    while true; do
        _read_key
        local k="$KEY"
        case "$k" in
            "$KEY_ENTER"|"$KEY_ENTER2")
                printf '\n' >&2
                printf '%s' "$buf"
                return 0
                ;;
            "$KEY_ESC")
                printf '\e[?25l' >&2
                _SELECT_CANCELLED=1
                printf ''
                return 1
                ;;
            "$KEY_BACKSPACE"|"$KEY_BACKSPACE2")
                if (( ${#buf} > 0 )); then
                    buf="${buf%?}"
                    printf '\b \b' >&2
                fi
                ;;
            *)
                if [[ ${#k} -eq 1 ]] && (( $(printf '%d' "'$k" 2>/dev/null || echo 0) >= 32 )); then
                    buf+="$k"
                    printf '%s' "$k" >&2
                fi
                ;;
        esac
    done
}

read_remote_user() {
    local default_user="${1:-$DEFAULT_USER}"
    read_host_with_default "Remote username:" "$default_user"
}

read_remote_host_address() {
    local subnet="${1:-$DEFAULT_SUBNET_PREFIX}"
    _LAST_SELECTED_ALIAS=""

    local -a host_entries=()
    local -a host_aliases=()
    while IFS='|' read -r alias hn user; do
        host_aliases+=("$alias")
        if [[ -n $hn ]]; then
            host_entries+=("$alias  ($hn)")
        else
            host_entries+=("$alias")
        fi
    done < <(get_configured_ssh_hosts)

    if (( ${#host_entries[@]} > 0 )); then
        select_from_list -p "Select remote host  (Esc = enter manually)" "${host_entries[@]}"
        if (( _SELECT_CANCELLED == 0 )) && [[ -n $_SELECT_RESULT ]]; then
            local sel="$_SELECT_RESULT"
            # Extract alias (part before "  (")
            local alias="${sel%%  (*}"
            alias="${alias%"${alias##*[! ]}"}"  # trim trailing spaces
            # Find the hostname for this alias
            local i
            for (( i=0; i<${#host_aliases[@]}; i++ )); do
                if [[ "${host_aliases[$i]}" == "$alias" ]]; then
                    _LAST_SELECTED_ALIAS="$alias"
                    local hn
                    hn=$(get_ip_from_host_config "$alias")
                    if [[ -n $hn ]]; then
                        printf '%s' "$hn"
                    else
                        printf '%s' "$alias"
                    fi
                    return 0
                fi
            done
        fi
        # ESC or no match → fall through to manual entry
    fi

    local addr
    addr=$(read_colored_input \
        "  Enter remote IP / hostname (or last 1–3 digits for ${subnet}.xx)" cyan)
    if [[ -z $addr ]]; then
        printf '  \e[31m❗ No input provided.\e[0m\n' >&2
        printf ''
        return 1
    fi
    if [[ $addr =~ ^[0-9]{1,3}$ ]]; then
        local resolved="${subnet}.${addr}"
        printf '  \e[32m📡 Interpreted as: %s\e[0m\n' "$resolved" >&2
        printf '%s' "$resolved"
        return 0
    fi
    if [[ $addr =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        printf '  \e[36m🌐 Full IP address: %s\e[0m\n' "$addr" >&2
        printf '%s' "$addr"
        return 0
    fi
    printf '  \e[36m🏷  Hostname: %s\e[0m\n' "$addr" >&2
    printf '%s' "$addr"
}

read_remote_host_name() {
    local subnet="${1:-$DEFAULT_SUBNET_PREFIX}"
    local -a aliases=()
    while IFS='|' read -r alias _ _; do
        aliases+=("$alias")
    done < <(get_configured_ssh_hosts)

    if (( ${#aliases[@]} > 0 )); then
        select_from_list -p "Select host alias  (Esc = enter manually)" "${aliases[@]}"
        if (( _SELECT_CANCELLED == 0 )) && [[ -n $_SELECT_RESULT ]]; then
            printf '%s' "$_SELECT_RESULT"
            return 0
        fi
    fi

    local name
    name=$(read_colored_input "  Enter the host alias / hostname" cyan)
    if [[ -z $name ]]; then
        printf '  \e[31m❗ Hostname is required.\e[0m\n' >&2
        printf ''
        return 1
    fi
    printf '%s' "$name"
}

read_ssh_key_name() {
    local -a keys=()
    while IFS= read -r k; do keys+=("$k"); done < <(get_available_ssh_keys)

    if (( ${#keys[@]} > 0 )); then
        select_from_list -p "Select SSH key" "${keys[@]}"
        if (( _SELECT_CANCELLED == 0 )) && [[ -n $_SELECT_RESULT ]]; then
            printf '%s' "$_SELECT_RESULT"
            return 0
        fi
    fi

    local name
    name=$(read_colored_input "  Enter SSH key name" cyan)
    if [[ -z $name ]]; then
        printf '  \e[31m❗ Key name is required.\e[0m\n' >&2
        read_ssh_key_name   # recurse
        return $?
    fi
    printf '%s' "$name"
}

read_ssh_key_comment() {
    local default="${1:-}"
    read_host_with_default "Key comment:" "$default"
}

# Y/N confirmation.  default = "y" or "n".  Executes action_fn (no args) if confirmed.
confirm_user_choice() {
    local message="$1" default="${2:-n}"
    local action_fn="$3"
    local suffix
    if [[ ${default,,} == 'y' ]]; then suffix="[Y/n]"
    elif [[ ${default,,} == 'n' ]]; then suffix="[y/N]"
    else suffix="[y/n]"
    fi

    local response
    response=$(read_colored_input "$message $suffix" cyan)
    [[ -z $response ]] && response="$default"

    case "${response,,}" in
        y|yes)
            "$action_fn"
            return 0
            ;;
        n|no)
            printf '  \e[33m❌ Action cancelled.\e[0m\n'
            return 1
            ;;
        *)
            printf '  \e[31m⚠️  Invalid input. Please enter y or n.\e[0m\n'
            confirm_user_choice "$message" "$default" "$action_fn"
            ;;
    esac
}

# ─── Finders / getters ────────────────────────────────────────────────────────

# Return config path or "" (with warning).
find_config_file() {
    if [[ ! -f "$SSH_CONFIG" ]]; then
        printf '  \e[33m⚠️  SSH config file not found at %s.\e[0m\n' "$SSH_CONFIG" >&2
        printf ''
        return 1
    fi
    printf '%s' "$SSH_CONFIG"
}

find_private_key() {
    local keyname="$1"
    [[ -f "$SSH_DIR/$keyname" ]]
}

find_public_key() {
    local keyname="$1"
    [[ -f "$SSH_DIR/${keyname}.pub" ]]
}

# Print public key content, or return 1 on failure.
get_public_key() {
    local keyname="$1"
    local path="$SSH_DIR/${keyname}.pub"
    if [[ ! -f "$path" ]]; then
        printf '  \e[31m❌ Public key '\''%s.pub'\'' not found at %s.\e[0m\n' "$keyname" "$path"
        return 1
    fi
    local content
    content=$(cat "$path")
    printf '  \e[32m✅ Public key loaded successfully:\n  %s\e[0m\n' "$content"
    printf '%s' "$content"
}

# Given an IP/address and user, return "user@alias" if a matching Host block exists
# in ~/.ssh/config (direct alias match or HostName match).  Falls back to "user@address".
resolve_ssh_target() {
    local addr="$1" user="$2"
    if [[ -f "$SSH_CONFIG" ]]; then
        while IFS='|' read -r alias hn _; do
            # Direct alias match
            if [[ $alias == "$addr" ]]; then
                printf '  \e[90mℹ  SSH config entry '\''%s'\'' will be used.\e[0m\n' "$alias" >&2
                printf '%s@%s' "$user" "$alias"
                return 0
            fi
            # HostName match
            if [[ -n $hn && $hn == "$addr" ]]; then
                printf '  \e[90mℹ  SSH config entry '\''%s'\'' found for %s — key from config will be used.\e[0m\n' \
                    "$alias" "$addr" >&2
                printf '%s@%s' "$user" "$alias"
                return 0
            fi
        done < <(get_configured_ssh_hosts)
    fi
    printf '%s@%s' "$user" "$addr"
}

# ─── SSH key operations ───────────────────────────────────────────────────────

# TCP port-22 pre-check.  Returns 0 if reachable, 1 if not.
_tcp_check() {
    local host="$1"
    timeout 3 bash -c "echo >/dev/tcp/$host/22" 2>/dev/null
}

test_ssh_connection() {
    local user="$1" host="$2" identity="${3:-}"
    local target
    target=$(resolve_ssh_target "$host" "$user")

    if ! _tcp_check "$host"; then
        printf '  \e[31m❌ Connection refused: %s is not accepting SSH connections on port 22.\e[0m\n' "$host"
        return 1
    fi

    local -a ssh_args=()
    if [[ -n $identity ]]; then
        ssh_args+=(-i "$identity" -o BatchMode=yes)
    fi
    ssh_args+=(-o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new \
               "$target" "echo SSH Connection Successful")

    local result
    result=$(ssh "${ssh_args[@]}" 2>&1) || true

    if printf '%s' "$result" | grep -qE "Name or service not known|Could not resolve hostname"; then
        printf '  \e[31m❌ DNS error: Could not resolve %s.\e[0m\n' "$host"
        return 1
    elif printf '%s' "$result" | grep -q "Permission denied"; then
        if [[ -n $identity ]]; then
            printf '  \e[33m⚠️  Key rejected or passphrase required — add key to ssh-agent first.\e[0m\n'
        else
            printf '  \e[33m⚠️  SSH reachable, but permission denied for user '\''%s'\''.\e[0m\n' "$user"
        fi
        return 0
    else
        printf '  \e[32m✅ SSH connection to %s is successful.\e[0m\n' "$host"
        return 0
    fi
}

# Generate an ED25519 key pair.
add_ssh_key_in_host() {
    local keyname="$1" comment="$2"
    local keypath="$SSH_DIR/$keyname"

    printf '  \e[36mPassphrase\e[0m \e[90m(empty = passwordless)\e[0m  '
    local passphrase
    IFS= read -r -s passphrase 2>/dev/null || passphrase=''
    printf '\n'

    local stars
    if [[ -n $passphrase ]]; then
        stars=$(printf '%*s' "${#passphrase}" '' | tr ' ' '*')
    else
        stars=$'\e[90m(none)\e[0m'
    fi
    printf '\n'
    printf '  \e[90m  key      \e[0m\e[36m%s\e[0m\n' "$keyname"
    printf '  \e[90m  comment  \e[0m\e[36m%s\e[0m\n' "$comment"
    printf '  \e[90m  password \e[0m\e[90m%s\e[0m\n\n' "$stars"
    printf '  \e[90mGenerating SSH key…\e[0m\n'

    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    ssh-keygen -t ed25519 -f "$keypath" -C "$comment" -N "$passphrase"
    chmod 600 "$keypath"

    printf '  \e[32m✓\e[0m  \e[36m%s\e[0m  generated.\n' "$keypath"
}

# Add or update a Host block in ~/.ssh/config.
add_ssh_key_to_host_config() {
    local keyname="$1" host_name="$2" host_addr="$3" remote_user="$4"
    local keypath="$SSH_DIR/$keyname"
    local identity_line="    IdentityFile $keypath"

    if ! find_private_key "$keyname"; then
        printf '  \e[31m❌ Could not find private SSH key at %s\e[0m\n' "$keypath"
        return 1
    fi

    local cfg
    cfg=$(find_config_file) || {
        # Config doesn't exist — create it
        mkdir -p "$SSH_DIR"
        touch "$SSH_CONFIG"
        chmod 600 "$SSH_CONFIG"
        cfg="$SSH_CONFIG"
    }

    _get_host_block "$host_name"
    if [[ -n $_HOST_BLOCK ]]; then
        # Block exists — add IdentityFile if missing
        if printf '%s\n' "$_HOST_BLOCK" | grep -qF "${identity_line#    }"; then
            printf '  \e[33m⚠  IdentityFile already exists under Host %s.\e[0m\n' "$host_name"
            return 0
        fi
        # Insert after last IdentityFile line, or after Host line
        local new_block
        new_block=$(printf '%s\n' "$_HOST_BLOCK" | awk -v il="$identity_line" '
            { lines[NR]=$0 }
            /^[[:space:]]*IdentityFile[[:space:]]/ { last_id=NR }
            END {
                ins = (last_id > 0) ? last_id : 1
                for (i=1; i<=NR; i++) {
                    print lines[i]
                    if (i == ins) print il
                }
            }
        ')
        # Replace old block in file
        local esc; esc=$(_regex_escape "$_HOST_BLOCK")
        local new_esc; new_esc=$(printf '%s\n' "$new_block" | sed 's/[&/\\]/\\&/g')
        perl -0777 -i -pe "s/\Q${_HOST_BLOCK}\E/${new_block}/" "$SSH_CONFIG" 2>/dev/null || \
            python3 -c "
import sys, re
old=open('$SSH_CONFIG').read()
new=old.replace(open('/dev/stdin').read().rstrip('\n'), '''${new_block}''', 1)
open('$SSH_CONFIG','w').write(new)
" <<< "$_HOST_BLOCK" 2>/dev/null || {
            # Fallback: simple awk replacement
            printf '%s\n' "$new_block" >> "$SSH_CONFIG"
        }
        printf '  \e[32m✅ IdentityFile added to existing Host %s.\e[0m\n' "$host_name"
    else
        # Create new block
        local entry
        entry=$(printf '\nHost %s\n    HostName %s\n    User %s\n    IdentityFile %s\n' \
            "$host_name" "$host_addr" "$remote_user" "$keypath")
        printf '%s' "$entry" >> "$SSH_CONFIG"
        printf '  \e[32m✅ SSH config block created for %s.\e[0m\n' "$host_name"
        printf '  \e[36mℹ  Connect with: ssh %s\e[0m\n' "$host_name"
    fi
}

# Remove all IdentityFile lines referencing KeyName from the named Host block.
remove_identity_file_from_config_block() {
    local keyname="$1" host_alias="$2"
    [[ -f "$SSH_CONFIG" ]] || { printf '  \e[33m⚠  No SSH config found.\e[0m\n'; return 1; }

    _get_host_block "$host_alias"
    if [[ -z $_HOST_BLOCK ]]; then
        printf '  \e[33m⚠  No config block found for '\''%s'\''.\e[0m\n' "$host_alias"
        return 1
    fi

    local esc; esc=$(_regex_escape "$keyname")
    local new_block
    new_block=$(printf '%s\n' "$_HOST_BLOCK" | \
        grep -vE "^\s*IdentityFile\s+.*[/\\\\]?${esc}\s*$" || true)

    if [[ "$new_block" == "$_HOST_BLOCK" ]]; then
        printf '  \e[90mℹ  Key '\''%s'\'' not found in config block '\''%s'\''.\e[0m\n' \
            "$keyname" "$host_alias"
        return 0
    fi

    # Replace in file using perl
    perl -0777 -i -pe "s/\Q${_HOST_BLOCK}\E/${new_block}/" "$SSH_CONFIG" 2>/dev/null || \
        python3 -c "
f='$SSH_CONFIG'
old=open(f).read()
open(f,'w').write(old.replace('''${_HOST_BLOCK}''', '''${new_block}''', 1))
" 2>/dev/null
    printf '  \e[32m✅ IdentityFile '\''%s'\'' removed from config block '\''%s'\''.\e[0m\n' \
        "$keyname" "$host_alias"
}

# Remove IdentityFile lines for a key from a host block (by host alias).
remove_identity_file_from_config_entry() {
    local keyname="$1" host_name="$2"
    remove_identity_file_from_config_block "$keyname" "$host_name"
}

# Install a public key on a remote machine and register in ~/.ssh/config.
install_ssh_key_on_remote() {
    local keyname="$1"

    local pubkey
    pubkey=$(get_public_key "$keyname") || return 1

    local host_addr
    host_addr=$(read_remote_host_address "$DEFAULT_SUBNET_PREFIX") || return 1
    local selected_alias="$_LAST_SELECTED_ALIAS"
    local remote_user
    remote_user=$(read_remote_user "$DEFAULT_USER") || return 1

    local target
    target=$(resolve_ssh_target "$host_addr" "$remote_user")

    local id_lookup="${selected_alias:-$host_addr}"
    local k
    while IFS= read -r k; do
        printf '  \e[90m🔑 Using key: %s\e[0m\n' "$k"
    done < <(get_identity_files_for_host "$id_lookup")

    printf '  🔃 Connecting to %s...\n' "$target"

    local remote_hostname
    if [[ -n $DEFAULT_PASSWORD ]] && command -v sshpass &>/dev/null; then
        printf '  \e[90mℹ  Using sshpass with stored password.\e[0m\n'
        remote_hostname=$(printf '%s\n' "$pubkey" | \
            sshpass -p "$DEFAULT_PASSWORD" ssh -o StrictHostKeyChecking=accept-new \
            "$target" 'mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname' 2>&1) || {
            printf '  \e[31m❌ Failed to inject SSH key. Check network, credentials, or host status.\e[0m\n'
            return 1
        }
    else
        remote_hostname=$(printf '%s\n' "$pubkey" | \
            ssh "$target" 'mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname' 2>&1) || {
            printf '  \e[31m❌ Failed to inject SSH key. Check network, credentials, or host status.\e[0m\n'
            return 1
        }
    fi

    printf '  \e[32m✅ SSH Public Key installed successfully.\e[0m\n'
    local default_alias="${selected_alias:-$remote_hostname}"
    printf '  \e[90m🏷  Remote hostname: %s\e[0m\n' "$remote_hostname"

    local host_alias
    host_alias=$(read_host_with_default "Name this Host in ~/.ssh/config:" "$default_alias") || \
        host_alias="$default_alias"
    [[ -z $host_alias ]] && host_alias="$default_alias"

    printf '  Registering key to SSH config as '\''%s'\''...\n' "$host_alias"
    add_ssh_key_to_host_config "$keyname" "$host_alias" "$host_addr" "$remote_user"
}

deploy_ssh_key_to_remote() {
    local keyname="$1"
    if ! find_private_key "$keyname"; then
        printf '\n%s\e[33m🔑 Key does not exist. Generating...\e[0m\n' "$P"
        local comment
        comment=$(read_ssh_key_comment "${keyname}${DEFAULT_COMMENT_SUFFIX}")
        add_ssh_key_in_host "$keyname" "$comment"
    else
        printf '\n%s\e[36mℹ  Key already exists. Proceeding with installation...\e[0m\n\n' "$P"
    fi
    install_ssh_key_on_remote "$keyname"
}

# Remove a public key from a remote's authorized_keys using awk on the remote.
remove_ssh_key_from_remote() {
    local remote_user="$1" remote_host="$2" keyname="$3"

    local pubkey
    pubkey=$(get_public_key "$keyname") || return 1

    local target
    target=$(resolve_ssh_target "$remote_host" "$remote_user")
    local k
    while IFS= read -r k; do
        printf '  \e[90m🔑 Using key: %s\e[0m\n' "$k"
    done < <(get_identity_files_for_host "$remote_host")

    printf '\n  \e[33m🔒 Will connect to remove the public key from %s:\n  %s\e[0m\n\n' \
        "$target" "$(printf '%s' "$pubkey" | tr -d '\n')"

    local remote_cmd
    remote_cmd="TMP_FILE=\$(mktemp) && printf '%s\n' '${pubkey}' > \$TMP_FILE && \
awk 'NR==FNR { keys[\$0]; next } !(\$0 in keys)' \$TMP_FILE ~/.ssh/authorized_keys \
> ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys \
&& rm -f \$TMP_FILE"

    if ssh "$target" "$remote_cmd"; then
        printf '  \e[32m✅ SSH key removed from remote authorized_keys.\e[0m\n'
        # Offer to delete local key
        local priv="$SSH_DIR/$keyname" pub="$SSH_DIR/${keyname}.pub"
        _do_delete_local_key() {
            [[ -f $priv ]] && rm -f "$priv" && printf '  \e[32m🗑  Deleted: %s\e[0m\n' "$priv"
            [[ -f $pub  ]] && rm -f "$pub"  && printf '  \e[32m🗑  Deleted: %s\e[0m\n' "$pub"
        }
        confirm_user_choice \
            "  Remove local key '$keyname' from THIS machine? ⚠" \
            "n" \
            _do_delete_local_key || true
    else
        printf '  \e[31m❌ Failed to remove the SSH key from remote.\e[0m\n'
    fi
}

register_remote_host_config() {
    printf '  \e[36mEnter the IP or hostname of the remote machine (not yet in config).\e[0m\n'
    local host_addr
    host_addr=$(read_colored_input "  Remote IP / hostname" cyan)
    [[ $host_addr =~ ^[0-9]{1,3}$ ]] && host_addr="${DEFAULT_SUBNET_PREFIX}.${host_addr}"
    if [[ -z $host_addr ]]; then return; fi

    local remote_user
    remote_user=$(read_remote_user "$DEFAULT_USER")
    local target="${remote_user}@${host_addr}"

    printf '  \e[90m🔃 Connecting to %s to read authorized_keys…\e[0m\n' "$target"
    local raw_keys
    raw_keys=$(ssh -o StrictHostKeyChecking=accept-new "$target" \
        "cat ~/.ssh/authorized_keys 2>/dev/null") || {
        printf '  \e[31m❌ Connection failed.\e[0m\n'
        return 1
    }

    if [[ -z $raw_keys ]]; then
        printf '  \e[33mℹ  No authorized_keys found on %s.\e[0m\n' "$target"
        return
    fi

    # Match local .pub files against remote authorized_keys
    local -a matches=()
    local pubfile
    for pubfile in "$SSH_DIR"/*.pub; do
        [[ -f $pubfile ]] || continue
        local content; content=$(cat "$pubfile")
        if printf '%s\n' "$raw_keys" | grep -qxF "$content"; then
            matches+=("$(basename "${pubfile%.pub}")")
        fi
    done

    if (( ${#matches[@]} == 0 )); then
        printf '  \e[33mℹ  No local public keys match authorized_keys on %s.\e[0m\n' "$target"
        printf '  \e[90mℹ  Install a key first via '\''Generate & Install'\'' or '\''Install SSH Key'\''.\e[0m\n'
        return
    fi

    printf '  \e[32m✅ Found %d matching local key(s):\e[0m\n' "${#matches[@]}"
    local m; for m in "${matches[@]}"; do printf '     \e[36m🔑 %s\e[0m\n' "$m"; done

    local chosen
    if (( ${#matches[@]} > 1 )); then
        select_from_list -s -p "Select key for the config block:" "${matches[@]}"
        (( _SELECT_CANCELLED )) && return
        chosen="$_SELECT_RESULT"
    else
        chosen="${matches[0]}"
    fi

    local host_alias
    host_alias=$(read_host_with_default "  Alias for this host in ~/.ssh/config:" "$host_addr") || \
        host_alias="$host_addr"
    [[ -z $host_alias ]] && host_alias="$host_addr"

    add_ssh_key_to_host_config "$chosen" "$host_alias" "$host_addr" "$remote_user"
}

deploy_promoted_key() {
    printf '  \e[36mWhich key do you want to demote (remove from remote)?\e[0m\n'
    local key_to_remove; key_to_remove=$(read_ssh_key_name) || return 1

    printf '  \e[36mFrom which remote machine?\e[0m\n'
    local remote_host_name; remote_host_name=$(read_remote_host_name "$DEFAULT_SUBNET_PREFIX") || return 1

    printf '  \e[36mReplace with which key?\e[0m\n'
    local key_new; key_new=$(read_ssh_key_name) || return 1
    deploy_ssh_key_to_remote "$key_new"

    local remote_addr; remote_addr=$(get_ip_from_host_config "$remote_host_name")
    local remote_user; remote_user=$(get_user_from_host_config "$remote_host_name")

    _do_demote() {
        remove_ssh_key_from_remote "$remote_user" "${remote_addr:-$remote_host_name}" "$key_to_remove"
    }
    confirm_user_choice \
        "  Remove demoted key '$key_to_remove' from remote '$remote_host_name'? ⚠" \
        "n" \
        _do_demote || true
}

# ─── Config file display / edit ───────────────────────────────────────────────

# Interactive pager for ~/.ssh/config with syntax highlighting.
show_ssh_config_file() {
    if [[ ! -f "$SSH_CONFIG" ]]; then
        printf '  \e[31m❌ SSH config not found at %s\e[0m\n' "$SSH_CONFIG"
        return
    fi

    # Build highlighted lines array
    local -a out=()
    local line
    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*$ ]]; then
            out+=("")
        elif [[ $line =~ ^[[:space:]]*# ]]; then
            out+=("$(printf '\e[90m  %s\e[0m' "$line")")
        elif [[ $line =~ ^(Host)[[:space:]]+(.+)$ ]]; then
            out+=("")
            out+=("$(printf '  \e[1;96mHost\e[0m \e[97m%s\e[0m' "${BASH_REMATCH[2]}")")
        elif [[ $line =~ ^[[:space:]]*(IdentityFile)[[:space:]]+(.+)$ ]]; then
            out+=("$(printf '    \e[93m%s\e[0m \e[32m%s\e[0m' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")")
        elif [[ $line =~ ^[[:space:]]*(HostName|User|Port|ForwardAgent|ServerAliveInterval|ServerAliveCountMax|IdentitiesOnly|AddKeysToAgent)[[:space:]]+(.+)$ ]]; then
            out+=("$(printf '    \e[93m%s\e[0m \e[37m%s\e[0m' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")")
        elif [[ $line =~ ^[[:space:]]*([A-Za-z]+)[[:space:]]+(.+)$ ]]; then
            out+=("$(printf '    \e[33m%s\e[0m \e[37m%s\e[0m' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")")
        else
            out+=("$(printf '  \e[37m%s\e[0m' "$line")")
        fi
    done < "$SSH_CONFIG"

    local total=${#out[@]}
    _term_size
    local content_rows=$(( TERM_H - 5 ))
    (( content_rows < 1 )) && content_rows=1
    local off=0

    printf '\e[?25l'

    while true; do
        (( off < 0 )) && off=0
        local max_off=$(( total - content_rows ))
        (( max_off < 0 )) && max_off=0
        (( off > max_off )) && off=$max_off

        local rule; rule=$(_repeat '─' "$(( TERM_W - 4 > 0 ? TERM_W - 4 : 0 ))")
        local hdr="  $SSH_CONFIG"
        local hfill; hfill=$(_repeat ' ' "$(( TERM_W - ${#hdr} > 0 ? TERM_W - ${#hdr} : 0 ))")
        local f
        f="$(printf '\e[2J\e[H')"
        f+="$(printf '\e[2;1H  \e[96m%s\e[0m\e[K' "$rule")"
        f+="$(printf '\e[3;1H\e[48;5;23m\e[1;97m%s%s\e[0m' "$hdr" "$hfill")"
        f+="$(printf '\e[4;1H  \e[96m%s\e[0m\e[K' "$rule")"

        local row=5 i
        for (( i=off; i<off+content_rows && i<total; i++ )); do
            f+="$(printf '\e[%d;1H%s\e[K' "$row" "${out[$i]}")"
            (( row++ ))
        done
        while (( row <= TERM_H - 1 )); do
            f+="$(printf '\e[%d;1H\e[K' "$row")"
            (( row++ ))
        done

        local pct
        if (( total <= content_rows )); then pct="all"
        else pct="$(( (off + content_rows) * 100 / total ))%"
        fi
        local status="  ↑↓ / PgUp / PgDn  scroll     Home  top     End  bottom     Q  close     ${pct}  "
        local spad; spad=$(_repeat ' ' "$(( TERM_W - ${#status} > 0 ? TERM_W - ${#status} : 0 ))")
        f+="$(printf '\e[%d;1H\e[7m%s%s\e[0m' "$TERM_H" "$status" "$spad")"

        printf '%s' "$f"

        _read_key
        case "$KEY" in
            "$KEY_UP")   (( off-- )) ;;
            "$KEY_DOWN") (( off++ )) ;;
            "$KEY_PGUP") (( off -= content_rows )) ;;
            "$KEY_PGDN") (( off += content_rows )) ;;
            "$KEY_HOME"|"$KEY_HOME2") off=0 ;;
            "$KEY_END"|"$KEY_END2")   off=$(( total - content_rows )) ;;
            q|Q) break ;;
        esac

        # Detect terminal resize
        local nw nh
        nw=$(tput cols 2>/dev/null || echo 80)
        nh=$(tput lines 2>/dev/null || echo 24)
        if (( nw != TERM_W || nh != TERM_H )); then
            TERM_W=$nw; TERM_H=$nh
            content_rows=$(( TERM_H - 5 ))
            (( content_rows < 1 )) && content_rows=1
        fi
    done

    printf '\e[?25h'
}

edit_ssh_config_file() {
    if [[ ! -f "$SSH_CONFIG" ]]; then
        printf '  \e[31m❌ SSH config not found at %s\e[0m\n' "$SSH_CONFIG"
        return
    fi

    local editor=""
    if [[ -n ${VISUAL:-} ]] && command -v "$VISUAL" &>/dev/null; then
        editor="$VISUAL"
    elif [[ -n ${EDITOR:-} ]] && command -v "$EDITOR" &>/dev/null; then
        editor="$EDITOR"
    else
        local e
        for e in nvim vim nano vi; do
            command -v "$e" &>/dev/null && editor="$e" && break
        done
    fi
    [[ -z $editor ]] && editor="vi"

    printf '  \e[90mOpening in %s...\e[0m\n' "$editor"
    "$editor" "$SSH_CONFIG" && printf '  \e[32m✅ Done.\e[0m\n' || \
        printf '  \e[31m❌ Could not open editor '\''%s'\''.\e[0m\n' "$editor"
}

remove_host_from_ssh_config() {
    local -a aliases=()
    while IFS='|' read -r alias _ _; do aliases+=("$alias"); done < <(get_configured_ssh_hosts)

    local host_name=""
    if (( ${#aliases[@]} > 0 )); then
        select_from_list -p "Select host to remove" "${aliases[@]}"
        (( _SELECT_CANCELLED == 0 )) && host_name="$_SELECT_RESULT"
    fi
    if [[ -z $host_name ]]; then
        host_name=$(read_colored_input "  Enter the Host alias to remove" cyan)
    fi
    if [[ -z $host_name ]]; then
        printf '  \e[31m❗ Host alias is required.\e[0m\n'
        return
    fi

    if [[ ! -f "$SSH_CONFIG" ]]; then
        printf '  \e[31m❌ SSH config not found at %s\e[0m\n' "$SSH_CONFIG"
        return
    fi

    _get_host_block "$host_name"
    if [[ -z $_HOST_BLOCK ]]; then
        printf '  \e[33m⚠️  No Host block found for '\''%s'\''\e[0m\n' "$host_name"
        return
    fi

    printf '\n  \e[90mBlock that will be removed:\e[0m\n'
    printf '\e[37m%s\e[0m\n' "$_HOST_BLOCK"

    local confirm
    confirm=$(read_colored_input "Remove this block? [y/N]" yellow)
    if [[ ! ${confirm,,} =~ ^(y|yes)$ ]]; then
        printf '  \e[33m❌ Cancelled.\e[0m\n'
        return
    fi

    # Remove the block using perl
    perl -0777 -i -pe "s/\Q${_HOST_BLOCK}\E//" "$SSH_CONFIG" 2>/dev/null || \
        python3 -c "
f='$SSH_CONFIG'
content=open(f).read()
open(f,'w').write(content.replace('''${_HOST_BLOCK}''', '', 1))
" 2>/dev/null

    # Clean up trailing whitespace
    local cleaned; cleaned=$(sed -e 's/[[:space:]]*$//' -e '/^$/N;/^\n$/d' "$SSH_CONFIG")
    printf '%s\n' "$cleaned" > "$SSH_CONFIG"

    printf '  \e[32m✅ Host '\''%s'\'' removed from SSH config.\e[0m\n' "$host_name"
}

show_ssh_key_inventory() {
    if [[ ! -d "$SSH_DIR" ]]; then
        printf '  \e[31m❌ .ssh directory not found at %s\e[0m\n' "$SSH_DIR"
        return
    fi

    # Collect all key names (union of priv + pub basenames)
    local -A has_pub=() has_priv=()
    local f
    for f in "$SSH_DIR"/*.pub; do
        [[ -f $f ]] && has_pub["$(basename "${f%.pub}")"]="1"
    done
    while IFS= read -r k; do has_priv["$k"]="1"; done < <(get_available_ssh_keys)

    # Union
    local -A all_keys=()
    local k
    for k in "${!has_pub[@]}" "${!has_priv[@]}"; do all_keys["$k"]="1"; done

    if (( ${#all_keys[@]} == 0 )); then
        printf '  \e[33mℹ️  No key files found in %s\e[0m\n' "$SSH_DIR"
        return
    fi

    # Build usage map: keyfile → "host1, host2"
    local -A usage_map=()
    if [[ -f "$SSH_CONFIG" ]]; then
        while IFS='|' read -r alias _ _; do
            _get_host_block "$alias"
            local idf
            while IFS= read -r idf; do
                local kname; kname=$(basename "$idf")
                if [[ -n ${usage_map[$kname]+x} ]]; then
                    usage_map["$kname"]+=",$alias"
                else
                    usage_map["$kname"]="$alias"
                fi
            done < <(printf '%s\n' "$_HOST_BLOCK" | \
                grep -E '^\s*IdentityFile\s+' | \
                sed -E 's/^\s*IdentityFile\s+//; s/^"(.*)"$/\1/' | \
                xargs -I{} basename {} 2>/dev/null)
        done < <(get_configured_ssh_hosts)
    fi

    # Sort keys
    local -a sorted_keys=()
    while IFS= read -r k; do sorted_keys+=("$k"); done < <(printf '%s\n' "${!all_keys[@]}" | sort)

    # Column widths
    local w_num=${#sorted_keys[@]}
    w_num=${#w_num}
    local w_key=3 w_use=5
    for k in "${sorted_keys[@]}"; do
        (( ${#k} > w_key )) && w_key=${#k}
        local u="${usage_map[$k]:-}"
        (( ${#u} > w_use )) && w_use=${#u}
    done

    local w_pub=3 w_prv=4
    local top mid bot hdr
    local h1=$(( w_num + 2 )) h2=$(( w_key + 2 )) h3=$(( w_pub + 2 )) h4=$(( w_prv + 1 )) h5=$(( w_use + 2 ))
    local r1; r1=$(_repeat '─' "$h1")
    local r2; r2=$(_repeat '─' "$h2")
    local r3; r3=$(_repeat '─' "$h3")
    local r4; r4=$(_repeat '─' "$h4")
    local r5; r5=$(_repeat '─' "$h5")
    top="  ┌${r1}┬${r2}┬${r3}┬${r4}┬${r5}┐"
    hdr="  │ $(printf '%*s' "$w_num" '#') │ $(printf '%-*s' "$w_key" 'Key') │ Pub │ Prv │ $(printf '%-*s' "$w_use" 'Usage') │"
    mid="  ├${r1}┼${r2}┼${r3}┼${r4}┼${r5}┤"
    bot="  └${r1}┴${r2}┴${r3}┴${r4}┴${r5}┘"

    local -a table_lines=()
    table_lines+=("$(printf '\e[97m%s\e[0m' "$top")")
    table_lines+=("$(printf '\e[1;37m%s\e[0m' "$hdr")")
    table_lines+=("$(printf '\e[97m%s\e[0m' "$mid")")

    local i=1
    for k in "${sorted_keys[@]}"; do
        local pub_c prv_c
        if [[ -n ${has_pub[$k]+x} ]]; then pub_c="$(printf '\e[32m  ✓  \e[0m')"
        else                                  pub_c="$(printf '\e[31m  ✗  \e[0m')"; fi
        if [[ -n ${has_priv[$k]+x} ]]; then prv_c="$(printf '\e[32m  ✓  \e[0m')"
        else                                   prv_c="$(printf '\e[31m  ✗  \e[0m')"; fi
        local usage="${usage_map[$k]:-}"
        local row
        row="  $(printf '\e[97m│\e[0m') $(printf '%*d' "$w_num" "$i") $(printf '\e[97m│\e[0m') $(printf '\e[36m%-*s\e[0m' "$w_key" "$k") $(printf '\e[97m│\e[0m')${pub_c}$(printf '\e[97m│\e[0m')${prv_c}$(printf '\e[97m│\e[0m') $(printf '\e[37m%-*s\e[0m' "$w_use" "$usage") $(printf '\e[97m│\e[0m')"
        table_lines+=("$row")
        (( i++ ))
    done
    table_lines+=("$(printf '\e[97m%s\e[0m' "$bot")")

    show_paged "${table_lines[@]}"
}

# ─── Menu dispatcher ──────────────────────────────────────────────────────────
# Returns 0 normally; returns 1 to signal "skip wait_user_acknowledge"
# (pager and editor handle their own exits).
invoke_menu_choice() {
    local choice="$1"
    case "$choice" in
        1)  # Generate & Install SSH Key on A Remote Machine
            printf '\n'
            local keyname; keyname=$(read_ssh_key_name) || return 0
            deploy_ssh_key_to_remote "$keyname"
            ;;
        15) # Install SSH Key on A Remote Machine (key must already exist)
            local keyname; keyname=$(read_ssh_key_name) || return 0
            if ! find_private_key "$keyname"; then
                printf '  \e[31m❌ Key '\''%s'\'' not found locally. Use '\''Generate & Install'\'' to create it first.\e[0m\n' "$keyname"
                return 0
            fi
            install_ssh_key_on_remote "$keyname"
            ;;
        2)  # Test SSH Connection
            local host; host=$(read_remote_host_address "$DEFAULT_SUBNET_PREFIX") || return 0
            local user; user=$(read_remote_user "$DEFAULT_USER") || return 0
            local sel_alias="$_LAST_SELECTED_ALIAS"

            # Find configured identity files for this alias
            local -a cfg_keys=()
            if [[ -n $sel_alias ]]; then
                while IFS= read -r k; do cfg_keys+=("$k"); done \
                    < <(get_identity_files_for_host "$sel_alias")
            fi

            if (( ${#cfg_keys[@]} > 1 )); then
                local all_label="── Test ALL (${#cfg_keys[@]} keys)"
                select_from_list -p "Select key to test:" "$all_label" "${cfg_keys[@]}"
                if (( _SELECT_CANCELLED == 0 )) && [[ -n $_SELECT_RESULT ]]; then
                    local sel="$_SELECT_RESULT"
                    if [[ $sel == "── Test ALL"* ]]; then
                        local first=1 k
                        for k in "${cfg_keys[@]}"; do
                            (( first )) || printf '\n'
                            first=0
                            printf '  \e[90m🔑 Testing with key: %s\e[0m\n' "$k"
                            test_ssh_connection "$user" "$host" "$k"
                        done
                    else
                        printf '  \e[90m🔑 Using key: %s\e[0m\n' "$sel"
                        test_ssh_connection "$user" "$host" "$sel"
                    fi
                fi
            elif (( ${#cfg_keys[@]} == 1 )); then
                printf '  \e[90m🔑 Using key: %s\e[0m\n' "${cfg_keys[0]}"
                test_ssh_connection "$user" "$host" "${cfg_keys[0]}"
            else
                test_ssh_connection "$user" "$host"
            fi
            ;;
        3)  # Delete SSH Key From A Remote Machine
            local host; host=$(read_remote_host_address "$DEFAULT_SUBNET_PREFIX") || return 0
            local user; user=$(read_remote_user "$DEFAULT_USER") || return 0
            local sel_alias="$_LAST_SELECTED_ALIAS"
            local target; target=$(resolve_ssh_target "$host" "$user")
            local id_lookup="${sel_alias:-$host}"
            local k
            while IFS= read -r k; do
                printf '  \e[90m🔑 Using key: %s\e[0m\n' "$k"
            done < <(get_identity_files_for_host "$id_lookup")

            printf '  \e[90m🔃 Fetching authorized keys from %s…\e[0m\n' "$target"
            local raw_keys
            raw_keys=$(ssh "$target" "cat ~/.ssh/authorized_keys 2>/dev/null" 2>&1) || {
                printf '  \e[31m❌ Could not connect to %s.\e[0m\n' "$target"
                return 0
            }

            if [[ -z $raw_keys ]]; then
                printf '  \e[90mℹ  No authorized_keys found on %s.\e[0m\n' "$target"
                return 0
            fi

            # Match local .pub files against remote keys
            local -a matched_keys=() matched_labels=()
            local pubfile
            for pubfile in "$SSH_DIR"/*.pub; do
                [[ -f $pubfile ]] || continue
                local content; content=$(cat "$pubfile")
                if printf '%s\n' "$raw_keys" | grep -qxF "$content"; then
                    local kname; kname=$(basename "${pubfile%.pub}")
                    matched_keys+=("$kname")
                    matched_labels+=("$kname  ($pubfile)")
                fi
            done

            if (( ${#matched_keys[@]} == 0 )); then
                printf '  \e[33mℹ  No local public keys found in %s authorized_keys.\e[0m\n' "$target"
                return 0
            fi

            select_from_list -s -p "Select key to remove from remote:" "${matched_labels[@]}"
            (( _SELECT_CANCELLED )) && return 0
            [[ -z $_SELECT_RESULT ]] && return 0

            # Find the picked key name
            local picked_idx=0 i
            for (( i=0; i<${#matched_labels[@]}; i++ )); do
                [[ "${matched_labels[$i]}" == "$_SELECT_RESULT" ]] && picked_idx=$i && break
            done
            local picked_key="${matched_keys[$picked_idx]}"
            local pub_content; pub_content=$(cat "$SSH_DIR/${picked_key}.pub")

            # Remove from remote via awk
            local remote_cmd
            remote_cmd="TMP_FILE=\$(mktemp) && printf '%s\n' '${pub_content}' > \$TMP_FILE && \
awk 'NR==FNR { keys[\$0]; next } !(\$0 in keys)' \$TMP_FILE ~/.ssh/authorized_keys \
> ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys \
&& rm -f \$TMP_FILE"
            printf '  \e[33m🔒 Removing key '\''%s'\'' from %s…\e[0m\n' "$picked_key" "$target"
            if ssh "$target" "$remote_cmd"; then
                printf '  \e[32m✅ Key removed from remote authorized_keys.\e[0m\n'
            else
                printf '  \e[31m❌ Failed to remove key from remote.\e[0m\n'
                return 0
            fi

            # Optionally remove IdentityFile from config block
            if [[ -n $sel_alias ]]; then
                _rm_id_from_cfg() { remove_identity_file_from_config_block "$picked_key" "$sel_alias"; }
                confirm_user_choice \
                    "  Remove IdentityFile '$picked_key' from config block '$sel_alias'? ⚠" \
                    "y" _rm_id_from_cfg || true
            fi

            # Optionally delete local key files
            local priv="$SSH_DIR/$picked_key" pub="$SSH_DIR/${picked_key}.pub"
            _rm_local_key3() {
                [[ -f $priv ]] && rm -f "$priv" && printf '  \e[32m🗑  Deleted: %s\e[0m\n' "$priv"
                [[ -f $pub  ]] && rm -f "$pub"  && printf '  \e[32m🗑  Deleted: %s\e[0m\n' "$pub"
            }
            confirm_user_choice \
                "  Delete local key '$picked_key' from this machine? ⚠" \
                "n" _rm_local_key3 || true
            ;;
        4)  # Promote Key on A Remote Machine
            deploy_promoted_key
            ;;
        5)  # Generate SSH Key (without installation)
            local keyname; keyname=$(read_ssh_key_name) || return 0
            local comment; comment=$(read_ssh_key_comment "${keyname}${DEFAULT_COMMENT_SUFFIX}") || return 0
            add_ssh_key_in_host "$keyname" "$comment"
            ;;
        6)  # List SSH Keys
            show_ssh_key_inventory
            ;;
        7)  # Append SSH Key to Hostname in Host Config
            local keyname; keyname=$(read_ssh_key_name) || return 0
            local host_name; host_name=$(read_remote_host_name "$DEFAULT_SUBNET_PREFIX") || return 0
            local host_addr; host_addr=$(read_remote_host_address "$DEFAULT_SUBNET_PREFIX") || return 0
            local remote_user; remote_user=$(read_remote_user "$DEFAULT_USER") || return 0

            local keypath="$SSH_DIR/$keyname"
            local test_out
            test_out=$(ssh -i "$keypath" -o BatchMode=yes -o ConnectTimeout=6 \
                -o StrictHostKeyChecking=accept-new \
                "${remote_user}@${host_addr}" "echo ok" 2>&1) || true

            if [[ $test_out == "ok" ]]; then
                printf '  \e[32m✅ Key verified on %s.\e[0m\n' "$host_addr"
            else
                printf '  \e[33m⚠  Could not verify '\''%s'\'' on %s — it may not be installed yet.\e[0m\n' \
                    "$keyname" "$host_addr"
                local proceed
                proceed=$(read_host_with_default "Add to config anyway? (y/N):" "N") || proceed="N"
                [[ ${proceed,,} =~ ^y ]] || return 0
            fi
            add_ssh_key_to_host_config "$keyname" "$host_name" "$host_addr" "$remote_user"
            ;;
        8)  # Delete an SSH Key Locally
            local keyname; keyname=$(read_ssh_key_name) || return 0
            [[ -z $keyname ]] && return 0

            # Find hosts that reference this key
            local -a key_hosts=() key_host_labels=()
            while IFS='|' read -r alias hn user; do
                key_hosts+=("$alias|$hn|$user")
                if [[ -n $hn ]]; then key_host_labels+=("$alias  ($hn)")
                else key_host_labels+=("$alias"); fi
            done < <(get_hosts_using_key "$keyname")

            if (( ${#key_hosts[@]} > 0 )); then
                local all_label="── ALL  (${#key_hosts[@]} host$(( ${#key_hosts[@]} != 1 )) && echo s || true))"
                all_label="── ALL  (${#key_hosts[@]} host(s))"
                select_from_list -p "Remove key from remote host(s)  (Esc = skip remote)" \
                    "$all_label" "${key_host_labels[@]}"

                local -a targets_to_remove=()
                if (( _SELECT_CANCELLED == 0 )) && [[ -n $_SELECT_RESULT ]]; then
                    local sel="$_SELECT_RESULT"
                    if [[ $sel == "── ALL"* ]]; then
                        targets_to_remove=("${key_hosts[@]}")
                    else
                        local entry
                        for entry in "${key_hosts[@]}"; do
                            local a="${entry%%|*}"
                            [[ "$sel" == "$a"* ]] && targets_to_remove+=("$entry") && break
                        done
                    fi
                fi

                local entry
                for entry in "${targets_to_remove[@]}"; do
                    IFS='|' read -r r_alias r_hn r_user <<< "$entry"
                    local ruser="${r_user:-$DEFAULT_USER}"
                    local rhost="${r_hn:-$r_alias}"
                    printf '  \e[90m🔒 Removing key from %s…\e[0m\n' "$r_alias"
                    remove_ssh_key_from_remote "$ruser" "$rhost" "$keyname"
                done
            else
                printf '  \e[90mℹ  No configured hosts reference this key.\e[0m\n'
            fi

            # Delete local files
            local priv="$SSH_DIR/$keyname" pub="$SSH_DIR/${keyname}.pub"
            local deleted=0
            if [[ -f $priv ]]; then rm -f "$priv"; printf '  \e[32m🗑  Deleted: %s\e[0m\n' "$priv"; deleted=1; fi
            if [[ -f $pub  ]]; then rm -f "$pub";  printf '  \e[32m🗑  Deleted: %s\e[0m\n' "$pub";  deleted=1; fi
            if (( deleted )); then
                printf '  \e[32m✅ Key '\''%s'\'' removed locally.\e[0m\n' "$keyname"
            else
                printf '  \e[33m⚠  No local key files found for '\''%s'\''.\e[0m\n' "$keyname"
            fi
            ;;
        9)  # Remove an SSH Key From Config
            local -a all_hosts=()
            while IFS='|' read -r alias _ _; do all_hosts+=("$alias"); done < <(get_configured_ssh_hosts)
            if (( ${#all_hosts[@]} == 0 )); then
                printf '  \e[90mℹ  No configured hosts found in ~/.ssh/config.\e[0m\n'
                return 0
            fi
            select_from_list -s -p "Select host:" "${all_hosts[@]}"
            (( _SELECT_CANCELLED )) && return 0
            local host_name="$_SELECT_RESULT"
            [[ -z $host_name ]] && return 0

            _get_host_block "$host_name"
            local -a key_names=()
            while IFS= read -r kn; do
                key_names+=("$(basename "$kn")")
            done < <(printf '%s\n' "$_HOST_BLOCK" | \
                grep -E '^\s*IdentityFile\s+' | \
                sed -E 's/^\s*IdentityFile\s+//; s/^"(.*)"$/\1/' | \
                xargs -I{} basename {} 2>/dev/null)

            if (( ${#key_names[@]} == 0 )); then
                printf '  \e[90mℹ  No IdentityFile entries found under host '\''%s'\''.\e[0m\n' "$host_name"
                return 0
            fi
            select_from_list -p "Select key to remove from '$host_name':" "${key_names[@]}"
            (( _SELECT_CANCELLED )) && return 0
            [[ -z $_SELECT_RESULT ]] && return 0
            remove_identity_file_from_config_entry "$_SELECT_RESULT" "$host_name"
            ;;
        10) # Help: Best Practices
            printf '\n'
            printf '  \e[36mBest Practices\e[0m\n'
            printf '  \e[90m──────────────\e[0m\n'
            printf '  \e[36m1. CTs demo'\''d over LAN         → shared key (e.g. demo-lan)\e[0m\n'
            printf '  \e[36m2. CTs in development over LAN → shared key (e.g. dev-lan)\e[0m\n'
            printf '  \e[36m3. CTs promoted into the stack → shared key (e.g. prod-lan)\e[0m\n'
            printf '  \e[31m4. CTs accessed over the WAN   → individual key (e.g. sonarr-wan)\e[0m\n'
            ;;
        11) # Conf: Global Defaults  (inline TUI editor)
            _run_conf_editor
            return 1  # conf has its own Q-to-exit; skip wait_user_acknowledge
            ;;
        12) # Remove Host from SSH Config
            remove_host_from_ssh_config
            ;;
        13) # View SSH Config
            show_ssh_config_file
            return 1  # pager has its own exit; skip wait_user_acknowledge
            ;;
        14) # Edit SSH Config
            edit_ssh_config_file
            return 1  # editor returns directly; skip wait_user_acknowledge
            ;;
        16) # List Authorized Keys on Remote Host
            local host; host=$(read_remote_host_address "$DEFAULT_SUBNET_PREFIX") || return 0
            local user; user=$(read_remote_user "$DEFAULT_USER") || return 0
            local target; target=$(resolve_ssh_target "$host" "$user")
            printf '  \e[90m🔑 Fetching authorized_keys from %s…\e[0m\n' "$target"
            local keys
            keys=$(ssh "$target" "cat ~/.ssh/authorized_keys 2>/dev/null" 2>&1) || {
                printf '  \e[31m❌ Failed to fetch authorized_keys.\e[0m\n'
                return 0
            }
            if [[ -z $keys ]]; then
                printf '  \e[90mℹ  No authorized_keys found on %s.\e[0m\n' "$target"
            else
                printf '  \e[1;37mAuthorized keys on %s:\e[0m\n' "$target"
                local i=1 line
                while IFS= read -r line; do
                    [[ -z $line ]] && continue
                    printf '  \e[90m%3d\e[0m  \e[36m%s\e[0m\n' "$i" "$line"
                    (( i++ ))
                done <<< "$keys"
            fi
            ;;
        17) # Add Config Block for Existing Remote Key
            register_remote_host_config
            ;;
    esac
    return 0
}

# Conf editor for Global Defaults (inline TUI, spawned from the main menu).
_run_conf_editor() {
    local -a field_names=( DEFAULT_USER DEFAULT_SUBNET_PREFIX DEFAULT_COMMENT_SUFFIX DEFAULT_PASSWORD )
    local -a field_labels=( "Default Username      " "Default Subnet Prefix " "Default Comment Suffix" "Default Password      " )
    local conf_sel=0 conf_run=1

    printf '\e[?25l'
    while (( conf_run )); do
        _term_size
        local rule; rule=$(_repeat '─' "$(( TERM_W - 4 > 0 ? TERM_W - 4 : 0 ))")
        local title="Conf: Global Defaults"
        local tpad; tpad=$(_repeat ' ' "$(( (TERM_W - 4 - ${#title}) / 2 > 0 ? (TERM_W - 4 - ${#title}) / 2 : 0 ))")
        local cf
        cf="$(printf '\e[2J\e[H')"
        cf+="$(printf '\e[2;1H  \e[96m%s\e[0m\e[K' "$rule")"
        cf+="$(printf '\e[3;1H  \e[96m%s%s\e[0m\e[K' "$tpad" "$title")"
        cf+="$(printf '\e[4;1H  \e[96m%s\e[0m\e[K' "$rule")"
        local i
        for (( i=0; i<${#field_names[@]}; i++ )); do
            local varname="${field_names[$i]}"
            local val="${!varname}"
            local disp
            if [[ $varname == "DEFAULT_PASSWORD" && -n $val ]]; then
                disp=$(printf '%*s' "${#val}" '' | tr ' ' '*')
            else
                disp="$val"
            fi
            local row=$(( 6 + i ))
            cf+="$(printf '\e[%d;1H' "$row")"
            if (( i == conf_sel )); then
                cf+="$(printf '  \e[1;36m▶ %s  \e[0;36m%s\e[0m\e[K' "${field_labels[$i]}" "$disp")"
            else
                cf+="$(printf '  \e[0;37m    %s  \e[90m%s\e[0m\e[K' "${field_labels[$i]}" "$disp")"
            fi
        done
        local hint="  ↑↓  navigate     Enter  edit     Q  back  "
        local hpad; hpad=$(_repeat ' ' "$(( TERM_W - ${#hint} > 0 ? TERM_W - ${#hint} : 0 ))")
        cf+="$(printf '\e[%d;1H\e[7m%s%s\e[0m' "$TERM_H" "$hint" "$hpad")"
        printf '%s' "$cf"

        _read_key
        case "$KEY" in
            "$KEY_UP")   (( conf_sel = (conf_sel - 1 + ${#field_names[@]}) % ${#field_names[@]} )) ;;
            "$KEY_DOWN") (( conf_sel = (conf_sel + 1) % ${#field_names[@]} )) ;;
            "$KEY_ENTER"|"$KEY_ENTER2")
                local row=$(( 6 + conf_sel ))
                printf '\e[%d;1H\e[K  \e[1;33m▶ %s  \e[0;33m' "$row" "${field_labels[$conf_sel]}"
                printf '\e[?25h'
                local new_val
                read -r new_val || new_val=''
                printf '\e[?25l'
                if [[ -n $new_val ]]; then
                    printf -v "${field_names[$conf_sel]}" '%s' "$new_val"
                fi
                ;;
            q|Q) conf_run=0 ;;
        esac
    done
    printf '\e[?25h'
    printf '\n'
    printf '  \e[32m✅ Defaults updated for this session.\e[0m\n'
    printf '  \e[33mℹ  To persist: pass as script arguments (--user, --subnet, etc.)\e[0m\n'
}
