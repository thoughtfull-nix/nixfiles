{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull) graphical;
  inherit (lib) mkDefault mkIf;
  inherit (pkgs.thoughtfull) ssh-askpass;
in
{
  environment.systemPackages = mkIf graphical.enable [ ssh-askpass ];
  programs.ssh = {
    # An absolute path, not just "ssh-askpass": the ssh-agent systemd unit's
    # own askpass wrapper execs this with the unit's minimal generated PATH
    # (no /run/current-system/sw/bin), so a bare command name silently fails
    # to resolve there. That failure is invisible for touch-only FIDO2 keys
    # (their notify-only prompt never needs a real answer) but breaks PIN
    # (verify-required) keys: ssh-agent gets no PIN back and the signature
    # is refused with a misleading "incorrect passphrase" error.
    #
    # /run/current-system/sw/bin/ssh-askpass rather than "${ssh-askpass}/bin/
    # ssh-askpass": the long-lived ssh-agent systemd unit resolves this path
    # fresh on every invocation, so it keeps working across a nixos-rebuild
    # switch without needing a restart. A baked-in store path would go stale
    # (and eventually be garbage-collected) the moment ssh-askpass rebuilds.
    askPassword = mkIf graphical.enable "/run/current-system/sw/bin/ssh-askpass";
    enableAskPassword = mkDefault graphical.enable;
    extraConfig = ''
      VerifyHostKeyDNS yes
      VisualHostKey yes
      # Workaround: Firewalla returns :: (IPv6 unspecified) AAAA records for
      # .lan hosts even with IPv6 disabled, causing SSH to fall back to
      # localhost when the target refuses the connection. Remove this if
      # Firewalla fixes their DNS behavior.
      Match host *.lan
        AddressFamily inet
    '';
    knownHostsFiles = [
      ./openssh/known_hosts_github
    ];
    startAgent = true;
  };
  security.pam = {
    # rssh will authenticate using ssh-agent.
    rssh = {
      enable = mkDefault true;
      # I have for sudo a separate key on my yubikey that requires touch.
      settings.auth_key_file = mkDefault "/etc/ssh/authorized_keys.d/\${ruser}_sudo";
    };
    services.sudo = {
      # I can ssh into a machine with agent forwarding and touch my yubikey locally to authenticate
      # sudo.
      rssh = mkDefault true;
      # Both u2f and rssh are "sufficient", so auth stops at whichever succeeds first: prefer
      # touching the yubikey directly by running u2f before rssh. rssh then only kicks in as a
      # fallback when the yubikey isn't directly plugged in, e.g. over agent-forwarded ssh.
      rules.auth.u2f.order = config.security.pam.services.sudo.rules.auth.rssh.order - 10;
    };
  };
  services.openssh.hostKeys = [
    {
      path = "/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
  # my boostrapping process uses a preconfigured key for hosts, so I don't need automatic keygen
  systemd.services.sshd-keygen.enable = mkDefault false;
  thoughtfull.impermanence = {
    files = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
    user.directories = [
      {
        directory = ".ssh";
        mode = "0700";
      }
    ];
  };
}
