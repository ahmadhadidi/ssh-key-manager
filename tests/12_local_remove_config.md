# Test: Local — Remove Key from Config (R)

**Python counterpart:** `12_local_remove_config.py`  
**Menu hotkey:** `R`  
**bash requirement:** `/proj/bash32/bin/bash` — bash 3.2.57

## What this tests

`_menu_remove_key_from_config` → `remove_identity_file_from_config_block`:
picks a host block, then picks an `IdentityFile` entry within it, and removes
that single line from `~/.ssh/config`. Does not delete key files.

## Prerequisites

- `~/.ssh/config` has `Host sshhdd-test` with at least one `IdentityFile` line.
- Terminal ≥ 40 rows × 100 columns.

## Launch

```
/proj/bash32/bin/bash sshhdd.sh
```

---

## TC-1: Remove one IdentityFile from a host block

**Setup:** `~/.ssh/config` `sshhdd-test` block contains:
```
IdentityFile ~/.ssh/rmcfg-a
IdentityFile ~/.ssh/rmcfg-b
```

**Steps:**
1. Press **`R`**.
2. Verify "Remove Config" header.
3. In host selector, type `sshhdd-test`, **Enter**.
4. In IdentityFile selector, choose `rmcfg-a`, **Enter**.
5. At confirmation prompt, confirm `y` **Enter**.
6. Observe "removed" confirmation.
7. Acknowledge with any key.

**Expected:** `sshhdd-test` block in `~/.ssh/config` no longer contains
`IdentityFile ~/.ssh/rmcfg-a`; `rmcfg-b` line is untouched.
Local key files are NOT deleted.

---

## TC-2: Host block has no IdentityFile entries

**Setup:** `~/.ssh/config` has a host block with no `IdentityFile` lines.

**Steps:**
1. Press **`R`**.
2. Select that host.

**Expected:** TUI shows "no IdentityFile entries found" (or similar) and
returns cleanly.

---

## TC-3: ESC at host selector

**Steps:**
1. Press **`R`**.
2. Press **ESC** at the host selector.

**Expected:** Returns to main menu. Config unchanged. Wait 150 ms after ESC.

---

## TC-4: ESC at IdentityFile selector

**Steps:**
1. Press **`R`**.
2. Select `sshhdd-test`.
3. Press **ESC** at the IdentityFile selector.

**Expected:** Returns to main menu. Config unchanged.
