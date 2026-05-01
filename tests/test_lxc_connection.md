# Test: LXC Infrastructure Connection

**Python counterpart:** `test_lxc_connection.py`  
**bash requirement:** `/usr/bin/bash` — bash 3.2 on macOS  
**Scope:** Verifies the LXC test target is reachable and that the TUI correctly
reports success/failure for SSH key authentication — before running any
operation-level tests.

## Prerequisites

- LXC container running at `192.168.0.213`, user `testuser`, password `testpass`.
- `sshpass` installed locally (for pre-test key deployment outside the TUI).
- `~/.ssh/config` contains (or will contain) a `Host lxc-test` block pointing
  to `192.168.0.213`.
- Terminal ≥ 40 rows × 100 columns.

## bash 3.2 timing notes

- SSH test connections inside the TUI go through `test_ssh_connection` in
  `ssh-ops.sh`. That function uses `-F /dev/null -o IdentitiesOnly=yes
  -o PreferredAuthentications=publickey` — no `BatchMode=yes` — so passphrase
  prompts work on bash 3.2.
- `-F /dev/null` completely bypasses `~/.ssh/config`; the test is isolated to
  the specific key even if other keys are authorized.

## Launch

```
/usr/bin/bash hddssh.sh --user testuser --subnet 192.168.0 --password testpass
```

---

## TC-1: LXC is reachable via TCP (port 22)

**Steps:**
1. Outside the TUI: `nc -z 192.168.0.213 22 && echo OK`

**Expected:** `OK` printed. If this fails, all downstream tests will also fail —
fix LXC connectivity first.

---

## TC-2: Test Connection — key NOT in authorized_keys

**Setup:** Generate a local key `lxc-test-key` but do NOT deploy it to the LXC.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/lxc-test-key -N "" -C "lxc-test-key"
```

**Steps:**
1. Launch the TUI.
2. Press `T` (Test SSH Connection).
3. In the host selector, filter to `lxc-test` and press **Enter**.
4. In the key selector, filter to `lxc-test-key` and press **Enter**.

**Expected:** Output line containing "not authorized on" or "Permission denied"
(key rejected). The TUI does not hang or crash.

**Cleanup:** Delete `~/.ssh/lxc-test-key` and `~/.ssh/lxc-test-key.pub`.

---

## TC-3: Test Connection — key IS in authorized_keys

**Setup:**
1. Generate `lxc-test-key` as above.
2. Deploy it to the LXC:

```bash
ssh-copy-id -i ~/.ssh/lxc-test-key.pub -o StrictHostKeyChecking=no testuser@192.168.0.213
# enter password: testpass
```

3. Ensure `~/.ssh/config` has a `Host lxc-test` block with `IdentityFile ~/.ssh/lxc-test-key`.

**Steps:**
1. Launch the TUI.
2. Press `T`.
3. Select `lxc-test` host.
4. Select `lxc-test-key`.

**Expected:** Output line containing "SSH connection … is successful" (green).

**Cleanup:**
- Remove `lxc-test-key` from LXC `authorized_keys`.
- Delete local key files.

---

## TC-4: TUI uses /usr/bin/bash (bash 3.2 verification)

**Steps:**
1. Inside the running TUI, in a separate terminal:
   ```bash
   ps aux | grep hddssh
   ```
2. Confirm the process shows `/usr/bin/bash` as the interpreter (not `/bin/bash`,
   not `/usr/local/bin/bash`).

**Expected:** `/usr/bin/bash` with version 3.2 — confirm with:
```bash
/usr/bin/bash --version | head -1
# GNU bash, version 3.2.x(1)-release (x86_64-apple-darwin...)
```
