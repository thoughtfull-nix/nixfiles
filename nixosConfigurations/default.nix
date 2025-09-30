self:
let
  inherit (self.lib) nixosConfiguration;
in
{
  mehida = nixosConfiguration {
    modules = [ (import ./mehida.nix) ];
    system = "x86_64-linux";
  };
}
