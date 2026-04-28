def test_remote_promote(run_tui):
    child = run_tui()
    child.send("P")
    child.expect("Promote Key on A Remote Machine")
    child.send("q")