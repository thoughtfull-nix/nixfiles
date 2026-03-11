{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull) user;
  inherit (lib) mkDefault;
in
{
  environment = {
    etc = {
      "gnupg/gpg.conf".text = ''
        cert-digest-algo SHA512
        charset utf-8
        default-preference-list SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed
        fixed-list-mode
        keyid-format 0xlong
        list-options show-uid-validity
        no-comments
        no-emit-version
        no-symkey-cache
        personal-cipher-preferences AES256 AES192 AES
        personal-compress-preferences ZLIB BZIP2 ZIP Uncompressed
        personal-digest-preferences SHA512 SHA384 SHA256
        require-cross-certification
        s2k-cipher-algo AES256
        s2k-digest-algo SHA512
        use-agent
        verify-options show-uid-validity
        with-fingerprint
      '';
      "gnupg/scdaemon.conf".text = ''
        disable-ccid
      '';
    };
    interactiveShellInit = ''
      # Bind gpg-agent to this TTY if gpg commands are used.
      export GPG_TTY=$(tty)
    '';
  };
  programs.gnupg.agent = {
    enable = mkDefault true;
    pinentryPackage = pkgs.pinentry-gtk2;
    settings = {
      grab = "";
      # Disable external cache to ensure gpg-agent reads shadow key files on each
      # operation, allowing yubikey-touch-detector to detect GPG touch requests
      no-allow-external-cache = "";
    };
  };
  thoughtfull = {
    impermanence.user.directories = [
      {
        directory = ".gnupg";
        user = user.name;
        group = "users";
        mode = "0700";
      }
    ];
  };
}
