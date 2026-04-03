{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "sound-theme-smooth";
  version = "1.2";

  src = pkgs.fetchurl {
    url = "https://my.opendesktop.org/s/QrcjmXiTpqQsciE/download";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/sounds/Smooth"
    cp -r . "$out/share/sounds/Smooth/"
    runHook postInstall
  '';

  meta = {
    description = "Smooth sound theme providing comprehensive XDG-compatible event sounds";
    homepage = "https://www.pling.com/p/1187979/";
    license = pkgs.lib.licenses.gpl2Plus;
    platforms = pkgs.lib.platforms.all;
  };
}
