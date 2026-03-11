{ inputs, ... }:
{ sha256, username }:
let
  inherit (builtins) fetchurl readFile;
in
inputs.nixpkgs.lib.strings.splitString "\n" (
  readFile (fetchurl {
    inherit sha256;
    url = "https://github.com/${username}.keys";
  })
)
