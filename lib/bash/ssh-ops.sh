# lib/ssh-ops.sh — SSH key operations
# Sourced by ssh-key-manager.sh — do not execute directly.
[[ -n "${_SSH_OPS_SH_LOADED:-}" ]] && return 0
_SSH_OPS_SH_LOADED=1

# ─── Remote ───────────────────────────────────────────────────────────────────

# Generate key if missing, then install on remote.
deploy_ssh_key_to_remote() {
    local keyname="$1"
    _dbg "deploy_ssh_key_to_remote: keyname='$keyname'"
    if ! find_private_key "$keyname"; then
        printf '\n'
        _out warn 'Key does not exist. Generating...'
        local comment
        comment=$(read_ssh_key_comment "${keyname}${DEFAULT_COMMENT_SUFFIX}")
        add_ssh_key_in_host "$keyname" "$comment"
    else
        printf '\n'
        _out info 'Key already exists. Proceeding with installation...'
        printf '\n'
    fi
    install_ssh_key_on_remote "$keyname"
}

# Copy a public key to a remote's authorized_keys and register in ~/.ssh/config.
install_ssh_key_on_remote() {
    local keyname="$1"
    _dbg "install_ssh_key_on_remote: keyname='$keyname'"

    local pubkey
    pubkey=$(get_public_key "$keyname") || return 1

    _prompt_remote || return 1
    local host_addr="$_REMOTE_HOST" selected_alias="$_REMOTE_ALIAS" remote_user="$_REMOTE_USER"

    local target
    target=$(resolve_ssh_target "$host_addr" "$remote_user")
    _dbg "install_ssh_key_on_remote: target='$target'"

    _print_identity_files "${selected_alias:-$host_addr}"
    printf '  Connecting to %s...\n' "$target"

    local remote_hostname
    if [[ -n $DEFAULT_PASSWORD ]] && command -v sshpass &>/dev/null; then
        _out dim 'Using sshpass with stored password.'
        remote_hostname=$(printf '%s\n' "$pubkey" | \
            sshpass -p "$DEFAULT_PASSWORD" ssh -o StrictHostKeyChecking=accept-new \
            "$target" 'mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname' 2>&1) || {
            _out error 'Failed to inject SSH key. Check network, credentials, or host status.'
            _dbg "install_ssh_key_on_remote: sshpass failed"
            return 1
        }
    else
        _ssh_fence "$target"
        remote_hostname=$(printf '%s\n' "$pubkey" | \
            ssh "$target" 'mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname' 2>&1) || {
            _ssh_fence_close
            _out error 'Failed to inject SSH key. Check network, credentials, or host status.'
            _dbg "install_ssh_key_on_remote: ssh failed"
            return 1
        }
        _ssh_fence_close
    fi

    _out ok 'SSH Public Key installed successfully.'
    _out dim 'Remote hostname: %s' "$remote_hostname"

    local host_alias="${selected_alias:-$remote_hostname}"
    _add_identity_to_config() {
        printf "  Registering key to SSH config as '%s'...\n" "$host_alias"
        add_ssh_key_to_host_config "$keyname" "$host_alias" "$host_addr" "$remote_user"
    }
    confirm_user_choice \
        "  Add '$keyname' as IdentityFile in config block '$host_alias'?" \
        "y" _add_identity_to_config || true
}

test_ssh_connection() {
    local user="$1" host="$2" identity="${3:-}"
    _dbg "test_ssh_connection: user='$user' host='$host' identity='$identity'"

    if ! _tcp_check "$host"; then
        _out error 'Connection refused: %s is not accepting SSH on port 22.' "$host"
        return 1
    fi

    local target
    local -a ssh_args=()
    if [[ -n $identity ]]; then
        # Bypass ~/.ssh/config entirely so no other IdentityFile entries from the
        # host's config block can succeed as fallbacks — this tests ONLY this key.
        # Do NOT use BatchMode=yes: passphrase-protected keys need to prompt.
        # PreferredAuthentications=publickey restricts to key auth only (no
        # password fallback). SSH_ASKPASS_REQUIRE=force (set by _setup_askpass)
        # routes any passphrase prompt through our padded askpass script.
        target="${user}@${host}"
        ssh_args+=(-F /dev/null -i "$identity" -o IdentitiesOnly=yes \
                   -o PreferredAuthentications=publickey)
    else
        target=$(resolve_ssh_target "$host" "$user")
    fi
    ssh_args+=(-o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new \
               "$target" "echo SSH Connection Successful")

    _ssh_fence "$target"
    local result
    result=$(ssh "${ssh_args[@]}" 2>&1) || true
    _ssh_fence_close
    _dbg "test_ssh_connection result: $result"

    if printf '%s' "$result" | grep -qE "Name or service not known|Could not resolve hostname"; then
        _out error 'DNS error: Could not resolve %s.' "$host"
        return 1
    elif printf '%s' "$result" | grep -q "Permission denied"; then
        if [[ -n $identity ]]; then
            _out warn 'Key not authorized on %s.' "$host"
        else
            _out warn "SSH reachable, but permission denied for user '%s'." "$user"
        fi
        return 0
    else
        _out ok 'SSH connection to %s is successful.' "$host"
        return 0
    fi
}

# Remove a public key from a remote's authorized_keys.
remove_ssh_key_from_remote() {
    local remote_user="$1" remote_host="$2" keyname="$3"
    _dbg "remove_ssh_key_from_remote: user='$remote_user' host='$remote_host' key='$keyname'"

    local pubkey
    pubkey=$(get_public_key "$keyname") || return 1

    local target
    target=$(resolve_ssh_target "$remote_host" "$remote_user")
    _print_identity_files "$remote_host"

    printf '\n'
    _out warn 'Will connect to remove the public key from %s:' "$target"
    printf '  \e[90m  %s\e[0m\n\n' "$(printf '%s' "$pubkey" | tr -d '\n')"

    local remote_cmd
    remote_cmd="TMP_FILE=\$(mktemp) && printf '%s\n' '${pubkey}' > \$TMP_FILE && \
awk 'NR==FNR { keys[\$0]; next } !(\$0 in keys)' \$TMP_FILE ~/.ssh/authorized_keys \
> ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys \
&& rm -f \$TMP_FILE"

    _ssh_fence "$target"
    local _rm_rc=0
    ssh "$target" "$remote_cmd" || _rm_rc=$?
    _ssh_fence_close

    if (( _rm_rc == 0 )); then
        _out ok 'SSH key removed from remote authorized_keys.'
        local priv="$SSH_DIR/$keyname" pub="$SSH_DIR/${keyname}.pub"
        _do_delete_local_key() {
            [[ -f $priv ]] && rm -f "$priv" && _out ok 'Deleted: %s' "$priv"
            [[ -f $pub  ]] && rm -f "$pub"  && _out ok 'Deleted: %s' "$pub"
        }
        confirm_user_choice \
            "  Remove local key '$keyname' from THIS machine?" \
            "n" \
            _do_delete_local_key || true
    else
        _out error 'Failed to remove the SSH key from remote.'
    fi
}

deploy_promoted_key() {
    _out info 'Which key do you want to demote (remove from remote)?'
    local key_to_remove; key_to_remove=$(read_ssh_key_name) || return 1

    _out info 'From which remote machine?'
    local remote_host_name; remote_host_name=$(read_remote_host_name "$DEFAULT_SUBNET_PREFIX") || return 1

    _out info 'Replace with which key?'
    local key_new; key_new=$(read_ssh_key_name) || return 1
    deploy_ssh_key_to_remote "$key_new"

    local remote_addr; remote_addr=$(get_ip_from_host_config "$remote_host_name")
    local remote_user; remote_user=$(get_user_from_host_config "$remote_host_name")

    _do_demote() {
        remove_ssh_key_from_remote "$remote_user" "${remote_addr:-$remote_host_name}" "$key_to_remove"
    }
    confirm_user_choice \
        "  Remove demoted key '$key_to_remove' from remote '$remote_host_name'?" \
        "n" \
        _do_demote || true
}

# Connect to a host, match its authorized_keys against local keys,
# and write the matching key into ~/.ssh/config.
register_remote_host_config() {
    _prompt_remote || return 1
    local host_addr="$_REMOTE_HOST" remote_user="$_REMOTE_USER"
    local target="${remote_user}@${host_addr}"

    _out dim 'Connecting to %s to read authorized_keys...' "$target"
    _ssh_fence "$target"
    local raw_keys
    raw_keys=$(ssh -o StrictHostKeyChecking=accept-new "$target" \
        "cat ~/.ssh/authorized_keys 2>/dev/null") || {
        _ssh_fence_close
        _out error 'Connection failed.'
        return 1
    }
    _ssh_fence_close

    if [[ -z $raw_keys ]]; then
        _out warn 'No authorized_keys found on %s.' "$target"
        return
    fi

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
        _out warn 'No local public keys match authorized_keys on %s.' "$target"
        _out dim "Install a key first via 'Generate & Install' or 'Install SSH Key'."
        return
    fi

    _out ok 'Found %d matching local key(s):' "${#matches[@]}"
    local m; for m in "${matches[@]}"; do printf '     \e[36m%s\e[0m\n' "$m"; done

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

# ─── Local ────────────────────────────────────────────────────────────────────

# Generate an ED25519 key pair in ~/.ssh.
add_ssh_key_in_host() {
    local keyname="$1" comment="$2"
    local keypath="$SSH_DIR/$keyname"
    _dbg "add_ssh_key_in_host: keyname='$keyname' comment='$comment'"

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
    _out dim 'Generating SSH key...'

    _ensure_ssh_dir
    ssh-keygen -t ed25519 -f "$keypath" -C "$comment" -N "$passphrase"
    chmod 600 "$keypath"

    _out_item '\e[36m%s\e[0m  generated.' "$keypath"
}

# Add or update a Host block in ~/.ssh/config.
add_ssh_key_to_host_config() {
    local keyname="$1" host_name="$2" host_addr="$3" remote_user="$4"
    local keypath="$SSH_DIR/$keyname"
    local identity_line="    IdentityFile $keypath"
    _dbg "add_ssh_key_to_host_config: keyname='$keyname' host='$host_name'"

    if ! find_private_key "$keyname"; then
        _out error 'Could not find private SSH key at %s' "$keypath"
        return 1
    fi

    local cfg
    cfg=$(find_config_file) || {
        mkdir -p "$SSH_DIR"
        touch "$SSH_CONFIG"
        chmod 600 "$SSH_CONFIG"
        cfg="$SSH_CONFIG"
    }

    _get_host_block "$host_name"
    if [[ -n $_HOST_BLOCK ]]; then
        if printf '%s\n' "$_HOST_BLOCK" | grep -qF "${identity_line#    }"; then
            _out warn '⚠️ IdentityFile already exists under Host %s.' "$host_name"
            return 0
        fi
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
        _replace_host_block "$_HOST_BLOCK" "$new_block" || \
            printf '%s\n' "$new_block" >> "$SSH_CONFIG"
        _out ok '✅ IdentityFile added to existing Host %s.' "$host_name"
    else
        local entry
        entry=$(printf '\nHost %s\n    HostName %s\n    User %s\n    IdentityFile %s\n' \
            "$host_name" "$host_addr" "$remote_user" "$keypath")
        printf '%s' "$entry" >> "$SSH_CONFIG"
        _out ok 'SSH config block created for %s.' "$host_name"
        _out info 'Connect with: ssh %s' "$host_name"
    fi
}

# Remove all IdentityFile lines referencing keyname from the named Host block.
remove_identity_file_from_config_block() {
    local keyname="$1" host_alias="$2"
    [[ -f "$SSH_CONFIG" ]] || { _out warn 'No SSH config found.'; return 1; }

    _get_host_block "$host_alias"
    if [[ -z $_HOST_BLOCK ]]; then
        _out warn "No config block found for '%s'." "$host_alias"
        return 1
    fi

    local esc; esc=$(_regex_escape "$keyname")
    local new_block
    new_block=$(printf '%s\n' "$_HOST_BLOCK" | \
        grep -vE "^\s*IdentityFile\s+.*[/\\\\]?${esc}\s*$" || true)

    if [[ "$new_block" == "$_HOST_BLOCK" ]]; then
        _out dim "Key '%s' not found in config block '%s'." "$keyname" "$host_alias"
        return 0
    fi

    _replace_host_block "$_HOST_BLOCK" "$new_block"
    _out ok "IdentityFile '%s' removed from config block '%s'." "$keyname" "$host_alias"
}

# Multi-select configured hosts and append keyname as an IdentityFile to each chosen block.
_add_key_to_hosts() {
    local _kname="$1"
    local -a _aliases=() _ips=() _users=() _display=()
    while IFS='|' read -r _a _hn _u; do
        _aliases+=("$_a"); _ips+=("$_hn"); _users+=("$_u")
        [[ -n $_hn ]] && _display+=("$_a  ($_hn)") || _display+=("$_a")
    done < <(get_configured_ssh_hosts)

    if (( ${#_display[@]} == 0 )); then
        _out warn 'No configured hosts — add a host block first.'
        return 0
    fi

    select_multi_from_list -p "Add '$_kname' as IdentityFile in:" "${_display[@]}"
    (( _SELECT_CANCELLED )) && return 0
    if (( ${#_SELECT_MULTI_RESULT[@]} == 0 )); then
        _out warn 'No hosts selected.'
        return 0
    fi

    local _sel
    for _sel in "${_SELECT_MULTI_RESULT[@]}"; do
        local _alias="${_sel%%  (*}"
        _alias="${_alias%"${_alias##*[! ]}"}"
        local _i
        for (( _i=0; _i<${#_aliases[@]}; _i++ )); do
            if [[ "${_aliases[$_i]}" == "$_alias" ]]; then
                add_ssh_key_to_host_config \
                    "$_kname" "${_aliases[$_i]}" "${_ips[$_i]}" \
                    "${_users[$_i]:-$DEFAULT_USER}"
                break
            fi
        done
    done
}

# Import a key pair (private + public) generated on another machine into ~/.ssh/.
# Source can be a local path, a remote machine via SCP, or pasted key content.
import_external_ssh_key() {
    select_from_list -s -p "Import source" \
        "Local file path" \
        "Remote machine (SCP)" \
        "Paste key content"
    (( _SELECT_CANCELLED )) && return 0
    local choice="$_SELECT_RESULT"

    local priv_src pub_src key_name

    if [[ $choice == "Local file path" ]]; then
        # ── Local path ──────────────────────────────────────────────────────
        local priv_path
        priv_path=$(read_colored_input "  Path to private key file" cyan)
        [[ -z $priv_path ]] && _out error 'Path is required.' && return 1
        priv_path="${priv_path/#\~/$HOME}"
        if [[ ! -f $priv_path ]]; then
            _out error 'File not found: %s' "$priv_path"
            return 1
        fi
        local auto_pub="${priv_path}.pub"
        local pub_path
        _out dim 'Public key — leave blank to use %s' "$auto_pub"
        pub_path=$(read_colored_input "  Path to public key file" cyan)
        [[ -z $pub_path ]] && pub_path="$auto_pub"
        pub_path="${pub_path/#\~/$HOME}"
        if [[ ! -f $pub_path ]]; then
            _out error 'Public key not found: %s' "$pub_path"
            return 1
        fi
        priv_src="$priv_path"
        pub_src="$pub_path"
        key_name=$(basename "$priv_src")

    elif [[ $choice == "Remote machine (SCP)" ]]; then
        # ── Remote SCP ──────────────────────────────────────────────────────
        _out dim 'Connect to the machine that holds the keys.'
        _prompt_remote || return 1
        local host_addr="$_REMOTE_HOST" remote_user="$_REMOTE_USER"
        local target="${remote_user}@${host_addr}"

        local remote_priv
        remote_priv=$(read_colored_input "  Full path to private key on remote" cyan)
        [[ -z $remote_priv ]] && _out error 'Path is required.' && return 1

        key_name=$(basename "$remote_priv")
        local dest_priv="$SSH_DIR/$key_name"
        local dest_pub="${dest_priv}.pub"

        _out dim 'Downloading %s ...' "$remote_priv"
        _ssh_fence "$target"
        if ! scp -q "${target}:${remote_priv}" "$dest_priv" 2>&1; then
            _ssh_fence_close
            _out error 'Failed to download private key.'
            return 1
        fi
        _out dim 'Downloading %s.pub ...' "$remote_priv"
        if ! scp -q "${target}:${remote_priv}.pub" "$dest_pub" 2>/dev/null; then
            _out warn 'Public key not found at %s.pub — skipping.' "$remote_priv"
        fi
        _ssh_fence_close
        chmod 600 "$dest_priv" 2>/dev/null || true
        [[ -f $dest_pub ]] && chmod 644 "$dest_pub" 2>/dev/null || true
        _out ok 'Keys downloaded to %s.' "$SSH_DIR"
        _add_key_to_hosts "$key_name"
        return 0

    elif [[ $choice == "Paste key content" ]]; then
        # ── Paste ───────────────────────────────────────────────────────────
        key_name=$(read_host_with_default "Key name:" "imported-key") || return 1
        [[ -z $key_name ]] && _out error 'Key name is required.' && return 1

        printf '\n'
        _out info 'Paste the private key.'
        _out dim 'Input ends automatically at the -----END...----- line.'
        printf '\n'
        local priv_content="" _pl
        while IFS= read -r _pl; do
            priv_content+="${_pl}"$'\n'
            [[ $_pl == "-----END"* ]] && break
        done
        if [[ $priv_content != *"-----BEGIN"* || $priv_content != *"-----END"* ]]; then
            _out error 'Invalid private key — BEGIN/END markers not found.'
            return 1
        fi

        printf '\n'
        _out info 'Paste the public key (single line, e.g. ssh-ed25519 AAAA...):'
        local pub_content
        while IFS= read -r pub_content; do
            [[ -n $pub_content ]] && break
        done
        if [[ -z $pub_content ]]; then
            _out error 'Public key is required.'
            return 1
        fi

        _ensure_ssh_dir
        local dest_priv="$SSH_DIR/$key_name"
        local dest_pub="${dest_priv}.pub"
        _write_key_pair "$dest_priv" "$dest_pub" "$priv_content" "$pub_content" || return 1
        _add_key_to_hosts "$key_name"
        return 0
    else
        return 0
    fi

    # ── Install local copies (Local file path branch) ────────────────────────
    _ensure_ssh_dir
    local dest_priv="$SSH_DIR/$key_name"
    local dest_pub="${dest_priv}.pub"
    _write_key_pair "$dest_priv" "$dest_pub" "$priv_src" "$pub_src" 1 || return 1
    _add_key_to_hosts "$key_name"
}
