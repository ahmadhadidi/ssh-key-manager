# Plan: Lock bash scripts to bash 3.2 (macOS-only)

## Goal

Remove all bash 5+ code paths from `lib/bash/` so the scripts run correctly
on macOS's system bash (3.2.57) with no version branching.

The codebase already avoids `${var,,}`, `local -A`, `declare -A`, and
`${var@Q}` — those are already done per the CLAUDE.md compat rules.
Two concrete issues remain.

---

## Change 1 — `tui.sh`: simplify `_esc_drain`

**File:** `lib/bash/tui.sh` lines 79–116  
**Problem:** `_esc_drain` has an `if (( BASH_VERSINFO[0] >= 5 ))` branch that
uses `read -t 0.05 -n1` (decimal timeout — bash 4+ only). The else-branch
(bash 3/4 path with `stty min 0 time 1`) is the only path that matters.

**Change:**
- Delete the `if (( BASH_VERSINFO[0] >= 5 )); then … else` wrapper and its
  closing `fi`.
- Keep the body of the current `else` block unchanged — it is already the
  correct bash 3.2 path.
- Remove/update the function comment that describes the two-strategy split.
- Result: `_esc_drain` becomes ~15 lines with no version check.

**Resulting behaviour (unchanged on macOS):**
```bash
_esc_drain() {
    local _restore_stty=${1:-}
    local s1 s2 s3 s4
    stty min 0 time 1 2>/dev/null || true
    IFS= read -r -n1 s1 2>/dev/null || s1=''
    if [[ -n $s1 ]]; then
        IFS= read -r -n1 s2 2>/dev/null || s2=''
        if [[ ${s2} =~ ^[0-9]$ ]]; then
            IFS= read -r -n1 s3 2>/dev/null || s3=''
            if [[ ${s3} =~ ^[0-9]$ ]]; then
                IFS= read -r -n1 s4 2>/dev/null || s4=''
            else s4=''; fi
        else s3=''; s4=''; fi
    else s2=''; s3=''; s4=''; fi
    [[ -n $_restore_stty ]] && stty $_restore_stty 2>/dev/null || true
    _ESC_TAIL="${s1}${s2}${s3}${s4}"
}
```

---

## Change 2 — `menu-support.sh`: replace `printf '%q'`

**File:** `lib/bash/menu-support.sh` lines 55–58  
**Problem:** `printf '%q'` (bash builtin `%q` format) was added in bash 4.0.
On bash 3.2 it silently emits the value unquoted, which breaks the copy-paste
command strings for values containing spaces or special characters.

**Location:** inside `_run_conf_editor`, the block that builds `_bf` (bash
flags) and `_pf` (PowerShell flags) for the four "persist" command strings
shown at the bottom of the Conf Defaults screen.

**Fix:** Add a small `_sq` (shell-quote) helper that wraps a value in single
quotes and escapes embedded single quotes as `'\''`:

```bash
# Single-quote a value for use in shell command strings (bash 3.2-safe).
# Escapes embedded single quotes as '\''.
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
```

Uses only `${v:0:1}` / `${v:1}` substring expansion (bash 3.0+) and a simple
`while` loop — no subshells, no `sed`, no `printf '%q'`.

Replace the four `printf '%q'` calls:

```bash
# Before (bash 4+ only):
_bf+=" --user $(printf '%q' "$DEFAULT_USER")"

# After (bash 3.2):
_bf+=" --user $(_sq "$DEFAULT_USER")"
```

Apply the same pattern to `--subnet`, `--comment-suffix`, and `--password`.

Place `_sq` near the top of `menu-support.sh` (after the guard block, before
`_run_conf_editor`), or inline it at the top of `_run_conf_editor` as a
`local` function if bash 3.2 supports nested functions (it does not in local
scope — define it at module level before `_run_conf_editor`).

---

## Change 3 — `CLAUDE.md`: update docs to reflect single target

Sections to update:

1. **`_esc_drain` entry in the `tui.sh` module breakdown table** — remove the
   "two strategies, bash 5+ vs bash 3/4" description; replace with a single
   description of the bash 3/4 `stty min 0 time 1` approach.

2. **Key implementation notes block** — the note that starts with
   _"bash read -n1 overrides VMIN regardless of stty (Linux bash 5.x bug)"_ is
   now historical context only. Remove it or condense to a one-line warning
   comment inside `_esc_drain` itself.

3. **macOS / bash 3.2 compatibility rules table** — add a row:
   `printf '%q'` → `_sq` (single-quote wrapper defined in `menu-support.sh`).

4. **Top-level project overview** — note that the bash implementation targets
   bash 3.2+ (macOS system bash).

---

## Non-changes (already done)

| Construct | Status |
|---|---|
| `${var,,}` / `${var^^}` | Already replaced with `tr` throughout |
| `local -A` / `declare -A` | Already replaced with parallel `local -a` arrays |
| `${var@Q}` | Not used anywhere |
| `read -t <decimal>` in main loop | Already absent — `_read_key_nb` uses stty VTIME |
| `mapfile` / `readarray` | Not used |
| `local -n` / `declare -n` | Not used |
| `declare -g` | Not used |
| `coproc` | Not used |

---

## File change summary

| File | Lines changed | Risk |
|---|---|---|
| `lib/bash/tui.sh` | ~20 deleted (bash 5+ branch) | Low — else-branch is unchanged |
| `lib/bash/menu-support.sh` | +10 (`_sq` helper), 4 one-line replacements | Low — display-only code path |
| `CLAUDE.md` | ~30 edited | No functional impact |

---

## Testing

Run the existing test suite after both code changes:

```bash
bash scripts/run-tests.sh
```

Specific tests that exercise the affected code paths:
- `tests/test_navigation.py` — exercises the menu render loop (arrow keys,
  ESC) which goes through `_esc_drain`
- `tests/16_config_edit.py` — exercises `_run_conf_editor` where `_sq` is used

If a macOS machine is available, smoke-test the conf-defaults screen manually
to verify the persist commands display correctly with special characters in the
values.
