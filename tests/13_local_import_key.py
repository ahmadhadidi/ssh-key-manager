def test_local_import_key(run_tui):
    child = run_tui()
    child.send("M")
    child.expect("Import Key")
    child.send("q")