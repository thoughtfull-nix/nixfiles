self@{ inputs, ... }:
{
  x86_64-linux = {
    mehida = import ./mehida.nix (
      self
      // {
        pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
      }
    );
  };
}
