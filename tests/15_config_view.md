# Test: Config — View Config (V)

**Python counterpart:** `15_config_view.py`  
**Menu hotkey:** `V`  
**bash requirement:** `/proj/bash32/bin/bash` — bash 3.2.57

## What this tests

`_menu_view_config` → `show_ssh_config_file`: a full-screen paginated viewer
for `~/.ssh/config` with syntax colouring. Uses buffer-mode `_draw_op_header`
and `show_op_banner`. Returns 1 to skip `wait_user_acknowledge` — pressing Q
or ESC exits straight to main menu.

## Prerequisites

- `~/.ssh/config` exists with at least two `Host` blocks.
- Terminal ≥ 40 rows × 100 columns.

## Launch

```
/proj/bash32/bin/bash sshhdd.sh
```

---

## TC-1: View config — Q exits

**Steps:**
1. Press **`V`**.
2. Verify the SSH config content is displayed with syntax colouring
   (`Host` lines in a distinct colour from field lines).
3. Press **`Q`** → main menu appears immediately (no "Press any key" bar).

**Expected:** Config content visible, Q exits without going to the ack bar.

---

## TC-2: View config — ESC exits

**Steps:**
1. Press **`V`**.
2. Press **ESC** → main menu.

**Expected:** ESC also exits the pager. Wait 150 ms after ESC before next input.

---

## TC-3: Page navigation

**Setup:** `~/.ssh/config` has enough blocks to exceed one screen (> ~30 lines).

**Steps:**
1. Press **`V`**.
2. Press **Page Down** (`\x1b[6~`) to advance a page.
3. Verify content scrolled.
4. Press **Page Up** (`\x1b[5~`) to go back.
5. Press **Q** → main menu.

**Expected:** Pager scrolls forward and backward correctly. No ANSI escape
sequences appear as raw text (bash 3.2 `printf -v` rendering confirmed).

---

## TC-4: Config missing — prompt to create

**Setup:** Rename `~/.ssh/config` temporarily:
```bash
mv ~/.ssh/config ~/.ssh/config.bak
```

**Steps:**
1. Launch the TUI (the startup check triggers).
2. Verify a full-screen prompt offers to create `~/.ssh/config`.
3. Answer `y` **Enter**.
4. Press **`V`** — view the (now empty) config.
5. Press **Q** → main menu.

**Cleanup:** `mv ~/.ssh/config.bak ~/.ssh/config`

---

## TC-5: Terminal resize while viewing

**Steps:**
1. Press **`V`**.
2. Resize the terminal window while viewing the config.
3. Verify the pager redraws to the new terminal size.
4. Press **Q** → main menu.
