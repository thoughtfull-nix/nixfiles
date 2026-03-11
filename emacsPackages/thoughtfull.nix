_self: epkgs:
let
  inherit (epkgs)
    adwaita-dark-theme
    all-the-icons
    all-the-icons-completion
    all-the-icons-dired
    all-the-icons-ibuffer
    auto-dark
    chatgpt-shell
    company
    consult
    dap-mode
    diminish
    flycheck
    lsp-mode
    lsp-ui
    magit
    marginalia
    markdown-mode
    nix-mode
    orderless
    paredit
    trivialBuild
    use-package
    vertico
    visual-fill-column
    wgrep
    which-key
    writegood-mode
    yaml-mode
    ;
in
trivialBuild {
  packageRequires = [
    adwaita-dark-theme
    all-the-icons
    all-the-icons-completion
    all-the-icons-dired
    all-the-icons-ibuffer
    auto-dark
    chatgpt-shell
    company
    consult
    dap-mode
    diminish
    flycheck
    lsp-mode
    lsp-ui
    magit
    marginalia
    markdown-mode
    nix-mode
    orderless
    paredit
    use-package
    vertico
    visual-fill-column
    wgrep
    which-key
    writegood-mode
    yaml-mode
  ];
  pname = "thoughtfull";
  src = ./thoughtfull;
  version = "∞";
}
