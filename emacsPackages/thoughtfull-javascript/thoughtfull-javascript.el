;;; thoughtfull-javascript.el --- Configure JavaScript development       -*- lexical-binding: t; -*-

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

;; Configure js2, json, and typescript modes.

;;; Code:

(use-package js2-mode
  :mode "\\.js\\'")
(use-package json-mode)
(use-package typescript-mode)

(provide 'thoughtfull-javascript)
;;; thoughtfull-javascript.el ends here
