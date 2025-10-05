{ pkgs, ... }:
pkgs.replaceVarsWith {
  dir = "bin";
  isExecutable = true;
  meta.mainProgram = "ttfl-provision";
  name = "ttfl-provision";
  replacements = {
    git = "${pkgs.git}/bin/git";
    gpg = "${pkgs.gnupg}/bin/gpg";
    ssh = "${pkgs.openssh}/bin/ssh";
  };
  src = ./ttfl-provision.bash;
}
