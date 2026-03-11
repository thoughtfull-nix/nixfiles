self: _final: prev:
# following examples from
# https://nixos.org/manual/nixpkgs/stable/#sec-emacs-config
# https://github.com/nix-community/emacs-overlay/blob/master/overlays/package.nix
{
  emacsPackagesFor =
    emacs: (prev.emacsPackagesFor emacs).overrideScope (efinal: _eprev: self.emacsPackages efinal);
}
