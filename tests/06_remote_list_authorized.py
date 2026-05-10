import pytest

pytestmark = pytest.mark.lxc


def test_remote_list_authorized(run_tui):
    child = run_tui()
    child.send("Z")
    child.expect("List Authorized Keys on Remote Host")
    child.send("q")
