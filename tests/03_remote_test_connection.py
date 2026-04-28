ESC = "\x1b"
ENTER = "\r"

def test_remote_test_connection(run_tui):
    child = run_tui("--user testuser")
    
    # Trigger 'Test Connection' via hotkey
    child.send("T")
    
    # Verify we are on the right screen
    child.expect("Test SSH Connection")
    child.expect("Select remote host")
    
    # Escape back to menu and quit
    child.send(ESC)
    child.send("q")