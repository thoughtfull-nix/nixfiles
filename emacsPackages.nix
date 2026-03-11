self: epkgs: {
  thoughtfull = import ./emacsPackages/thoughtfull.nix self epkgs;
  thoughtfull-clojure = import ./emacsPackages/thoughtfull-clojure.nix self epkgs;
  thoughtfull-javascript = import ./emacsPackages/thoughtfull-javascript.nix self epkgs;
  thoughtfull-rust = import ./emacsPackages/thoughtfull-rust.nix self epkgs;
}
