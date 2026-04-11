1. Can we do the same nice connectors we did in the helper banner to the table in List SSH Keys? But notice that the table has more than one column so you need to find some more connectors.
2. The key is not being set to bold "• SSH DIR:  /home/kraid/.ssh" SSH DIR is not being bold.
3. If there's more than 1 key, you can place them next to each other not below each other but make sure that there's sufficient space between each kvp
4. There's an unnecessary step or a catch that shouldn't happen:
  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
                                                                                                                         🗑️  Delete an SSH Key Locally
  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │                                                                                                                                                                                                                                                                          │
  │  • SSH DIR:  /home/kraid/.ssh                                                                                                                                                                                                                                            │
  │                                                                                                                                                                                                                                                                          │
  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
  Remove key from remote host(s)  (Esc = skip remote)  axc  (192.168.0.210)
  Removing key from axc...
  Public key loaded.
  SSH config entry 'axc' found for 192.168.0.210.

  Will connect to remove the public key from kraid@axc:
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMP5ziAJEbEkbVwT2JonIGa/cOJ92dEyI/85NJKxvfb2 dev-poc2-[dev-poc]

  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────── SSH Session kraid@axc ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────── SSH session closed ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  SSH key removed from remote authorized_keys.
  Remove local key 'dev-poc2' from THIS machine? [y/N]
  Deleted: /home/kraid/.ssh/dev-poc2
  Deleted: /home/kraid/.ssh/dev-poc2.pub
  No local key files found for 'dev-poc2'.

  obviously "No local key files found for 'dev-poc2'." because it was just deleted in the 2 commands above it.

5. Let's try to make the header look like the helper banner (not the color but the box that the helper draws) -- so something like this:
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │                                                                                                                                                                                                                                                                          │
  │  🗑️  Delete an SSH Key Locally                                                                                                                                                                                                                                            │
  │                                                                                                                                                                                                                                                                          │
  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  But obviously the header's text must be centered

6. the bottom bar -- please make sure it's only 1 line, not 2 this is precious space.