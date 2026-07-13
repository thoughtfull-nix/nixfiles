{ config, lib, ... }:
let
  cfg = config.thoughtfull.binaryCache;
  inherit (lib)
    mkIf
    mkOption
    types
    ;
  hasCredentials = cfg.awsCredentialsFile != null;
in
{
  config = mkIf (cfg.enable && hasCredentials) {
    age.secrets.nix-cache-host-credentials = {
      file = cfg.awsCredentialsFile;
      mode = "0440";
    };
    nix.settings = {
      extra-substituters = [
        "s3://${cfg.bucket}?region=${cfg.region}"
      ];
      extra-trusted-public-keys = [ cfg.publicKey ];
    };
    systemd.services.nix-daemon.serviceConfig.EnvironmentFile =
      config.age.secrets.nix-cache-host-credentials.path;
  };

  options.thoughtfull.binaryCache = {
    awsCredentialsFile = mkOption {
      default = null;
      description = ''
        Path to an age-encrypted file in `EnvironmentFile` format (one
        `KEY=value` pair per line) containing this host's own read-only AWS
        credentials for the cache bucket:

        ```
        AWS_ACCESS_KEY_ID=AKIA...
        AWS_SECRET_ACCESS_KEY=...
        AWS_DEFAULT_REGION=us-east-1
        ```

        Each host has its own IAM access key and its own encrypted file
        (typically `./<host>/secrets/nix-cache-host-credentials.age`), so
        that revoking or rotating one host's key doesn't affect the others.
        Set this once the operator has generated a `nix-cache-host` IAM
        access key for this host and run `nixfiles secret encrypt <host>
        nix-cache-host-credentials`.
      '';
      type = types.nullOr types.path;
    };
    bucket = mkOption {
      default = "thoughtfull-nix-cache";
      description = "Name of the S3 bucket holding the cache.";
      type = types.str;
    };
    enable = mkOption {
      default = true;
      description = ''
        Enable the binary cache as an S3 substituter on this host.

        Has no effect unless `awsCredentialsFile` is also set. Disable on
        installer/bootstrap images that don't yet have a committed
        credentials file.
      '';
      type = types.bool;
    };
    publicKey = mkOption {
      default = "nix-cache.thoughtfull.systems-1:kN4M+h0QLcDpQksBsFNtE9t6+bLa/s4axEWYpDmz2ag=";
      description = ''
        Public half of the Nix signing key used by CI to sign closures
        pushed to the cache. Hosts must trust this key to use the cache.

        Generate the key pair once with:
        ```
        nix key generate-secret --key-name nix-cache.thoughtfull.systems-1 > priv
        nix key convert-secret-to-public < priv > pub
        ```
        The contents of `pub` go here (committed in the clear). The
        contents of `priv` go into the `CACHE_SIGNING_KEY` GitHub Actions
        secret. See `doc/binary-cache.md`.
      '';
      type = types.str;
    };
    region = mkOption {
      default = "us-east-1";
      description = "AWS region containing the cache bucket.";
      type = types.str;
    };
  };
}
