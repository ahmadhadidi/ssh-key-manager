import pexpect
import time


def test_local_list_ssh_keys(run_tui):
    """L hotkey opens the key inventory; Q closes it and returns to main menu."""
    child = run_tui()
    child.send("L")
    child.expect("List SSH Keys", timeout=5)
    child.expect("Up/Dn navigate", timeout=5)
    time.sleep(0.2)
    child.send("Q")
    child.expect("HDD SSH Keys Manager", timeout=5)
    time.sleep(0.15)
    child.send("Q")
    child.expect(pexpect.EOF, timeout=5)
