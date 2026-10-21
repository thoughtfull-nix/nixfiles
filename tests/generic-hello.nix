# hello without its rpath and with the generic loader path, like a downloaded Linux binary
pkgs:
pkgs.runCommand "generic-hello" { nativeBuildInputs = [ pkgs.patchelf ]; } ''
  install -Dm755 ${pkgs.hello}/bin/hello $out/bin/hello
  patchelf --set-interpreter "$(cat ${pkgs.nix-ld}/nix-support/ldpath)" --remove-rpath $out/bin/hello
''
