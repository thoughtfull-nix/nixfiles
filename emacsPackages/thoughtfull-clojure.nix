_self: epkgs:
let
  inherit (epkgs)
    cider
    clojure-mode
    clojure-mode-extra-font-locking
    flycheck
    flycheck-clj-kondo
    paredit
    thoughtfull
    trivialBuild
    ;
in
trivialBuild {
  packageRequires = [
    cider
    clojure-mode
    clojure-mode-extra-font-locking
    flycheck
    flycheck-clj-kondo
    paredit
    thoughtfull
  ];
  pname = "thoughtfull-clojure";
  src = ./thoughtfull-clojure;
  version = "∞";
}
