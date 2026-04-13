# lib/menu.sh — Menu dispatcher and all _menu_* handlers
# Sourced by hddssh.sh — do not execute directly.
[[ -n "${_MENU_SH_LOADED:-}" ]] && return 0
_MENU_SH_LOADED=1
# EXPORTS: invoke_menu_choice
#   handlers: _menu_generate_and_install  _menu_install_key  _menu_test_connection
#             _menu_delete_remote_key  _menu_promote_key  _menu_generate_key
#             _menu_list_keys  _menu_append_key_to_config  _menu_delete_local_key
#             _menu_remove_key_from_config  _menu_show_best_practices
#             _menu_conf_defaults  _menu_remove_host  _menu_view_config
#             _menu_edit_config  _menu_list_authorized_keys
#             _menu_add_config_block  _menu_import_key
#   support:  _do_create_config  _check_config_at_start

# ─── Menu dispatcher ──────────────────────────────────────────────────────────
# Returns 0 normally; returns 1 to signal "skip wait_user_acknowledge".
invoke_menu_choice() {
    local choice="$1"
    _dbg "invoke_menu_choice: '$choice'"
    case "$choice" in
        1)  _menu_generate_and_install ;;
        2)  _menu_test_connection ;;
        3)  _menu_delete_remote_key ;;
        4)  _menu_promote_key ;;
        5)  _menu_generate_key ;;
        6)  _menu_list_keys ;;
        7)  _menu_append_key_to_config ;;
        8)  _menu_delete_local_key ;;
        9)  _menu_remove_key_from_config ;;
        10) _menu_show_best_practices ;;
        11) _menu_conf_defaults ;;
        12) _menu_remove_host ;;
        13) _menu_view_config ;;
        14) _menu_edit_config ;;
        15) _menu_install_key ;;
        16) _menu_list_authorized_keys ;;
        17) _menu_add_config_block ;;
        18) _menu_import_key ;;
    esac
    return 0
}

# ─── Menu case handlers ───────────────────────────────────────────────────────

_menu_generate_and_install() {   # choice 1
    show_op_banner "host" "$(hostname)"
    local keyname; keyname=$(read_ssh_key_name) || return 0
    deploy_ssh_key_to_remote "$keyname"
}

_menu_install_key() {            # choice 15 — key must already exist locally
    show_op_banner "host" "$(hostname)"
    local keyname; keyname=$(read_ssh_key_name) || return 0
    if ! find_private_key "$keyname"; then
        printf '  \e[31mKey '\''%s'\'' not found locally. Use '\''Generate & Install'\'' to create it first.\e[0m\n' "$keyname"
        return 0
    fi
    install_ssh_key_on_remote "$keyname"
}

_menu_test_connection() {        # choice 2
    show_op_banner "host" "$(hostname)" "user" "$DEFAULT_USER"
    _prompt_remote || return 0
    local host="$_REMOTE_HOST" user="$_REMOTE_USER" sel_alias="$_REMOTE_ALIAS"

    # Primary: IdentityFile entries from the config block for this host.
    # Fallback: all local keys in ~/.ssh when host has no config entry.
    local -a key_paths=() key_labels=()
    local id_lookup="${sel_alias:-$host}"
    local _kp
    while IFS= read -r _kp; do
        key_paths+=("$_kp")
        key_labels+=("$_kp")   # use full path as label to avoid basename collisions
    done < <(get_identity_files_for_host "$id_lookup")

    if (( ${#key_paths[@]} == 0 )); then
        local _kn
        while IFS= read -r _kn; do
            key_paths+=("$SSH_DIR/$_kn")
            key_labels+=("$_kn")
        done < <(get_available_ssh_keys)
    fi

    _run_test_with_keys() {
        local _path="$1" _label="$2"
        printf '  \e[90mTesting with key: %s\e[0m\n' "$_label"
        test_ssh_connection "$user" "$host" "$_path"
    }

    if (( ${#key_paths[@]} == 0 )); then
        test_ssh_connection "$user" "$host"
    elif (( ${#key_paths[@]} == 1 )); then
        _run_test_with_keys "${key_paths[0]}" "$(basename "${key_paths[0]}")"
    else
        local all_label="-- Test ALL (${#key_paths[@]} keys)"
        select_from_list -p "Select key to test:" "$all_label" "${key_labels[@]}"
        if (( _SELECT_CANCELLED == 0 )) && [[ -n $_SELECT_RESULT ]]; then
            local sel="$_SELECT_RESULT"
            if [[ $sel == "-- Test ALL"* ]]; then
                local _i
                for (( _i=0; _i<${#key_paths[@]}; _i++ )); do
                    (( _i > 0 )) && printf '\n'
                    _run_test_with_keys "${key_paths[$_i]}" "$(basename "${key_paths[$_i]}")"
                done
            else
                local _i
                for (( _i=0; _i<${#key_labels[@]}; _i++ )); do
                    if [[ "${key_labels[$_i]}" == "$sel" ]]; then
                        _run_test_with_keys "${key_paths[$_i]}" "$(basename "${key_paths[$_i]}")"
                        break
                    fi
                done
            fi
        fi
    fi
}

_menu_delete_remote_key() {      # choice 3
    show_op_banner "host" "$(hostname)"
    _prompt_remote || return 0
    local host="$_REMOTE_HOST" user="$_REMOTE_USER" sel_alias="$_REMOTE_ALIAS"
    local target; target=$(resolve_ssh_target "$host" "$user")
    _print_identity_files "${sel_alias:-$host}"

    printf '  \e[90mFetching authorized keys from %s...\e[0m\n' "$target"
    _ssh_fence "$target"
    local raw_keys
    raw_keys=$(ssh "$target" "cat ~/.ssh/authorized_keys 2>/dev/null" 2>&1) || {
        _ssh_fence_close
        printf '  \e[31mCould not connect to %s.\e[0m\n' "$target"
        return 0
    }
    _ssh_fence_close

    if [[ -z $raw_keys ]]; then
        printf '  \e[90mNo authorized_keys found on %s.\e[0m\n' "$target"
        return 0
    fi

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
        printf '  \e[33mNo local public keys found in %s authorized_keys.\e[0m\n' "$target"
        return 0
    fi

    select_from_list -s -p "Select key to remove from remote:" "${matched_labels[@]}"
    (( _SELECT_CANCELLED )) && return 0
    [[ -z $_SELECT_RESULT ]] && return 0

    local picked_idx=0 i
    for (( i=0; i<${#matched_labels[@]}; i++ )); do
        [[ "${matched_labels[$i]}" == "$_SELECT_RESULT" ]] && picked_idx=$i && break
    done
    local picked_key="${matched_keys[$picked_idx]}"
    local pub_content; pub_content=$(cat "$SSH_DIR/${picked_key}.pub")

    local remote_cmd
    remote_cmd="TMP_FILE=\$(mktemp) && printf '%s\n' '${pub_content}' > \$TMP_FILE && \
awk 'NR==FNR { keys[\$0]; next } !(\$0 in keys)' \$TMP_FILE ~/.ssh/authorized_keys \
> ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys \
&& rm -f \$TMP_FILE"
    printf '  \e[33mRemoving key '\''%s'\'' from %s...\e[0m\n' "$picked_key" "$target"
    _ssh_fence "$target"
    local _rm_rc=0
    ssh "$target" "$remote_cmd" || _rm_rc=$?
    _ssh_fence_close
    if (( _rm_rc != 0 )); then
        printf '  \e[31mFailed to remove key from remote.\e[0m\n'
        return 0
    fi
    printf '  \e[32mKey removed from remote authorized_keys.\e[0m\n'

    if [[ -n $sel_alias ]]; then
        _rm_id_from_cfg() { remove_identity_file_from_config_block "$picked_key" "$sel_alias"; }
        confirm_user_choice \
            "  Remove IdentityFile '$picked_key' from config block '$sel_alias'?" \
            "y" _rm_id_from_cfg || true
    fi

    local priv="$SSH_DIR/$picked_key" pub="$SSH_DIR/${picked_key}.pub"
    _rm_local_key3() {
        [[ -f $priv ]] && rm -f "$priv" && printf '  \e[32mDeleted: %s\e[0m\n' "$priv"
        [[ -f $pub  ]] && rm -f "$pub"  && printf '  \e[32mDeleted: %s\e[0m\n' "$pub"
    }
    confirm_user_choice \
        "  Delete local key '$picked_key' from this machine?" \
        "n" _rm_local_key3 || true
}

_menu_promote_key() {            # choice 4
    show_op_banner "host" "$(hostname)"
    deploy_promoted_key
}

_menu_generate_key() {           # choice 5
    show_op_banner "host" "$(hostname)"
    local keyname; keyname=$(read_ssh_key_name) || return 0
    local comment; comment=$(read_ssh_key_comment "${keyname}${DEFAULT_COMMENT_SUFFIX}") || return 0
    add_ssh_key_in_host "$keyname" "$comment"
}

_menu_append_key_to_config() {   # choice 7
    show_op_banner "config" "$SSH_CONFIG"
    local keyname; keyname=$(read_ssh_key_name) || return 0
    _prompt_remote || return 0
    local host_addr="$_REMOTE_HOST" remote_user="$_REMOTE_USER"
    local host_name="${_REMOTE_ALIAS:-$_REMOTE_HOST}"
    local host_display="$host_name"
    [[ "$host_name" != "$host_addr" ]] && host_display="$host_name ($host_addr)"

    local keypath="$SSH_DIR/$keyname"
    _ssh_fence
    local test_out
    test_out=$(ssh -F /dev/null -i "$keypath" -o IdentitiesOnly=yes \
        -o BatchMode=yes -o ConnectTimeout=6 \
        -o StrictHostKeyChecking=accept-new \
        "${remote_user}@${host_addr}" "echo ok" 2>&1) || true

    if [[ $test_out == "ok" ]]; then
        printf '  \e[32m✅ Key verified on %s.\e[0m\n' "$host_display"
    else
        printf '  \e[33m🚨 Could not verify '\''%s'\'' on %s — it may not be installed yet.\e[0m\n' \
            "$keyname" "$host_display"
        local proceed
        proceed=$(read_host_with_default "Add to config anyway? (y/N):" "N") || proceed="N"
        [[ "$proceed" =~ ^[yY] ]] || return 0
    fi
    add_ssh_key_to_host_config "$keyname" "$host_name" "$host_addr" "$remote_user"
}

_menu_delete_local_key() {       # choice 8
    show_op_banner "ssh dir" "$SSH_DIR"
    local keyname; keyname=$(read_ssh_key_name) || return 0
    [[ -z $keyname ]] && return 0

    local -a key_hosts=() key_host_labels=()
    while IFS='|' read -r alias hn user; do
        key_hosts+=("$alias|$hn|$user")
        if [[ -n $hn ]]; then key_host_labels+=("$alias  ($hn)")
        else key_host_labels+=("$alias"); fi
    done < <(get_hosts_using_key "$keyname")

    if (( ${#key_hosts[@]} > 0 )); then
        local all_label="-- ALL  (${#key_hosts[@]} host(s))"
        select_from_list -p "Remove key from remote host(s)  (Esc = skip remote)" \
            "$all_label" "${key_host_labels[@]}"

        local -a targets_to_remove=()
        if (( _SELECT_CANCELLED == 0 )) && [[ -n $_SELECT_RESULT ]]; then
            local sel="$_SELECT_RESULT"
            if [[ $sel == "-- ALL"* ]]; then
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
            printf '  \e[90mRemoving key from %s...\e[0m\n' "$r_alias"
            remove_ssh_key_from_remote "$ruser" "$rhost" "$keyname"
        done
    else
        printf '  \e[90mNo configured hosts reference this key.\e[0m\n'
    fi

    local priv="$SSH_DIR/$keyname" pub="$SSH_DIR/${keyname}.pub"
    local deleted=0
    if [[ -f $priv ]]; then rm -f "$priv"; printf '  \e[32mDeleted: %s\e[0m\n' "$priv"; deleted=1; fi
    if [[ -f $pub  ]]; then rm -f "$pub";  printf '  \e[32mDeleted: %s\e[0m\n' "$pub";  deleted=1; fi
    if (( deleted )); then
        printf '  \e[32mKey '\''%s'\'' removed locally.\e[0m\n' "$keyname"
    else
        printf '  \e[33mNo local key files found for '\''%s'\''.\e[0m\n' "$keyname"
    fi
}

_menu_remove_key_from_config() { # choice 9
    show_op_banner "config" "$SSH_CONFIG"
    local -a all_hosts=()
    while IFS='|' read -r alias _ _; do all_hosts+=("$alias"); done < <(get_configured_ssh_hosts)
    if (( ${#all_hosts[@]} == 0 )); then
        printf '  \e[90mNo configured hosts found in ~/.ssh/config.\e[0m\n'
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
        printf '  \e[90mNo IdentityFile entries found under host '\''%s'\''.\e[0m\n' "$host_name"
        return 0
    fi
    select_from_list -p "Select key to remove from '$host_name':" "${key_names[@]}"
    (( _SELECT_CANCELLED )) && return 0
    [[ -z $_SELECT_RESULT ]] && return 0
    remove_identity_file_from_config_block "$_SELECT_RESULT" "$host_name"
}

_menu_show_best_practices() {    # choice 10
    printf '\n'
    printf '  \e[36mBest Practices\e[0m\n'
    printf '  \e[90m--------------\e[0m\n'
    printf '  \e[36m1. CTs demo'\''d over LAN         -> shared key (e.g. demo-lan)\e[0m\n'
    printf '  \e[36m2. CTs in development over LAN -> shared key (e.g. dev-lan)\e[0m\n'
    printf '  \e[36m3. CTs promoted into the stack -> shared key (e.g. prod-lan)\e[0m\n'
    printf '  \e[31m4. CTs accessed over the WAN   -> individual key (e.g. sonarr-wan)\e[0m\n'
}

_menu_list_keys() {              # choice 6
    show_ssh_key_inventory
    return 1
}

_menu_conf_defaults() {          # choice 11
    _run_conf_editor
    return 1
}

_menu_remove_host() {            # choice 12
    remove_host_from_ssh_config
}

_menu_view_config() {            # choice 13
    show_ssh_config_file
    return 1
}

_menu_edit_config() {            # choice 14
    edit_ssh_config_file
    return 1
}

_menu_list_authorized_keys() {   # choice 16
    show_op_banner "host" "$(hostname)" "user" "$DEFAULT_USER"
    _prompt_remote || return 0
    local host="$_REMOTE_HOST" user="$_REMOTE_USER"
    local target; target=$(resolve_ssh_target "$host" "$user")
    printf '  \e[90mFetching authorized_keys from %s...\e[0m\n' "$target"
    _ssh_fence "$target"
    local keys
    keys=$(ssh "$target" "cat ~/.ssh/authorized_keys 2>/dev/null" 2>&1) || {
        _ssh_fence_close
        printf '  \e[31mFailed to fetch authorized_keys.\e[0m\n'
        return 0
    }
    _ssh_fence_close
    if [[ -z $keys ]]; then
        printf '  \e[90mNo authorized_keys found on %s.\e[0m\n' "$target"
    else
        printf '  \e[1;37mAuthorized keys on %s:\e[0m\n' "$target"
        local i=1 line
        while IFS= read -r line; do
            [[ -z $line ]] && continue
            printf '  \e[90m%3d\e[0m  \e[36m%s\e[0m\n' "$i" "$line"
            (( i++ ))
        done <<< "$keys"
    fi
}

_menu_add_config_block() {       # choice 17
    show_op_banner "host" "$(hostname)" "config" "$SSH_CONFIG"
    register_remote_host_config
}

_menu_import_key() {             # choice 18
    show_op_banner "host" "$(hostname)" "ssh dir" "$SSH_DIR"
    import_external_ssh_key
}

# ─── Config file helpers ──────────────────────────────────────────────────────

# Create ~/.ssh/config with correct permissions.  Sets _CONFIG_MISSING=0.
_do_create_config() {
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    touch "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
    _CONFIG_MISSING=0
    printf '  \e[32mCreated %s (permissions: 600).\e[0m\n' "$SSH_CONFIG"
}

# Full-screen prompt shown once on startup when ~/.ssh/config is absent.
_check_config_at_start() {
    _term_size
    local rule; rule=$(_repeat '─' "$(( TERM_W - 4 > 0 ? TERM_W - 4 : 0 ))")
    local warn_msg="  SSH Config File Not Found"

    printf '\e[2J\e[H'
    printf '\e[2;1H  \e[96m%s\e[0m\e[K\n' "$rule"
    printf '\e[48;5;196m\e[1;97m%s\e[K\e[0m\n' "$warn_msg"
    printf '  \e[96m%s\e[0m\e[K\n\n' "$rule"
    printf '  \e[97mNo SSH config was found at \e[33m%s\e[0m\n' "$SSH_CONFIG"
    printf '  \e[97mMost operations require this file.\e[0m\n\n'
    printf '\e[?25h'

    printf '  \e[36mCreate ~/.ssh/config now?\e[0m \e[90m[Y/n] \e[0m'
    local ans
    IFS= read -r ans 2>/dev/null || ans=''
    printf '\e[?25l'

    if [[ -z $ans || "$ans" == [yY]* ]]; then
        _do_create_config
        printf '\n  \e[90mPress any key to continue...\e[0m'
        _read_key
    else
        _CONFIG_MISSING=1
    fi
}
