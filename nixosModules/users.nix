{
  config,
  lib,
  thoughtfull,
  ...
}:
with lib;
with thoughtfull.lib;
with config.users.users;
{
  users = {
    mutableUsers = mkDefault false;
    users = {
      root.openssh.authorizedKeys.keys =
        with technosophist;
        mkIf (elem "wheel" extraGroups) openssh.authorizedKeys.keys;
      technosophist = with technosophist; {
        isNormalUser = mkIf enable (mkDefault true);
        openssh.authorizedKeys.keys = mkIf enable (githubKeys {
          sha256 = "18kzyik9mv77iis76pbn40pms5mdmzj4y4mpxgsvx17mbllbj1ia";
          username = "technosophist";
        });
        uid = mkIf enable (mkDefault 1000);
      };
    };
  };
}
