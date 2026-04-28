def test_local_gen_key(run_tui):
    child = run_tui()
    child.send("W")
    child.expect("Generate SSH Key")
    child.send("q")