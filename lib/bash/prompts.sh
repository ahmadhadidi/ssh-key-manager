# lib/prompts.sh — Input/prompt functions and finders
# Sourced by sshhdd.sh — do not execute directly.
[[ -n "${_PROMPTS_SH_LOADED:-}" ]] && return 0
_PROMPTS_SH_LOADED=1

# Use a foolproof way to get the absolute path of the directory containing this script
_PROMPTS_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Source TUI dependency using the absolute path
if [[ -f "${_PROMPTS_DIR}/tui.sh" ]]; then
    source "${_PROMPTS_DIR}/tui.sh"
else
    echo "CRITICAL: Could not find ${_PROMPTS_DIR}/tui.sh" >&2
fi

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
    _RCI_RESULT=""
    local buf=""
    local cur=0
    # Hold raw mode for the entire input session so ESC is never echoed.
    local _rci_st
    _rci_st=$(stty -g 2>/dev/null) || true
    stty -echo -icanon min 1 time 0 2>/dev/null || true

    while true; do
        # Read one key using the same multi-byte-aware logic as _read_key,
        # but without the per-call stty save/restore (we own the mode here).
        local k
        IFS= read -r -n1 k 2>/dev/null || k=''
        [[ -z $k ]] && k=$'\n'
        if [[ $k == $'\x1b' ]]; then
            # Use _esc_drain (read -r, no -n) — read -r -n1 blocks on Linux bash 3.2
            # because -n prevents the 0-byte VTIME return from being treated as EOF.
            _esc_drain ""
            stty -echo -icanon min 1 time 0 2>/dev/null || true
            k="${k}${_ESC_TAIL}"
        fi

        case "$k" in
            $'\r'|$'\n')
                printf '\n\e[?25l' >&2
                stty "$_rci_st" 2>/dev/null || true
                _RCI_RESULT="$buf"
                printf '%s' "$buf"
                return 0
                ;;
            $'\x1b')
                # Bare ESC (no trailing bytes) — cancel
                printf '\n\e[?25l' >&2
                stty "$_rci_st" 2>/dev/null || true
                _SELECT_CANCELLED=1
                _RCI_RESULT=""
                return 1  # <--- CRITICAL: Exit the function immediately
                ;;
            "$KEY_LEFT")
                if (( cur > 0 )); then
                    (( cur-- ))
                    printf '\b' >&2
                fi
                ;;
            "$KEY_RIGHT")
                if (( cur < ${#buf} )); then
                    printf '%s' "${buf:$cur:1}" >&2
                    (( cur++ ))
                fi
                ;;
            "$KEY_HOME"|"$KEY_HOME2")
                if (( cur > 0 )); then
                    local _i
                    for (( _i=0; _i<cur; _i++ )); do printf '\b' >&2; done
                    cur=0
                fi
                ;;
            "$KEY_END"|"$KEY_END2")
                if (( cur < ${#buf} )); then
                    printf '%s' "${buf:$cur}" >&2
                    cur=${#buf}
                fi
                ;;
            "$KEY_DEL")
                if (( cur < ${#buf} )); then
                    local rest="${buf:$(( cur+1 ))}"
                    buf="${buf:0:$cur}${rest}"
                    printf '%s ' "${rest}" >&2
                    local _back=$(( ${#rest} + 1 )) _i
                    for (( _i=0; _i<_back; _i++ )); do printf '\b' >&2; done
                fi
                ;;
            $'\x7f'|$'\x08')
                if (( cur > 0 )); then
                    local rest="${buf:$cur}"
                    buf="${buf:0:$(( cur-1 ))}${rest}"
                    (( cur-- ))
                    printf '\b' >&2
                    printf '%s ' "${rest}" >&2
                    local _back=$(( ${#rest} + 1 )) _i
                    for (( _i=0; _i<_back; _i++ )); do printf '\b' >&2; done
                fi
                ;;
            $'\x1b\x7f'|$'\x1b\x08'|$'\x17')
                # ALT+Backspace or Ctrl+W — delete word before cursor
                if (( cur > 0 )); then
                    local _old_cur=$cur
                    while (( cur > 0 )) && [[ "${buf:$(( cur-1 )):1}" == " " ]]; do (( cur-- )); done
                    while (( cur > 0 )) && [[ "${buf:$(( cur-1 )):1}" != " " ]]; do (( cur-- )); done
                    local _deleted=$(( _old_cur - cur ))
                    if (( _deleted > 0 )); then
                        local rest="${buf:$_old_cur}"
                        buf="${buf:0:$cur}${rest}"
                        local _i
                        for (( _i=0; _i<_deleted; _i++ )); do printf '\b' >&2; done
                        printf '%s' "${rest}" >&2
                        for (( _i=0; _i<_deleted; _i++ )); do printf ' ' >&2; done
                        local _back=$(( ${#rest} + _deleted ))
                        for (( _i=0; _i<_back; _i++ )); do printf '\b' >&2; done
                    fi
                fi
                ;;
            *)
                # Accept printable single-byte characters only
                if [[ ${#k} -eq 1 ]] && (( $(printf '%d' "'$k" 2>/dev/null || echo 0) >= 32 )); then
                    local rest="${buf:$cur}"
                    buf="${buf:0:$cur}${k}${rest}"
                    (( cur++ ))
                    printf '%s' "${k}${rest}" >&2
                    if (( ${#rest} > 0 )); then
                        local _i
                        for (( _i=0; _i<${#rest}; _i++ )); do printf '\b' >&2; done
                    fi
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
    local cur=${#buf}
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
                printf '\e[?25l\n' >&2
                _SELECT_CANCELLED=1
                return 1  # <--- CRITICAL: Exit the function immediately
                ;;
            "$KEY_LEFT")
                if (( cur > 0 )); then
                    (( cur-- ))
                    printf '\b' >&2
                fi
                ;;
            "$KEY_RIGHT")
                if (( cur < ${#buf} )); then
                    printf '%s' "${buf:$cur:1}" >&2
                    (( cur++ ))
                fi
                ;;
            "$KEY_HOME"|"$KEY_HOME2")
                if (( cur > 0 )); then
                    local _i
                    for (( _i=0; _i<cur; _i++ )); do printf '\b' >&2; done
                    cur=0
                fi
                ;;
            "$KEY_END"|"$KEY_END2")
                if (( cur < ${#buf} )); then
                    printf '%s' "${buf:$cur}" >&2
                    cur=${#buf}
                fi
                ;;
            "$KEY_DEL")
                if (( cur < ${#buf} )); then
                    local rest="${buf:$(( cur+1 ))}"
                    buf="${buf:0:$cur}${rest}"
                    printf '%s ' "${rest}" >&2
                    local _back=$(( ${#rest} + 1 )) _i
                    for (( _i=0; _i<_back; _i++ )); do printf '\b' >&2; done
                fi
                ;;
            "$KEY_BACKSPACE"|"$KEY_BACKSPACE2")
                if (( cur > 0 )); then
                    local rest="${buf:$cur}"
                    buf="${buf:0:$(( cur-1 ))}${rest}"
                    (( cur-- ))
                    printf '\b' >&2
                    printf '%s ' "${rest}" >&2
                    local _back=$(( ${#rest} + 1 )) _i
                    for (( _i=0; _i<_back; _i++ )); do printf '\b' >&2; done
                fi
                ;;
            $'\x1b\x7f'|$'\x1b\x08'|$'\x17')
                # ALT+Backspace or Ctrl+W — delete word before cursor
                if (( cur > 0 )); then
                    local _old_cur=$cur
                    while (( cur > 0 )) && [[ "${buf:$(( cur-1 )):1}" == " " ]]; do (( cur-- )); done
                    while (( cur > 0 )) && [[ "${buf:$(( cur-1 )):1}" != " " ]]; do (( cur-- )); done
                    local _deleted=$(( _old_cur - cur ))
                    if (( _deleted > 0 )); then
                        local rest="${buf:$_old_cur}"
                        buf="${buf:0:$cur}${rest}"
                        local _i
                        for (( _i=0; _i<_deleted; _i++ )); do printf '\b' >&2; done
                        printf '%s' "${rest}" >&2
                        for (( _i=0; _i<_deleted; _i++ )); do printf ' ' >&2; done
                        local _back=$(( ${#rest} + _deleted ))
                        for (( _i=0; _i<_back; _i++ )); do printf '\b' >&2; done
                    fi
                fi
                ;;
            *)
                if [[ ${#k} -eq 1 ]] && (( $(printf '%d' "'$k" 2>/dev/null || echo 0) >= 32 )); then
                    local rest="${buf:$cur}"
                    buf="${buf:0:$cur}${k}${rest}"
                    (( cur++ ))
                    printf '%s' "${k}${rest}" >&2
                    if (( ${#rest} > 0 )); then
                        local _i
                        for (( _i=0; _i<${#rest}; _i++ )); do printf '\b' >&2; done
                    fi
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

    local -a host_entries=() host_aliases=() host_ips=()
    while IFS='|' read -r alias hn user; do
        host_aliases+=("$alias")
        host_ips+=("$hn")
        if [[ -n $hn ]]; then
            host_entries+=("$alias  ($hn)")
        else
            host_entries+=("$alias")
        fi
    done < <(get_configured_ssh_hosts)

    if (( ${#host_entries[@]} > 0 )); then
        # Probe all configured hosts in parallel (2 s timeout per host).
        local -a _probe_files=() _probe_pids=()
        local _pi _pf
        for (( _pi=0; _pi<${#host_ips[@]}; _pi++ )); do
            _pf=$(mktemp /tmp/.hprobe-XXXXXX 2>/dev/null || \
                  printf '/tmp/.hprobe-%s-%d' "$$" "$_pi")
            _probe_files+=("$_pf")
            ( timeout 2 bash -c "echo >/dev/tcp/${host_ips[$_pi]}/22" 2>/dev/null \
                && printf 1 || printf 0 ) > "$_pf" &
            _probe_pids+=($!)
        done
        _spin_start "Checking host availability..."
        for _pi in "${_probe_pids[@]}"; do wait "$_pi" 2>/dev/null || true; done
        _spin_stop

        # Build display list: green ● for reachable, dim ● for unreachable.
        # Use \e[97m (fg reset only) not \e[0m so the teal selection bg is preserved.
        local _dot_green=$'\e[32m●\e[97m '
        local _dot_dim=$'\e[90m●\e[97m '
        local -a _dot_entries=()
        local _reach _pfc
        for (( _pi=0; _pi<${#host_ips[@]}; _pi++ )); do
            _reach=0
            if [[ -f "${_probe_files[$_pi]}" ]]; then
                _pfc=$(cat "${_probe_files[$_pi]}" 2>/dev/null)
                [[ "$_pfc" == "1" ]] && _reach=1
                rm -f "${_probe_files[$_pi]}" 2>/dev/null || true
            fi
            if (( _reach )); then
                _dot_entries+=("${_dot_green}${host_entries[$_pi]}")
            else
                _dot_entries+=("${_dot_dim}${host_entries[$_pi]}")
            fi
        done

        select_from_list -p "Select remote host  (Esc = enter manually)" "${_dot_entries[@]}"
        (( _SELECT_CANCELLED )) && return 1
        if [[ -n $_SELECT_RESULT ]]; then
            local _sel_disp="$_SELECT_RESULT"
            for (( _pi=0; _pi<${#_dot_entries[@]}; _pi++ )); do
                if [[ "${_dot_entries[$_pi]}" == "$_sel_disp" ]]; then
                    _LAST_SELECTED_ALIAS="${host_aliases[$_pi]}"
                    if [[ -n "${host_ips[$_pi]}" ]]; then
                        printf '%s' "${host_ips[$_pi]}"
                    else
                        printf '%s' "${host_aliases[$_pi]}"
                    fi
                    return 0
                fi
            done
        fi
    fi

    # Call read_colored_input directly (not via $()) to avoid nested subshells.
    # Result is in _RCI_RESULT; stdout of read_colored_input is discarded.
    _RCI_RESULT=""
    read_colored_input \
        "  Enter remote IP / hostname (or last 1-3 digits for ${subnet}.xx):" cyan >/dev/null
    local addr="$_RCI_RESULT"
    if [[ -z $addr ]]; then
        (( _SELECT_CANCELLED )) || printf '  \e[31m No input provided.\e[0m\n' >&2
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

    # 1. Try the selection list first
    if (( ${#aliases[@]} > 0 )); then
        select_from_list -p "Select host alias  (Esc = enter manually)" "${aliases[@]}"
        (( _SELECT_CANCELLED )) && return 1
        if [[ -n $_SELECT_RESULT ]]; then
            printf '%s' "$_SELECT_RESULT"
            return 0
        fi
    fi

    # 2. Manual entry fallback (if list was empty or had no selection)
    _RCI_RESULT=""
    # Call directly to ensure _SELECT_CANCELLED isn't lost in a subshell
    read_colored_input "  Enter the host alias / hostname" cyan >/dev/null
    
    # 3. Check if they pressed ESC during manual entry
    if (( _SELECT_CANCELLED )); then 
        return 1 
    fi
    
    # 4. Validate and Return
    if [[ -z "$_RCI_RESULT" ]]; then
        printf '  \e[31mHostname is required.\e[0m\n' >&2
        return 1
    fi
    
    printf '%s' "$_RCI_RESULT"
}

read_ssh_key_name() {
    local -a keys=()
    while IFS= read -r k; do keys+=("$k"); done < <(get_available_ssh_keys)

    # 1. Try the selection list
    if (( ${#keys[@]} > 0 )); then
        select_from_list -p "Select SSH key" "${keys[@]}"
        (( _SELECT_CANCELLED )) && return 1
        if [[ -n $_SELECT_RESULT ]]; then
            printf '%s' "$_SELECT_RESULT"
            return 0
        fi
    fi

    # 2. Manual entry with validation loop
    while true; do
        _RCI_RESULT=""
        read_colored_input "  Enter SSH key name" cyan >/dev/null
        
        # 3. Check if ESC was pressed - exit immediately
        if (( _SELECT_CANCELLED )); then
            return 1
        fi

        # 4. Validate non-empty
        if [[ -n "$_RCI_RESULT" ]]; then
            printf '%s' "$_RCI_RESULT"
            return 0
        fi

        printf '  \e[31mKey name is required.\e[0m\n' >&2
    done
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
