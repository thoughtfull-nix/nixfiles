{ pkgs, ... }:
let
  inherit (pkgs)
    fetchurl
    jdk25
    makeBinaryWrapper
    stdenvNoCC
    udev
    ;
  inherit (pkgs.lib)
    getExe
    makeLibraryPath
    licenses
    optionalString
    platforms
    ;
in
# nixpkgs' papermc is stuck on 1.21.11: its update.py targets the sunset PaperMC v2 API, so it
# can't see builds published under Minecraft/Paper's newer date-based versioning (26.x) via the
# v3/fill API. Tracked upstream at https://github.com/NixOS/nixpkgs/issues/527546. Delete this
# package and switch back to pkgs.papermc once that lands.
#
# Paper 26.x also requires running with Java 25+, unlike nixpkgs' papermc which wraps the
# default (older) jre.
stdenvNoCC.mkDerivation {
  pname = "papermc";
  version = "26.2-63";

  src = fetchurl {
    url = "https://fill-data.papermc.io/v1/objects/3f79f638434eb004a2d2ae7cc23235a6f95ca94e18480f05280bb9728bf1e8cf/paper-26.2-63.jar";
    hash = "sha256-P3n2OENOsASi0q58wjI1pvlcqU4YSA8FKAu5covx6M8=";
  };

  dontUnpack = true;
  preferLocalBuild = true;
  allowSubstitutes = false;

  nativeBuildInputs = [ makeBinaryWrapper ];

  installPhase = ''
    runHook preInstall

    install -D $src $out/share/papermc/papermc.jar

    makeWrapper ${getExe jdk25} "$out/bin/minecraft-server" \
      --append-flags "-jar $out/share/papermc/papermc.jar nogui" \
      ${optionalString stdenvNoCC.hostPlatform.isLinux "--prefix LD_LIBRARY_PATH : ${makeLibraryPath [ udev ]}"}

    runHook postInstall
  '';

  meta = {
    description = "High-performance Minecraft server, pinned to Paper 26.2 build 63";
    homepage = "https://papermc.io/";
    license = licenses.gpl3Only;
    platforms = platforms.unix;
    mainProgram = "minecraft-server";
  };
}
