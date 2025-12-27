# 🌊 HDD SSH Keys
A powershell script that manages your SSH keys

Give it a go:
``` powershell
$u  = "https://raw.githubusercontent.com/ahmadhadidi/ssh-key-manager/refs/heads/main/generate_key_test.ps1"
$sb = [scriptblock]::Create((irm $u))

& $sb -DefaultUserName "hdd" -DefaultSubnetPrefix "192.168.0" -DefaultCommentSuffix "-[github]"
```
