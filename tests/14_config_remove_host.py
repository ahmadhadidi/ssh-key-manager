def test_config_remove_host(run_tui):
    child = run_tui()
    child.send("H")
    child.expect("Remove Host from SSH Config")
    child.send("q")