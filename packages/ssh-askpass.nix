{ lib, pkgs, ... }:
let
  inherit (pkgs) bash x11_ssh_askpass;
  inherit (lib) writeFileScriptBin;
in
writeFileScriptBin {
  name = "ssh-askpass";
  replacements = {
    bash = "${bash}/bin/bash";
    x11_ssh_askpass = "${x11_ssh_askpass}/libexec/x11-ssh-askpass";
  };
  src = ./ssh-askpass.bash;
}
