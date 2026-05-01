def test_local_gen_key(run_tui):
    child = run_tui()
    child.send("W")
    child.expect("Generate Local SSH Key")
    child.send("q")