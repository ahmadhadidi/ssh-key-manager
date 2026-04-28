import time

def test_remote_gen_install(run_tui):
    child = run_tui("--user testuser --subnet 127.0.0")
    
    # 1. Send Capital G (Bash case statements are usually case-sensitive)
    # We send it directly without flushing first to keep the TTY state clean
    child.send("G")
    
    # 2. Wait for the specific sub-menu title
    # Using 'Install SSH Key' since it's unique to that screen
    try:
        child.expect("Install SSH Key on A Remote Machine", timeout=5)
        print("\n[Success] Sub-menu reached.")
    except Exception:
        # Debug: If it fails, try lowercase as a fallback
        child.send("g")
        child.expect("Install SSH Key on A Remote Machine", timeout=5)

    # 3. Clean exit
    time.sleep(0.5)
    child.send("q")