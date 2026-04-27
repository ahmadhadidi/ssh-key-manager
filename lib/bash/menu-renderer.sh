# lib/menu-renderer.sh — TUI event loop and operation runner
# Sourced by hddssh.sh — do not execute directly.
# Depends on menu.sh (invoke_menu_choice, _check_config_at_start,
#                      _show_menu_help, _do_create_config).
[[ -n "${_MENU_RENDERER_SH_LOADED:-}" ]] && return 0
_MENU_RENDERER_SH_LOADED=1
# EXPORTS: show_main_menu  _invoke_choice

# ─── Operation runner ─────────────────────────────────────────────────────────

# Clear screen, render the op title box, run invoke_menu_choice, wait for ack.
# Sets need_full=1 on return (local in show_main_menu — bash dynamic scoping).
_invoke_choice() {
    local choice="$1" label="$2"
    _dbg "_invoke_choice: choice='$choice' label='$label'"
    _term_size
    local _bw=$(( TERM_W - 4 > 0 ? TERM_W - 4 : 10 ))
    local _iw=$(( _bw - 2 ))
    local _TL=$'\xe2\x94\x8c' _TR=$'\xe2\x94\x90' _BL=$'\xe2\x94\x94' _BR=$'\xe2\x94\x98' _VB=$'\xe2\x94\x82'
    local _hrule; printf -v _hrule '%*s' "$_iw" ''; _hrule="${_hrule// /─}"
    local _ipad; printf -v _ipad '%*s' "$_iw" ''
    local _llen=${#label}
    local _lpad=$(( (_iw - _llen) / 2 )); (( _lpad < 0 )) && _lpad=0
    local _rpad=$(( _iw - 0 - _llen - _lpad )); (( _rpad < 0 )) && _rpad=0
    local _lspc _rspc; printf -v _lspc '%*s' "$_lpad" ''; printf -v _rspc '%*s' "$_rpad" ''
    printf '\e[2J\e[H\e[?25h\n'
    printf '  \e[96m%s%s%s\e[0m\n' "$_TL" "$_hrule" "$_TR"
    printf '  \e[96m%s\e[0m\e[48;5;23m%s\e[0m\e[96m%s\e[0m\n' "$_VB" "$_ipad" "$_VB"
    printf '  \e[96m%s\e[0m\e[48;5;23m\e[1;97m%s%s%s\e[0m\e[96m%s\e[0m\n' "$_VB" "$_lspc" "$label" "$_rspc" "$_VB"
    printf '  \e[96m%s\e[0m\e[48;5;23m%s\e[0m\e[96m%s\e[0m\n' "$_VB" "$_ipad" "$_VB"
    printf '  \e[96m%s%s%s\e[0m\n\n' "$_BL" "$_hrule" "$_BR"

    # Restore cooked terminal mode for operations that use normal read
    local _stty_saved_inner
    _stty_saved_inner=$(stty -g 2>/dev/null) || true
    stty sane 2>/dev/null || true

    _setup_askpass
    local skip_wait=0
    invoke_menu_choice "$choice" || skip_wait=$?
    _dbg "_invoke_choice: '$choice' completed, skip_wait=$skip_wait"
    _destroy_askpass

    stty "$_stty_saved_inner" 2>/dev/null || true

    (( skip_wait )) || wait_user_acknowledge
    printf '\e[?25l'
    need_full=1
}

# ─── Main menu ────────────────────────────────────────────────────────────────

show_main_menu() {
    local -a m_type=(
        header  item    item    item    item    item    item    item
        header  item    item    item    item    item    item
        header  item    item    item    item
    )
    local -a m_label=(
        "Remote"
        "🔑  Generate & Install SSH Key on A Remote Machine"
        "📤  Install SSH Key on A Remote Machine"
        "🔌  Test SSH Connection"
        "🗑️  Delete SSH Key From A Remote Machine"
        "🔄  Promote Key on A Remote Machine"
        "📋  List Authorized Keys on Remote Host"
        "🔗  Add Config Block for Existing Remote Key"
        "Local"
        "✨  Generate SSH Key (Without installation)"
        "🗝️  List SSH Keys"
        "➕  Append SSH Key to Hostname in Host Config"
        "🗑️  Delete an SSH Key Locally [x]"
        "❌  Remove an SSH Key From Config"
        "📥  Import SSH Key from Another Machine"
        "Config File"
        "🏚️  Remove Host from SSH Config"
        "👁️  View SSH Config"
        "✏️  Edit SSH Config"
        "🚪  Exit"
    )
    local -a m_choice=(
        ""   "1"  "15" "2"  "3"  "4"  "16" "17"
        ""   "5"  "6"  "7"  "8"  "9"  "18"
        ""   "12" "13" "14" "q"
    )
    local -a m_hotkey=(
        ""   "G"  "I"  "T"  "D"  "P"  "Z"  "N"
        ""   "W"  "L"  "A"  "X"  "R"  "M"
        ""   "H"  "V"  "E"  "Q"
    )

    # Build flat rows
    local -a fr_type=() fr_label=() fr_nidx=() fr_choice=() fr_hotkey=()
    local ni=0 i
    for (( i=0; i<${#m_type[@]}; i++ )); do
        if [[ ${m_type[$i]} == "header" ]]; then
            fr_type+=("blank");  fr_label+=("");               fr_nidx+=(-1); fr_choice+=(""); fr_hotkey+=("")
            fr_type+=("header"); fr_label+=("${m_label[$i]}"); fr_nidx+=(-1); fr_choice+=(""); fr_hotkey+=("")
        else
            fr_type+=("item");   fr_label+=("${m_label[$i]}"); fr_nidx+=($ni); fr_choice+=("${m_choice[$i]}"); fr_hotkey+=("${m_hotkey[$i]}")
            (( ni++ ))
        fi
    done
    local flat_count=${#fr_type[@]}

    local -a nav_label=() nav_choice=() nav_hotkey=()
    for (( i=0; i<flat_count; i++ )); do
        if [[ ${fr_type[$i]} == "item" ]]; then
            nav_label+=("${fr_label[$i]}")
            nav_choice+=("${fr_choice[$i]}")
            nav_hotkey+=("${fr_hotkey[$i]}")
        fi
    done
    local nav_count=${#nav_label[@]}

    local sel=0 prev_sel=-1 need_full=1 running=1
    local term_w=0 term_h=0 view_off=0
    local -a item_rows  # integer-keyed; indexed array works on bash 3.2

    # Enter alternate screen, save terminal state globally for reliable cleanup.
    # Then enter raw/noecho immediately so the event loop never echoes escape sequences.
    _STTY_SAVED=$(stty -g 2>/dev/null) || true
    printf '\e[?1049h\e[?25l'
    stty -echo -icanon min 0 time 1 2>/dev/null || true

    _MENU_CLEANED_UP=0
    _menu_cleanup() {
        (( _MENU_CLEANED_UP )) && return 0
        _MENU_CLEANED_UP=1
        # Clear the alternate screen before leaving so no content bleeds through,
        # then restore cursor visibility and switch back to the normal screen.
        printf '\e[?25h\e[2J\e[H\e[?1049l' >/dev/tty 2>/dev/null || \
        printf '\e[?25h\e[2J\e[H\e[?1049l'
        stty "$_STTY_SAVED" 2>/dev/null || stty sane 2>/dev/null || true
    }

    # EXIT covers all paths. INT/TERM/TSTP set the right exit code then let EXIT
    # handle cleanup — the guard flag ensures _menu_cleanup runs exactly once.
    trap '_menu_cleanup' EXIT
    trap 'exit 130' INT
    trap 'exit 0'   TERM TSTP

    # ── Startup config file check ────────────────────────────────────────────
    if [[ ! -f "$SSH_CONFIG" ]]; then
        _check_config_at_start
    fi

    while (( running )); do

        # ── Full render ──────────────────────────────────────────────────────
        if (( need_full )); then
            _term_size
            term_w=$TERM_W; term_h=$TERM_H

            local rule; rule=$(_repeat '─' "$(( term_w - 4 > 0 ? term_w - 4 : 0 ))")
            local menu_title="🌊 HDD SSH Keys Manager"
            local title_pad; title_pad=$(_repeat ' ' "$(( (term_w - 4 - ${#menu_title} - 1) / 2 > 0 ? (term_w - 4 - ${#menu_title} - 1) / 2 : 0 ))")
            local title_content="  ${title_pad}${menu_title}"

            local content_start=5
            # Reserve 1 row for hint bar; add 1 more if config warning bar is shown
            local content_end=$(( _CONFIG_MISSING ? term_h - 2 : term_h - 1 ))
            local content_rows=$(( content_end - content_start + 1 ))
            (( content_rows < 1 )) && content_rows=1

            local sel_flat=-1
            for (( i=0; i<flat_count; i++ )); do
                if [[ ${fr_type[$i]} == "item" ]] && (( fr_nidx[$i] == sel )); then
                    sel_flat=$i; break
                fi
            done
            if (( sel_flat >= 0 )); then
                if (( sel_flat < view_off )); then
                    view_off=$sel_flat
                elif (( sel_flat >= view_off + content_rows )); then
                    view_off=$(( sel_flat - content_rows + 1 ))
                fi
            fi
            (( view_off < 0 )) && view_off=0

            local f
            f="$(printf '\e[2J\e[H')"
            f+="$(printf '\e[2;1H  \e[96m%s\e[0m\e[K' "$rule")"
            f+="$(printf '\e[3;1H\e[48;5;23m\e[1;97m%s\e[K\e[0m' "$title_content")"
            f+="$(printf '\e[4;1H  \e[96m%s\e[0m\e[K' "$rule")"

            item_rows=()
            local row=$content_start
            local end_fi=$(( view_off + content_rows < flat_count ? view_off + content_rows : flat_count ))
            for (( i=view_off; i<end_fi; i++ )); do
                case "${fr_type[$i]}" in
                    blank)
                        f+="$(printf '\e[%d;1H\e[K' "$row")" ;;
                    header)
                        f+="$(printf '\e[%d;1H  \e[90m  > \e[1m%s\e[0m\e[K' "$row" "${fr_label[$i]}")" ;;
                    item)
                        item_rows[${fr_nidx[$i]}]=$row
                        if (( fr_nidx[$i] == sel )); then
                            f+="$(printf '\e[%d;1H\e[48;5;6m\e[1;97m    %s\e[K\e[0m' "$row" "${fr_label[$i]}")"
                        else
                            local lbl; lbl=$(format_menu_label "${fr_label[$i]}" "${fr_hotkey[$i]}")
                            f+="$(printf '\e[%d;1H\e[0m\e[97m    %s\e[0m\e[K' "$row" "$lbl")"
                        fi
                        ;;
                esac
                (( row++ ))
            done
            while (( row <= content_end )); do
                f+="$(printf '\e[%d;1H\e[K' "$row")"
                (( row++ ))
            done

            # Scroll indicators (ASCII ^/v instead of Unicode arrows)
            (( view_off > 0 )) && \
                f+="$(printf '\e[%d;%dH\e[90m^\e[0m' "$content_start" "$(( term_w - 1 ))")"
            (( view_off + content_rows < flat_count )) && \
                f+="$(printf '\e[%d;%dH\e[90mv\e[0m' "$content_end" "$(( term_w - 1 ))")"

            # Optional red warning bar when SSH config file is absent
            if (( _CONFIG_MISSING )); then
                local wmsg="  ⚠  SSH config missing — press F2 to create it"
                local wpad; wpad=$(_repeat ' ' "$(( term_w - ${#wmsg} > 0 ? term_w - ${#wmsg} : 0 ))")
                f+="$(printf '\e[%d;1H\e[41m\e[1;97m%s%s\e[0m' "$(( term_h - 1 ))" "$wmsg" "$wpad")"
            fi

            # Single-row hint bar
            local hn_plain="  Up/Dn Navigate   Enter Select   G Generate   T Test   D Delete   L List   Q Quit"
            local hn; hn="$(printf '\e[7m  \e[1mUp/Dn\e[0;7m Navigate   \e[1mEnter\e[0;7m Select   \e[1mG\e[0;7m Generate   \e[1mT\e[0;7m Test   \e[1mD\e[0;7m Delete   \e[1mL\e[0;7m List   \e[1mQ\e[0;7m Quit')"
            local hn_pad; hn_pad=$(_repeat ' ' "$(( term_w - ${#hn_plain} > 0 ? term_w - ${#hn_plain} : 0 ))")
            f+="$(printf '\e[%d;1H%s%s\e[0m' "$term_h" "$hn" "$hn_pad")"

            printf '%s' "$f"
            prev_sel=$sel
            need_full=0

        # ── Differential update ──────────────────────────────────────────────
        elif (( prev_sel != sel )); then
            if [[ -n ${item_rows[$sel]+x} && -n ${item_rows[$prev_sel]+x} ]]; then
                local r=${item_rows[$prev_sel]}
                local lbl; lbl=$(format_menu_label "${nav_label[$prev_sel]}" "${nav_hotkey[$prev_sel]}")
                printf '\e[%d;1H\e[0m\e[97m    %s\e[0m\e[K' "$r" "$lbl"
                r=${item_rows[$sel]}
                printf '\e[%d;1H\e[48;5;6m\e[1;97m    %s\e[K\e[0m' "$r" "${nav_label[$sel]}"
                prev_sel=$sel
            else
                need_full=1
            fi
        fi

        # ── Poll for input (with resize detection) ───────────────────────────
        local got_key=0
        while (( ! got_key )); do
            if _read_key_nb; then
                got_key=1
            else
                local nw nh _sz
                _sz=$(stty size 2>/dev/null)
                if [[ -n $_sz ]]; then
                    nh=${_sz%% *}; nw=${_sz##* }
                else
                    nw=$(tput cols  2>/dev/null || echo 80)
                    nh=$(tput lines 2>/dev/null || echo 24)
                fi
                if (( nw != term_w || nh != term_h )); then
                    term_w=$nw; term_h=$nh
                    need_full=1
                    break
                fi
            fi
        done
        (( ! got_key )) && continue

        local k="$KEY"
        _dbg "key pressed: $(printf '%s' "$k" | od -An -tx1 2>/dev/null | tr -d ' \n')"

        # ── Navigation keys ──────────────────────────────────────────────────
        case "$k" in
            "$KEY_UP")
                (( sel = (sel - 1 + nav_count) % nav_count )) ;;
            "$KEY_DOWN")
                (( sel = (sel + 1) % nav_count )) ;;
            "$KEY_HOME"|"$KEY_HOME2")
                sel=0 ;;
            "$KEY_END"|"$KEY_END2")
                sel=$(( nav_count - 1 )) ;;
            "$KEY_ENTER"|"$KEY_ENTER2")
                local choice="${nav_choice[$sel]}"
                _dbg "Enter pressed: sel=$sel choice='$choice' label='${nav_label[$sel]}'"
                if [[ $choice == "q" ]]; then
                    running=0
                else
                    _invoke_choice "$choice" "${nav_label[$sel]}"
                fi
                ;;
            "$KEY_F1_A"|"$KEY_F1_B")
                _invoke_choice "10" "Help: Best Practices"
                ;;
            '?')
                stty sane 2>/dev/null || true
                printf '\e[?25h'
                _show_menu_help
                stty -echo -icanon min 0 time 1 2>/dev/null || true
                need_full=1
                ;;
            "$KEY_F2_A"|"$KEY_F2_B")
                if (( _CONFIG_MISSING )); then
                    _term_size
                    stty sane 2>/dev/null || true
                    printf '\e[?25h'
                    _do_create_config
                    printf '\n  \e[90mPress any key to continue...\e[0m'
                    _read_key
                    printf '\e[?25l'
                    stty -echo -icanon min 0 time 1 2>/dev/null || true
                    need_full=1
                fi
                ;;
            "$KEY_F5")
                _invoke_choice "11" "Conf: Global Defaults"
                ;;
            q|Q)
                running=0 ;;
            *)
                if [[ ${#k} -eq 1 ]]; then
                    # Convert pressed key to uppercase once for case-insensitive match.
                    # All hotkeys are defined as uppercase letters, so comparing k_up
                    # against nav_hotkey avoids bash 4+ ${var^^} operator.
                    local k_up hki
                    k_up=$(tr 'a-z' 'A-Z' <<< "$k")
                    for (( hki=0; hki<nav_count; hki++ )); do
                        if [[ -n ${nav_hotkey[$hki]} && \
                              "${nav_hotkey[$hki]}" == "$k_up" ]]; then
                            local hk_choice="${nav_choice[$hki]}"
                            _dbg "Hotkey '$k' -> choice='$hk_choice'"
                            if [[ $hk_choice == "q" ]]; then
                                running=0
                            else
                                _invoke_choice "$hk_choice" "${nav_label[$hki]}"
                            fi
                            break
                        fi
                    done
                fi
                ;;
        esac
    done

    _menu_cleanup
    trap - EXIT INT TERM TSTP
}
