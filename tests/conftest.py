import pexpect
import os
import pytest
import sys
import time

BASH32 = "/proj/bash32/bin/bash"

@pytest.fixture
def run_tui():
    def _run(args=""):
        script_path = "./hddssh.sh"
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
def check_navigation():
    def _check(child, enter_key, expected_header):
        child.send(enter_key)
        child.expect(expected_header)
        time.sleep(0.2)
        child.send("\x1b")  # ESC
        child.expect("HDD SSH Keys Manager")
    return _check
