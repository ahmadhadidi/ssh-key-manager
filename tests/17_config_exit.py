import pexpect

def test_config_exit(run_tui):
    child = run_tui()
    child.send("Q")
    # Verify the process actually terminates
    child.expect(pexpect.EOF)