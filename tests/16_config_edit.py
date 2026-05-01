def test_config_edit(run_tui):
    child = run_tui()
    child.send("E")
    child.expect("Edit Config")
    child.send("q")