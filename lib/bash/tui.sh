# lib/tui.sh — Terminal helpers and TUI widgets
# Sourced by hddssh.sh — do not execute directly.
[[ -n "${_TUI_SH_LOADED:-}" ]] && return 0
_TUI_SH_LOADED=1
# EXPORTS: _dbg  _term_size  _regex_escape  _repeat  _max  _min
#          _read_key  _read_key_nb  _read_key_raw
#          wait_user_acknowledge  show_paged  format_menu_label
#          select_multi_from_list  select_from_list

# ─── Debug logging ────────────────────────────────────────────────────────────

_dbg() {
    (( VERBOSE )) || return 0
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$_LOG_FILE"
}

# ─── Terminal helpers ─────────────────────────────────────────────────────────

_term_size() {
    local _sz
    _sz=$(stty size 2>/dev/null)
    if [[ -n $_sz ]]; then
        TERM_H=${_sz%% *}
        TERM_W=${_sz##* }
    else
        TERM_W=$(tput cols  2>/dev/null || echo 80)
        TERM_H=$(tput lines 2>/dev/null || echo 24)
    fi
}

# Return the terminal display-column width of a string.
# bash ${#str} counts Unicode code points, not display columns:
#   - Wide chars (emoji ≥ U+10000, some BMP symbols): 2 cols, bash counts 1 → add 1 each
#   - Variation selectors (U+FE0F/FE0E) and ZWJ (U+200D): 0 cols, bash counts 1 → subtract 1 each
# The two effects cancel for emoji+VS pairs (🗑️, 👁️, etc.) — those already produce
# correct centering. Only bare wide chars need correction.
_visual_width() {
    local str="$1" n s adj t sym
    n=${#str}
    # Strip zero-width code points; each removed char = 1 bash unit but 0 display cols.
    local _vs16=$'\xef\xb8\x8f' _vs15=$'\xef\xb8\x8e' _zwj=$'\xe2\x80\x8d'
    s="${str//$_vs16/}"; s="${s//$_vs15/}"; s="${s//$_zwj/}"
    adj=$(( ${#s} - n ))   # negative count of zero-width chars removed
    # 4-byte UTF-8 lead bytes (0xF0-0xF4) identify non-BMP wide emoji; each adds 1 col.
    local w4
    w4=$(printf '%s' "$s" | LC_ALL=C tr -cd '\360\361\362\363\364' | wc -c)
    adj=$(( adj + w4 ))
    # Wide BMP symbols used in these menus: ✨ (U+2728) ➕ (U+2795) ❌ (U+274C).
    for sym in '✨' '➕' '❌'; do
        t="${s//$sym/}"; adj=$(( adj + ${#s} - ${#t} )); s="$t"
    done
    printf '%d' $(( n + adj ))
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
# Handles arrow keys and multi-byte escape sequences including 2-digit F-keys
# (e.g. F5 = \x1b[15~, F10 = \x1b[21~).
_read_key() {
    local k s1 s2 s3 s4
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
            # Numeric modifier — may be a 1-digit (\x1b[5~) or 2-digit (\x1b[21~) code
            IFS= read -r -n1 -t 0.05 s3 2>/dev/null || s3=''
            if [[ ${s3:-} =~ ^[0-9]$ ]]; then
                # Two-digit code: read the trailing terminator (~)
                IFS= read -r -n1 -t 0.05 s4 2>/dev/null || s4=''
            else
                s4=''
            fi
        else
            s3=''; s4=''
        fi
        k="${k}${s1}${s2}${s3}${s4}"
    fi
    stty "$_st" 2>/dev/null || true
    KEY="$k"
}

# Non-blocking read: relies on stty VTIME (min 0 time 1 = 100 ms kernel timeout)
# set by show_main_menu. Returns 0 if key read, 1 on timeout.
# Does NOT use bash's -t flag — unreliable on bash 3.2 / macOS.
# Caller must already hold raw mode (-echo -icanon min 0 time 1).
_read_key_nb() {
    local k s1 s2 s3 s4
    # No -t: timeout comes from stty VTIME=1 (100ms). A 0-byte kernel return
    # is seen as EOF by bash's read builtin, which returns exit code 1.
    IFS= read -r -n1 k 2>/dev/null || {
        KEY=''
        return 1
    }
    [[ -z $k ]] && k=$'\n'
    if [[ $k == $'\x1b' ]]; then
        # Switch to truly non-blocking (VTIME=0) for ESC continuation bytes.
        # Arrow/F-key bytes are already in the buffer; standalone ESC gets
        # empty s1/s2 immediately instead of waiting 100 ms each.
        stty min 0 time 0 2>/dev/null || true
        IFS= read -r -n1 s1 2>/dev/null || s1=''
        IFS= read -r -n1 s2 2>/dev/null || s2=''
        if [[ ${s2:-} =~ ^[0-9]$ ]]; then
            IFS= read -r -n1 s3 2>/dev/null || s3=''
            if [[ ${s3:-} =~ ^[0-9]$ ]]; then
                IFS= read -r -n1 s4 2>/dev/null || s4=''
            else
                s4=''
            fi
        else
            s3=''; s4=''
        fi
        stty min 0 time 1 2>/dev/null || true
        k="${k}${s1}${s2}${s3}${s4}"
    fi
    KEY="$k"
    return 0
}

# Like _read_key but WITHOUT stty save/restore.
# Caller must already hold raw mode (-echo -icanon min 1 time 0).
# Eliminates 2 subprocess forks per keypress in tight interactive loops.
_read_key_raw() {
    local k s1 s2 s3 s4
    IFS= read -r -n1 k 2>/dev/null || k=''
    [[ -z $k ]] && k=$'\n'
    if [[ $k == $'\x1b' ]]; then
        IFS= read -r -n1 -t 0.05 s1 2>/dev/null || s1=''
        IFS= read -r -n1 -t 0.05 s2 2>/dev/null || s2=''
        if [[ ${s2:-} =~ ^[0-9]$ ]]; then
            IFS= read -r -n1 -t 0.05 s3 2>/dev/null || s3=''
            if [[ ${s3:-} =~ ^[0-9]$ ]]; then
                IFS= read -r -n1 -t 0.05 s4 2>/dev/null || s4=''
            else s4=''; fi
        else s3=''; s4=''; fi
        k="${k}${s1}${s2}${s3}${s4}"
    fi
    KEY="$k"
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
            printf '\e[90m-- %d/%d lines shown | Enter=more, Q/Esc=quit --\e[0m' "$i" "$total"
            _read_key
            printf '\n'
            [[ $KEY == 'q' || $KEY == 'Q' || $KEY == "$KEY_ESC" ]] && break
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
    # tr is portable to bash 3.2; ${var,,}/${var^^} require bash 4+.
    local lo up
    lo=$(tr 'A-Z' 'a-z' <<< "$hotkey")
    up=$(tr 'a-z' 'A-Z' <<< "$hotkey")
    # Pure bash regex — no subprocess, no BSD/GNU sed incompatibility.
    # [^${lo}${up}]* matches greedily up to the first hotkey char (case-insensitive).
    if [[ "$label" =~ ^([^${lo}${up}]*)([$lo$up])(.*)$ ]]; then
        printf '%s\e[1;4m%s\e[0;97m%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    else
        printf '%s' "$label"
    fi
}

# Multi-select checklist widget.
# Args: [-p PROMPT] item1 item2 ...
# Space toggles, Enter confirms, ESC cancels.
# Sets _SELECT_MULTI_RESULT (array of selected items) and _SELECT_CANCELLED.
select_multi_from_list() {
    local prompt="Select"
    while [[ ${1:-} == -* ]]; do
        case "$1" in
            -p|--prompt) prompt="$2"; shift 2 ;;
            *) break ;;
        esac
    done

    local -a items=("$@")
    local item_count=${#items[@]}
    _SELECT_MULTI_RESULT=()
    _SELECT_CANCELLED=0

    if (( item_count == 0 )); then return 1; fi

    local _tty=/dev/tty
    [[ -c /dev/tty ]] || _tty=/proc/self/fd/2

    local _sml_stty
    _sml_stty=$(stty -g 2>/dev/null) || true
    stty -echo -icanon min 1 time 0 2>/dev/null || true

    _term_size
    local start_row=$(( 8 + ${_SFL_BANNER_ROWS:-0} ))
    _SFL_BANNER_ROWS=0
    local max_vis=$(( TERM_H - start_row - 2 ))
    (( max_vis < 1 )) && max_vis=1

    local sel=0 view_off=0
    local -a checked=()
    local _ci
    for (( _ci=0; _ci<item_count; _ci++ )); do checked+=( 0 ); done

    printf '\e[?25l' >"$_tty"

    local prompt_row=$(( start_row - 2 ))
    local clr="" _ct
    for (( _ci=prompt_row; _ci<start_row+max_vis+1 && _ci<TERM_H; _ci++ )); do
        printf -v _ct '\e[%d;1H\e[K' "$_ci"; clr+="$_ct"
    done

    while true; do
        if   (( sel >= view_off + max_vis )); then view_off=$(( sel - max_vis + 1 ))
        elif (( sel < view_off           )); then view_off=$sel; fi
        (( view_off < 0 )) && view_off=0

        local _t f
        printf -v _t '\e[%d;1H\e[K  \e[90m%s\e[0m' "$prompt_row" "$prompt"; f="$_t"

        local i
        for (( i=0; i<max_vis; i++ )); do
            local idx=$(( view_off + i )) r=$(( start_row + i ))
            if (( idx < item_count )); then
                local _box="[ ]"; (( checked[idx] )) && _box="[✓]"
                if (( idx == sel )); then
                    printf -v _t '\e[%d;1H\e[48;5;6m\e[1;97m  %s  %s\e[K\e[0m' "$r" "$_box" "${items[$idx]}"
                elif (( checked[idx] )); then
                    printf -v _t '\e[%d;1H\e[K  \e[32m%s\e[0m  %s' "$r" "$_box" "${items[$idx]}"
                else
                    printf -v _t '\e[%d;1H\e[K  \e[90m%s\e[0m  %s' "$r" "$_box" "${items[$idx]}"
                fi
            else
                printf -v _t '\e[%d;1H\e[K' "$r"
            fi
            f+="$_t"
        done

        local up_ind="  " dn_ind="  "
        (( view_off > 0 )) && up_ind="^ "
        (( view_off + max_vis < item_count )) && dn_ind="v "
        local hint="  Up/Dn navigate   Space toggle   Enter confirm   Esc cancel   ${up_ind}${dn_ind}"
        local hint_pad="" _hn=$(( TERM_W - ${#hint} > 0 ? TERM_W - ${#hint} : 0 )) _hi
        for (( _hi=0; _hi<_hn; _hi++ )); do hint_pad+=' '; done
        printf -v _t '\e[%d;1H\e[7m%s%s\e[0m' "$TERM_H" "$hint" "$hint_pad"; f+="$_t"

        printf '%s' "$f" >"$_tty"
        _read_key_raw

        case "$KEY" in
            "$KEY_UP")   (( sel = (sel <= 0          ? item_count-1 : sel-1) )) ;;
            "$KEY_DOWN") (( sel = (sel >= item_count-1 ? 0           : sel+1) )) ;;
            ' ')         (( checked[sel] = checked[sel] ? 0 : 1 )) ;;
            "$KEY_ENTER"|"$KEY_ENTER2")
                printf '%s\e[%d;1H\e[K\e[?25h' "$clr" "$TERM_H" >"$_tty"
                local _si _labels=""
                for (( _si=0; _si<item_count; _si++ )); do
                    if (( checked[_si] )); then
                        _SELECT_MULTI_RESULT+=( "${items[$_si]}" )
                        [[ -n $_labels ]] && _labels+=", "
                        _labels+="${items[$_si]}"
                    fi
                done
                printf '\e[%d;1H  \e[90m%s\e[0m  \e[36m%s\e[0m\n' \
                    "$prompt_row" "$prompt" "${_labels:-(none selected)}" >"$_tty"
                stty "$_sml_stty" 2>/dev/null || true
                _SELECT_CANCELLED=0
                return 0
                ;;
            "$KEY_ESC")
                printf '%s\e[%d;1H\e[K\e[%d;1H\e[?25h' "$clr" "$TERM_H" "$prompt_row" >"$_tty"
                stty "$_sml_stty" 2>/dev/null || true
                _SELECT_CANCELLED=1
                return 1
                ;;
        esac
    done
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

    # Hold raw mode for the full widget so arrow keys are never echoed between reads.
    local _sfl_stty
    _sfl_stty=$(stty -g 2>/dev/null) || true
    stty -echo -icanon min 1 time 0 2>/dev/null || true

    _term_size
    local start_row=$(( 8 + ${_SFL_BANNER_ROWS:-0} ))
    _SFL_BANNER_ROWS=0
    local max_vis=$(( TERM_H - start_row - 2 ))
    (( max_vis < 1 )) && max_vis=1

    local sel=0
    (( item_count == 0 )) && sel=-1
    local view_off=0
    local filter=""
    local -a filtered=("${items[@]}")

    printf '\e[?25l' >"$_tty"

    # Geometry is fixed for the lifetime of this widget — compute once.
    local prompt_row=$(( start_row - 2 ))
    local input_row=$(( start_row - 1 ))

    # Pre-build the clear-widget escape (used only on exit).
    local clr="" _ct _ci
    for (( _ci=prompt_row; _ci<start_row+max_vis+1 && _ci<TERM_H; _ci++ )); do
        printf -v _ct '\e[%d;1H\e[K' "$_ci"
        clr+="$_ct"
    done

    while true; do
        filtered=()
        local it
        for it in "${items[@]}"; do
            shopt -s nocasematch
            [[ -z $filter || "$it" == *"$filter"* ]] && filtered+=("$it")
            shopt -u nocasematch
        done
        local fcount=${#filtered[@]}

        (( sel >= fcount )) && sel=$(( fcount - 1 ))
        if (( sel >= 0 && sel < view_off )); then
            view_off=$sel
        elif (( sel >= 0 && sel >= view_off + max_vis )); then
            view_off=$(( sel - max_vis + 1 ))
        fi
        (( view_off < 0 )) && view_off=0

        # ── Build render frame without any subshell forks ────────────────────
        local _t f input_disp
        if [[ -n $filter ]]; then
            printf -v input_disp '\e[37m%s\e[90m|\e[0m' "$filter"
        else
            input_disp=$'\e[90m(type to filter or create new)\e[0m'
        fi

        printf -v _t '\e[%d;1H\e[K  \e[90m%s\e[0m' "$prompt_row" "$prompt"; f="$_t"
        printf -v _t '\e[%d;1H\e[K  \e[36m>\e[0m %s' "$input_row" "$input_disp"; f+="$_t"

        local i
        for (( i=0; i<max_vis; i++ )); do
            local idx=$(( view_off + i ))
            local r=$(( start_row + i ))
            if (( idx < fcount )); then
                if (( idx == sel )); then
                    printf -v _t '\e[%d;1H\e[48;5;6m\e[1;97m    %s\e[K\e[0m' "$r" "${filtered[$idx]}"
                else
                    printf -v _t '\e[%d;1H\e[K  \e[97m  %s\e[0m' "$r" "${filtered[$idx]}"
                fi
            else
                printf -v _t '\e[%d;1H\e[K' "$r"
            fi
            f+="$_t"
        done

        local up_ind="  " dn_ind="  "
        (( view_off > 0 )) && up_ind="^ "
        (( view_off + max_vis < fcount )) && dn_ind="v "
        local hint="  Up/Dn navigate   Enter select   type filter/new   Esc cancel   ${up_ind}${dn_ind}"
        local hint_pad="" _hn=$(( TERM_W - ${#hint} > 0 ? TERM_W - ${#hint} : 0 )) _hi
        for (( _hi=0; _hi<_hn; _hi++ )); do hint_pad+=' '; done
        printf -v _t '\e[%d;1H\e[7m%s%s\e[0m' "$TERM_H" "$hint" "$hint_pad"; f+="$_t"

        printf '%s' "$f" >"$_tty"

        _read_key_raw
        local k="$KEY"

        case "$k" in
            "$KEY_UP")
                if (( fcount > 0 )); then
                    (( sel = (sel <= 0 ? fcount - 1 : sel - 1) ))
                fi
                ;;
            "$KEY_DOWN")
                if (( fcount > 0 )); then
                    (( sel = (sel < 0 || sel >= fcount - 1 ? 0 : sel + 1) ))
                fi
                ;;
            "$KEY_BACKSPACE"|"$KEY_BACKSPACE2")
                if (( ${#filter} > 0 )); then
                    filter="${filter%?}"
                    (( fcount > 0 && sel < 0 )) && sel=0
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
                stty "$_sfl_stty" 2>/dev/null || true
                _SELECT_RESULT="$chosen"
                _SELECT_CANCELLED=0
                return 0
                ;;
            "$KEY_ESC")
                printf '%s\e[%d;1H\e[K\e[%d;1H\e[?25h' "$clr" "$TERM_H" "$prompt_row" >"$_tty"
                stty "$_sfl_stty" 2>/dev/null || true
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

    stty "$_sfl_stty" 2>/dev/null || true
    printf '\e[?25h' >"$_tty"
    _SELECT_RESULT=""
    _SELECT_CANCELLED=0
    return 1
}
