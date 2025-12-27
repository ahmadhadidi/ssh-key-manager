# 🌊 HDD SSH Keys
A powershell script that manages your SSH keys

# Give it a go - Online
``` powershell
$u  = "https://raw.githubusercontent.com/ahmadhadidi/ssh-key-manager/refs/heads/main/generate_key_test.ps1"
$sb = [scriptblock]::Create((irm $u))

& $sb -DefaultUserName "username_of_target_machine" -DefaultSubnetPrefix "192.168.0" -DefaultCommentSuffix "-[my-machine]"
```

# Give it a go - Locally
``` powershell
git clone https://github.com/ahmadhadidi/ssh-key-manager.git
cd ssh-key-manager

& ./generate_key_test.ps1 -DefaultUserName username_of_target_machine -DefaultSubnetPrefix 192.168.0 -DefaultCommentSuffix "-[my-machine]"
```


# Todo
- [ ] Finish Function #6
- [ ] Ability to list and `cat` the public keys
- [ ] Ability to list and `cat` the private keys
- [ ] Reduce the amount of prompts needed by querying the Config file more
- [ ] Reduce the amount of prompts by SSHing via the available Config file if it already exists.
- [ ] Implement Delete IdentityFile from a certain config block