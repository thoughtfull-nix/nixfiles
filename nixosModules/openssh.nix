{
  config,
  lib,
  thoughtfull,
  ...
}:
let
  inherit (config.thoughtfull) graphical;
  inherit (lib) mkDefault mkIf;
  inherit (thoughtfull.pkgs) ssh-askpass;
in
{
  programs.ssh = {
    askPassword = mkIf graphical.enable "${ssh-askpass}/bin/ssh-askpass";
    enableAskPassword = mkDefault graphical.enable;
    extraConfig = ''
      VerifyHostKeyDNS yes
      VisualHostKey yes
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
    # I can ssh into a machine with agent forwarding and touch my yubikey locally to authenticate
    # sudo.
    services.sudo.rssh = mkDefault true;
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
