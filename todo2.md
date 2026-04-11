✅ # Show the command to run after setting something in config
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
                                                                                                                             Conf: Global Defaults
  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

      Default Username        kraid
      Default Subnet Prefix   192.168.0
      Default Comment Suffix  -[dev-poc]
    Default Password        *********

You see when I enter my new config, I want you to show me the cloud and local variables I need to set when I see this config, if I change one of the values, below them, I need to see the commands that I need to enter in the script the next time around I want to run it.

✅ ## Display this config for all the methods we can run the script mentioned in the readme
bash <(curl -fsSL https://raw.githubusercontent.com/ahmadhadidi/ssh-key-manager/refs/heads/main/ssh-key-manager.sh) \
  --user username_of_target_machine \
  --subnet 192.168.0 \
  --comment-suffix "-[my-machine]"

git clone https://github.com/ahmadhadidi/ssh-key-manager.git
cd ssh-key-manager

---

bash ssh-key-manager.sh \
  --user username_of_target_machine \
  --subnet 192.168.0 \
  --comment-suffix "-[my-machine]"


✅ # There's a phantom "character" that appears when I cycle between menu items.
When I cyle in the menu, I see those two things flash briefly: ^[[B and ^[[A, I want you to forbid that from appearing, also it happens when I press PAGE UP, PAGE DOWN

# Import SSH Key From another machine
1. It would be great if there was a brief tutorial on how each menu item can be used, maybe when I press "?"
2. I wish there was a third item where I copy/paste the private key and public key to the script so it can be created.

✅ # Re-title the application
It must be "🌊 HDD SSH Keys Manager"

# More accelerators support
1. When I view the SSH key config, I want to be able to go back to the mainmenu by pressing esc, right now I can go back to the menu by pressing Q which is unintuitive.
2. When I press ESC in a place that's expecting input, e.g., 📋  List Authorized Keys on Remote Host, it shows as "^[" I want that button to be interpreted as go back in the script 1 step

✅ # Formatting
Right now, almost all window titles are wrapping, which tells me that the calculation for the screen's width is not very accurate (it's adding exactly 1 extra teal-backgrounded-block to the middle block). Here's an example:
  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
                                                                                                                     📋  List Authorized Keys on Remote Host                                                                                                                    
  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

Also, the 

✅ # Editing
1. When the script asks me for the Remote Username, by default it shows me "default_non_root_username" and that's fine, what's annoying is that I can't press "ALT+Backspace" or whatever's equivalent to remove 1 full word

# Consistency in padding when opening connections
Right now when I "List Authorized Keys on Remote Host" and it opens a connection, the padding is not respected and it looks off-kilter, here's an example:
  Enter remote IP / hostname (or last 1-3 digits for 192.168.0.xx) 204
  Interpreted as: 192.168.0.204
  Remote username:  kraid
  Fetching authorized_keys from kraid@192.168.0.204...
kraid@192.168.0.204's password:

What can be done to handle this?

✅ # Cycling display bugs
When I select "List SSH Keys" and I cycle between the keys with the up and down arrow the menu keeps adding duplicates of options like this:
 View — dev-poc
  View — dev-poc
  View — dev-poc
  View — dev-poc
  View — dev-poc
  View — dev-poc
  > (type to filter or create new)
    Public Key  (.pub)
    Private Key (handle with care)
    Back























                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  Up/Dn navigate   Enter select   type filter/new   Esc cancel                                                                                                                                                                                                                    Up/Dn navigate   Enter select   type filter/new   Esc cancel                                                                                                                                                                                                                    Up/Dn navigate   Enter select   type filter/new   Esc cancel

✅ # Make the config menu look nicer
the config menu looks bad
1. the selected item does not respect the padding
2. the "to persist across session:" and downwards looks too huddled up and it wouldn't hurt if you used a ☁️ and a 🏠 emojis to signify between both commands


✅ # Quitting the application does not properly cleanup the terminal
When I quit the application by pressing "Q" the app does not properly clean itsself, here's how it looks like (notice "kraid@dev-poc:/proj/ssh-key-manager$"):

  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
                                                                                                                            🌊 HDD SSH Keys Manager                                                                                                                             kraid@dev-poc:/proj/ssh-key-manager$

    > Remote
    🔑  Generate & Install SSH Key on A Remote Machine
    📤  Install SSH Key on A Remote Machine
    🔌  Test SSH Connection
    🗑️  Delete SSH Key From A Remote Machine
    🔄  Promote Key on A Remote Machine
    📋  List Authorized Keys on Remote Host
    🔗  Add Config Block for Existing Remote Key

    > Local
    ✨  Generate SSH Key (Without installation)
    🗝️  List SSH Keys
    ➕  Append SSH Key to Hostname in Host Config
    🗑️  Delete an SSH Key Locally
    ❌  Remove an SSH Key From Config
    📥  Import SSH Key from Another Machine

    > Config File
    🏚️  Remove Host from SSH Config
    👁️  View SSH Config
    ✏️  Edit SSH Config
    🚪  Exit


# Bug in the flow of importing a key
  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
                                                                                                                     📥  Import SSH Key from Another Machine
  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

  Import source  Paste key content
  Key name (e.g. my-server) new-lan

  Paste the private key.
  Input ends automatically at the -----END...----- line.

-----BEGIN OPENSSH PRIVATE KEY-----
abcabc
-----END OPENSSH PRIVATE KEY-----

  Paste the public key (single line, e.g. ssh-ed25519 AAAA...):
ssh-ed25519 abcabc new-lan-[HO5]
  +  /home/kraid/.ssh/new-lan  imported.
  +  /home/kraid/.ssh/new-lan.pub  imported.
  Add 'new-lan' to ~/.ssh/config? [Y/n]

# You see
## Key name with default value
Key name (e.g. my-server)
> it should look like this:
Key name: <default value -- set to development-key>

## Add 'new-lan' to ~/.ssh/config? [Y/n]
You're a moron. nobody connects with ssh <keyname>, you should ask "Add 'new-lan' to host(s) in ~/.ssh/config? [Y/n]

When I press "Yes" you should let me select from a list of available hosts to check with a ✅ each host as to where I want this key installed to which host

## Adding the key
Another moronic thing you've developed, you're setting the Host value as the IP address of the LXC not its hostname somewhere, want proof? look at this:
  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
                                                                                                                     📥  Import SSH Key from Another Machine
  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

  Select remote host  (Esc = enter manually)  axc  (192.168.0.210)
  Remote username:  kraid
  IdentityFile added to existing Host 192.168.0.210.

Want more proof? Here's a listing of "View SSH Config":
  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  /home/kraid/.ssh/config
  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------


  Host axc
    HostName 192.168.0.210
    User kraid
    IdentityFile /home/kraid/.ssh/demo-lan
    IdentityFile /home/kraid/.ssh/dev-lan


  Host 192.168.0.210
    HostName 192.168.0.210
    User kraid
    IdentityFile /home/kraid/.ssh/dev-lan
    IdentityFile /home/kraid/.ssh/new-lan

I can't fathom why I have to spend my hard-earned money on stupid mistakes, if you were working for me I would've fired you on the spot. You deserve to have the subscription cancelled.