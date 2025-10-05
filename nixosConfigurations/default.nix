self:
let
  inherit (self.lib) nixosConfiguration;
in
{
  mehida = nixosConfiguration {
    modules = [ (import ./mehida.nix) ];
    system = "x86_64-linux";
  };
  gemariah = nixosConfiguration {
    modules = [ (import ./gemariah) ];
    system = "x86_64-linux";
  };
}
