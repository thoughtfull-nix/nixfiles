{ inputs, ... }:
{ sha256, username }:
inputs.nixpkgs.lib.strings.splitString "\n" (
  builtins.readFile (
    builtins.fetchurl {
      inherit sha256;
      url = "https://github.com/${username}.keys";
    }
  )
)
