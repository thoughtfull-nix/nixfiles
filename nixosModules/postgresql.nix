{ config, lib, ... }:
let
  inherit (lib) mkIf;
in
{
  thoughtfull = mkIf config.services.postgresql.enable {
    impermanence.directories = [
      {
        directory = "/var/lib/postgresql";
        user = "postgres";
        group = "postgres";
        mode = "0700";
        backup = false;
      }
    ];
    monitoring.services = [ "postgresql" ];
  };
}
