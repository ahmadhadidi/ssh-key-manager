"""
Integration tests against a real LXC container.

LXC: 192.168.0.213  user: testuser  password: testpass

Two scenarios:
  test_connection_no_key   — local key exists but is NOT in authorized_keys → "Key not authorized on"
  test_connection_with_key — key deployed to LXC first               → "SSH connection ... is successful"

Fixtures manage ~/.ssh/config and ~/.ssh/lxc-test-key* setup/teardown.
"""

import os
import re
import stat
import subprocess
import time

import pexpect
import pytest

# ── Constants ────────────────────────────────────────────────────────────────

LXC_HOST  = "192.168.0.213"
LXC_USER  = "testuser"
LXC_PASS  = "testpass"
LXC_ALIAS = "lxc-test"
TEST_KEY  = "lxc-test-key"

SSH_DIR    = os.path.expanduser("~/.ssh")
SSH_CONFIG = os.path.join(SSH_DIR, "config")

ESC   = "\x1b"
ENTER = "\r"

# ── SSH helpers (run outside the TUI) ────────────────────────────────────────

def _askpass_env(password: str) -> dict:
    """Return env dict that forces SSH to use a temp askpass script."""
    script = "/tmp/_lxc_test_askpass.sh"
    with open(script, "w") as f:
        f.write(f"#!/bin/sh\necho '{password}'\n")
    os.chmod(script, stat.S_IRWXU)
    env = os.environ.copy()
    env["SSH_ASKPASS"]         = script
    env["SSH_ASKPASS_REQUIRE"] = "force"
    env["DISPLAY"]             = "x"
    return env


def _ssh_run(cmd: str, stdin_data: bytes = None, timeout: int = 10) -> subprocess.CompletedProcess:
    """Run an ssh command against the LXC using password auth."""
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


def _deploy_key(key_name: str):
    """Append ~/.ssh/{key_name}.pub to LXC authorized_keys via password auth."""
    pub = open(os.path.join(SSH_DIR, f"{key_name}.pub"), "rb").read()
    result = _ssh_run(
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys",
        stdin_data=pub,
    )
    assert result.returncode == 0, f"deploy_key failed: {result.stderr.decode()}"


def _remove_key(key_name: str):
    """Remove public key from LXC authorized_keys."""
    pub_path = os.path.join(SSH_DIR, f"{key_name}.pub")
    if not os.path.exists(pub_path):
        return
    pubkey = open(pub_path).read().strip()
    # Use grep -v to filter out the key; ignore errors (file may already be clean)
    safe = pubkey.replace("'", "'\\''")
    _ssh_run(
        f"grep -vF '{safe}' ~/.ssh/authorized_keys > /tmp/_ak.tmp "
        f"&& mv /tmp/_ak.tmp ~/.ssh/authorized_keys || true"
    )


def _generate_key(key_name: str):
    """Generate a fresh ED25519 key pair in ~/.ssh/."""
    priv = os.path.join(SSH_DIR, key_name)
    for p in [priv, priv + ".pub"]:
        if os.path.exists(p):
            os.remove(p)
    subprocess.run(
        ["ssh-keygen", "-t", "ed25519", "-f", priv, "-N", "", "-C", f"test-{key_name}"],
        capture_output=True, check=True,
    )


# ── SSH config helpers ────────────────────────────────────────────────────────

def _add_host_block(alias: str, host: str, user: str, key_name: str = None):
    block = f"\nHost {alias}\n    HostName {host}\n    User {user}\n"
    if key_name:
        block += f"    IdentityFile {SSH_DIR}/{key_name}\n"
    with open(SSH_CONFIG, "a") as f:
        f.write(block)


def _remove_host_block(alias: str):
    if not os.path.exists(SSH_CONFIG):
        return
    with open(SSH_CONFIG) as f:
        text = f.read()
    text = re.sub(
        rf'\nHost {re.escape(alias)}\n(?:[ \t]+[^\n]*\n)*', "", text
    )
    with open(SSH_CONFIG, "w") as f:
        f.write(text)


# ── Fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture
def lxc_no_key():
    """
    Add lxc-test to SSH config with demo-lan as IdentityFile.
    demo-lan is a local key that is NOT in the LXC's authorized_keys.
    """
    _add_host_block(LXC_ALIAS, LXC_HOST, LXC_USER, key_name="demo-lan")
    yield
    _remove_host_block(LXC_ALIAS)


@pytest.fixture
def lxc_with_key():
    """
    Generate lxc-test-key, deploy it to the LXC via password auth,
    and add lxc-test to SSH config pointing at that key.
    """
    _generate_key(TEST_KEY)
    _deploy_key(TEST_KEY)
    _add_host_block(LXC_ALIAS, LXC_HOST, LXC_USER, key_name=TEST_KEY)
    yield
    _remove_key(TEST_KEY)
    _remove_host_block(LXC_ALIAS)
    for p in [os.path.join(SSH_DIR, TEST_KEY), os.path.join(SSH_DIR, TEST_KEY + ".pub")]:
        if os.path.exists(p):
            os.remove(p)


# ── TUI helper ───────────────────────────────────────────────────────────────

def _run_tui(args=""):
    env = os.environ.copy()
    env.update({"TERM": "xterm-256color", "LANG": "en_US.UTF-8", "EDITOR": "/bin/true", "VISUAL": ""})
    child = pexpect.spawn(
        f"/usr/bin/bash ./hddssh.sh --user {LXC_USER} {args}",
        env=env, encoding="utf-8", timeout=20,
    )
    child.setwinsize(40, 100)
    child.logfile = None  # suppress noise; enable with sys.stdout for debugging
    child.expect(["HDD SSH Keys Manager", "Quit"], timeout=10)
    time.sleep(0.3)
    return child


def _navigate_test_connection(child):
    """
    Press T, select lxc-test, confirm user, and return.
    Caller should then expect() the result string.
    """
    child.send("T")
    child.expect("Test SSH Connection", timeout=5)

    # Host selector — type alias prefix to filter, then Enter
    child.expect("Select remote host", timeout=5)
    time.sleep(0.15)
    child.send(LXC_ALIAS)
    time.sleep(0.2)
    child.send(ENTER)

    # User prompt pre-filled with LXC_USER (passed via --user)
    child.expect("Remote username", timeout=5)
    time.sleep(0.1)
    child.send(ENTER)


# ── Tests ─────────────────────────────────────────────────────────────────────

def test_connection_no_key(lxc_no_key):
    """
    T → lxc-test → demo-lan (not in authorized_keys) → 'Key not authorized on'
    """
    child = _run_tui()
    _navigate_test_connection(child)

    child.expect("Key not authorized on", timeout=15)

    # Acknowledge and quit cleanly
    child.send(ENTER)
    time.sleep(0.2)
    child.send("Q")
    child.expect(pexpect.EOF, timeout=5)


def test_connection_with_key(lxc_with_key):
    """
    Fixture deploys lxc-test-key to LXC via password.
    T → lxc-test → lxc-test-key → 'SSH connection ... is successful'
    """
    child = _run_tui()
    _navigate_test_connection(child)

    child.expect("is successful", timeout=15)

    # Acknowledge and quit cleanly
    child.send(ENTER)
    time.sleep(0.2)
    child.send("Q")
    child.expect(pexpect.EOF, timeout=5)
