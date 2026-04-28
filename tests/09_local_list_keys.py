def test_local_list_ssh_keys(run_tui):
    child = run_tui()
    
    # Trigger 'List' via hotkey
    child.send("L")
    
    # Check for the header and the instruction footer
    child.expect("List SSH Keys")
    child.expect("Up/Dn navigate")
    
    # Quit
    child.send("q")