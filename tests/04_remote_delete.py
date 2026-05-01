def test_remote_delete(run_tui):
    child = run_tui()
    child.send("D")
    child.expect("Delete Remote SSH Key")
    child.send("q")