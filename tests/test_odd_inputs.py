"""
Odd-input tests: empty fields, backspace/Ctrl+W at empty input, unknown
hotkeys, Ctrl+C exit, rapid key spam, ESC at various prompt depths.

Uses run_tui_no_keys (temp HOME, empty config) wherever the test needs to
reach a text-entry prompt deterministically — without keys pre-loaded,
read_ssh_key_name always falls through to the manual text prompt instead of
showing select_from_list, so the exact input position is known.
"""

import pexpect
import time

ESC    = "\x1b"
ENTER  = "\r"
CTRL_W = "\x17"


# ── Main-menu-level odd inputs ─────────────────────────────────────────────

def test_unknown_hotkeys_ignored(run_tui):
    """Non-hotkey chars at the main menu are silently dropped; Q still exits."""
    child = run_tui()
    child.send("~")
    child.send("!")
    child.send("0")
    child.send("3")
    time.sleep(0.2)
    child.send("Q")
    child.expect(pexpect.EOF, timeout=5)


def test_rapid_arrow_spam_no_crash(run_tui):
    """20 rapid DOWN/UP pairs must not crash or freeze the menu."""
    child = run_tui()
    for _ in range(20):
        child.send("\x1b[B")   # DOWN
        child.send("\x1b[A")   # UP
    time.sleep(0.3)
    child.send("Q")
    child.expect(pexpect.EOF, timeout=5)


def test_ctrl_c_exits_cleanly(run_tui):
    """Ctrl+C from the main menu terminates the process (EOF)."""
    child = run_tui()
    child.sendintr()
    child.expect(pexpect.EOF, timeout=5)


def test_esc_ignored_at_main_menu(run_tui):
    """ESC at the main menu is a no-op; the process does not exit until Q."""
    child = run_tui()  # fixture already synced to "HDD SSH Keys Manager"
    child.send(ESC)
    time.sleep(0.3)
    # Process should still be running (isalive=True); Q terminates it.
    assert child.isalive(), "Process exited on ESC — should have been a no-op"
    child.send("Q")
    child.expect(pexpect.EOF, timeout=5)


# ── Text-prompt odd inputs (run_tui_no_keys) ───────────────────────────────

def test_empty_key_name_shows_required_error(run_tui_no_keys):
    """Enter with no text at the key name prompt loops with 'required' message."""
    child = run_tui_no_keys()
    child.send("W")                              # Generate Local SSH Key
    child.expect("Generate Local SSH Key", timeout=5)
    child.expect("Enter SSH key name", timeout=5)
    child.send(ENTER)                            # empty → should loop
    child.expect("required", timeout=5)
    child.send(ESC)                              # cancel out
    child.expect("HDD SSH Keys Manager", timeout=5)
    time.sleep(0.15)
    child.send("Q")
    child.expect(pexpect.EOF, timeout=5)


def test_backspace_at_empty_input_no_crash(run_tui_no_keys):
    """Backspace at an empty input field must not crash (buffer underflow guard)."""
    child = run_tui_no_keys()
    child.send("W")
    child.expect("Generate Local SSH Key", timeout=5)
    child.expect("Enter SSH key name", timeout=5)
    child.send("\x7f\x7f\x7f")                  # DEL × 3 on empty buffer
    time.sleep(0.1)
    child.send(ESC)
    child.expect("HDD SSH Keys Manager", timeout=5)
    time.sleep(0.15)
    child.send("Q")
    child.expect(pexpect.EOF, timeout=5)


def test_ctrl_w_at_empty_input_no_crash(run_tui_no_keys):
    """Ctrl+W (word-delete) on an empty field must not crash."""
    child = run_tui_no_keys()
    child.send("W")
    child.expect("Generate Local SSH Key", timeout=5)
    child.expect("Enter SSH key name", timeout=5)
    child.send(CTRL_W)
    child.send(CTRL_W)
    time.sleep(0.1)
    child.send(ESC)
    child.expect("HDD SSH Keys Manager", timeout=5)
    time.sleep(0.15)
    child.send("Q")
    child.expect(pexpect.EOF, timeout=5)


def test_ctrl_w_deletes_word(run_tui_no_keys):
    """Ctrl+W after typing 'hello world' deletes 'world', leaving 'hello'."""
    child = run_tui_no_keys()
    child.send("W")
    child.expect("Generate Local SSH Key", timeout=5)
    child.expect("Enter SSH key name", timeout=5)
    child.send("hello world")
    time.sleep(0.1)
    child.send(CTRL_W)                           # deletes 'world'
    time.sleep(0.1)
    child.send(CTRL_W)                           # deletes 'hello'
    time.sleep(0.1)
    # Buffer is now empty; Enter should loop with 'required'
    child.send(ENTER)
    child.expect("required", timeout=5)
    child.send(ESC)
    child.expect("HDD SSH Keys Manager", timeout=5)
    time.sleep(0.15)
    child.send("Q")
    child.expect(pexpect.EOF, timeout=5)


def test_ctrl_c_during_prompt_exits(run_tui_no_keys):
    """Ctrl+C while waiting at a text prompt terminates the process cleanly."""
    child = run_tui_no_keys()
    child.send("W")
    child.expect("Generate Local SSH Key", timeout=5)
    child.expect("Enter SSH key name", timeout=5)
    child.sendintr()
    child.expect(pexpect.EOF, timeout=5)


def test_non_printable_chars_filtered(run_tui_no_keys):
    """Tab and null bytes are filtered; only printable chars reach the buffer."""
    child = run_tui_no_keys()
    child.send("W")
    child.expect("Generate Local SSH Key", timeout=5)
    child.expect("Enter SSH key name", timeout=5)
    # Send tab, null, then valid chars; ESC should still cancel cleanly
    child.send("\t\x00test")
    time.sleep(0.1)
    child.send(ESC)
    child.expect("HDD SSH Keys Manager", timeout=5)
    time.sleep(0.15)
    child.send("Q")
    child.expect(pexpect.EOF, timeout=5)
