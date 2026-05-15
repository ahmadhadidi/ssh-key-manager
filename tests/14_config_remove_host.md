# Test: Config — Remove Host (H)

**Python counterpart:** `14_config_remove_host.py`  
**Menu hotkey:** `H`  
**bash requirement:** `/proj/bash32/bin/bash` — bash 3.2.57

## What this tests

`_menu_remove_host` → `remove_host_from_ssh_config`: shows a preview of the
selected `Host` block, asks for confirmation, then removes the entire block
from `~/.ssh/config`. Uses `perl` (primary) or `python3` (fallback) to
rewrite the config file.

## Prerequisites

- `~/.ssh/config` has at least one `Host` block (e.g. `rm-host-test`).
- Terminal ≥ 40 rows × 100 columns.

## Launch

```
/proj/bash32/bin/bash sshhdd.sh
```

---

## TC-1: Remove a host block with confirmation

**Setup:** Add a test block to `~/.ssh/config`:
```
Host rm-host-test
    HostName 192.168.0.250
    User testuser
```

**Steps:**
1. Press **`H`**.
2. Verify "Remove Host" header.
3. In host selector, type `rm-host-test`, **Enter**.
4. Review the block preview shown on screen.
5. At "Remove this host block?" confirm `y` **Enter**.
6. Observe "removed" confirmation.
7. Acknowledge with any key.

**Expected:** `~/.ssh/config` no longer contains the `rm-host-test` block.
All other host blocks are unchanged.

---

## TC-2: Cancel removal at confirmation

**Setup:** Same `rm-host-test` block exists.

**Steps:**
1. Press **`H`**.
2. Select `rm-host-test`, **Enter**.
3. At confirmation, answer `n` **Enter**.

**Expected:** `~/.ssh/config` unchanged. `rm-host-test` block still present.

---

## TC-3: ESC at host selector

**Steps:**
1. Press **`H`**.
2. Press **ESC** in the host selector.

**Expected:** Returns to main menu. Config unchanged. Wait 150 ms after ESC.

---

## TC-4: Only one host in config — removed successfully

**Setup:** `~/.ssh/config` contains exactly one `Host` block.

**Steps:**
1. Press **`H`**.
2. Select the only host, confirm `y`.

**Expected:** Config file still exists (not deleted) but contains no Host blocks
(may be empty or contain only global `Host *` if it existed).
