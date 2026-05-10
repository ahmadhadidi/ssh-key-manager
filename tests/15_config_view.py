import pexpect
import time


def test_config_view_file(run_tui):
    """V hotkey opens the config viewer; Q closes it and returns to main menu."""
    child = run_tui()
    child.send("V")
    child.expect("View Config", timeout=5)
    time.sleep(0.2)
    child.send("Q")
    child.expect("HDD SSH Keys Manager", timeout=5)
    time.sleep(0.15)
    child.send("Q")
    child.expect(pexpect.EOF, timeout=5)
