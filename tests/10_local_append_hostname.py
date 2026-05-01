def test_local_append_hostname(run_tui):
    child = run_tui()
    child.send("A")
    child.expect("Append Hostname")
    child.send("q")