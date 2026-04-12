#!/usr/bin/env bash
# scripts/update-line-numbers.sh
# Scan all lib files for function definitions, then patch every `name`:NNN
# reference in CLAUDE.md to reflect the current line number.
#
# Usage:
#   bash scripts/update-line-numbers.sh
#
# Run before committing after any edit that shifts line numbers.
set -euo pipefail
cd "$(dirname "$0")/.."

# ── 1. Index every function definition in lib/ ────────────────────────────────
declare -A MAP  # funcname → linenum

_index_file() {
    local file="$1" lineno=0 line
    while IFS= read -r line; do
        (( ++lineno ))
        # Bash style: funcname() {  or  funcname () {
        if [[ $line =~ ^([a-zA-Z_][a-zA-Z0-9_]*)\ *\(\)\ *\{ ]]; then
            MAP["${BASH_REMATCH[1]}"]=$lineno
        # PS / bash 'function' keyword: function Name { or function Name(
        elif [[ $line =~ ^function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_-]+) ]]; then
            MAP["${BASH_REMATCH[1]}"]=$lineno
        fi
    done < "$file"
}

for f in lib/bash/*.sh lib/ps/*.ps1; do
    [[ -f $f ]] && _index_file "$f"
done

printf '  Indexed %d functions across lib/bash/ and lib/ps/\n' "${#MAP[@]}"

# ── 2. Build a Perl script that rewrites `name`:NNN in place ──────────────────
perl_file=$(mktemp)

# Header: strict + the lookup hash
printf 'use strict; use warnings;\n' >> "$perl_file"
printf 'my %%m = (\n'                >> "$perl_file"
for fn in "${!MAP[@]}"; do
    printf "  '%s' => %d,\n" "$fn" "${MAP[$fn]}" >> "$perl_file"
done
printf ');\n' >> "$perl_file"

# Body: slurp the file, substitute all name:NNN occurrences, write back.
# Pattern uses \x60 (hex for backtick) so bash never sees a raw backtick here.
printf '%s\n' \
    'local $/;' \
    'open(my $fh, "<", $ARGV[0]) or die "Cannot open $ARGV[0]: $!";' \
    'my $txt = <$fh>; close $fh;' \
    '$txt =~ s{\x60([^\x60]+)\x60:(\d+)}{ exists $m{$1} ? "\x60$1\x60:$m{$1}" : "\x60$1\x60:$2" }ge;' \
    'open($fh, ">", $ARGV[0]) or die "Cannot write $ARGV[0]: $!";' \
    'print $fh $txt; close $fh;' \
    >> "$perl_file"

# ── 3. Apply and report diff ──────────────────────────────────────────────────
tmp=$(mktemp)
cp CLAUDE.md "$tmp"
perl "$perl_file" CLAUDE.md
rm -f "$perl_file"

if diff -q "$tmp" CLAUDE.md > /dev/null 2>&1; then
    printf '  \e[90mNo line numbers changed.\e[0m\n'
else
    diff "$tmp" CLAUDE.md \
        | grep '^[<>]' \
        | sed 's|^< \(.*\)|  \x1b[31m- \1\x1b[0m|; s|^> \(.*\)|  \x1b[32m+ \1\x1b[0m|' \
        | head -60 || true
    printf '\n  \e[32mCLAUDE.md updated.\e[0m\n'
fi
rm -f "$tmp"

# ── 4. Warn about functions in lib/ with no `name`:NNN entry in CLAUDE.md ────
# Extract all documented function names from `name`:NNN patterns in CLAUDE.md.
# Uses $'\x60' (hex for backtick) to avoid raw backticks in this script.
declare -A DOCUMENTED
while IFS= read -r fn; do
    [[ -n "$fn" ]] && DOCUMENTED["$fn"]=1
done < <(grep -oE $'\x60[^\x60]+\x60:[0-9]+' CLAUDE.md \
         | sed $'s/\x60//g; s/:[0-9]*//')

undoc=()
for fn in "${!MAP[@]}"; do
    [[ -z "${DOCUMENTED[$fn]+x}" ]] && undoc+=("$fn")
done

if [[ ${#undoc[@]} -gt 0 ]]; then
    printf '\n  \e[33m⚠  %d function(s) in lib/ have no \x60name\x60:NNN entry in CLAUDE.md:\e[0m\n' \
        "${#undoc[@]}"
    printf '%s\n' "${undoc[@]}" | sort | while IFS= read -r fn; do
        printf '     \e[90m%s\e[0m\n' "$fn"
    done
    printf '\n'
fi
