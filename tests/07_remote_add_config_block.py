def test_remote_add_config(run_tui):
    child = run_tui()
    child.send("N")
    child.expect("Add Config Block for Existing Remote Key")
    child.send("q")