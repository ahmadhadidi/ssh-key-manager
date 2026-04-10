# lib/tui.sh — Terminal helpers and TUI widgets
# Sourced by ssh-key-manager.sh — do not execute directly.
[[ -n "${_TUI_SH_LOADED:-}" ]] && return 0
_TUI_SH_LOADED=1

# ─── Debug logging ────────────────────────────────────────────────────────────

_dbg() {
    (( VERBOSE )) || return 0
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$_LOG_FILE"
}

# ─── Terminal helpers ─────────────────────────────────────────────────────────

_term_size() {
    TERM_W=$(tput cols  2>/dev/null || echo 80)
    TERM_H=$(tput lines 2>/dev/null || echo 24)
}

_regex_escape() {
    printf '%s' "$1" | sed 's/[.^$*+?{}|\\()\[\]]/\\&/g'
}

# Repeat a character N times — pure bash loop, safe for multi-byte characters.
_repeat() {
    local char="$1" n="$2" s="" i
    for (( i=0; i<n; i++ )); do s+="$char"; done
    printf '%s' "$s"
}

_max() { (( $1 >= $2 )) && printf '%d' "$1" || printf '%d' "$2"; }
_min() { (( $1 <= $2 )) && printf '%d' "$1" || printf '%d' "$2"; }

# Read one keypress (blocking). Sets global KEY.
# Handles arrow keys and other multi-byte escape sequences.
_read_key() {
    local k s1 s2 s3
    local _st
    _st=$(stty -g 2>/dev/null) || true
    stty -echo -icanon min 1 time 0 2>/dev/null || true
    IFS= read -r -n1 k 2>/dev/null || k=''
    # read -n1 consumes the newline terminator without including it in $k.
    # An empty result after a successful read means Enter was pressed.
    [[ -z $k ]] && k=$'\n'
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
}

# Non-blocking read: waits up to ~50 ms. Returns 0 if key read, 1 on timeout.
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
    # Successful read with empty $k = Enter key (newline was consumed by read).
    [[ -z $k ]] && k=$'\n'
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

# Key constants
readonly KEY_UP=$'\x1b[A'
readonly KEY_DOWN=$'\x1b[B'
readonly KEY_HOME=$'\x1b[H'
readonly KEY_END=$'\x1b[F'
readonly KEY_PGUP=$'\x1b[5~'
readonly KEY_PGDN=$'\x1b[6~'
readonly KEY_HOME2=$'\x1bOH'
readonly KEY_END2=$'\x1bOF'
readonly KEY_F1_A=$'\x1bOP'
readonly KEY_F1_B=$'\x1b[11~'
readonly KEY_F2_A=$'\x1bOQ'    # application-mode F2 (xterm, GNOME Terminal)
readonly KEY_F2_B=$'\x1b[12~'  # VT100/cursor-mode F2 (needs 4-byte reader fix in commit 10)
readonly KEY_F5=$'\x1b[15~'    # F5 — safe replacement for F10 (rarely intercepted)
readonly KEY_F10=$'\x1b[21~'   # kept for reference; not used in menu (GNOME intercepts it)
readonly KEY_ENTER=$'\r'
readonly KEY_ENTER2=$'\n'
readonly KEY_ESC=$'\x1b'
readonly KEY_BACKSPACE=$'\x7f'
readonly KEY_BACKSPACE2=$'\x08'

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

# Page through an array of lines. Lines may contain ANSI codes.
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
format_menu_label() {
    local label="$1" hotkey="${2:-}"
    if [[ -z $hotkey ]]; then
        printf '%s' "$label"
        return
    fi
    local lo="${hotkey,,}" up="${hotkey^^}"
    printf '%s' "$label" | sed "s/[$lo$up]/\x1b[1;4m&\x1b[0;97m/1"
}

# Interactive combo-box with filtering.
# Args: [-s|--strict] [-p PROMPT] item1 item2 ...
# Sets _SELECT_RESULT and _SELECT_CANCELLED (1=ESC). Returns 0 on selection, 1 on cancel.
# All TUI output goes to /dev/tty so the widget renders correctly even when the caller
# is inside a $(...) subshell (stdout captured for return value).
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

    # Always write TUI to the controlling terminal, never to a captured pipe.
    local _tty=/dev/tty
    [[ -c /dev/tty ]] || _tty=/proc/self/fd/2  # stderr fallback if no tty

    _term_size
    local start_row=8
    local max_vis=$(( TERM_H - start_row - 2 ))
    (( max_vis < 1 )) && max_vis=1

    local sel=-1
    local view_off=0
    local filter=""
    local -a filtered=("${items[@]}")

    printf '\e[?25l' >"$_tty"

    while true; do
        filtered=()
        local it
        for it in "${items[@]}"; do
            [[ -z $filter || "${it,,}" == *"${filter,,}"* ]] && filtered+=("$it")
        done
        local fcount=${#filtered[@]}

        (( sel >= fcount )) && sel=$(( fcount - 1 ))
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
            input_disp="$(printf '\e[37m%s\e[90m|\e[0m' "$filter")"
        else
            input_disp="$(printf '\e[90m(type to filter or create new)\e[0m')"
        fi

        local f
        f="$(printf '\e[%d;1H\e[K  \e[90m%s\e[0m' "$prompt_row" "$prompt")"
        f+="$(printf '\e[%d;1H\e[K  \e[36m>\e[0m %s' "$input_row" "$input_disp")"

        local i
        for (( i=0; i<max_vis; i++ )); do
            local idx=$(( view_off + i ))
            local r=$(( start_row + i ))
            if (( idx < fcount )); then
                if (( idx == sel )); then
                    f+="$(printf '\e[%d;1H\e[48;5;6m\e[1;97m  %s\e[K\e[0m' "$r" "${filtered[$idx]}")"
                else
                    f+="$(printf '\e[%d;1H\e[K  \e[97m  %s\e[0m' "$r" "${filtered[$idx]}")"
                fi
            else
                f+="$(printf '\e[%d;1H\e[K' "$r")"
            fi
        done

        local up_ind="  " dn_ind="  "
        (( view_off > 0 )) && up_ind="^ "
        (( view_off + max_vis < fcount )) && dn_ind="v "
        local hint="  Up/Dn navigate   Enter select   type filter/new   Esc cancel   ${up_ind}${dn_ind}"
        local hint_pad
        hint_pad=$(_repeat ' ' "$(( TERM_W - ${#hint} > 0 ? TERM_W - ${#hint} : 0 ))")
        f+="$(printf '\e[%d;1H\e[7m%s%s\e[0m' "$TERM_H" "$hint" "$hint_pad")"

        printf '%s' "$f" >"$_tty"

        _read_key
        local k="$KEY"

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
                    else continue
                    fi
                elif [[ -n $filter ]]; then
                    chosen="$filter"
                fi
                printf '%s\e[%d;1H\e[K\e[?25h' "$clr" "$TERM_H" >"$_tty"
                if [[ -n $chosen ]]; then
                    printf '\e[%d;1H  \e[90m%s\e[0m  \e[36m%s\e[0m\n' \
                        "$prompt_row" "$prompt" "$chosen" >"$_tty"
                else
                    printf '\e[%d;1H' "$prompt_row" >"$_tty"
                fi
                _SELECT_RESULT="$chosen"
                _SELECT_CANCELLED=0
                return 0
                ;;
            "$KEY_ESC")
                printf '%s\e[%d;1H\e[K\e[%d;1H\e[?25h' "$clr" "$TERM_H" "$prompt_row" >"$_tty"
                _SELECT_RESULT=""
                _SELECT_CANCELLED=1
                return 1
                ;;
            *)
                if [[ ${#k} -eq 1 && $(printf '%d' "'$k") -ge 32 ]] 2>/dev/null; then
                    filter+="$k"
                    sel=-1
                fi
                ;;
        esac
    done

    printf '\e[?25h' >"$_tty"
    _SELECT_RESULT=""
    _SELECT_CANCELLED=0
    return 1
}
