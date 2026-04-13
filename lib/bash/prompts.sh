# lib/prompts.sh — Input/prompt functions and finders
# Sourced by hddssh.sh — do not execute directly.
[[ -n "${_PROMPTS_SH_LOADED:-}" ]] && return 0
_PROMPTS_SH_LOADED=1
# EXPORTS: read_colored_input  read_host_with_default
#          read_remote_user  read_remote_host_address  read_remote_host_name
#          read_ssh_key_name  read_ssh_key_comment  confirm_user_choice
#          find_config_file  find_private_key  find_public_key
#          get_public_key  resolve_ssh_target

# ─── Input / prompt functions ─────────────────────────────────────────────────

# Prompt with color. Result printed to stdout.
read_colored_input() {
    local prompt="${1:-Input}" color="${2:-cyan}"
    local code
    case "$color" in
        cyan)    code=36 ;;
        yellow)  code=33 ;;
        green)   code=32 ;;
        red)     code=31 ;;
        gray)    code=90 ;;
        *)       code=37 ;;
    esac
    printf '\e[%dm%s \e[0m\e[?25h' "$code" "$prompt" >&2

    _SELECT_CANCELLED=0
    local buf=""
    # Hold raw mode for the entire input session so ESC is never echoed.
    local _rci_st
    _rci_st=$(stty -g 2>/dev/null) || true
    stty -echo -icanon min 1 time 0 2>/dev/null || true

    while true; do
        # Read one key using the same multi-byte-aware logic as _read_key,
        # but without the per-call stty save/restore (we own the mode here).
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

        case "$k" in
            $'\r'|$'\n')
                printf '\n\e[?25l' >&2
                stty "$_rci_st" 2>/dev/null || true
                printf '%s' "$buf"
                return 0
                ;;
            $'\x1b')
                # Bare ESC (no trailing bytes) — cancel
                printf '\n\e[?25l' >&2
                stty "$_rci_st" 2>/dev/null || true
                _SELECT_CANCELLED=1
                printf ''
                return 1
                ;;
            $'\x7f'|$'\x08')
                if (( ${#buf} > 0 )); then
                    buf="${buf%?}"
                    printf '\b \b' >&2
                fi
                ;;
            $'\x1b\x7f'|$'\x1b\x08'|$'\x17')
                # ALT+Backspace or Ctrl+W — delete previous word
                local _tmp="$buf" _cnt=0
                while [[ ${#_tmp} -gt 0 && "${_tmp: -1}" == " " ]]; do _tmp="${_tmp%?}"; (( _cnt++ )); done
                while [[ ${#_tmp} -gt 0 && "${_tmp: -1}" != " " ]]; do _tmp="${_tmp%?}"; (( _cnt++ )); done
                if (( _cnt > 0 )); then
                    local _i; for (( _i=0; _i<_cnt; _i++ )); do printf '\b \b' >&2; done
                    buf="$_tmp"
                fi
                ;;
            *)
                # Accept printable single-byte characters only
                if [[ ${#k} -eq 1 ]] && (( $(printf '%d' "'$k" 2>/dev/null || echo 0) >= 32 )); then
                    buf+="$k"
                    printf '%s' "$k" >&2
                fi
                ;;
        esac
    done
}

# Show a prompt with a default value pre-filled and editable (char-by-char).
# Returns the edited value (or default on Enter). ESC sets _SELECT_CANCELLED=1.
read_host_with_default() {
    local prompt="${1:-Value:}" default="${2:-}"
    printf '  \e[36m%s\e[0m  ' "$prompt" >&2
    printf '%s' "$default" >&2
    printf '\e[?25h' >&2

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
            $'\x1b\x7f'|$'\x1b\x08'|$'\x17')
                # ALT+Backspace or Ctrl+W — delete previous word
                local _tmp="$buf" _cnt=0
                while [[ ${#_tmp} -gt 0 && "${_tmp: -1}" == " " ]]; do _tmp="${_tmp%?}"; (( _cnt++ )); done
                while [[ ${#_tmp} -gt 0 && "${_tmp: -1}" != " " ]]; do _tmp="${_tmp%?}"; (( _cnt++ )); done
                if (( _cnt > 0 )); then
                    local _i; for (( _i=0; _i<_cnt; _i++ )); do printf '\b \b' >&2; done
                    buf="$_tmp"
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
            local alias="${sel%%  (*}"
            alias="${alias%"${alias##*[! ]}"}"
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
    fi

    local addr
    addr=$(read_colored_input \
        "  Enter remote IP / hostname (or last 1-3 digits for ${subnet}.xx)" cyan)
    if [[ -z $addr ]]; then
        printf '  \e[31m No input provided.\e[0m\n' >&2
        printf ''
        return 1
    fi
    if [[ $addr =~ ^[0-9]{1,3}$ ]]; then
        local resolved="${subnet}.${addr}"
        printf '  \e[32mInterpreted as: %s\e[0m\n' "$resolved" >&2
        printf '%s' "$resolved"
        return 0
    fi
    if [[ $addr =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        printf '  \e[36mFull IP address: %s\e[0m\n' "$addr" >&2
        printf '%s' "$addr"
        return 0
    fi
    printf '  \e[36mHostname: %s\e[0m\n' "$addr" >&2
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
        printf '  \e[31mHostname is required.\e[0m\n' >&2
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
        (( _SELECT_CANCELLED )) && return 1
        printf '  \e[31mKey name is required.\e[0m\n' >&2
        read_ssh_key_name
        return $?
    fi
    printf '%s' "$name"
}

read_ssh_key_comment() {
    local default="${1:-}"
    read_host_with_default "Key comment:" "$default"
}

# Y/N confirmation. Executes action_fn (no args) if confirmed.
confirm_user_choice() {
    local message="$1" default="${2:-n}"
    local action_fn="$3"
    local suffix
    if [[ "$default" == [yY] ]]; then suffix="[Y/n]"
    elif [[ "$default" == [nN] ]]; then suffix="[y/N]"
    else suffix="[y/n]"
    fi

    local response
    response=$(read_colored_input "$message $suffix" cyan)
    [[ -z $response ]] && response="$default"

    case "$response" in
        y|Y|yes|Yes|YES)
            "$action_fn"
            return 0
            ;;
        n|N|no|No|NO)
            printf '  \e[33mAction cancelled.\e[0m\n'
            return 1
            ;;
        *)
            printf '  \e[31mInvalid input. Please enter y or n.\e[0m\n'
            confirm_user_choice "$message" "$default" "$action_fn"
            ;;
    esac
}

# ─── Finders / getters ────────────────────────────────────────────────────────

find_config_file() {
    if [[ ! -f "$SSH_CONFIG" ]]; then
        printf '  \e[33mSSH config file not found at %s.\e[0m\n' "$SSH_CONFIG" >&2
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

get_public_key() {
    local keyname="$1"
    local path="$SSH_DIR/${keyname}.pub"
    if [[ ! -f "$path" ]]; then
        printf '  \e[31mPublic key '\''%s.pub'\'' not found at %s.\e[0m\n' "$keyname" "$path" >&2
        return 1
    fi
    # Feedback goes to stderr so callers using pubkey=$(get_public_key ...) capture
    # only the raw key content — no ANSI codes or status messages mixed in.
    printf '  \e[32mPublic key loaded.\e[0m\n' >&2
    cat "$path"
}

# Given an IP/address and user, return "user@alias" if a matching Host block exists,
# or fall back to "user@address".
resolve_ssh_target() {
    local addr="$1" user="$2"
    if [[ -f "$SSH_CONFIG" ]]; then
        while IFS='|' read -r alias hn _; do
            if [[ $alias == "$addr" ]]; then
                printf '  \e[90mSSH config entry '\''%s'\'' will be used.\e[0m\n' "$alias" >&2
                printf '%s@%s' "$user" "$alias"
                return 0
            fi
            if [[ -n $hn && $hn == "$addr" ]]; then
                printf '  \e[90mSSH config entry '\''%s'\'' found for %s.\e[0m\n' "$alias" "$addr" >&2
                printf '%s@%s' "$user" "$alias"
                return 0
            fi
        done < <(get_configured_ssh_hosts)
    fi
    printf '%s@%s' "$user" "$addr"
}
