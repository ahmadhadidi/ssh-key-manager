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
        local status="  Up/Dn/PgUp/PgDn scroll   Home top   End bottom   Q close   ${pct}  "
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
        for e in nvim vim nano vi; do
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
    local r1; r1=$(_repeat '-' "$h1")
    local r2; r2=$(_repeat '-' "$h2")
    local r3; r3=$(_repeat '-' "$h3")
    local r4; r4=$(_repeat '-' "$h4")
    local r5; r5=$(_repeat '-' "$h5")
    top="  +${r1}+${r2}+${r3}+${r4}+${r5}+"
    hdr="  | $(printf '%*s' "$w_num" '#') | $(printf '%-*s' "$w_key" 'Key') | Pub | Prv | $(printf '%-*s' "$w_use" 'Usage') |"
    mid="  +${r1}+${r2}+${r3}+${r4}+${r5}+"
    bot="  +${r1}+${r2}+${r3}+${r4}+${r5}+"

    local -a table_lines=()
    table_lines+=("$(printf '\e[97m%s\e[0m' "$top")")
    table_lines+=("$(printf '\e[1;37m%s\e[0m' "$hdr")")
    table_lines+=("$(printf '\e[97m%s\e[0m' "$mid")")

    local i=1
    for k in "${sorted_keys[@]}"; do
        local pub_c prv_c
        if [[ -n ${has_pub[$k]+x} ]]; then pub_c="$(printf '\e[32m  Y  \e[0m')"
        else                                  pub_c="$(printf '\e[31m  N  \e[0m')"; fi
        if [[ -n ${has_priv[$k]+x} ]]; then prv_c="$(printf '\e[32m  Y  \e[0m')"
        else                                   prv_c="$(printf '\e[31m  N  \e[0m')"; fi
        local usage="${usage_map[$k]:-}"
        local row
        row="  $(printf '\e[97m|\e[0m') $(printf '%*d' "$w_num" "$i") $(printf '\e[97m|\e[0m') $(printf '\e[36m%-*s\e[0m' "$w_key" "$k") $(printf '\e[97m|\e[0m')${pub_c}$(printf '\e[97m|\e[0m')${prv_c}$(printf '\e[97m|\e[0m') $(printf '\e[37m%-*s\e[0m' "$w_use" "$usage") $(printf '\e[97m|\e[0m')"
        table_lines+=("$row")
        (( i++ ))
    done
    table_lines+=("$(printf '\e[97m%s\e[0m' "$bot")")

    show_paged "${table_lines[@]}"
}
