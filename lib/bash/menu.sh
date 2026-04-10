# lib/menu.sh — Menu dispatcher and main menu
# Sourced by ssh-key-manager.sh — do not execute directly.
[[ -n "${_MENU_SH_LOADED:-}" ]] && return 0
_MENU_SH_LOADED=1

# ─── Menu dispatcher ──────────────────────────────────────────────────────────
# Returns 0 normally; returns 1 to signal "skip wait_user_acknowledge".
invoke_menu_choice() {
    local choice="$1"
    _dbg "invoke_menu_choice: '$choice'"
    case "$choice" in
        1)  # Generate & Install SSH Key on A Remote Machine
            printf '\n'
            local keyname; keyname=$(read_ssh_key_name) || return 0
            deploy_ssh_key_to_remote "$keyname"
            ;;
        15) # Install SSH Key on A Remote Machine (key must already exist)
            local keyname; keyname=$(read_ssh_key_name) || return 0
            if ! find_private_key "$keyname"; then
                printf '  \e[31mKey '\''%s'\'' not found locally. Use '\''Generate & Install'\'' to create it first.\e[0m\n' "$keyname"
                return 0
            fi
            install_ssh_key_on_remote "$keyname"
            ;;
        2)  # Test SSH Connection
            local host; host=$(read_remote_host_address "$DEFAULT_SUBNET_PREFIX") || return 0
            local user; user=$(read_remote_user "$DEFAULT_USER") || return 0
            local sel_alias="$_LAST_SELECTED_ALIAS"

            # Primary: IdentityFile entries from the config block for this host.
            # Fallback: all local keys in ~/.ssh when host has no config entry.
            local -a key_paths=() key_labels=()
            local id_lookup="${sel_alias:-$host}"
            local _kp
            while IFS= read -r _kp; do
                key_paths+=("$_kp")
                key_labels+=("$(basename "$_kp")")
            done < <(get_identity_files_for_host "$id_lookup")

            if (( ${#key_paths[@]} == 0 )); then
                # No config keys — offer all local keys
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
                _run_test_with_keys "${key_paths[0]}" "${key_labels[0]}"
            else
                local all_label="-- Test ALL (${#key_paths[@]} keys)"
                select_from_list -p "Select key to test:" "$all_label" "${key_labels[@]}"
                if (( _SELECT_CANCELLED == 0 )) && [[ -n $_SELECT_RESULT ]]; then
                    local sel="$_SELECT_RESULT"
                    if [[ $sel == "-- Test ALL"* ]]; then
                        local _i
                        for (( _i=0; _i<${#key_paths[@]}; _i++ )); do
                            (( _i > 0 )) && printf '\n'
                            _run_test_with_keys "${key_paths[$_i]}" "${key_labels[$_i]}"
                        done
                    else
                        # Find matching path by label
                        local _i
                        for (( _i=0; _i<${#key_labels[@]}; _i++ )); do
                            if [[ "${key_labels[$_i]}" == "$sel" ]]; then
                                _run_test_with_keys "${key_paths[$_i]}" "${key_labels[$_i]}"
                                break
                            fi
                        done
                    fi
                fi
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
                printf '  \e[90mUsing key: %s\e[0m\n' "$k"
            done < <(get_identity_files_for_host "$id_lookup")

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
            _ssh_fence
            local test_out
            test_out=$(ssh -i "$keypath" -o BatchMode=yes -o ConnectTimeout=6 \
                -o StrictHostKeyChecking=accept-new \
                "${remote_user}@${host_addr}" "echo ok" 2>&1) || true

            if [[ $test_out == "ok" ]]; then
                printf '  \e[32mKey verified on %s.\e[0m\n' "$host_addr"
            else
                printf '  \e[33mCould not verify '\''%s'\'' on %s — it may not be installed yet.\e[0m\n' \
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
            ;;
        9)  # Remove an SSH Key From Config
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
            ;;
        10) # Help: Best Practices
            printf '\n'
            printf '  \e[36mBest Practices\e[0m\n'
            printf '  \e[90m--------------\e[0m\n'
            printf '  \e[36m1. CTs demo'\''d over LAN         -> shared key (e.g. demo-lan)\e[0m\n'
            printf '  \e[36m2. CTs in development over LAN -> shared key (e.g. dev-lan)\e[0m\n'
            printf '  \e[36m3. CTs promoted into the stack -> shared key (e.g. prod-lan)\e[0m\n'
            printf '  \e[31m4. CTs accessed over the WAN   -> individual key (e.g. sonarr-wan)\e[0m\n'
            ;;
        11) # Conf: Global Defaults
            _run_conf_editor
            return 1
            ;;
        12) # Remove Host from SSH Config
            remove_host_from_ssh_config
            ;;
        13) # View SSH Config
            show_ssh_config_file
            return 1
            ;;
        14) # Edit SSH Config
            edit_ssh_config_file
            return 1
            ;;
        16) # List Authorized Keys on Remote Host
            local host; host=$(read_remote_host_address "$DEFAULT_SUBNET_PREFIX") || return 0
            local user; user=$(read_remote_user "$DEFAULT_USER") || return 0
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
            ;;
        17) # Add Config Block for Existing Remote Key
            register_remote_host_config
            ;;
        18) # Import SSH Key from Another Machine
            import_external_ssh_key
            ;;
    esac
    return 0
}

# Inline TUI editor for Global Defaults.
_run_conf_editor() {
    local -a field_names=( DEFAULT_USER DEFAULT_SUBNET_PREFIX DEFAULT_COMMENT_SUFFIX DEFAULT_PASSWORD )
    local -a field_labels=( "Default Username      " "Default Subnet Prefix " "Default Comment Suffix" "Default Password      " )
    local conf_sel=0 conf_run=1

    # Hold raw mode for the full navigation loop — same fix as show_main_menu.
    local _conf_stty
    _conf_stty=$(stty -g 2>/dev/null) || true
    stty -echo -icanon min 1 time 0 2>/dev/null || true

    printf '\e[?25l'
    while (( conf_run )); do
        _term_size
        local rule; rule=$(_repeat '-' "$(( TERM_W - 4 > 0 ? TERM_W - 4 : 0 ))")
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
                # 2-space margin inside the teal block so label aligns with unselected rows
                cf+="$(printf '\e[48;5;6m\e[1;97m      %s  %s\e[K\e[0m' "${field_labels[$i]}" "$disp")"
            else
                cf+="$(printf '  \e[0;97m    %s  \e[90m%s\e[0m\e[K' "${field_labels[$i]}" "$disp")"
            fi
        done
        # ── Persist commands (4 methods) ─────────────────────────────────────
        local _raw_url="https://raw.githubusercontent.com/ahmadhadidi/ssh-key-manager/refs/heads/main"
        local _bf="" _pf=""   # bash flags, powershell flags
        [[ -n $DEFAULT_USER           ]] && _bf+=" --user $(printf '%q' "$DEFAULT_USER")"            && _pf+=" -DefaultUserName \"$DEFAULT_USER\""
        [[ -n $DEFAULT_SUBNET_PREFIX  ]] && _bf+=" --subnet $(printf '%q' "$DEFAULT_SUBNET_PREFIX")" && _pf+=" -DefaultSubnetPrefix \"$DEFAULT_SUBNET_PREFIX\""
        [[ -n $DEFAULT_COMMENT_SUFFIX ]] && _bf+=" --comment-suffix $(printf '%q' "$DEFAULT_COMMENT_SUFFIX")" && _pf+=" -DefaultCommentSuffix \"$DEFAULT_COMMENT_SUFFIX\""
        [[ -n $DEFAULT_PASSWORD       ]] && _bf+=" --password $(printf '%q' "$DEFAULT_PASSWORD")"    && _pf+=" -DefaultPassword \"$DEFAULT_PASSWORD\""
        local _c1="bash <(curl -fsSL ${_raw_url}/ssh-key-manager.sh)${_bf}"
        local _c2="bash ssh-key-manager.sh${_bf}"
        local _c3="\$sb=[scriptblock]::Create((irm \"${_raw_url}/generate_key_test.ps1\")); & \$sb${_pf}"
        local _c4="& ./generate_key_test.ps1${_pf}"
        # Truncate each command to terminal width (account for 4-space indent)
        local _tw=$(( TERM_W - 6 ))
        local _t1="$_c1"; (( ${#_t1} > _tw )) && _t1="${_t1:0:$(( _tw - 3 ))}..."
        local _t2="$_c2"; (( ${#_t2} > _tw )) && _t2="${_t2:0:$(( _tw - 3 ))}..."
        local _t3="$_c3"; (( ${#_t3} > _tw )) && _t3="${_t3:0:$(( _tw - 3 ))}..."
        local _t4="$_c4"; (( ${#_t4} > _tw )) && _t4="${_t4:0:$(( _tw - 3 ))}..."
        cf+="$(printf '\e[11;1H\e[K')"
        cf+="$(printf '\e[12;1H  \e[90mTo persist across sessions:\e[0m\e[K')"
        cf+="$(printf '\e[13;1H\e[K')"
        cf+="$(printf '\e[14;1H  \e[90m☁️  Bash · cloud\e[0m\e[K')"
        cf+="$(printf '\e[15;1H    \e[33m%s\e[0m\e[K' "$_t1")"
        cf+="$(printf '\e[16;1H  \e[90m🏠  Bash · local\e[0m\e[K')"
        cf+="$(printf '\e[17;1H    \e[33m%s\e[0m\e[K' "$_t2")"
        cf+="$(printf '\e[18;1H\e[K')"
        cf+="$(printf '\e[19;1H  \e[90m☁️  PowerShell · cloud\e[0m\e[K')"
        cf+="$(printf '\e[20;1H    \e[36m%s\e[0m\e[K' "$_t3")"
        cf+="$(printf '\e[21;1H  \e[90m🏠  PowerShell · local\e[0m\e[K')"
        cf+="$(printf '\e[22;1H    \e[36m%s\e[0m\e[K' "$_t4")"

        local hint="  Up/Dn navigate   Enter edit   Q back  "
        local hpad; hpad=$(_repeat ' ' "$(( TERM_W - ${#hint} > 0 ? TERM_W - ${#hint} : 0 ))")
        cf+="$(printf '\e[%d;1H\e[7m%s%s\e[0m' "$TERM_H" "$hint" "$hpad")"
        printf '%s' "$cf"

        _read_key
        case "$KEY" in
            "$KEY_UP")   (( conf_sel = (conf_sel - 1 + ${#field_names[@]}) % ${#field_names[@]} )) ;;
            "$KEY_DOWN") (( conf_sel = (conf_sel + 1) % ${#field_names[@]} )) ;;
            "$KEY_ENTER"|"$KEY_ENTER2")
                local row=$(( 6 + conf_sel ))
                printf '\e[%d;1H\e[K  \e[1;33m    %s  \e[0;33m' "$row" "${field_labels[$conf_sel]}"
                local new_val
                # read_colored_input manages its own raw mode and silently
                # consumes arrow/F-key sequences instead of echoing them.
                new_val=$(read_colored_input "" cyan)
                if [[ -n $new_val ]] && (( ! _SELECT_CANCELLED )); then
                    printf -v "${field_names[$conf_sel]}" '%s' "$new_val"
                fi
                ;;
            q|Q|"$KEY_ESC") conf_run=0 ;;
        esac
    done
    stty "$_conf_stty" 2>/dev/null || true
    printf '\e[?25h'
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
    local rule; rule=$(_repeat '-' "$(( TERM_W - 4 > 0 ? TERM_W - 4 : 0 ))")
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

    if [[ -z $ans || ${ans,,} == y* ]]; then
        _do_create_config
        printf '\n  \e[90mPress any key to continue...\e[0m'
        _read_key
    else
        _CONFIG_MISSING=1
    fi
}

# ─── Menu help ────────────────────────────────────────────────────────────────

_show_menu_help() {
    printf '\e[2J\e[H'
    local -a lines=(
        ""
        "  $(printf '\e[1;97mMenu Item Guide\e[0m')   $(printf '\e[90m(Q / Esc to close)\e[0m')"
        ""
        "  $(printf '\e[2m─── Remote ─────────────────────────────────────────────────────────────────\e[0m')"
        ""
        "  $(printf '\e[1;97m🔑  Generate \& Install SSH Key on A Remote Machine\e[0m')"
        "  $(printf '\e[90mCreates a new ED25519 key pair on this machine and pushes the public key\e[0m')"
        "  $(printf '\e[90mto the remote host'\''s authorized_keys in one step. Best choice for\e[0m')"
        "  $(printf '\e[90mfirst-time passwordless SSH setup to a new machine.\e[0m')"
        ""
        "  $(printf '\e[1;97m📤  Install SSH Key on A Remote Machine\e[0m')"
        "  $(printf '\e[90mInstalls an already-existing local key onto a remote host. Use this when\e[0m')"
        "  $(printf '\e[90myou generated a key separately and want to deploy it to another machine.\e[0m')"
        ""
        "  $(printf '\e[1;97m🔌  Test SSH Connection\e[0m')"
        "  $(printf '\e[90mVerifies that a key is accepted by a remote host. Run after installing a\e[0m')"
        "  $(printf '\e[90mkey to confirm passwordless login works before disabling password access.\e[0m')"
        ""
        "  $(printf '\e[1;97m🗑️  Delete SSH Key From A Remote Machine\e[0m')"
        "  $(printf '\e[90mRemoves a public key from a remote host'\''s authorized_keys. Also offers\e[0m')"
        "  $(printf '\e[90mto delete the local key files and the IdentityFile line in ~/.ssh/config.\e[0m')"
        ""
        "  $(printf '\e[1;97m🔄  Promote Key on A Remote Machine\e[0m')"
        "  $(printf '\e[90mInstalls a new key on a remote host while removing an old one in one\e[0m')"
        "  $(printf '\e[90moperation. Use this to rotate keys or upgrade from a shared key to a\e[0m')"
        "  $(printf '\e[90mdedicated one.\e[0m')"
        ""
        "  $(printf '\e[1;97m📋  List Authorized Keys on Remote Host\e[0m')"
        "  $(printf '\e[90mFetches and displays all public keys in the remote host'\''s authorized_keys.\e[0m')"
        "  $(printf '\e[90mUseful for auditing which identities have access to a machine.\e[0m')"
        ""
        "  $(printf '\e[1;97m🔗  Add Config Block for Existing Remote Key\e[0m')"
        "  $(printf '\e[90mReads the remote host'\''s authorized_keys, lets you pick a key, and registers\e[0m')"
        "  $(printf '\e[90mthe host in ~/.ssh/config under an alias. Use to document access set up\e[0m')"
        "  $(printf '\e[90moutside this tool.\e[0m')"
        ""
        "  $(printf '\e[2m─── Local ──────────────────────────────────────────────────────────────────\e[0m')"
        ""
        "  $(printf '\e[1;97m✨  Generate SSH Key (Without installation)\e[0m')"
        "  $(printf '\e[90mCreates a key pair locally without pushing it anywhere. Use for offline\e[0m')"
        "  $(printf '\e[90mgeneration or when you'\''ll deploy the key manually or via another tool.\e[0m')"
        ""
        "  $(printf '\e[1;97m🗝️  List SSH Keys\e[0m')"
        "  $(printf '\e[90mShows all key pairs in ~/.ssh with fingerprints and which host config\e[0m')"
        "  $(printf '\e[90mentries reference each key. Useful for auditing your key inventory.\e[0m')"
        ""
        "  $(printf '\e[1;97m➕  Append SSH Key to Hostname in Host Config\e[0m')"
        "  $(printf '\e[90mAdds an IdentityFile line to an existing host block in ~/.ssh/config.\e[0m')"
        "  $(printf '\e[90mUse when a remote host should accept more than one of your local keys.\e[0m')"
        ""
        "  $(printf '\e[1;97m🗑️  Delete an SSH Key Locally\e[0m')"
        "  $(printf '\e[90mRemoves the private and public key files from ~/.ssh on this machine only.\e[0m')"
        "  $(printf '\e[90mDoes NOT revoke the key from any remote host — use Delete From Remote first.\e[0m')"
        ""
        "  $(printf '\e[1;97m❌  Remove an SSH Key From Config\e[0m')"
        "  $(printf '\e[90mRemoves an IdentityFile reference from a host block in ~/.ssh/config without\e[0m')"
        "  $(printf '\e[90mdeleting the key files themselves.\e[0m')"
        ""
        "  $(printf '\e[1;97m📥  Import SSH Key from Another Machine\e[0m')"
        "  $(printf '\e[90mBrings a key pair into ~/.ssh from three sources:\e[0m')"
        "  $(printf '\e[90m  1. Local file path — copy from a path already on this machine\e[0m')"
        "  $(printf '\e[90m  2. Remote machine (SCP) — download directly from another host\e[0m')"
        "  $(printf '\e[90m  3. Paste key content — paste the private and public key text directly\e[0m')"
        ""
        "  $(printf '\e[2m─── Config File ────────────────────────────────────────────────────────────\e[0m')"
        ""
        "  $(printf '\e[1;97m🏚️  Remove Host from SSH Config\e[0m')"
        "  $(printf '\e[90mDeletes an entire Host block from ~/.ssh/config. Use when decommissioning\e[0m')"
        "  $(printf '\e[90ma machine or cleaning up stale entries.\e[0m')"
        ""
        "  $(printf '\e[1;97m👁️  View SSH Config\e[0m')"
        "  $(printf '\e[90mDisplays the current ~/.ssh/config content with syntax highlighting.\e[0m')"
        ""
        "  $(printf '\e[1;97m✏️  Edit SSH Config\e[0m')"
        "  $(printf '\e[90mOpens ~/.ssh/config in \$EDITOR (or nano) for manual editing.\e[0m')"
        ""
    )
    show_paged "${lines[@]}"
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
        "🗑️  Delete an SSH Key Locally"
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
    local -A item_rows=()

    # Enter alternate screen, save terminal state globally for reliable cleanup.
    # Then enter raw/noecho immediately so the event loop never echoes escape sequences.
    _STTY_SAVED=$(stty -g 2>/dev/null) || true
    printf '\e[?1049h\e[?25l'
    stty -echo -icanon min 0 time 0 2>/dev/null || true

    _menu_cleanup() {
        printf '\e[?25h\e[?1049l' >/dev/tty 2>/dev/null || printf '\e[?25h\e[?1049l'
        stty "$_STTY_SAVED" 2>/dev/null || stty sane 2>/dev/null || true
    }

    # INT (Ctrl+C): cleanup + exit with SIGINT code
    # TSTP (Ctrl+Z): cleanup + exit cleanly
    # TERM: cleanup + exit
    # EXIT: cleanup (catches all paths)
    trap '_menu_cleanup' EXIT
    trap '_menu_cleanup; exit 130' INT
    trap '_menu_cleanup; exit 0'   TERM TSTP

    # ── Startup config file check ────────────────────────────────────────────
    if [[ ! -f "$SSH_CONFIG" ]]; then
        _check_config_at_start
    fi

    while (( running )); do

        # ── Full render ──────────────────────────────────────────────────────
        if (( need_full )); then
            _term_size
            term_w=$TERM_W; term_h=$TERM_H

            local rule; rule=$(_repeat '-' "$(( term_w - 4 > 0 ? term_w - 4 : 0 ))")
            local menu_title="🌊 HDD SSH Keys Manager"
            local title_pad; title_pad=$(_repeat ' ' "$(( (term_w - 4 - ${#menu_title} - 1) / 2 > 0 ? (term_w - 4 - ${#menu_title} - 1) / 2 : 0 ))")
            local title_content="  ${title_pad}${menu_title}"

            local content_start=5
            # Reserve 2 rows for hint bar; add 1 more if config warning bar is shown
            local content_end=$(( _CONFIG_MISSING ? term_h - 3 : term_h - 2 ))
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
                f+="$(printf '\e[%d;1H\e[41m\e[1;97m%s%s\e[0m' "$(( term_h - 2 ))" "$wmsg" "$wpad")"
            fi

            # Two-row Nano-style hint bar
            local hn_plain="  Up/Dn Navigate   Home/End Jump   Enter Select   ? Guide   F5 Conf"
            local hk_plain="  G Generate   T Test   D Delete   L List   V View   E Edit   Q Quit"
            local hn; hn="$(printf '\e[7m  \e[1mUp/Dn\e[0;7m Navigate   \e[1mHome/End\e[0;7m Jump   \e[1mEnter\e[0;7m Select   \e[1m?\e[0;7m Guide   \e[1mF5\e[0;7m Conf')"
            local hk; hk="$(printf '\e[7m  \e[1mG\e[0;7m Generate   \e[1mT\e[0;7m Test   \e[1mD\e[0;7m Delete   \e[1mL\e[0;7m List   \e[1mV\e[0;7m View   \e[1mE\e[0;7m Edit   \e[1mQ\e[0;7m Quit')"
            local hn_pad; hn_pad=$(_repeat ' ' "$(( term_w - ${#hn_plain} > 0 ? term_w - ${#hn_plain} : 0 ))")
            local hk_pad; hk_pad=$(_repeat ' ' "$(( term_w - ${#hk_plain} > 0 ? term_w - ${#hk_plain} : 0 ))")
            f+="$(printf '\e[%d;1H%s%s\e[0m' "$(( term_h - 1 ))" "$hn" "$hn_pad")"
            f+="$(printf '\e[%d;1H%s%s\e[0m' "$term_h"           "$hk" "$hk_pad")"

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
                local nw nh
                nw=$(tput cols 2>/dev/null || echo 80)
                nh=$(tput lines 2>/dev/null || echo 24)
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
                stty -echo -icanon min 0 time 0 2>/dev/null || true
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
                    stty -echo -icanon min 0 time 0 2>/dev/null || true
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
                    local hki
                    for (( hki=0; hki<nav_count; hki++ )); do
                        if [[ -n ${nav_hotkey[$hki]} && \
                              "${nav_hotkey[$hki],,}" == "${k,,}" ]]; then
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

# Helper: clear screen, show op header, run the choice, wait for ack.
_invoke_choice() {
    local choice="$1" label="$2"
    _dbg "_invoke_choice: choice='$choice' label='$label'"
    _term_size
    local rule; rule=$(_repeat '-' "$(( TERM_W - 4 > 0 ? TERM_W - 4 : 0 ))")
    local pad; pad=$(_repeat ' ' "$(( (TERM_W - 4 - ${#label}) / 2 > 0 ? (TERM_W - 4 - ${#label}) / 2 : 0 ))")
    local op_title="  ${pad}${label}"
    printf '\e[2J\e[H\e[?25h\n'
    printf '  \e[96m%s\e[0m\n' "$rule"
    printf '\e[48;5;23m\e[1;97m%s\e[K\e[0m\n' "$op_title"
    printf '  \e[96m%s\e[0m\n\n' "$rule"

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
