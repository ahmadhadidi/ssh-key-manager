def test_remote_install(run_tui):
    child = run_tui("--user testuser --subnet 127.0.0")
    child.send("I")
    child.expect("Install SSH Key on A Remote Machine")
    child.send("q")