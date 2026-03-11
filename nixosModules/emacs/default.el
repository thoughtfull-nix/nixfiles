;;; default.el --- Default configuration                                 -*- lexical-binding: t; -*-

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

;; This default configuration applies to every Emacs everywhere, so should be minimal, or deferred.
;; This includes customization for optional packages that may or may not be installed.  When a
;; package is installed, it will be properly configured.  When it is not installed, the
;; configuration is never run.

;; Any configuration for a particular machine or circumstance should be done with customization,
;; which should override anything configured here.

;; Initialization files are loaded in this order: early-init.el, init.el, default.el.
;; `user-emacs-directory' is set based on where init.el is found, and the search locations are the
;; usual suspects (~/.emacs, ~/.emacs.el, ~/.emacs.d/init.el, ~/.config/emacs/init.el, etc.).

;; early-init.el should exist at either ~/.emacs.d/early-init.el or ~/.config/emacs/early-init.el
;; and loads before the package system and GUI are initialized.  Anything not package related should
;; be in init.el if at all possible.  Anything GUI related should be in init.el or use hooks if in
;; early-init.el.

;; default.el is a library found on the library path.  If early-init.el or init.el set
;; `inhibit-default-init' to nil, then default.el is not loaded.

;;; Code:
(require 'thoughtfull)

@extraConfig@

(provide 'default)
;;; default.el ends here
