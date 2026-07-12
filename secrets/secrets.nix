let
  # Personal key: allows editing/re-encrypting secrets from this user account
  # (derived from ~/.ssh/id_ed25519.pub via `ssh-to-age`).
  briangyss = "age1nj84gxa944tahra3hhyjclh0l80res6gssvl0mk0x7jgawvzs9asv7z8pm";

  # Host key: allows decryption at system activation time
  # (derived from /etc/ssh/ssh_host_ed25519_key.pub on garmonbozia via `ssh-to-age`).
  garmonbozia = "age1yhqg8ezdxrpulf0urzynlz9c69uvyfpl5zyd40qklzhryzqt4pyqcx0ar8";

  allKeys = [ briangyss garmonbozia ];
in
{
  "openai-api-key.age".publicKeys = allKeys;
}
