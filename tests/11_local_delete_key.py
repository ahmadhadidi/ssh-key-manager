def test_local_delete_key(run_tui):
    child = run_tui()
    child.send("X") # Note: lowercase x as per your list
    child.expect("Delete an SSH Key Locally")
    child.send("q")