def test_local_remove_config(run_tui):
    child = run_tui()
    child.send("R")
    child.expect("Remove Config")
    child.send("q")