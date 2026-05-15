# Test: Config — Edit Config (E)

**Python counterpart:** `16_config_edit.py`  
**Menu hotkey:** `E`  
**bash requirement:** `/proj/bash32/bin/bash` — bash 3.2.57

## What this tests

`_menu_edit_config` → `edit_ssh_config_file`: opens `~/.ssh/config` in the
user's `$EDITOR`. The TUI returns to main menu immediately after the editor
exits — no `wait_user_acknowledge` bar. Editor fallback order:
`$EDITOR` → `code` → `nvim` → `vim` → `nano` → `notepad.exe`.

## Prerequisites

- `~/.ssh/config` exists.
- `$EDITOR` set to `/bin/true` in test environment (exits immediately).
- Terminal ≥ 40 rows × 100 columns.

## Launch

```
EDITOR=/bin/true /proj/bash32/bin/bash sshhdd.sh
```

---

## TC-1: Opens editor and returns to main menu (CI / /bin/true)

**Steps:**
1. Press **`E`**.
2. Editor (`/bin/true`) exits immediately.
3. Verify main menu reappears without any "Press any key" prompt.

**Expected:** `_menu_edit_config` returns 1 (skip ack); main menu is shown
automatically. Total round-trip < 1 second with `/bin/true`.

---

## TC-2: Opens editor and returns — real editor

**Setup:** Set `$EDITOR` to a real editor (e.g. `nano`).

**Steps:**
1. Press **`E`**.
2. `nano ~/.ssh/config` opens.
3. Make a minor comment change (add `# test`).
4. Save and exit (`Ctrl+X`, `y`, **Enter**).
5. Verify main menu reappears.
6. Press **`V`** to confirm the change is visible.

**Expected:** Config reflects the edit. Main menu restored cleanly after editor exit.
No raw-mode artifacts in terminal (stty restored correctly after editor runs).

---

## TC-3: Navigate to E via arrow keys

**Steps:**
1. From main menu, use **↓** to highlight "Edit Config".
2. Press **Enter**.
3. Editor (`/bin/true`) exits.
4. Verify main menu.

---

## TC-4: $EDITOR not set — fallback chain

**Setup:** `unset EDITOR VISUAL`.

**Steps:**
1. Press **`E`**.

**Expected:** TUI tries `code`, then `nvim`, then `vim`, then `nano` in order.
Whichever is first installed opens the file. On a minimal system with none
installed, TUI shows an error and returns to main menu cleanly.
