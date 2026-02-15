final: prev: {
  c4 = prev.buildGoModule rec {
    pname = "c4";
    version = "0-unstable-2025-07-30";

    src = prev.fetchFromGitHub {
      owner = "Avalanche-io";
      repo = "c4";
      rev = "c6c5e435354f685d66631d6e15ac5369bb992b1c";
      hash = "sha256-ePXhkmuZ2xERvZfLHWKjB+W/VtpqHrSpUK/NcB9wXkw=";
    };

    vendorHash = "sha256-afTmUzfzaln7CmYseKBZpBO1zw0hkUpqQz9TB/ZdOpE=";

    subPackages = [ "cmd/c4" ];

    meta = with prev.lib; {
      description = "C4 ID - Universally Unique and Consistent Identification (SMPTE ST 2114:2017)";
      homepage = "https://github.com/Avalanche-io/c4";
      license = licenses.mit;
      mainProgram = "c4";
    };
  };
}
