# lib/ssh-helpers.sh — SSH utility helpers shared across ssh-ops and menu
# Sourced by ssh-key-manager.sh — do not execute directly.
[[ -n "${_SSH_HELPERS_SH_LOADED:-}" ]] && return 0
_SSH_HELPERS_SH_LOADED=1

# ─── Output helpers ───────────────────────────────────────────────────────────

# _out STYLE FORMAT [ARGS...]
# Prints a 2-space indented, color-coded line to stdout.
# Styles: ok (green)  warn (yellow)  error (red)  info (cyan)
#         dim (gray)  heading (bright-cyan)  plain (bright-white)
_out() {
    local style="$1" fmt="$2"; shift 2
    local code
    case "$style" in
        ok)      code=32 ;;
        warn)    code=33 ;;
        error)   code=31 ;;
        info)    code=36 ;;
        dim)     code=90 ;;
        heading) code=96 ;;
        plain)   code=97 ;;
        *)       code=37 ;;
    esac
    # shellcheck disable=SC2059
    printf "  \e[${code}m${fmt}\e[0m\n" "$@"
}

# _out_item FORMAT [ARGS...]
# Prints "  + FORMAT" with a green plus sign and plain unstyled text.
_out_item() {
    local fmt="$1"; shift
    # shellcheck disable=SC2059
    printf "  \e[32m+\e[0m  ${fmt}\n" "$@"
}

# ─── Connection helpers ───────────────────────────────────────────────────────

# TCP port-22 pre-check. Returns 0 if reachable.
_tcp_check() {
    local host="$1"
    timeout 3 bash -c "echo >/dev/tcp/$host/22" 2>/dev/null
}

# Opening fence rule: "── SSH Session user@host ──"
_ssh_fence() {
    local target="${1:-}"
    _term_size
    local inner_w=$(( TERM_W - 4 > 0 ? TERM_W - 4 : 10 ))
    local label=""
    [[ -n $target ]] && label=" SSH Session ${target} "
    if [[ -n $label ]]; then
        local llen=${#label}
        local dtotal=$(( inner_w - llen ))
        (( dtotal < 4 )) && dtotal=4
        local lw=$(( dtotal / 2 )) rw=$(( dtotal - dtotal / 2 ))
        printf '  \e[2m%s\e[0m\e[90m%s\e[0m\e[2m%s\e[0m\n' \
            "$(_repeat '─' "$lw")" "$label" "$(_repeat '─' "$rw")"
    else
        printf '  \e[2m%s\e[0m\n' "$(_repeat '─' "$inner_w")"
    fi
}

# Closing fence rule: "── SSH session closed ──"
_ssh_fence_close() {
    _term_size
    local inner_w=$(( TERM_W - 4 > 0 ? TERM_W - 4 : 10 ))
    local label=" SSH session closed "
    local llen=${#label}
    local dtotal=$(( inner_w - llen ))
    (( dtotal < 4 )) && dtotal=4
    local lw=$(( dtotal / 2 )) rw=$(( dtotal - dtotal / 2 ))
    printf '  \e[2m%s\e[0m\e[90m%s\e[0m\e[2m%s\e[0m\n' \
        "$(_repeat '─' "$lw")" "$label" "$(_repeat '─' "$rw")"
}

# Create a temporary SSH_ASKPASS helper so password/passphrase prompts are
# displayed with 2-space padding. Requires OpenSSH 8.4+ (SSH_ASKPASS_REQUIRE=force).
# Call _destroy_askpass when the SSH operation completes.
_setup_askpass() {
    _ASKPASS_TMP=$(mktemp /tmp/.ssh-askpass-XXXXXX 2>/dev/null) || return 0
    chmod 700 "$_ASKPASS_TMP"
    cat > "$_ASKPASS_TMP" << 'ASKPASS_SCRIPT'
#!/bin/bash
printf '  \e[36m%s\e[0m' "$1" >/dev/tty
stty -echo </dev/tty 2>/dev/null
IFS= read -r _pw </dev/tty
stty echo </dev/tty 2>/dev/null
printf '\n' >/dev/tty
printf '%s\n' "$_pw"
ASKPASS_SCRIPT
    export SSH_ASKPASS="$_ASKPASS_TMP"
    export SSH_ASKPASS_REQUIRE=force
}

_destroy_askpass() {
    rm -f "${_ASKPASS_TMP:-}"
    unset SSH_ASKPASS SSH_ASKPASS_REQUIRE _ASKPASS_TMP
}

# ─── Local filesystem helpers ─────────────────────────────────────────────────

# Ensure ~/.ssh exists with correct permissions.
_ensure_ssh_dir() {
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
}

# Write a key pair to ~/.ssh and set permissions.
# Prompts for overwrite confirmation if the private key already exists.
# Args: dest_priv dest_pub priv_data pub_data [copy_mode]
#   copy_mode=1 → cp priv_data/pub_data as file paths
#   copy_mode=0 → write priv_data/pub_data as literal strings (default)
# Returns 1 if aborted.
_write_key_pair() {
    local dest_priv="$1" dest_pub="$2" priv_data="$3" pub_data="$4" copy="${5:-0}"
    if [[ -f $dest_priv ]]; then
        local overwrite
        overwrite=$(read_colored_input "  '$(basename "$dest_priv")' already exists. Overwrite? [y/N]" yellow)
        [[ ! ${overwrite,,} =~ ^y ]] && _out warn 'Aborted.' && return 1
    fi
    if (( copy )); then
        cp "$priv_data" "$dest_priv" && chmod 600 "$dest_priv"
        cp "$pub_data"  "$dest_pub"  && chmod 644 "$dest_pub"
    else
        printf '%s' "$priv_data" > "$dest_priv" && chmod 600 "$dest_priv"
        printf '%s\n' "${pub_data%$'\n'}" > "$dest_pub" && chmod 644 "$dest_pub"
    fi
    _out_item '%s  imported.' "$dest_priv"
    _out_item '%s  imported.' "$dest_pub"
}

# ─── Prompt helpers ───────────────────────────────────────────────────────────

# Print the IdentityFile entries configured for a host (informational only).
_print_identity_files() {
    local id_lookup="$1"
    local k
    while IFS= read -r k; do
        _out dim 'Using key: %s' "$k"
    done < <(get_identity_files_for_host "$id_lookup")
}

# Prompt for a remote host and user in one call.
# Sets globals: _REMOTE_HOST  _REMOTE_USER  _REMOTE_ALIAS
# Returns 1 if the user cancels either prompt.
_prompt_remote() {
    _REMOTE_HOST=$(read_remote_host_address "$DEFAULT_SUBNET_PREFIX") || return 1
    _REMOTE_ALIAS=$(get_alias_for_host_ip "$_REMOTE_HOST")
    _REMOTE_USER=$(read_remote_user "$DEFAULT_USER") || return 1
}
