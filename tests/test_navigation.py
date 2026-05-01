import pytest
import pexpect
import time

# Constants for keys
ESC   = "\x1b"
DOWN  = "\x1b[B"
ENTER = "\r"
QUIT  = "Q"

# List of (Hotkey, Expected Header Fragment)
MENU_MAPPING = [
    ("G", "Generate & Install"),
    ("I", "Install SSH Key"),
    ("T", "Test SSH Connection"),
    ("D", "Delete (Remote)"),
    ("P", "Promote Key"),
    ("Z", "List Authorized"),
    ("N", "Add Config Block"),
    ("W", "Generate (Local)"),
    ("L", "List Keys (Local)"),
    ("A", "Append Hostname"),
    ("x", "Delete (Local)"),
    ("R", "Remove Config"),
    ("M", "Import Key"),
    ("H", "Remove Host"),
    ("V", "View Config"),
    ("E", "Edit Config"),
    ("S", "SSH Config"),
]

def test_full_menu_navigation_loop(run_tui):
    """
    Test that every menu option can be entered and exited via ESC
    returning the user safely to the Main Menu.
    """
    child = run_tui()

    # Operations that return to the main menu immediately without waiting for
    # user input (e.g. they open an external editor that exits at once in the
    # test environment).  Sending ESC after they finish would hit the main
    # menu and quit the app, so we skip the ESC step for these entries.
    RETURNS_IMMEDIATELY = {"E"}

    for key, header in MENU_MAPPING:
        # 1. Press the hotkey
        child.send(key)

        # 2. Expect the sub-menu header
        # We use a partial match to be flexible with icons/emojis
        child.expect(header, timeout=5)

        # 3. Small settle time to ensure Bash has finished rendering
        time.sleep(0.2)

        if key not in RETURNS_IMMEDIATELY:
            # 4. Press Escape to go back
            child.send(ESC)

        # 5. Expect to be back at the Main Menu
        child.expect("HDD SSH Keys Manager", timeout=5)

        # 6. Wait for any ESC drain reads in the main event loop to complete
        # before sending the next hotkey. Drain reads use read -t 0.05 per byte,
        # so two reads take up to 100ms. 150ms gives reliable slack.
        time.sleep(0.15)

        # 7. Log progress to stdout (visible with -s)
        print(f"  [OK] Navigation: Main -> {header} -> Main")

    # Final Clean Exit
    child.send(QUIT)
    child.expect(pexpect.EOF)


def test_arrow_key_navigation(run_tui):
    """
    Test that arrow key (DOWN) navigation works by pressing DOWN twice from
    the initial selection to reach 'Test SSH Connection' (3rd item), then
    confirming with Enter and exiting with ESC.

    Menu order: Generate & Install (0) -> Install SSH Key (1) -> Test SSH Connection (2)
    """
    child = run_tui()

    # Navigate down twice using arrow keys
    child.send(DOWN)
    time.sleep(0.1)
    child.send(DOWN)
    time.sleep(0.1)

    # Confirm selection with Enter
    child.send(ENTER)

    # Should arrive at "Test SSH Connection" operation header
    child.expect("Test SSH Connection", timeout=5)
    print("  [OK] Arrow DOWN x2 + Enter reached: Test SSH Connection")

    # Let the operation render (it will show a select_from_list widget)
    time.sleep(0.2)

    # Exit back to main menu via ESC
    child.send(ESC)
    child.expect("HDD SSH Keys Manager", timeout=5)
    time.sleep(0.15)
    print("  [OK] ESC returned to Main Menu")

    # Clean exit
    child.send(QUIT)
    child.expect(pexpect.EOF)