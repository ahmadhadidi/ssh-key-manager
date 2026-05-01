# Test: Menu Navigation (hotkeys + arrow keys)

**Python counterpart:** `test_navigation.py`  
**bash requirement:** `/usr/bin/bash` — bash 3.2 on macOS

## Prerequisites

- `hddssh.sh` is executable in the project root.
- Terminal is at least 40 rows × 100 columns.
- `~/.ssh/config` exists (create it if not — the TUI will offer on startup).

## bash 3.2 timing notes

- After pressing **ESC**, wait ≥ 150 ms before the next input. The `_esc_drain`
  function holds a 100 ms `stty VTIME` window; if the next key arrives within
  that window it gets consumed by the drain and never reaches the menu.
- Arrow keys (`↑ ↓`) are three-byte sequences (`\x1b[A` / `\x1b[B`). They must
  be sent as a single burst — do not insert delays between the three bytes.
- `_read_key_nb` uses no `-t` flag; timeout is owned by the kernel via
  `stty min 0 time 1`. The poll loop fires at ~100 ms.

## Launch

```
/usr/bin/bash hddssh.sh --user <user> --subnet 192.168.0
```

---

## TC-1: Every hotkey enters its screen and ESC returns to main menu

**Steps (repeat for each row):**

| Hotkey | Expected screen header |
|--------|------------------------|
| `G`    | Generate & Install     |
| `I`    | Install SSH Key        |
| `T`    | Test SSH Connection    |
| `D`    | Delete (Remote)        |
| `P`    | Promote Key            |
| `Z`    | List Authorized        |
| `N`    | Add Config Block       |
| `W`    | Generate (Local)       |
| `L`    | List Keys (Local)      |
| `A`    | Append Hostname        |
| `x`    | Delete (Local)         |
| `R`    | Remove Config          |
| `M`    | Import Key             |
| `H`    | Remove Host            |
| `V`    | View Config            |
| `S`    | Best Practices         |

For each row:
1. With the main menu visible, press the hotkey.
2. Verify the operation header appears (teal box at the top).
3. Press **ESC**.
4. Verify "HDD SSH Keys Manager" title is visible again.
5. Wait 150 ms before pressing the next hotkey.

**Expected:** Every hotkey reaches the correct screen; ESC always returns to main menu.

**Note for `E` (Edit Config):** The editor (`/bin/true` in CI) exits immediately
and the TUI returns to main menu without waiting for ESC.

---

## TC-2: Arrow key (↓) navigation

1. Launch the TUI — cursor starts on the first item (Generate & Install).
2. Press **↓** (send `\x1b[B` as one burst).
3. Press **↓** again.
4. Press **Enter** (`\r`).
5. Verify "Test SSH Connection" header appears (third item, 0-indexed = 2).
6. Press **ESC** → main menu.

**Expected:** Arrow navigation moves the highlight; Enter activates the
highlighted item regardless of hotkey.

---

## TC-3: Arrow key (↑) wraps at top

1. From the main menu, press **↑** (`\x1b[A`).
2. The selection should wrap to the last menu item.
3. Press **↑** again — selection should move upward.
4. Press **ESC** (or `Q`) to exit without selecting.

**Expected:** ↑ at the top item wraps to the bottom; no crash or freeze.

---

## TC-4: Page Down / Page Up in a paged list

1. Press `L` (List Keys) — opens the key inventory.
2. If more keys exist than fit on screen, press `Page Down` (send `\x1b[6~`).
3. Press `Page Up` (send `\x1b[5~`).
4. Press **ESC** → main menu.

**Expected:** Pager scrolls without corruption; cursor-positioning ANSI codes
render correctly in bash 3.2 (no `\e[` literals visible on screen).

---

## TC-5: Ctrl+Z exits the application

1. From the main menu, press **Ctrl+Z** (`\x1a`).
2. Terminal should restore (alternate screen exited, cursor visible, stty normal).

**Expected:** Clean exit; `stty sane` in the terminal after exit shows a normal
state (echo on, icanon on).

---

## TC-6: Q hotkey quits

1. From the main menu, press `Q` (uppercase).
2. TUI exits; shell prompt returns.

**Expected:** Process exits with code 0; no stray raw-mode artifacts.

---

## TC-7: Terminal resize mid-navigation

1. Launch the TUI.
2. Resize the terminal window (make it narrower/wider) while the main menu is visible.
3. Verify the menu redraws: title bar, rule lines, hint bar all repaint correctly.
4. Resize again while inside an operation (e.g. after pressing `L`).
5. Press **ESC** → main menu.

**Expected:** WINCH signal triggers a full redraw on the next poll cycle.
No static elements (rules, title, hint bar) remain from the previous size.
