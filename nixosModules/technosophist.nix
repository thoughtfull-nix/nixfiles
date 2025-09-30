{
  config,
  lib,
  thoughtfull,
  ...
}:
let
  hasWheel = builtins.elem "wheel" config.users.users.technosophist.extraGroups;
  keys = thoughtfull.lib.githubKeys {
    sha256 = "18kzyik9mv77iis76pbn40pms5mdmzj4y4mpxgsvx17mbllbj1ia";
    username = "technosophist";
  };
in
{
  users = {
    mutableUsers = lib.mkDefault false;
    users = {
      root.openssh.authorizedKeys.keys = lib.mkIf hasWheel keys;
      technosophist = {
        isNormalUser = lib.mkDefault true;
        openssh.authorizedKeys.keys = keys;
        uid = lib.mkDefault 8000;
      };
    };
  };
}
