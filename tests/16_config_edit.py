def test_config_edit(run_tui):
    child = run_tui()
    child.send("E")
    # Note: If this opens nano/vim, the expect string 
    # should look for something the editor displays.
    child.expect("Edit SSH Config")
    child.send("q")