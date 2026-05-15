# Test: Local — List Keys (L)

**Python counterpart:** `09_local_list_keys.py`  
**Menu hotkey:** `L`  
**bash requirement:** `/proj/bash32/bin/bash` — bash 3.2.57

## What this tests

`_menu_list_keys` → `show_ssh_key_inventory`: renders an interactive key
inventory table. Arrow keys navigate rows; Enter drills into a key detail
sub-menu (public / private / back). Returns 1 to skip `wait_user_acknowledge`
so the main menu reappears immediately on ESC/Q.

## Prerequisites

- At least two ED25519 keys in `~/.ssh/` (e.g. `list-a`, `list-b`).
- Terminal ≥ 40 rows × 100 columns.

## Launch

```
/proj/bash32/bin/bash sshhdd.sh
```

---

## TC-1: List renders and ESC exits

**Setup:**
```bash
ssh-keygen -t ed25519 -f ~/.ssh/list-a -N "" -C "list-a"
ssh-keygen -t ed25519 -f ~/.ssh/list-b -N "" -C "list-b"
```

**Steps:**
1. Press **`L`**.
2. Verify the key inventory table appears (columns: name, fingerprint, hosts).
3. Verify `list-a` and `list-b` are both listed.
4. Press **ESC** → main menu appears immediately (no "Press any key" bar).

**Expected:** Both keys visible. ESC returns directly to main menu.

**Cleanup:** `rm -f ~/.ssh/list-a ~/.ssh/list-a.pub ~/.ssh/list-b ~/.ssh/list-b.pub`

---

## TC-2: Arrow navigation and Enter drills into detail

**Steps:**
1. Press **`L`**.
2. Press **↓** to move to the second key row.
3. Press **Enter** to open the detail sub-menu.
4. Verify sub-menu shows options: "View public key", "View private key", "Back".
5. Press **↓** to highlight "Back".
6. Press **Enter** → returns to the key list.
7. Press **ESC** → main menu.

---

## TC-3: View public key content

**Steps:**
1. Press **`L`**.
2. Select any key with **Enter**.
3. In the sub-menu, select "View public key" (first option), **Enter**.
4. Verify the public key content is displayed (`ssh-ed25519 AAAA…`).
5. Press **ESC** or **Q** to close the pager.
6. Press **ESC** → main menu.

---

## TC-4: View private key — warning shown

**Steps:**
1. Press **`L`**.
2. Select a key with **Enter**.
3. Select "View private key", **Enter**.
4. Verify a red warning banner appears before the private key content.
5. Confirm to view (or ESC to cancel).
6. Press **ESC** → main menu.

**Expected:** Private key only shown after explicit confirmation past the warning.

---

## TC-5: Empty key inventory

**Setup:** Remove all private keys from `~/.ssh/` (back them up first).

**Steps:**
1. Press **`L`**.

**Expected:** TUI shows "no keys found" or empty inventory message. No crash.
