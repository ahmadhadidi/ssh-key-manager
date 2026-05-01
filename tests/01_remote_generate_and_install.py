"""
End-to-end tests: G (Generate & Install) against LXC at 192.168.0.213.

Two variants:
  test_gen_install_passphraseless — creates gi-nopass key (no passphrase)
  test_gen_install_passphrased    — creates gi-passphrase key (passphrase = "testpass123")

Setup/teardown cleans up local key files and removes the key from LXC
authorized_keys so the test is repeatable. IdentityFile config update is
declined (answer 'n') to avoid modifying ~/.ssh/config.
"""

import os
import stat
import subprocess
import time

import pexpect
import pytest

# ── Constants ────────────────────────────────────────────────────────────────

LXC_HOST = "192.168.0.213"
LXC_USER = "testuser"
LXC_PASS = "testpass"

SSH_DIR = os.path.expanduser("~/.ssh")

ENTER = "\r"

TUI_ARGS = (
    "--user testuser "
    "--subnet 192.168.0 "
    "--comment-suffix -[hddssh-dev] "
    "--password testpass"
)

# ── SSH helpers ───────────────────────────────────────────────────────────────


def _askpass_env(password: str) -> dict:
    """Return an env dict that forces SSH to use a temp askpass script."""
    script = "/tmp/_gi_test_askpass.sh"
    with open(script, "w") as f:
        f.write(f"#!/bin/sh\necho '{password}'\n")
    os.chmod(script, stat.S_IRWXU)
    env = os.environ.copy()
    env["SSH_ASKPASS"]         = script
    env["SSH_ASKPASS_REQUIRE"] = "force"
    env["DISPLAY"]             = "x"
    return env


def _ssh_run(cmd: str, stdin_data: bytes = None, timeout: int = 15) -> subprocess.CompletedProcess:
    """Run a command on the LXC using password auth."""
    env = _askpass_env(LXC_PASS)
    args = [
        "ssh", "-o", "StrictHostKeyChecking=no",
        "-o", "BatchMode=no",
        "-o", "ConnectTimeout=5",
        f"{LXC_USER}@{LXC_HOST}", cmd,
    ]
    return subprocess.run(
        args, env=env, input=stdin_data,
        capture_output=True, timeout=timeout,
    )


def _remove_key_from_lxc(key_name: str):
    """Remove the public key from LXC authorized_keys (no-op if not present)."""
    pub_path = os.path.join(SSH_DIR, f"{key_name}.pub")
    if not os.path.exists(pub_path):
        return
    pubkey = open(pub_path).read().strip()
    safe = pubkey.replace("'", "'\\''")
    _ssh_run(
        f"grep -vF '{safe}' ~/.ssh/authorized_keys > /tmp/_ak.tmp "
        f"&& mv /tmp/_ak.tmp ~/.ssh/authorized_keys || true"
    )


def _remove_local_key(key_name: str):
    """Delete the local private and public key files."""
    for suffix in ["", ".pub"]:
        p = os.path.join(SSH_DIR, f"{key_name}{suffix}")
        if os.path.exists(p):
            os.remove(p)


# ── TUI spawner ───────────────────────────────────────────────────────────────


def _run_tui() -> pexpect.spawn:
    env = os.environ.copy()
    env.update({"TERM": "xterm-256color", "LANG": "en_US.UTF-8", "EDITOR": "/bin/true", "VISUAL": ""})
    child = pexpect.spawn(
        f"/usr/bin/bash ./hddssh.sh {TUI_ARGS}",
        env=env, encoding="utf-8", timeout=30,
    )
    child.setwinsize(40, 100)
    child.expect(["HDD SSH Keys Manager", "Quit"], timeout=10)
    time.sleep(0.3)
    return child


# ── Fixtures ─────────────────────────────────────────────────────────────────


@pytest.fixture
def gi_nopass():
    key = "gi-nopass"
    _remove_local_key(key)
    yield key
    _remove_key_from_lxc(key)
    _remove_local_key(key)


@pytest.fixture
def gi_passphrase():
    key = "gi-passphrase"
    _remove_local_key(key)
    yield key
    _remove_key_from_lxc(key)
    _remove_local_key(key)


# ── Shared navigation helpers ─────────────────────────────────────────────────


def _navigate_gen_install(child: pexpect.spawn, key_name: str, passphrase: str):
    """
    Drive the TUI through G → key name → comment → passphrase → host → user.
    Caller should then call _complete_install() to handle the SSH step.
    """
    # 1. Open Generate & Install
    child.send("G")
    child.expect("Generate & Install", timeout=5)
    time.sleep(0.2)

    # 2. Key name — select_from_list (non-strict mode): type new name then Enter
    child.send(key_name)
    time.sleep(0.2)
    child.send(ENTER)

    # 3. Key comment — pre-filled as "<key_name>-[hddssh-dev]" — accept default
    child.expect("comment", timeout=5)
    time.sleep(0.15)
    child.send(ENTER)

    # 4. Passphrase — IFS= read -r -s (cooked, no echo)
    child.expect("Passphrase", timeout=5)
    time.sleep(0.1)
    child.send(passphrase + ENTER)

    # 5. Host selector — type exact alias so the lookup succeeds without falling
    #    through to manual entry (non-strict select_from_list creates from filter text)
    child.expect("Select remote host", timeout=10)
    time.sleep(0.15)
    child.send("hddssh-test")
    time.sleep(0.2)
    child.send(ENTER)

    # 6. Remote username — pre-filled with "testuser" — accept default
    child.expect("Remote username", timeout=5)
    time.sleep(0.1)
    child.send(ENTER)


def _complete_install(child: pexpect.spawn):
    """
    Handle the SSH installation step:
      - If existing keys in the hddssh-test config block are authorized, SSH
        connects silently and no password prompt appears.
      - Otherwise the TUI's askpass script prompts for the LXC password.
    Then decline adding IdentityFile (to avoid modifying ~/.ssh/config) and
    acknowledge the operation completion.
    """
    # SSH may connect via an existing authorized key (no prompt) or ask for password
    idx = child.expect(
        ["password:", "installed successfully"],
        timeout=25,
    )
    if idx == 0:
        # Askpass is showing the LXC password prompt — send the password
        child.send("testpass")
        child.send(ENTER)
        child.expect("installed successfully", timeout=15)

    # Decline adding IdentityFile to config block (avoids modifying ~/.ssh/config)
    child.expect("IdentityFile", timeout=5)
    child.send("n")
    child.send(ENTER)

    # Acknowledge and return to main menu
    child.expect("Press any key", timeout=5)
    child.send(ENTER)


# ── Tests ─────────────────────────────────────────────────────────────────────


def test_gen_install_passphraseless(gi_nopass):
    """G → gi-nopass (no passphrase) → hddssh-test → SSH Public Key installed successfully."""
    child = _run_tui()
    _navigate_gen_install(child, gi_nopass, "")
    _complete_install(child)

    child.send("Q")
    child.expect(pexpect.EOF, timeout=5)


def test_gen_install_passphrased(gi_passphrase):
    """G → gi-passphrase (passphrase = testpass123) → hddssh-test → installed successfully."""
    child = _run_tui()
    _navigate_gen_install(child, gi_passphrase, "testpass123")
    _complete_install(child)

    child.send("Q")
    child.expect(pexpect.EOF, timeout=5)
