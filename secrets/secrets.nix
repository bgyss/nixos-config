let
  # Personal key: allows editing/re-encrypting secrets from this user account.
  # Raw SSH public key (~/.ssh/id_ed25519.pub) — NOT run through `ssh-to-age`.
  # age's own built-in ssh-ed25519 recipient handling uses a different
  # ed25519->X25519 conversion than `ssh-to-age`, so an `ssh-to-age`-derived
  # "age1..." recipient can never be decrypted by `age --identity <sshkey>`
  # (which is exactly what agenix's activation script calls). Using the raw
  # "ssh-ed25519 AAAA..." string lets age do its own conversion consistently
  # on both the encrypt and decrypt side.
  briangyss = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIONXRQ1pfF6rlm75AqclK0rrmXGBNHGzQzAAdlDDjaA/ bgyss@hey.com";

  # Host key: allows decryption at system activation time.
  # Raw SSH public key (/etc/ssh/ssh_host_ed25519_key.pub on garmonbozia).
  garmonbozia = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPkTyUljGW9Qw3kaNi9KTGsR/QOpVQPuvDREfc9ADqEX";

  allKeys = [ briangyss garmonbozia ];
in
{
  "openai-api-key.age".publicKeys = allKeys;
  "ssh-key.age".publicKeys = allKeys;
  "aws-credentials.age".publicKeys = allKeys;
}
