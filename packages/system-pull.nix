{ lib, pkgs }:
let
  inherit (pkgs.lib) makeOverridable;
  inherit (lib) writeFileScriptBin;
in
makeOverridable
  (
    {
      awscli2,
      bash,
      bucket,
      coreutils,
      credentialsFile,
      dotenvy,
      gcDeleteOlderThan,
      hostname-debian,
      jq,
      nix,
      region,
    }:
    writeFileScriptBin {
      name = "system-pull";
      replacements = {
        aws = "${awscli2}/bin/aws";
        bash = "${bash}/bin/bash";
        inherit bucket region;
        credentials_file = credentialsFile;
        dotenvy = "${dotenvy}/bin/dotenvy";
        gc_delete_older_than = gcDeleteOlderThan;
        hostname = "${hostname-debian}/bin/hostname";
        jq = "${jq}/bin/jq";
        nix_collect_garbage = "${nix}/bin/nix-collect-garbage";
        nix_env = "${nix}/bin/nix-env";
        nix_store = "${nix}/bin/nix-store";
        readlink = "${coreutils}/bin/readlink";
      };
      src = ./system-pull/system-pull.bash;
    }
  )
  {
    inherit (pkgs)
      awscli2
      bash
      coreutils
      dotenvy
      hostname-debian
      jq
      nix
      ;
    # Defaults match thoughtfull.binaryCache; the system-pull module overrides
    # these with the host's actual configuration.
    bucket = "thoughtfull-nix-cache";
    credentialsFile = "/run/agenix/nix-cache-credentials";
    gcDeleteOlderThan = "14d";
    region = "us-east-1";
  }
