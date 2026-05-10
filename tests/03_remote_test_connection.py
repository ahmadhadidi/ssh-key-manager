import pytest

pytestmark = pytest.mark.lxc

ESC   = "\x1b"
ENTER = "\r"


def test_remote_test_connection(run_tui):
    child = run_tui("--user testuser")
    child.send("T")
    child.expect("Test SSH Connection")
    child.expect("Select remote host")
    child.send(ESC)
    child.send("q")
