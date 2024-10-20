;;; help-remove-button.el --- Remove button for Help buffer -*- lexical-binding: t; -*-

;; Copyright (C) 2024 Gong Qijian <gongqijian@gmail.com>

;; Author: Gong Qijian <gongqijian@gmail.com>
;; Created: 2024/10/16
;; Version: 0.1.1
;; Last-Updated: 2024-10-20 16:00:05 +0800
;;           by: Gong Qijian
;; Package-Requires: ((emacs "28.1"))
;; URL: https://github.com/twlz0ne/help-remove-button.el
;; Keywords: help

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; # help-remove-button.el

;; Remove button for Help buffer.

;; ![Remove button for advice](./remove-advice.png)

;; ![Remove button for generic](./remove-generic.png)

;; ### Installation

;; * Manual

;; Clone this repository to `/path/to/help-remove-button/`.  Add the following to your configuration file:

;; ``` elisp
;; (add-to-list 'load-path "/path/to/help-remove-button/")
;; (require 'help-remove-button)
;; ```

;; * Quelpa

;; ``` elisp
;; (quelpa '(help-remove-button :fetcher github
;;                              :repo "twlz0ne/help-remove-button.el"
;;                              :files ("help-remove-button.el")))
;; ```

;;; Change Log:

;;  0.1.0  2024/10/16  Initial version.

;;; Code:

;;; Advice

(defun help-remove-button--function-advices (function)
  "Return FUNCTION's advices."
  (let ((flist (indirect-function function)) advices)
    (when (and (consp flist)
               (or (eq 'macro (car flist))
                   (and (autoloadp flist) (memq (nth 4 flist) '(macro t)))))
      (setq flist (cdr flist)))
    (while (advice--p flist)
      (setq advices `(,@advices ,(advice--car flist)))
      (setq flist (advice--cdr flist)))
    advices))

;; Based on @xuchunyang's work at https://emacs-china.org/t/advice/7566
(defun help-remove-button--add-button-for-advice (function)
  "Add a button to remove advice of FUNCTION in current buffer.

Return t if advice was found."
  (when-let ((advices (help-remove-button--function-advices function)))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^\\(?:This \\(?:function\\|macro\\) has \\)?:[-a-z]+ advice: \\(.+\\)\\.?$" nil t)
        (let* ((name (string-trim (match-string 1) "[‘'`]" "[’']"))
               (symbol (intern-soft name))
               (advice (or symbol (car advices))))
          (when advice
            (let ((inhibit-read-only t))
              (insert " ")
              (insert-text-button
               "[Remove]"
               'cursor-sensor-functions `((lambda (&rest _) (message "%s" ',advice)))
               'help-echo (format "%s" advice)
               'action
               ;; In case lexical-binding is off
               `(lambda (_)
                  (when (yes-or-no-p (format "Remove %s ? " ',advice))
                    (message "Removing %s of advice from %s" ',function ',advice)
                    (advice-remove ',function ',advice)
                    (revert-buffer nil t)))
               'follow-link t))))
        (setq advices (cdr advices))))
    t))

;;; Generic method

;; Base on Erik Anderson's work at https://github.com/ebpa/tui.el/blob/52d2f343c602ff04dfd2ee871c6e0e1212e2cc8b/tui-node-types.el#L172-L179
(defun help-remove-button--cl-generic-remove-method (function qualifiers specializers)
  "Remove a method from generic FUNCTION."
  (when-let* ((generic (cl-generic-ensure-function function))
              (mt (cl--generic-method-table generic))
              (me (cl--generic-member-method specializers qualifiers mt)))
    ;; Remove from describe buffer.
    (setf (cl--generic-method-table generic)
          (seq-filter (lambda (x) (not (eq x (car me)))) mt))
    ;; Make the changes take effect. Otherwise, the removed method will still be called.
    (let ((gfun (cl--generic-make-function generic)))
      (defalias function gfun))))

(defun help-remove-button--add-button-for-cl-method (function)
  "Add a button to remove generic method of FUNCTION in current buffer.

Return t if method was found."
  (when-let ((methods
              (ignore-error 'wrong-type-argument
                (cl--generic-method-table
                 (ignore-error 'error (cl-generic-ensure-function function))))))
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "\n\nImplementations:$" nil t)
        (dolist (method methods)
          (pcase-let*
              ((`(,quals ,args ,_doc) (cl--generic-method-info method))
               (specializers (cl--generic-method-specializers method))
               (qualifiers (cl--generic-method-qualifiers method))
               (re (concat (if (length> quals 0)
                               (concat (substring quals
                                                  0 (string-match " *\\'"
                                                                  quals))
                                       "\n")
                             "")
                           (format "%s" (cons function args)))))
            (when (re-search-forward re nil t)
              (end-of-line)
              (let ((inhibit-read-only t))
                (insert " ")
                (insert-text-button
                 "[Remove]"
                 'cursor-sensor-functions `((lambda (&rest _) (message "%s" ',re)))
                 'help-echo (format "%s" re)
                 'action
                 ;; In case lexical-binding is off
                 `(lambda (_)
                    (when (yes-or-no-p (format "Remove %s ? " ',re))
                      (message "Removing %s of implementation from %s" ',function ',re)
                      (help-remove-button--cl-generic-remove-method ',function ',qualifiers ',specializers)
                      (revert-buffer nil t)))
                 'follow-link t)))))))
    t))

;;; Setup

(defun help-remove-button--advice-describe-function-1 (function)
  "Advice after `describe-function-1' to remove advice or generic method of FUNCTION."
  (when (get-buffer "*Help*")
    (with-current-buffer "*Help*"
      (or (help-remove-button--add-button-for-advice function)
          (help-remove-button--add-button-for-cl-method function)))))

(advice-add 'describe-function-1 :after #'help-remove-button--advice-describe-function-1)
(add-hook 'help-mode-hook 'cursor-sensor-mode)

(provide 'help-remove-button)

;;; help-remove-button.el ends here
