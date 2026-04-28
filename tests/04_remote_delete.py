def test_remote_delete(run_tui):
    child = run_tui()
    child.send("D")
    child.expect("Delete SSH Key From A Remote Machine")
    child.send("q")