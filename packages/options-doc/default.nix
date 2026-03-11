self@{
  pkgs,
  ...
}:
let
  inherit (pkgs) deno fetchurl stdenv;
  inherit (pkgs.lib) any hasPrefix;

  markedJs = fetchurl {
    url = "https://cdn.jsdelivr.net/npm/marked@15.0.7/marked.min.js";
    hash = "sha256-k04+Nuni2gr7Gm51B1uw8JrwUpOoROhKdHfvQJEcNJo=";
  };

  # Use the ISO config (has all modules, no secrets)
  nixosSystem = self.nixosConfigurations.nixos;

  # Transform declarations to GitHub URLs
  # Match by path patterns since store paths differ between evaluation contexts
  nixfilesPatterns = [
    "nixosModules/"
    "lib/"
    "packages/"
    "flake.nix"
  ];
  nixpkgsPatterns = [
    "nixos/modules/"
    "pkgs/"
    "lib/"
  ];

  inherit (builtins) match;

  transformOptions =
    opt:
    let
      transformDecl =
        decl:
        let
          declStr = toString decl;
          # Extract path after /nix/store/hash-source/
          pathMatch = match "/nix/store/[a-z0-9]+-source/(.*)" declStr;
          relativePath = if pathMatch != null then builtins.head pathMatch else null;
          isNixfiles = relativePath != null && any (p: hasPrefix p relativePath) nixfilesPatterns;
          isNixpkgs =
            relativePath != null && !isNixfiles && any (p: hasPrefix p relativePath) nixpkgsPatterns;
        in
        if isNixfiles then
          {
            url = "https://github.com/thoughtfull-nix/nixfiles/blob/main/${relativePath}";
            source = "nixfiles";
          }
        else if isNixpkgs then
          {
            url = "https://github.com/NixOS/nixpkgs/blob/nixos-25.11/${relativePath}";
            source = "nixpkgs";
          }
        else
          {
            url = null;
            source = "unknown";
          };
    in
    opt // { declarations = map transformDecl opt.declarations; };

  optionsDoc = pkgs.nixosOptionsDoc {
    options = nixosSystem.options;
    warningsAreErrors = false;
    inherit transformOptions;
  };

in
stdenv.mkDerivation {
  pname = "options-doc";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [ deno ];

  buildPhase = ''
    export DENO_DIR=$(mktemp -d)
    deno run --allow-read --allow-write --allow-net \
      build.ts \
      --options "${optionsDoc.optionsJSON}/share/doc/nixos/options.json" \
      --output "$out"
    cp ${markedJs} $out/marked.min.js
  '';

  installPhase = "true";
}
