# lib/ssh-ops.sh — SSH key operations
# Sourced by ssh-key-manager.sh — do not execute directly.
[[ -n "${_SSH_OPS_SH_LOADED:-}" ]] && return 0
_SSH_OPS_SH_LOADED=1

# ─── SSH key operations ───────────────────────────────────────────────────────

# TCP port-22 pre-check. Returns 0 if reachable.
_tcp_check() {
    local host="$1"
    timeout 3 bash -c "echo >/dev/tcp/$host/22" 2>/dev/null
}

test_ssh_connection() {
    local user="$1" host="$2" identity="${3:-}"
    _dbg "test_ssh_connection: user='$user' host='$host' identity='$identity'"

    if ! _tcp_check "$host"; then
        printf '  \e[31mConnection refused: %s is not accepting SSH on port 22.\e[0m\n' "$host"
        return 1
    fi

    local target
    local -a ssh_args=()
    if [[ -n $identity ]]; then
        # Bypass ~/.ssh/config entirely so no other IdentityFile entries from the
        # host's config block can succeed as fallbacks — this tests ONLY this key.
        target="${user}@${host}"
        ssh_args+=(-F /dev/null -i "$identity" -o IdentitiesOnly=yes -o BatchMode=yes)
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
        printf '  \e[31mDNS error: Could not resolve %s.\e[0m\n' "$host"
        return 1
    elif printf '%s' "$result" | grep -q "Permission denied"; then
        if [[ -n $identity ]]; then
            printf '  \e[33mKey rejected or passphrase required — add key to ssh-agent first.\e[0m\n'
        else
            printf '  \e[33mSSH reachable, but permission denied for user '\''%s'\''.\e[0m\n' "$user"
        fi
        return 0
    else
        printf '  \e[32mSSH connection to %s is successful.\e[0m\n' "$host"
        return 0
    fi
}

# Generate an ED25519 key pair.
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
    printf '  \e[90mGenerating SSH key...\e[0m\n'

    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    ssh-keygen -t ed25519 -f "$keypath" -C "$comment" -N "$passphrase"
    chmod 600 "$keypath"

    printf '  \e[32m+\e[0m  \e[36m%s\e[0m  generated.\n' "$keypath"
}

# Add or update a Host block in ~/.ssh/config.
add_ssh_key_to_host_config() {
    local keyname="$1" host_name="$2" host_addr="$3" remote_user="$4"
    local keypath="$SSH_DIR/$keyname"
    local identity_line="    IdentityFile $keypath"
    _dbg "add_ssh_key_to_host_config: keyname='$keyname' host='$host_name'"

    if ! find_private_key "$keyname"; then
        printf '  \e[31mCould not find private SSH key at %s\e[0m\n' "$keypath"
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
            printf '  \e[33mIdentityFile already exists under Host %s.\e[0m\n' "$host_name"
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
        printf '  \e[32mIdentityFile added to existing Host %s.\e[0m\n' "$host_name"
    else
        local entry
        entry=$(printf '\nHost %s\n    HostName %s\n    User %s\n    IdentityFile %s\n' \
            "$host_name" "$host_addr" "$remote_user" "$keypath")
        printf '%s' "$entry" >> "$SSH_CONFIG"
        printf '  \e[32mSSH config block created for %s.\e[0m\n' "$host_name"
        printf '  \e[36mConnect with: ssh %s\e[0m\n' "$host_name"
    fi
}

# Remove all IdentityFile lines referencing KeyName from the named Host block.
remove_identity_file_from_config_block() {
    local keyname="$1" host_alias="$2"
    [[ -f "$SSH_CONFIG" ]] || { printf '  \e[33mNo SSH config found.\e[0m\n'; return 1; }

    _get_host_block "$host_alias"
    if [[ -z $_HOST_BLOCK ]]; then
        printf '  \e[33mNo config block found for '\''%s'\''.\e[0m\n' "$host_alias"
        return 1
    fi

    local esc; esc=$(_regex_escape "$keyname")
    local new_block
    new_block=$(printf '%s\n' "$_HOST_BLOCK" | \
        grep -vE "^\s*IdentityFile\s+.*[/\\\\]?${esc}\s*$" || true)

    if [[ "$new_block" == "$_HOST_BLOCK" ]]; then
        printf '  \e[90mKey '\''%s'\'' not found in config block '\''%s'\''.\e[0m\n' \
            "$keyname" "$host_alias"
        return 0
    fi

    _replace_host_block "$_HOST_BLOCK" "$new_block"
    printf '  \e[32mIdentityFile '\''%s'\'' removed from config block '\''%s'\''.\e[0m\n' \
        "$keyname" "$host_alias"
}

# Install a public key on a remote machine and register in ~/.ssh/config.
install_ssh_key_on_remote() {
    local keyname="$1"
    _dbg "install_ssh_key_on_remote: keyname='$keyname'"

    local pubkey
    pubkey=$(get_public_key "$keyname") || return 1

    local host_addr
    host_addr=$(read_remote_host_address "$DEFAULT_SUBNET_PREFIX") || return 1
    local selected_alias="$_LAST_SELECTED_ALIAS"
    local remote_user
    remote_user=$(read_remote_user "$DEFAULT_USER") || return 1

    local target
    target=$(resolve_ssh_target "$host_addr" "$remote_user")
    _dbg "install_ssh_key_on_remote: target='$target'"

    local id_lookup="${selected_alias:-$host_addr}"
    local k
    while IFS= read -r k; do
        printf '  \e[90mUsing key: %s\e[0m\n' "$k"
    done < <(get_identity_files_for_host "$id_lookup")

    printf '  Connecting to %s...\n' "$target"

    local remote_hostname
    if [[ -n $DEFAULT_PASSWORD ]] && command -v sshpass &>/dev/null; then
        printf '  \e[90mUsing sshpass with stored password.\e[0m\n'
        remote_hostname=$(printf '%s\n' "$pubkey" | \
            sshpass -p "$DEFAULT_PASSWORD" ssh -o StrictHostKeyChecking=accept-new \
            "$target" 'mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname' 2>&1) || {
            printf '  \e[31mFailed to inject SSH key. Check network, credentials, or host status.\e[0m\n'
            _dbg "install_ssh_key_on_remote: sshpass failed"
            return 1
        }
    else
        _ssh_fence "$target"
        remote_hostname=$(printf '%s\n' "$pubkey" | \
            ssh "$target" 'mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname' 2>&1) || {
            _ssh_fence_close
            printf '  \e[31mFailed to inject SSH key. Check network, credentials, or host status.\e[0m\n'
            _dbg "install_ssh_key_on_remote: ssh failed"
            return 1
        }
        _ssh_fence_close
    fi

    printf '  \e[32mSSH Public Key installed successfully.\e[0m\n'
    local default_alias="${selected_alias:-$remote_hostname}"
    printf '  \e[90mRemote hostname: %s\e[0m\n' "$remote_hostname"

    local host_alias
    host_alias=$(read_host_with_default "Name this Host in ~/.ssh/config:" "$default_alias") || \
        host_alias="$default_alias"
    [[ -z $host_alias ]] && host_alias="$default_alias"

    printf '  Registering key to SSH config as '\''%s'\''...\n' "$host_alias"
    add_ssh_key_to_host_config "$keyname" "$host_alias" "$host_addr" "$remote_user"
}

deploy_ssh_key_to_remote() {
    local keyname="$1"
    _dbg "deploy_ssh_key_to_remote: keyname='$keyname'"
    if ! find_private_key "$keyname"; then
        printf '\n%s\e[33mKey does not exist. Generating...\e[0m\n' "$P"
        local comment
        comment=$(read_ssh_key_comment "${keyname}${DEFAULT_COMMENT_SUFFIX}")
        add_ssh_key_in_host "$keyname" "$comment"
    else
        printf '\n%s\e[36mKey already exists. Proceeding with installation...\e[0m\n\n' "$P"
    fi
    install_ssh_key_on_remote "$keyname"
}

# Remove a public key from a remote's authorized_keys.
remove_ssh_key_from_remote() {
    local remote_user="$1" remote_host="$2" keyname="$3"
    _dbg "remove_ssh_key_from_remote: user='$remote_user' host='$remote_host' key='$keyname'"

    local pubkey
    pubkey=$(get_public_key "$keyname") || return 1

    local target
    target=$(resolve_ssh_target "$remote_host" "$remote_user")
    local k
    while IFS= read -r k; do
        printf '  \e[90mUsing key: %s\e[0m\n' "$k"
    done < <(get_identity_files_for_host "$remote_host")

    printf '\n  \e[33mWill connect to remove the public key from %s:\n  %s\e[0m\n\n' \
        "$target" "$(printf '%s' "$pubkey" | tr -d '\n')"

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
        printf '  \e[32mSSH key removed from remote authorized_keys.\e[0m\n'
        local priv="$SSH_DIR/$keyname" pub="$SSH_DIR/${keyname}.pub"
        _do_delete_local_key() {
            [[ -f $priv ]] && rm -f "$priv" && printf '  \e[32mDeleted: %s\e[0m\n' "$priv"
            [[ -f $pub  ]] && rm -f "$pub"  && printf '  \e[32mDeleted: %s\e[0m\n' "$pub"
        }
        confirm_user_choice \
            "  Remove local key '$keyname' from THIS machine?" \
            "n" \
            _do_delete_local_key || true
    else
        printf '  \e[31mFailed to remove the SSH key from remote.\e[0m\n'
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

    printf '  \e[90mConnecting to %s to read authorized_keys...\e[0m\n' "$target"
    _ssh_fence "$target"
    local raw_keys
    raw_keys=$(ssh -o StrictHostKeyChecking=accept-new "$target" \
        "cat ~/.ssh/authorized_keys 2>/dev/null") || {
        _ssh_fence_close
        printf '  \e[31mConnection failed.\e[0m\n'
        return 1
    }
    _ssh_fence_close

    if [[ -z $raw_keys ]]; then
        printf '  \e[33mNo authorized_keys found on %s.\e[0m\n' "$target"
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
        printf '  \e[33mNo local public keys match authorized_keys on %s.\e[0m\n' "$target"
        printf '  \e[90mInstall a key first via '\''Generate & Install'\'' or '\''Install SSH Key'\''.\e[0m\n'
        return
    fi

    printf '  \e[32mFound %d matching local key(s):\e[0m\n' "${#matches[@]}"
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
        [[ -z $priv_path ]] && printf '  \e[31mPath is required.\e[0m\n' && return 1
        priv_path="${priv_path/#\~/$HOME}"
        if [[ ! -f $priv_path ]]; then
            printf '  \e[31mFile not found: %s\e[0m\n' "$priv_path"
            return 1
        fi
        # Try the matching .pub; let user override
        local auto_pub="${priv_path}.pub"
        local pub_path
        printf '  \e[90mPublic key — leave blank to use %s\e[0m\n' "$auto_pub"
        pub_path=$(read_colored_input "  Path to public key file" cyan)
        [[ -z $pub_path ]] && pub_path="$auto_pub"
        pub_path="${pub_path/#\~/$HOME}"
        if [[ ! -f $pub_path ]]; then
            printf '  \e[31mPublic key not found: %s\e[0m\n' "$pub_path"
            return 1
        fi
        priv_src="$priv_path"
        pub_src="$pub_path"
        key_name=$(basename "$priv_src")

    elif [[ $choice == "Remote machine (SCP)" ]]; then
        # ── Remote SCP ──────────────────────────────────────────────────────
        printf '  \e[90mConnect to the machine that holds the keys.\e[0m\n'
        local host_addr
        host_addr=$(read_remote_host_address "$DEFAULT_SUBNET_PREFIX") || return 1
        local remote_user
        remote_user=$(read_remote_user "$DEFAULT_USER") || return 1
        local target="${remote_user}@${host_addr}"

        local remote_priv
        remote_priv=$(read_colored_input "  Full path to private key on remote" cyan)
        [[ -z $remote_priv ]] && printf '  \e[31mPath is required.\e[0m\n' && return 1

        key_name=$(basename "$remote_priv")
        local dest_priv="$SSH_DIR/$key_name"
        local dest_pub="${dest_priv}.pub"

        printf '  \e[90mDownloading %s ...\e[0m\n' "$remote_priv"
        _ssh_fence "$target"
        if ! scp -q "${target}:${remote_priv}" "$dest_priv" 2>&1; then
            _ssh_fence_close
            printf '  \e[31mFailed to download private key.\e[0m\n'
            return 1
        fi
        printf '  \e[90mDownloading %s.pub ...\e[0m\n' "$remote_priv"
        if ! scp -q "${target}:${remote_priv}.pub" "$dest_pub" 2>/dev/null; then
            printf '  \e[33mPublic key not found at %s.pub — skipping.\e[0m\n' "$remote_priv"
        fi
        _ssh_fence_close

        printf '  \e[32mKeys downloaded to %s\e[0m\n' "$SSH_DIR"
        chmod 600 "$dest_priv" 2>/dev/null || true
        [[ -f $dest_pub ]] && chmod 644 "$dest_pub" 2>/dev/null || true
        printf '  \e[32mPermissions set (600 private, 644 public).\e[0m\n'
        # Offer to add to SSH config
        _add_imported_to_config() {
            add_ssh_key_to_host_config "$key_name" "$host_addr" "$host_addr" "$remote_user"
        }
        confirm_user_choice "  Add '$key_name' to ~/.ssh/config?" "y" _add_imported_to_config || true
        return 0
    elif [[ $choice == "Paste key content" ]]; then
        # ── Paste ───────────────────────────────────────────────────────────
        key_name=$(read_colored_input "  Key name (e.g. my-server)" cyan)
        [[ -z $key_name ]] && printf '  \e[31mKey name is required.\e[0m\n' && return 1

        printf '\n  \e[36mPaste the private key.\e[0m\n'
        printf '  \e[90mInput ends automatically at the -----END...----- line.\e[0m\n\n'
        local priv_content="" _pl
        while IFS= read -r _pl; do
            priv_content+="${_pl}"$'\n'
            [[ $_pl == "-----END"* ]] && break
        done
        if [[ $priv_content != *"-----BEGIN"* || $priv_content != *"-----END"* ]]; then
            printf '  \e[31mInvalid private key — BEGIN/END markers not found.\e[0m\n'
            return 1
        fi

        printf '\n  \e[36mPaste the public key (single line, e.g. ssh-ed25519 AAAA...):\e[0m\n'
        local pub_content
        # Skip any blank lines left over from the private key paste
        while IFS= read -r pub_content; do
            [[ -n $pub_content ]] && break
        done
        if [[ -z $pub_content ]]; then
            printf '  \e[31mPublic key is required.\e[0m\n'
            return 1
        fi

        mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"
        local dest_priv="$SSH_DIR/$key_name"
        local dest_pub="${dest_priv}.pub"
        if [[ -f $dest_priv ]]; then
            local overwrite
            overwrite=$(read_colored_input "  '$key_name' already exists. Overwrite? [y/N]" yellow)
            [[ ! ${overwrite,,} =~ ^y ]] && printf '  \e[33mAborted.\e[0m\n' && return 1
        fi
        printf '%s' "$priv_content" > "$dest_priv" && chmod 600 "$dest_priv"
        printf '%s\n' "$pub_content"  > "$dest_pub"  && chmod 644 "$dest_pub"
        printf '  \e[32m+\e[0m  %s  imported.\n' "$dest_priv"
        printf '  \e[32m+\e[0m  %s  imported.\n' "$dest_pub"
        _add_imported_to_config() {
            local host_addr; host_addr=$(read_remote_host_address "$DEFAULT_SUBNET_PREFIX") || return 1
            local remote_user; remote_user=$(read_remote_user "$DEFAULT_USER") || return 1
            add_ssh_key_to_host_config "$key_name" "$host_addr" "$host_addr" "$remote_user"
        }
        confirm_user_choice "  Add '$key_name' to ~/.ssh/config?" "y" _add_imported_to_config || true
        return 0
    else
        return 0
    fi

    # ── Install local copies ─────────────────────────────────────────────────
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    local dest_priv="$SSH_DIR/$key_name"
    local dest_pub="${dest_priv}.pub"

    if [[ -f $dest_priv ]]; then
        local overwrite
        overwrite=$(read_colored_input "  '$key_name' already exists. Overwrite? [y/N]" yellow)
        [[ ! ${overwrite,,} =~ ^y ]] && printf '  \e[33mAborted.\e[0m\n' && return 1
    fi

    cp "$priv_src" "$dest_priv" && chmod 600 "$dest_priv"
    cp "$pub_src"  "$dest_pub"  && chmod 644 "$dest_pub"

    printf '  \e[32m+\e[0m  %s  imported.\n' "$dest_priv"
    printf '  \e[32m+\e[0m  %s  imported.\n' "$dest_pub"

    _add_imported_to_config() {
        local host_addr; host_addr=$(read_remote_host_address "$DEFAULT_SUBNET_PREFIX") || return 1
        local remote_user; remote_user=$(read_remote_user "$DEFAULT_USER") || return 1
        add_ssh_key_to_host_config "$key_name" "$host_addr" "$host_addr" "$remote_user"
    }
    confirm_user_choice "  Add '$key_name' to ~/.ssh/config?" "y" _add_imported_to_config || true
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
        "  Remove demoted key '$key_to_remove' from remote '$remote_host_name'?" \
        "n" \
        _do_demote || true
}
