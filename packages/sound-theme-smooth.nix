{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "sound-theme-smooth";
  version = "1.2";

  src = pkgs.fetchurl {
    url = "https://my.opendesktop.org/s/QrcjmXiTpqQsciE/download";
    name = "sound-theme-smooth-1.2.tar.gz";
    hash = "sha256-XtyXXOIWoVx+ExnSq08gIJ5j4DmP9IOaeH9ZihkfKtA=";
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
