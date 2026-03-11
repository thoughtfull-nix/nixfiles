_self: epkgs:
let
  inherit (epkgs)
    flycheck-rust
    rust-mode
    rustic
    thoughtfull
    trivialBuild
    ;
in
trivialBuild {
  packageRequires = [
    flycheck-rust
    rust-mode
    rustic
    thoughtfull
  ];
  pname = "thoughtfull-rust";
  src = ./thoughtfull-rust;
  version = "∞";
}
