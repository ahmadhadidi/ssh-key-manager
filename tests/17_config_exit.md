# Test: Config — Quit (Q)

**Python counterpart:** `17_config_exit.py`  
**Menu hotkey:** `Q`  
**bash requirement:** `/proj/bash32/bin/bash` — bash 3.2.57

## What this tests

Clean application exit from the main menu: terminal state restored (alternate
screen exited, cursor visible, echo on, icanon on), process exits with code 0.
The EXIT trap in `_menu_cleanup` runs exactly once (guarded by
`_MENU_CLEANED_UP=1` to prevent double-execution on Ctrl+C).

## Prerequisites

- Terminal ≥ 40 rows × 100 columns.

## Launch

```
/proj/bash32/bin/bash sshhdd.sh
```

---

## TC-1: Q hotkey exits cleanly

**Steps:**
1. From the main menu, press **`Q`**.
2. TUI exits; shell prompt returns.

**Expected:**
- Process exit code 0.
- Terminal is in normal cooked mode: `stty -a` shows `echo`, `icanon` on,
  `raw` off.
- Cursor is visible.
- Alternate screen buffer is off (content from before TUI launch is visible).

---

## TC-2: Ctrl+C exits cleanly (INT trap)

**Steps:**
1. From the main menu, press **Ctrl+C** (`\x03`).

**Expected:** Same terminal cleanup as TC-1. The INT trap sets exit code;
the EXIT trap runs `_menu_cleanup` exactly once (the `_MENU_CLEANED_UP` flag
prevents a second run). Process exits with code 130 (128 + SIGINT) or 1.

---

## TC-3: Ctrl+Z suspends and fg restores

**Steps:**
1. From the main menu, press **Ctrl+Z**.
2. Shell shows `[1]+ Stopped`.
3. Run `fg` to resume.
4. TUI main menu reappears correctly.
5. Press **Q** to exit.

**Expected:** Terminal state consistent after resume; no broken stty settings.

---

## TC-4: Exit while inside an operation

**Steps:**
1. Press **`W`** (Generate Local Key).
2. When the key-name selector appears, press **Ctrl+C**.

**Expected:** Terminal restored cleanly. No key files created. Stty is normal.

---

## TC-5: Q is case-sensitive (lowercase q ignored)

**Steps:**
1. From the main menu, press **`q`** (lowercase).

**Expected:** Nothing happens — `q` is not a registered hotkey; the main menu
stays visible and continues the poll loop normally.
