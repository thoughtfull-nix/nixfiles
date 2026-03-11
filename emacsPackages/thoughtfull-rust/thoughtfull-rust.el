;;; thoughtfull-rust.el --- Configure Rust development                   -*- lexical-binding: t; -*-

;; Copyright © technosophist

;; This program is free software: you can redistribute it and/or modify it under the terms of the
;; GNU General Public License as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
;; even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License along with this program.  If
;; not, see <https://www.gnu.org/licenses/>.

;; Author: technosophist <technosophist@thoughtfull.systems>

;;; Commentary:

;; Configures essential of the Rust development experience like flycheck, etc.

;;; Code:
(require 'thoughtfull)

(use-package flycheck-rust
  :hook (rust-mode . flycheck-rust-setup))
(use-package lsp-mode
  :custom ((lsp-rust-analyzer-cargo-watch-command "clippy")
           (lsp-rust-analyzer-display-lifetime-elision-hints-enable "skip_trivial")
           (lsp-rust-analyzer-display-chaining-hints t)
           (lsp-rust-analyzer-display-lifetime-elision-hints-use-parameter-names nil)
           (lsp-rust-analyzer-display-closure-return-type-hints t)
           (lsp-rust-analyzer-display-parameter-hints nil)
           (lsp-rust-analyzer-display-reborrow-hints nil))
  :defer)
(use-package rust-mode
  :defer)
(use-package rustic
  :defer)

(provide 'thoughtfull-rust)
;;; thoughtfull-rust.el ends here
