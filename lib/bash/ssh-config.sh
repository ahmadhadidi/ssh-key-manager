# lib/ssh-config.sh — SSH config parsing
# Sourced by hddssh.sh — do not execute directly.
[[ -n "${_SSH_CONFIG_SH_LOADED:-}" ]] && return 0
_SSH_CONFIG_SH_LOADED=1
# EXPORTS: get_configured_ssh_hosts  get_available_ssh_keys
#          _get_host_block  _replace_host_block  _block_field
#          get_identity_files_for_host  get_hosts_using_key
#          get_alias_for_host_ip  get_ip_from_host_config
#          get_user_from_host_config  get_identity_file_from_host_config

# ─── SSH config parsing ───────────────────────────────────────────────────────

# Print "alias|hostname|user" for every non-wildcard Host block in ~/.ssh/config.
get_configured_ssh_hosts() {
    [[ -f "$SSH_CONFIG" ]] || return 0
    awk '
        /^Host[[:space:]]/ {
            if (alias != "" && alias != "*") print alias "|" hn "|" user
            alias=$2; hn=""; user=""
        }
        /^[[:space:]]*HostName[[:space:]]/ { hn=$2 }
        /^[[:space:]]*User[[:space:]]/     { user=$2 }
        END { if (alias != "" && alias != "*") print alias "|" hn "|" user }
    ' "$SSH_CONFIG"
}

# Print names of private key files in ~/.ssh (no .pub, excluding system files).
get_available_ssh_keys() {
    [[ -d "$SSH_DIR" ]] || return 0
    local exclude="config known_hosts known_hosts.old authorized_keys authorized_keys2 environment rc"
    local f
    for f in "$SSH_DIR"/*; do
        [[ -f "$f" ]] || continue
        local name; name=$(basename "$f")
        [[ $name == *.pub ]] && continue
        local skip=0
        local ex
        for ex in $exclude; do [[ ${name,,} == "$ex" ]] && skip=1 && break; done
        (( skip )) || printf '%s\n' "$name"
    done | sort
}

# Extract the full text of the Host block for a given alias. Sets _HOST_BLOCK global.
_get_host_block() {
    local alias="$1"
    _HOST_BLOCK=""
    [[ -f "$SSH_CONFIG" ]] || return 0
    local esc; esc=$(_regex_escape "$alias")
    _HOST_BLOCK=$(perl -0777 -ne \
        "/(^Host[ \t]+${esc}\\b.*?)(?=^Host[ \t]|\\z)/ms and print \$1" \
        "$SSH_CONFIG" 2>/dev/null || true)
}

# Print IdentityFile values for a given host alias or IP address.
get_identity_files_for_host() {
    local target="$1"
    [[ -z $target || ! -f "$SSH_CONFIG" ]] && return 0

    _get_host_block "$target"
    local block="$_HOST_BLOCK"

    # If no alias match, search by HostName value
    if [[ -z $block ]]; then
        block=$(awk -v tgt="$target" '
            /^Host[[:space:]]/ { alias=$2; in_block=1; block="" }
            in_block { block=block $0 "\n" }
            /^[[:space:]]*HostName[[:space:]]/ && in_block && $2==tgt {
                found=block
            }
            /^$/ && in_block { in_block=0 }
            END { if (found) printf "%s", found }
        ' "$SSH_CONFIG" 2>/dev/null || true)
    fi

    [[ -z $block ]] && return 0
    printf '%s\n' "$block" | \
        grep -E '^\s*IdentityFile\s+' | \
        sed -E 's/^\s*IdentityFile\s+//; s/^"(.*)"$/\1/; s/^\s+//; s/\s+$//'
}

# Print "alias|hostname|user" for hosts whose config block references KeyName as IdentityFile.
get_hosts_using_key() {
    local keyname="$1"
    [[ -f "$SSH_CONFIG" ]] || return 0
    local esc; esc=$(_regex_escape "$keyname")
    while IFS='|' read -r alias hn user; do
        _get_host_block "$alias"
        if printf '%s\n' "$_HOST_BLOCK" | \
               grep -qE "IdentityFile\s+.*[/\\\\]?${esc}[[:space:]]*$"; then
            printf '%s|%s|%s\n' "$alias" "$hn" "$user"
        fi
    done < <(get_configured_ssh_hosts)
}

# Extract a single field value from a host block.
_block_field() {
    local field="$1" block="$2"
    printf '%s\n' "$block" | \
        grep -m1 -iE "^\s*${field}\s+" | \
        sed -E "s/^\s*${field}\s+//i; s/\s+$//"
}

# Return the Host alias whose HostName matches a given IP/hostname.
get_alias_for_host_ip() {
    local ip="$1"
    [[ -z $ip || ! -f "$SSH_CONFIG" ]] && return 0
    awk -v tgt="$ip" '
        /^Host[[:space:]]/ { alias=$2 }
        /^[[:space:]]*HostName[[:space:]]/ && $2==tgt { print alias; exit }
    ' "$SSH_CONFIG" 2>/dev/null
}

get_ip_from_host_config() {
    local alias="$1"
    _get_host_block "$alias"
    _block_field "HostName" "$_HOST_BLOCK"
}

get_user_from_host_config() {
    local alias="$1"
    _get_host_block "$alias"
    _block_field "User" "$_HOST_BLOCK"
}

get_identity_file_from_host_config() {
    local alias="$1"
    _get_host_block "$alias"
    local raw
    raw=$(_block_field "IdentityFile" "$_HOST_BLOCK")
    raw="${raw/#\~/$HOME}"
    raw="${raw/#\$HOME/$HOME}"
    printf '%s' "$raw"
}

# Replace old_block with new_block in SSH_CONFIG.
# Pass new_block="" to delete the block entirely.
# Uses perl (preferred) with python3 fallback.
_replace_host_block() {
    local old_block="$1" new_block="${2:-}"
    if command -v perl &>/dev/null; then
        perl -0777 -i -pe "s/\Q${old_block}\E/${new_block}/" "$SSH_CONFIG" 2>/dev/null && return 0
    fi
    if command -v python3 &>/dev/null; then
        python3 -c "
f='$SSH_CONFIG'
content=open(f).read()
open(f,'w').write(content.replace('''${old_block}''', '''${new_block}''', 1))
" 2>/dev/null && return 0
    fi
    return 1
}
