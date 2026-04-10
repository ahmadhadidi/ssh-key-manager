# lib/config-display.sh — SSH config display and edit functions
# Sourced by ssh-key-manager.sh — do not execute directly.
[[ -n "${_CONFIG_DISPLAY_SH_LOADED:-}" ]] && return 0
_CONFIG_DISPLAY_SH_LOADED=1

# ─── Config file display / edit ───────────────────────────────────────────────

# Interactive pager for ~/.ssh/config with syntax highlighting.
show_ssh_config_file() {
    if [[ ! -f "$SSH_CONFIG" ]]; then
        printf '  \e[31mSSH config not found at %s\e[0m\n' "$SSH_CONFIG"
        return
    fi

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

        local rule; rule=$(_repeat '-' "$(( TERM_W - 4 > 0 ? TERM_W - 4 : 0 ))")
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
        local status="  Up/Dn/PgUp/PgDn scroll   Home top   End bottom   Q/Esc close   ${pct}  "
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
            q|Q|"$KEY_ESC") break ;;
        esac

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
        printf '  \e[31mSSH config not found at %s\e[0m\n' "$SSH_CONFIG"
        return
    fi

    local editor=""
    if [[ -n ${VISUAL:-} ]] && command -v "$VISUAL" &>/dev/null; then
        editor="$VISUAL"
    elif [[ -n ${EDITOR:-} ]] && command -v "$EDITOR" &>/dev/null; then
        editor="$EDITOR"
    else
        local e
        for e in nano vi vim nvim; do
            command -v "$e" &>/dev/null && editor="$e" && break
        done
    fi
    [[ -z $editor ]] && editor="vi"

    printf '  \e[90mOpening in %s...\e[0m\n' "$editor"
    "$editor" "$SSH_CONFIG" && printf '  \e[32mDone.\e[0m\n' || \
        printf '  \e[31mCould not open editor '\''%s'\''.\e[0m\n' "$editor"
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
        printf '  \e[31mHost alias is required.\e[0m\n'
        return
    fi

    if [[ ! -f "$SSH_CONFIG" ]]; then
        printf '  \e[31mSSH config not found at %s\e[0m\n' "$SSH_CONFIG"
        return
    fi

    _get_host_block "$host_name"
    if [[ -z $_HOST_BLOCK ]]; then
        printf '  \e[33mNo Host block found for '\''%s'\''\e[0m\n' "$host_name"
        return
    fi

    printf '\n  \e[90mBlock that will be removed:\e[0m\n'
    printf '\e[37m%s\e[0m\n' "$_HOST_BLOCK"

    local confirm
    confirm=$(read_colored_input "Remove this block? [y/N]" yellow)
    if [[ ! ${confirm,,} =~ ^(y|yes)$ ]]; then
        printf '  \e[33mCancelled.\e[0m\n'
        return
    fi

    _replace_host_block "$_HOST_BLOCK" ""

    local cleaned; cleaned=$(sed -e 's/[[:space:]]*$//' -e '/^$/N;/^\n$/d' "$SSH_CONFIG")
    printf '%s\n' "$cleaned" > "$SSH_CONFIG"

    printf '  \e[32mHost '\''%s'\'' removed from SSH config.\e[0m\n' "$host_name"
}

show_ssh_key_inventory() {
    if [[ ! -d "$SSH_DIR" ]]; then
        printf '  \e[31m.ssh directory not found at %s\e[0m\n' "$SSH_DIR"
        return
    fi

    # ── Build key metadata ──────────────────────────────────────────────────
    local -A has_pub=() has_priv=()
    local f
    for f in "$SSH_DIR"/*.pub; do
        [[ -f $f ]] && has_pub["$(basename "${f%.pub}")"]="1"
    done
    while IFS= read -r k; do has_priv["$k"]="1"; done < <(get_available_ssh_keys)

    local -A all_keys=()
    local k
    for k in "${!has_pub[@]}" "${!has_priv[@]}"; do all_keys["$k"]="1"; done

    if (( ${#all_keys[@]} == 0 )); then
        printf '  \e[33mNo key files found in %s\e[0m\n' "$SSH_DIR"
        return
    fi

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

    local -a sorted_keys=()
    while IFS= read -r k; do sorted_keys+=("$k"); done < <(printf '%s\n' "${!all_keys[@]}" | sort)
    local key_count=${#sorted_keys[@]}

    # ── Column widths ───────────────────────────────────────────────────────
    local w_num=${#key_count}; (( w_num < 1 )) && w_num=1
    local w_key=3 w_use=5
    for k in "${sorted_keys[@]}"; do
        (( ${#k} > w_key )) && w_key=${#k}
        local u="${usage_map[$k]:-}"
        (( ${#u} > w_use )) && w_use=${#u}
    done

    # ── Build static header lines ───────────────────────────────────────────
    local h1=$(( w_num + 2 )) h2=$(( w_key + 2 )) h3=5 h4=5 h5=$(( w_use + 2 ))
    local r1; r1=$(_repeat '-' "$h1")
    local r2; r2=$(_repeat '-' "$h2")
    local r3; r3=$(_repeat '-' "$h3")
    local r4; r4=$(_repeat '-' "$h4")
    local r5; r5=$(_repeat '-' "$h5")
    local tbl_top="  +${r1}+${r2}+${r3}+${r4}+${r5}+"
    local tbl_hdr="  | $(printf '%*s' "$w_num" '#') | $(printf '%-*s' "$w_key" 'Key') | Pub | Prv | $(printf '%-*s' "$w_use" 'Usage') |"
    local tbl_sep="  +${r1}+${r2}+${r3}+${r4}+${r5}+"

    # ── Interactive loop ─────────────────────────────────────────────────────
    local sel=0 off=0 need_redraw=1
    _term_size
    printf '\e[?25l'

    while true; do
        if (( need_redraw )); then
            _term_size
            local hdr_rows=7   # 2J + rule + title + rule + tbl_top + tbl_hdr + tbl_sep
            local content_rows=$(( TERM_H - hdr_rows - 2 ))  # -2 for hint bar + border row
            (( content_rows < 1 )) && content_rows=1

            # Keep sel in viewport
            if (( sel < off )); then off=$sel
            elif (( sel >= off + content_rows )); then off=$(( sel - content_rows + 1 ))
            fi
            (( off < 0 )) && off=0

            local rule; rule=$(_repeat '-' "$(( TERM_W - 4 > 0 ? TERM_W - 4 : 0 ))")
            local title_str="  SSH Key Inventory"
            local title_fill; title_fill=$(_repeat ' ' "$(( TERM_W - ${#title_str} > 0 ? TERM_W - ${#title_str} : 0 ))")
            local g
            g="$(printf '\e[2J\e[H')"
            g+="$(printf '\e[2;1H  \e[96m%s\e[0m\e[K' "$rule")"
            g+="$(printf '\e[3;1H\e[48;5;23m\e[1;97m%s%s\e[0m' "$title_str" "$title_fill")"
            g+="$(printf '\e[4;1H  \e[96m%s\e[0m\e[K' "$rule")"
            g+="$(printf '\e[5;1H\e[97m%s\e[0m\e[K' "$tbl_top")"
            g+="$(printf '\e[6;1H\e[1;37m%s\e[0m\e[K' "$tbl_hdr")"
            g+="$(printf '\e[7;1H\e[97m%s\e[0m\e[K' "$tbl_sep")"

            local row=8 idx
            for (( idx=off; idx<off+content_rows && idx<key_count; idx++ )); do
                k="${sorted_keys[$idx]}"
                local pub_c prv_c
                if [[ -n ${has_pub[$k]+x} ]]; then pub_c="$(printf '\e[32m  Y  \e[0m')"
                else                                pub_c="$(printf '\e[31m  N  \e[0m')"; fi
                if [[ -n ${has_priv[$k]+x} ]]; then prv_c="$(printf '\e[32m  Y  \e[0m')"
                else                                 prv_c="$(printf '\e[31m  N  \e[0m')"; fi
                local usage="${usage_map[$k]:-}"
                local num_str; num_str=$(printf '%*d' "$w_num" $(( idx + 1 )))

                if (( idx == sel )); then
                    g+="$(printf '\e[%d;1H\e[48;5;6m\e[1;97m  | %s | %-*s |%s|%s| %-*s |\e[K\e[0m' \
                        "$row" "$num_str" "$w_key" "$k" "$pub_c" "$prv_c" "$w_use" "$usage")"
                else
                    local bar; bar="$(printf '\e[97m|\e[0m')"
                    g+="$(printf '\e[%d;1H  %s %s %s \e[36m%-*s\e[0m %s%s%s%s%s \e[37m%-*s\e[0m %s\e[K' \
                        "$row" "$bar" "$num_str" "$bar" "$w_key" "$k" "$bar" "$pub_c" "$bar" "$prv_c" "$bar" "$w_use" "$usage" "$bar")"
                fi
                (( row++ ))
            done

            # Bottom border + blank rows
            g+="$(printf '\e[%d;1H\e[97m%s\e[0m\e[K' "$row" "$tbl_top")"
            (( row++ ))
            while (( row < TERM_H - 1 )); do
                g+="$(printf '\e[%d;1H\e[K' "$row")"
                (( row++ ))
            done

            # Hint bar
            local hint="  Up/Dn navigate   Enter view key   Q close"
            local hpad; hpad=$(_repeat ' ' "$(( TERM_W - ${#hint} > 0 ? TERM_W - ${#hint} : 0 ))")
            g+="$(printf '\e[%d;1H\e[7m%s%s\e[0m' "$TERM_H" "$hint" "$hpad")"

            printf '%s' "$g"
            need_redraw=0
        fi

        _read_key
        case "$KEY" in
            "$KEY_UP")
                (( sel > 0 )) && { (( sel-- )); need_redraw=1; }
                ;;
            "$KEY_DOWN")
                (( sel < key_count - 1 )) && { (( sel++ )); need_redraw=1; }
                ;;
            "$KEY_PGUP")
                (( sel -= 5 )); (( sel < 0 )) && sel=0; need_redraw=1
                ;;
            "$KEY_PGDN")
                (( sel += 5 )); (( sel >= key_count )) && sel=$(( key_count - 1 )); need_redraw=1
                ;;
            "$KEY_HOME"|"$KEY_HOME2") sel=0; need_redraw=1 ;;
            "$KEY_END"|"$KEY_END2")   sel=$(( key_count - 1 )); need_redraw=1 ;;
            "$KEY_ENTER"|"$KEY_ENTER2")
                _view_ssh_key "${sorted_keys[$sel]}"
                need_redraw=1
                ;;
            q|Q) break ;;
        esac
    done

    printf '\e[?25h'
}

# Show a key viewer submenu then display the selected key file in a pager.
_view_ssh_key() {
    local keyname="$1"

    local -a options=()
    [[ -f "$SSH_DIR/${keyname}.pub" ]] && options+=("Public Key  (.pub)")
    [[ -f "$SSH_DIR/$keyname"       ]] && options+=("Private Key (handle with care)")
    options+=("Back")

    select_from_list -s -p "View — $keyname" "${options[@]}"
    (( _SELECT_CANCELLED )) && return

    case "$_SELECT_RESULT" in
        "Public Key"*)
            _display_key_file "$SSH_DIR/${keyname}.pub" "Public Key — ${keyname}.pub"
            ;;
        "Private Key"*)
            # Confirm before showing private key
            _term_size
            printf '\e[%d;1H\e[41m\e[1;97m  WARNING: You are about to display a private key on screen.%s\e[0m' \
                "$(( TERM_H - 3 ))" \
                "$(_repeat ' ' $(( TERM_W - 57 > 0 ? TERM_W - 57 : 0 )))"
            printf '\e[%d;1H  \e[97mShow private key contents? [y/N] \e[0m' "$(( TERM_H - 2 ))"
            printf '\e[?25h'
            _read_key
            printf '\e[?25l'
            [[ $KEY =~ ^[Yy]$ ]] || return
            _display_key_file "$SSH_DIR/$keyname" "Private Key — $keyname"
            ;;
    esac
}

# Full-screen pager for a raw key file.
_display_key_file() {
    local file="$1" title="$2"
    if [[ ! -f $file ]]; then
        printf '  \e[31mFile not found: %s\e[0m\n' "$file"
        wait_user_acknowledge
        return
    fi

    local -a lines=()
    while IFS= read -r line; do
        lines+=("  $(printf '\e[37m%s\e[0m' "$line")")
    done < "$file"

    _term_size
    local total=${#lines[@]}
    local content_rows=$(( TERM_H - 6 ))
    (( content_rows < 1 )) && content_rows=1
    local off=0

    printf '\e[?25l'
    while true; do
        (( off < 0 )) && off=0
        local max_off=$(( total - content_rows ))
        (( max_off < 0 )) && max_off=0
        (( off > max_off )) && off=$max_off

        local rule; rule=$(_repeat '-' "$(( TERM_W - 4 > 0 ? TERM_W - 4 : 0 ))")
        local t_fill; t_fill=$(_repeat ' ' "$(( TERM_W - ${#title} - 4 > 0 ? TERM_W - ${#title} - 4 : 0 ))")
        local g
        g="$(printf '\e[2J\e[H')"
        g+="$(printf '\e[2;1H  \e[96m%s\e[0m\e[K' "$rule")"
        g+="$(printf '\e[3;1H\e[48;5;23m\e[1;97m  %s%s\e[0m' "$title" "$t_fill")"
        g+="$(printf '\e[4;1H  \e[96m%s\e[0m\e[K' "$rule")"

        local row=5 i
        for (( i=off; i<off+content_rows && i<total; i++ )); do
            g+="$(printf '\e[%d;1H%s\e[K' "$row" "${lines[$i]}")"
            (( row++ ))
        done
        while (( row <= TERM_H - 1 )); do
            g+="$(printf '\e[%d;1H\e[K' "$row")"
            (( row++ ))
        done

        local pct
        if (( total <= content_rows )); then pct="all"
        else pct="$(( (off + content_rows) * 100 / total ))%"
        fi
        local status="  Up/Dn/PgUp/PgDn scroll   Home top   End bottom   Q/Esc close   ${pct}  "
        local spad; spad=$(_repeat ' ' "$(( TERM_W - ${#status} > 0 ? TERM_W - ${#status} : 0 ))")
        g+="$(printf '\e[%d;1H\e[7m%s%s\e[0m' "$TERM_H" "$status" "$spad")"
        printf '%s' "$g"

        _read_key
        case "$KEY" in
            "$KEY_UP")               (( off-- )) ;;
            "$KEY_DOWN")             (( off++ )) ;;
            "$KEY_PGUP")             (( off -= content_rows )) ;;
            "$KEY_PGDN")             (( off += content_rows )) ;;
            "$KEY_HOME"|"$KEY_HOME2") off=0 ;;
            "$KEY_END"|"$KEY_END2")   off=$max_off ;;
            q|Q|"$KEY_ESC") break ;;
        esac
    done
    printf '\e[?25h'
}
