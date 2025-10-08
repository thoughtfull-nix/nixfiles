{ inputs, ... }:
{ sha256, username }:
with builtins;
inputs.nixpkgs.lib.strings.splitString "\n" (
  readFile (fetchurl {
    inherit sha256;
    url = "https://github.com/${username}.keys";
  })
)
