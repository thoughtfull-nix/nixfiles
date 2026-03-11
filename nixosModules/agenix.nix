{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull) impermanence;
  inherit (lib) mkIf;
  inherit (pkgs) age;
in
{
  age.identityPaths = mkIf impermanence.enable [
    "/${impermanence.persistent.name}/etc/ssh/ssh_host_ed25519_key"
  ];
  environment.systemPackages = [ age ];
}
