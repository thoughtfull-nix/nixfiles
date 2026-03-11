;;; thoughtfull-clojure.el --- Configure Clojure development             -*- lexical-binding: t; -*-

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

;; Configures essential of the Clojure development experience like cider, kondo, etc.

;;; Code:
(require 'thoughtfull)

(use-package cider
  :after clojure-mode
  :custom ((cider-preferred-build-tool 'clojure-cli)
           (cider-repl-history-file "~/.cider-history")
           (nrepl-log-messages t)))
(use-package clojure-mode
  ;; clojure-mode fills to fill-column plus 2.  I think it is because it narrows the buffer to the
  ;; docstring, which removes the first two spaces on the line, so I'm adjusting for that here.
  :custom ((clojure-docstring-fill-column (- fill-column 2))
           ;; https://metaredux.com/posts/2024/02/19/configuring-fixed-tonsky-indentation-in-clojure-mode.html
           (clojure-indent-style 'always-indent)
           (clojure-indent-keyword-style 'always-indent)
           (clojure-enable-indent-specs nil))
  :defer)
(use-package clojure-mode-extra-font-locking
  :after clojure-mode)
(use-package flycheck
  :hook (clojure-mode . flycheck-mode))
(use-package flycheck-clj-kondo
  :after (clojure-mode flycheck))
(use-package paredit
  :hook (clojure-mode . paredit-mode))

(provide 'thoughtfull-clojure)
;;; thoughtfull-clojure.el ends here
