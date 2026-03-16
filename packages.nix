self@{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (inputs.disko.packages.${pkgs.stdenv.hostPlatform.system}) disko;
  inherit (pkgs)
    age
    bash
    git
    gnupg
    netcat
    openssh
    phraze
    pinentry-tty
    qemu
    ;
  inherit (lib)
    writeArgcScript
    writeFileScriptBin
    ;
in
# Keep these alphabetized
{
  attach-yubikey = writeArgcScript "attach-yubikey" ./packages/attach-yubikey.bash {
    bash = "${bash}/bin/bash";
    nc = "${netcat}/bin/nc";
  };
  brightness = import ./packages/brightness.nix self;
  detach-yubikey = writeArgcScript "detach-yubikey" ./packages/detach-yubikey.bash {
    nc = "${netcat}/bin/nc";
  };
  dictation = import ./packages/dictation.nix self;
  mic = import ./packages/mic.nix self;
  nixfiles = writeArgcScript "nixfiles" ./packages/nixfiles.bash {
    age = "${age}/bin/age";
    disko = "${disko}/bin/disko";
    git = "${git}/bin/git";
    gpg = "${gnupg}/bin/gpg";
    gpgconf = "${gnupg}/bin/gpgconf";
    phraze = "${phraze}/bin/phraze";
    pinentry = "${pinentry-tty}/bin/pinentry-tty";
    ssh-add = "${openssh}/bin/ssh-add";
    ssh-agent = "${openssh}/bin/ssh-agent";
  };
  options-doc = import ./packages/options-doc self;
  pins = import ./packages/pins.nix self;
  power-menu = import ./packages/power-menu.nix self;
  run-vm = writeArgcScript "run-vm" ./packages/run-vm.bash {
    ovmf-firmware = pkgs.OVMF.firmware;
    ovmf-variables = pkgs.OVMF.variables;
    qemu = "${qemu}/bin/qemu-system-x86_64";
    qemu-img = "${qemu}/bin/qemu-img";
  };
  speaker = import ./packages/speaker.nix self;
  ssh-askpass = import ./packages/ssh-askpass.nix self;
  theme-toggle = import ./packages/theme-toggle.nix self;
  uns = import ./packages/uns.nix self;
  waybar-weather = import ./packages/waybar-weather.nix self;
  waybar-yubikey = writeFileScriptBin {
    name = "waybar-yubikey";
    replacements = {
      bash = "${bash}/bin/bash";
      nc = "${netcat}/bin/nc";
    };
    src = ./packages/waybar-yubikey.bash;
  };
  yubikey-totp = import ./packages/yubikey-totp.nix self;
}
