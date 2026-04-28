from .constants import ENTER, DOWN

def test_config_view_file(run_tui):
    child = run_tui()
    
    # Navigate down to the Config section
    # If "View SSH Config" is the 15th item, we go UP from the top to wrap around
    child.send("\x1b[A") # Up to 'Exit'
    child.send("\x1b[A") # Up to 'Edit SSH Config'
    child.send("\x1b[A") # Up to 'View SSH Config'
    
    child.send(ENTER)
    
    child.expect("View SSH Config")
    child.send("q")