# lib/bash/menu-support.sh — Conf defaults editor TUI and menu help screen
# Sourced by hddssh.sh — do not execute directly.
# Depends on: tui.sh (_read_key, _term_size, _repeat, show_paged)
#             prompts.sh (read_colored_input)
[[ -n "${_MENU_SUPPORT_SH_LOADED:-}" ]] && return 0
_MENU_SUPPORT_SH_LOADED=1
# EXPORTS: _run_conf_editor  _show_menu_help  _sq

# ─── Shell-quoting helper ─────────────────────────────────────────────────────

# Wrap a value in single quotes, escaping embedded single quotes as '\''.
# Bash 3.2-compatible (uses ${v:0:1} / ${v:1} substring expansion only).
_sq() {
    local _v="$1" _out='' _ch
    while [[ ${#_v} -gt 0 ]]; do
        _ch="${_v:0:1}"
        _v="${_v:1}"
        if [[ "$_ch" == "'" ]]; then _out="${_out}'\\''"
        else _out="${_out}${_ch}"; fi
    done
    printf "'%s'" "$_out"
}

# ─── Command wrapper ──────────────────────────────────────────────────────────

# Break a shell command into display lines with OS-appropriate continuation.
# Args: cmd  cont_char  term_cols  first_indent  cont_indent
# Sets global _WRAP_LINES array.
_conf_wrap() {
    local _cw_cmd="$1" _cw_cont="$2" _cw_cols="$3"
    local _cw_ind="$4" _cw_ci="$5"
    _WRAP_LINES=()
    local _cw_rem="$_cw_cmd" _cw_first=1
    while [[ ${#_cw_rem} -gt 0 ]]; do
        local _cw_pfx
        if (( _cw_first )); then _cw_pfx="$_cw_ind"; else _cw_pfx="$_cw_ci"; fi
        local _cw_avail=$(( _cw_cols - ${#_cw_pfx} ))
        if (( _cw_avail < 3 )); then _WRAP_LINES+=( "${_cw_pfx}..." ); break; fi
        if (( ${#_cw_rem} <= _cw_avail )); then
            _WRAP_LINES+=( "${_cw_pfx}${_cw_rem}" ); break
        fi
        local _cw_max=$(( _cw_avail - 1 - ${#_cw_cont} ))
        (( _cw_max < 1 )) && _cw_max=1
        local _cw_chunk="${_cw_rem:0:$_cw_max}"
        local _cw_sp=-1 _cw_i
        for (( _cw_i = ${#_cw_chunk} - 1; _cw_i >= 0; _cw_i-- )); do
            [[ "${_cw_chunk:$_cw_i:1}" == " " ]] && { _cw_sp=$_cw_i; break; }
        done
        if (( _cw_sp < 0 )); then
            _WRAP_LINES+=( "${_cw_pfx}${_cw_rem:0:$_cw_max} ${_cw_cont}" )
            _cw_rem="${_cw_rem:$_cw_max}"
        else
            _WRAP_LINES+=( "${_cw_pfx}${_cw_rem:0:$_cw_sp} ${_cw_cont}" )
            _cw_rem="${_cw_rem:$((_cw_sp+1))}"
        fi
        _cw_first=0
    done
}

# ─── Conf defaults editor ─────────────────────────────────────────────────────

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
        local rule; rule=$(_repeat '─' "$(( TERM_W - 4 > 0 ? TERM_W - 4 : 0 ))")
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
        [[ -n $DEFAULT_USER           ]] && _bf+=" --user $(_sq "$DEFAULT_USER")"            && _pf+=" -DefaultUserName \"$DEFAULT_USER\""
        [[ -n $DEFAULT_SUBNET_PREFIX  ]] && _bf+=" --subnet $(_sq "$DEFAULT_SUBNET_PREFIX")" && _pf+=" -DefaultSubnetPrefix \"$DEFAULT_SUBNET_PREFIX\""
        [[ -n $DEFAULT_COMMENT_SUFFIX ]] && _bf+=" --comment-suffix $(_sq "$DEFAULT_COMMENT_SUFFIX")" && _pf+=" -DefaultCommentSuffix \"$DEFAULT_COMMENT_SUFFIX\""
        [[ -n $DEFAULT_PASSWORD       ]] && _bf+=" --password $(_sq "$DEFAULT_PASSWORD")"    && _pf+=" -DefaultPassword \"$DEFAULT_PASSWORD\""
        local _c1="bash <(curl -fsSL ${_raw_url}/hddssh.sh)${_bf}"
        local _c2="bash hddssh.sh${_bf}"
        local _c3="\$sb=[scriptblock]::Create((irm \"${_raw_url}/hddssh.ps1\")); & \$sb${_pf}"
        local _c4="& ./hddssh.ps1${_pf}"
        # Wrap each command with OS-appropriate continuation characters
        local _ln _cur_row=11
        cf+="$(printf '\e[%d;1H\e[K' "$_cur_row")"; (( _cur_row++ ))
        cf+="$(printf '\e[%d;1H  \e[90mTo persist across sessions:\e[0m\e[K' "$_cur_row")"; (( _cur_row++ ))
        cf+="$(printf '\e[%d;1H\e[K' "$_cur_row")"; (( _cur_row++ ))
        cf+="$(printf '\e[%d;1H  \e[90m☁️  Bash · cloud\e[0m\e[K' "$_cur_row")"; (( _cur_row++ ))
        _conf_wrap "$_c1" "\\" "$TERM_W" "    " "        "
        for _ln in "${_WRAP_LINES[@]}"; do
            (( _cur_row >= TERM_H )) && break
            cf+="$(printf '\e[%d;1H\e[33m%s\e[0m\e[K' "$_cur_row" "$_ln")"; (( _cur_row++ ))
        done
        cf+="$(printf '\e[%d;1H  \e[90m🏠  Bash · local\e[0m\e[K' "$_cur_row")"; (( _cur_row++ ))
        _conf_wrap "$_c2" "\\" "$TERM_W" "    " "        "
        for _ln in "${_WRAP_LINES[@]}"; do
            (( _cur_row >= TERM_H )) && break
            cf+="$(printf '\e[%d;1H\e[33m%s\e[0m\e[K' "$_cur_row" "$_ln")"; (( _cur_row++ ))
        done
        cf+="$(printf '\e[%d;1H\e[K' "$_cur_row")"; (( _cur_row++ ))
        cf+="$(printf '\e[%d;1H  \e[90m☁️  PowerShell · cloud\e[0m\e[K' "$_cur_row")"; (( _cur_row++ ))
        _conf_wrap "$_c3" '`' "$TERM_W" "    " "        "
        for _ln in "${_WRAP_LINES[@]}"; do
            (( _cur_row >= TERM_H )) && break
            cf+="$(printf '\e[%d;1H\e[36m%s\e[0m\e[K' "$_cur_row" "$_ln")"; (( _cur_row++ ))
        done
        cf+="$(printf '\e[%d;1H  \e[90m🏠  PowerShell · local\e[0m\e[K' "$_cur_row")"; (( _cur_row++ ))
        _conf_wrap "$_c4" '`' "$TERM_W" "    " "        "
        for _ln in "${_WRAP_LINES[@]}"; do
            (( _cur_row >= TERM_H )) && break
            cf+="$(printf '\e[%d;1H\e[36m%s\e[0m\e[K' "$_cur_row" "$_ln")"; (( _cur_row++ ))
        done

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
        "  $(printf '\e[1;97m🗑  Delete SSH Key From A Remote Machine\e[0m')"
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
        "  $(printf '\e[1;97m🗝  List SSH Keys\e[0m')"
        "  $(printf '\e[90mShows all key pairs in ~/.ssh with fingerprints and which host config\e[0m')"
        "  $(printf '\e[90mentries reference each key. Useful for auditing your key inventory.\e[0m')"
        ""
        "  $(printf '\e[1;97m➕  Append SSH Key to Hostname in Host Config\e[0m')"
        "  $(printf '\e[90mAdds an IdentityFile line to an existing host block in ~/.ssh/config.\e[0m')"
        "  $(printf '\e[90mUse when a remote host should accept more than one of your local keys.\e[0m')"
        ""
        "  $(printf '\e[1;97m🗑  Delete an SSH Key Locally\e[0m')"
        "  $(printf '\e[90mRemoves the private and public key files from ~/.ssh on this machine only.\e[0m')"
        "  $(printf '\e[90mDoes NOT revoke the key from any remote host — use Delete From Remote first.\e[0m')"
        ""
        "  $(printf '\e[1;97m❌  Remove an SSH Key From Config\e[0m')"
        "  $(printf '\e[90mRemoves an IdentityFile reference from a host block in ~/.ssh/config without\e[0m')"
        "  $(printf '\e[90mdeleting the key files themselves.\e[0m')"
        ""
        "  $(printf '\e[1;97m📥  Import SSH Key from Another Machine\e[0m')"
        "  $(printf '\e[90mBrings a key into ~/.ssh from four sources:\e[0m')"
        "  $(printf '\e[90m  1. SSH Agent — pick a key from a forwarded SSH agent (when connected\e[0m')"
        "  $(printf '\e[90m     with ForwardAgent yes); imports only the public key — the private\e[0m')"
        "  $(printf '\e[90m     key stays on your origin machine and is used via SSH_AUTH_SOCK.\e[0m')"
        "  $(printf '\e[90m  2. Local file path — copy from a path already on this machine\e[0m')"
        "  $(printf '\e[90m  3. Remote machine (SCP) — download directly from another host\e[0m')"
        "  $(printf '\e[90m  4. Paste key content — paste the private and public key text directly\e[0m')"
        ""
        "  $(printf '\e[2m─── Config File ────────────────────────────────────────────────────────────\e[0m')"
        ""
        "  $(printf '\e[1;97m🏚  Remove Host from SSH Config\e[0m')"
        "  $(printf '\e[90mDeletes an entire Host block from ~/.ssh/config. Use when decommissioning\e[0m')"
        "  $(printf '\e[90ma machine or cleaning up stale entries.\e[0m')"
        ""
        "  $(printf '\e[1;97m👁  View SSH Config\e[0m')"
        "  $(printf '\e[90mDisplays the current ~/.ssh/config content with syntax highlighting.\e[0m')"
        ""
        "  $(printf '\e[1;97m📝  Edit SSH Config\e[0m')"
        "  $(printf '\e[90mOpens ~/.ssh/config in \$EDITOR (or nano) for manual editing.\e[0m')"
        ""
    )
    show_paged "${lines[@]}"
}
