Execute everything step by step and make individual commits for each item with a meaningful commit message.

1. The shell files in the lib need to be in a bash folder
2. entering a name for a key shows a blank screen
3. bring back the emojis
4. when I select a menu item, the text annoyingly shifts to the left, they all need to be on the same "column"
5. the highlighted menu item needs to be teal, not grey, you took my request of making things behave like nano was too literal.
6. I need to be able to install public and private keys that were made on other machines from the tool
7. I want you to review every line and make sure if there are redundancies to be made in its own function, I want everything to be correctly inherited, I don't want to see code being duplicated because of sloppy work. Never reinvent the wheel.
8. If the tool ran, it needs to check if the config file exists, if it doesn't, the tool should offer to create it, if the user refuses, it needs to show a red bar below (above the tool bar) where it says that the config file is missing and that it must be created by pressing F2.
9. Editing the ssh config in bash should open nano > vi > vim
10. Pressing F10 to view the conf does not work, what is the reason behind that? maybe change it to another key that could potentially not conflict with something unless your code does not handle "F10" properly.
11. I want each menu item to have a flow chart of what it does and the pseudo code it executes, I want to be able to trace what the tool is doing so that we can adjust it accordingly. This "manual" is something that I will be referring to when I ask you to make adjustments so make sure that the code and this manual are something that are 1:1.
12. When listing the keys from "List SSH Keys" I need to be able to view the public key and private key of each key by selecting Public or private for a given key.