def test_local_delete_key(run_tui):
    child = run_tui()
    child.send("X") # Note: lowercase x as per your list
    child.expect("Delete Local SSH Key")
    child.send("q")