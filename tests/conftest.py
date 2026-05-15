import pexpect
import os
import pytest
import sys
import time

BASH32 = "/proj/bash32/bin/bash"

@pytest.fixture
def run_tui():
    def _run(args=""):
        script_path = "./sshhdd.sh"
        env = os.environ.copy()
        env.update({"TERM": "xterm-256color", "LANG": "en_US.UTF-8", "EDITOR": "/bin/true", "VISUAL": ""})

        child = pexpect.spawn(f"{BASH32} {script_path} {args}", env=env, encoding='utf-8', timeout=10)
        child.setwinsize(40, 100)
        child.logfile = sys.stdout

        child.expect(["HDD SSH Keys Manager", "Quit"], timeout=10)

        time.sleep(0.5)
        return child
    return _run

@pytest.fixture
def run_tui_no_keys(tmp_path):
    """Like run_tui but with an isolated temp HOME: no SSH keys, empty config.

    Guarantees the app always goes to the manual text prompt (not the
    select_from_list) when asking for a key name, making odd-input tests
    environment-independent.
    """
    def _run(args=""):
        ssh_dir = tmp_path / ".ssh"
        ssh_dir.mkdir(mode=0o700)
        config = ssh_dir / "config"
        config.write_text("")
        config.chmod(0o600)

        env = os.environ.copy()
        env.update({
            "TERM":   "xterm-256color",
            "LANG":   "en_US.UTF-8",
            "EDITOR": "/bin/true",
            "VISUAL": "",
            "HOME":   str(tmp_path),
        })
        child = pexpect.spawn(
            f"{BASH32} ./sshhdd.sh {args}", env=env, encoding='utf-8', timeout=10
        )
        child.setwinsize(40, 100)
        child.logfile = sys.stdout
        child.expect(["HDD SSH Keys Manager", "Quit"], timeout=10)
        time.sleep(0.5)
        return child
    return _run

@pytest.fixture
def check_navigation():
    def _check(child, enter_key, expected_header):
        child.send(enter_key)
        child.expect(expected_header)
        time.sleep(0.2)
        child.send("\x1b")  # ESC
        child.expect("HDD SSH Keys Manager")
    return _check
