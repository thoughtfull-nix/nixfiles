_self: epkgs:
let
  inherit (epkgs)
    js2-mode
    json-mode
    trivialBuild
    typescript-mode
    ;
in
trivialBuild {
  packageRequires = [
    js2-mode
    json-mode
    typescript-mode
  ];
  pname = "thoughtfull-javascript";
  src = ./thoughtfull-javascript;
  version = "∞";
}
