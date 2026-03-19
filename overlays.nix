self: {
  emacs = import ./overlays/emacs.nix self;
  thoughtfull = import ./overlays/thoughtfull.nix self;
}
