def test_local_append_hostname(run_tui):
    child = run_tui()
    child.send("A")
    child.expect("Append SSH Key to Hostname")
    child.send("q")