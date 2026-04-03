{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "sound-theme-smooth";
  version = "1.2";

  src = pkgs.fetchurl {
    url = "https://www.gnome-look.org/p/999081/startdownload?file_id=1468223087&file_name=sound-theme-smooth-1.2.tar.gz&file_type=application/x-gzip&file_size=592367";
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
    homepage = "https://www.gnome-look.org/p/999081/";
    license = pkgs.lib.licenses.gpl2Plus;
    platforms = pkgs.lib.platforms.all;
  };
}
