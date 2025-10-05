self@{ inputs, ... }:
{
  x86_64-linux = {
    mehida = import ./mehida (
      self
      // {
        pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
      }
    );
    ttfl-provision = import ./ttfl-provision (
      self
      // {
        pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
      }
    );
  };
}
