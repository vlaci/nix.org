;; -*- lexical-binding: t; -*-

;; Use font from Gsettings from /org/gnome/desktop/interface/
;; The keys read are:
;;  - ‘font-name’
;;  - 'monospace-font-name’
(require 'vlaci-emacs)

(setq font-use-system-font t)
(set-face-attribute 'fixed-pitch nil :height 1.0)
(set-face-attribute 'variable-pitch nil :height 1.0)

(setup (:package gcmh)
  (:hook-into on-first-buffer-hook)
  (:option gcmh-verbose init-file-debug
           gcmh-high-cons-threshold (* 128 1024 1024)))

(setup emacs
  (setq user-emacs-directory user-cache-directory)
  (:option
   custom-file (vlaci/in-cache-directory "custom.el")
   auto-save-interval 2400
   auto-save-timeout 300
   auto-save-list-file-name (vlaci/in-cache-directory "auto-save.lst")
   auto-save-file-name-transforms `((".*" ,(vlaci/in-cache-directory "auto-save/") t))
   backup-directory-alist `(("." . ,(vlaci/in-cache-directory "backup/")))
   backup-by-copying t
   version-control t
   delete-old-versions t
   kept-new-versions 10
   kept-old-versions 5)

  (make-directory (vlaci/in-cache-directory "auto-save/") :parents)

  (load custom-file :no-error-if-file-is-missing))


(setup recentf
  (:option recentf-max-saved-items 200
           recentf-auto-cleanup 300)
  (define-advice recentf-cleanup (:around (fun) silently)
    (let ((inhibit-message t)
          (message-log-max nil))
      (funcall fun)))
  (recentf-mode 1))

(setup savehist
  (:hook-into on-first-file-hook)
  (:option history-length 1000
           history-delete-duplicates t
           savehist-save-minibuffer-history t
           savehist-additional-variables
            '(kill-ring                            ; clipboard
              register-alist                       ; macros
              mark-ring global-mark-ring           ; marks
              search-ring regexp-search-ring)))    ; searches

(setup save-place
  (:hook-into on-first-file-hook)
  (:option save-place-limit 600))

(defun vl/zoxide-record (dir)
  (call-process "zoxide" nil nil nil "add" dir))

(advice-add 'eshell-add-to-dir-ring :after #'vl/zoxide-record)

(add-hook 'dired-mode-hook (lambda () (vl/zoxide-record dired-directory)))

(defun vl/zoxide-query ()
  (let ((candidates (with-temp-buffer
                      (call-process "zoxide" nil t nil "query" "-l")
                      (split-string (buffer-string) "\n" t))))
    (consult--read
     candidates
     :prompt "Zoxide: "
     :sort nil)))

(defun vl/dired-zoxide ()
  (interactive)
  (dired (vl/zoxide-query)))

(setup eshell
  (:when-loaded
    (defun eshell/zi ()
      (eshell/cd (vl/zoxide-query)))

    (defun eshell/z (target)
      (let ((res (with-temp-buffer
                   (call-process "zoxide" nil t nil "query" target)
                   (s-trim (buffer-string)))))
        (eshell/cd res)))))
(setup org
  (:option org-startup-indented t
           org-edit-src-content-indentation 0))

(setup (:package org-modern)
  (:hook-into org-mode-hook))
(setup (:package org-roam)
  (:defer-incrementally ansi-color dash f rx seq magit-section emacsql))
(setup (:package vc-jj))
(setup eshell
  (:option eshell-aliases-file (vlaci/in-init-directory "eshell/alias")
           eshell-visual-options '("git" "--help" "--paginate")
           eshell-visual-subcommands '("git" "log" "diff" "show")
           eshell-prompt-function #'vl/esh-prompt-func)
  (:hook (defun vl/set-eshell-term-h ()
           (setenv "TERM" "xterm-256color")))
  (:when-loaded
    (defun vl/eshell-pick-history ()
      "Show Eshell history in a completing-read picker and insert the selected command."
      (interactive)
      (let* ((history-file (expand-file-name "eshell/history" user-emacs-directory))
             (history-entries (when (file-exists-p history-file)
                                (with-temp-buffer
                                  (insert-file-contents history-file)
                                  (split-string (buffer-string) "\n" t))))
             (selection (completing-read "Eshell History: " history-entries)))
        (when selection
          (insert selection))))

    (add-hook 'eshell-mode-hook
              (lambda ()
                (local-set-key (kbd "C-c l") #'vl/eshell-pick-history)
                (local-set-key (kbd "C-l")
                               (lambda ()
                                 (interactive)
                                 (eshell/clear 1)
                                 (eshell-send-input)))))))
(setup (:package eshell-syntax-highlighting)
  (:hook-into eshell-mode-hook))

(setup (:package esh-help)
  (:with-feature eshell
    (:when-loaded
      (setup-esh-help-eldoc))))
(require 'dash)
(require 's)

(defvar vl/esh-sep " | ")
(defvar vl/esh-section-delim " ")
(defvar vl/esh-header "")
(defvar vl/eshell-funcs nil)

(setq eshell-prompt-regexp "❯ ")
(setq eshell-prompt-string "❯ ")

(defmacro vl/with-face (STR &rest PROPS)
  "Return STR propertized with PROPS."
  `(propertize ,STR 'face (list ,@PROPS)))

(defmacro vl/esh-section (NAME ICON FORM &rest PROPS)
  "Build eshell section NAME with ICON prepended to evaled FORM with PROPS."
  `(setq ,NAME
         (lambda () (when ,FORM
                      (-> ,ICON
                          (concat vl/esh-section-delim ,FORM)
                          (vl/with-face ,@PROPS))))))

(defun vl/esh-acc (acc x)
  "Accumulator for evaluating and concatenating esh-sections."
  (--if-let (funcall x)
      (if (s-blank? acc)
          it
        (concat acc vl/esh-sep it))
    acc))

(defun vl/esh-prompt-func ()
  "Build `eshell-prompt-function'"
  (concat vl/esh-header
          (-reduce-from 'vl/esh-acc "" vl/eshell-funcs)
          "\n"
          eshell-prompt-string))

(defvar vl/max-prefix-len 3)

(defun find-minimal-unique-prefix (target entries)
  "Find the shortest prefix of TARGET that uniquely identifies it in ENTRIES."
  (catch 'found
    (dotimes (len (min vl/max-prefix-len (length target)))
      (let ((prefix (substring target 0 (1+ len)))
            (count 0))
        (dolist (entry entries)
          (when (string-prefix-p prefix entry)
            (cl-incf count)))
        (when (= count 1)
          (throw 'found prefix))))
    target))

(defun vl/truncate-path-to-unique-completion (path)
  "Truncate PATH's directory components to shortest uniquely tab-completable segments, preserving ~ abbreviation."
  (let* ((abs-path (expand-file-name path))
         (dir-part (file-name-directory abs-path))
         (file-part (file-name-nondirectory abs-path))
         (home-dir (expand-file-name "~/"))
         (in-home (file-in-directory-p dir-part home-dir))
         (base-dir (if in-home home-dir "/"))
         (rel-dir (file-relative-name dir-part base-dir))
         (components (split-string rel-dir "/" t))
         (current-dir base-dir)
         (result '()))

    (dolist (comp components)
      (let* ((entries (directory-files current-dir nil "^[^.]"))
             (entries (delete "." (delete ".." entries)))
             (prefix (find-minimal-unique-prefix comp entries)))
        (push prefix result)
        (setq current-dir (expand-file-name comp current-dir))))

    (concat
     (cond
      (in-home
       (if (null components)
           "~/"
         (concat "~/" (mapconcat 'identity (nreverse result) "/") "/")))
      ((null components) "/")
      (t (concat "/" (mapconcat 'identity (nreverse result) "/") "/")))
     file-part)))

(vl/esh-section esh-dir
                (nerd-icons-faicon "nf-fa-folder_open_o")
                (vl/truncate-path-to-unique-completion (abbreviate-file-name (eshell/pwd)))
                '(:foreground "MediumPurple4" :weight ultra-bold :underline t))

(vl/esh-section esh-git
                (nerd-icons-faicon "nf-fa-git")
                (magit-get-current-branch)
                '(:foreground "green"))

(vl/esh-section esh-nix
                (nerd-icons-devicon "nf-dev-nixos")
                (getenv "IN_NIX_SHELL")
                '(:foreground "dark blue"))

(vl/esh-section esh-exit-code
                (nerd-icons-faicon "nf-fa-warning")
                (let ((rc eshell-last-command-status))
                  (when (not (eq rc 0)) (number-to-string rc)))
                '(:foreground "dark red"))

;; Choose which eshell-funcs to enable
(setq vl/eshell-funcs (list esh-dir esh-nix esh-git esh-exit-code))

(defun vl/delete-previous-eshell-prompt-segments ()
  "Delete previous prompts segments."
  (save-excursion
    (let ((inhibit-read-only t)) ; Allow modifications to read-only text
      (forward-line -1)
      (delete-line))))

(add-hook 'eshell-pre-command-hook #'vl/delete-previous-eshell-prompt-segments)

(define-advice eshell/cat (:override (filename) vl/eshell-cat-a)
  "Like cat(1) but with syntax highlighting."
  (let ((existing-buffer (get-file-buffer filename))
        (buffer (find-file-noselect filename)))
    (eshell-print
     (with-current-buffer buffer
       (if (fboundp 'font-lock-ensure)
           (font-lock-ensure)
         (with-no-warnings
           (font-lock-fontify-buffer)))
       (let ((contents (buffer-string)))
         (remove-text-properties 0 (length contents) '(read-only nil) contents)
         contents)))
    (unless existing-buffer
      (kill-buffer buffer))
    nil))
(setup emacs
  (:option help-window-keep-selected t)) ;; navigating to e.g. source from help window reuses said window
(setup which-key
  (:option which-key-popup-type 'minibuffer)
  (:hook-into on-first-input-hook))
(setup (:package helpful elisp-demos)
  (:option help-window-select t)
  (:global
   [remap describe-command] #'helpful-command
   [remap describe-function] #'helpful-callable
   [remap describe-macro] #'helpful-macro
   [remap describe-key] #'helpful-key
   [remap describe-symbol] #'helpful-symbol
   [remap describe-variable] #'helpful-variable)
  (:when-loaded
    (require 'elisp-demos)
    (advice-add 'helpful-update :after #'elisp-demos-advice-helpful-update)))
(setup (:package on)
  (:require on))
(setup emacs
  (:global [remap kill-buffer] #'kill-current-buffer))
(setup (:package doom-modeline auto-dark spacious-padding)
  (:option spacious-padding-subtle-mode-line t
           spacious-padding-widths
           '( :internal-border-width 15
              :header-line-width 4
              :mode-line-width 6
              :tab-width 4
              :right-divider-width 1
              :scroll-bar-width 8
              :fringe-width 8)
           auto-dark-themes '((modus-vivendi-tinted) (modus-operandi-tinted)))
  (defun vlaci--load-theme-h ()
    (require-theme 'modus-themes)
    (setq modus-themes-italic-constructs t
          modus-themes-bold-constructs t
          modus-themes-prompts '(background)
          modus-themes-mixed-fonts nil
          modus-themes-org-blocks 'gray-background
          modus-themes-headings '((0 . (2.0))
                                  (1 . (rainbow background overline 1.5))
                                  (2 . (background overline 1.4))
                                  (3 . (background overline 1.3))
                                  (4 . (background overline 1.2))
                                  (5 . (overline 1.2))
                                  (t . (no-bold 1.1)))
          modus-themes-common-palette-overrides
          `(,@modus-themes-preset-overrides-faint
            (builtin magenta)
            (comment fg-dim)
            (constant magenta-cooler)
            (docstring magenta-faint)
            (docmarkup green-faint)
            (fnname magenta-warmer)
            (keyword cyan)
            (preprocessor cyan-cooler)
            (string red-cooler)
            (type magenta-cooler)
            (variable blue-warmer)
            (rx-construct magenta-warmer)
            (rx-backslash blue-cooler)))
    (load-theme 'modus-operandi-tinted :no-confirm)
    (doom-modeline-mode)
    (spacious-padding-mode)
    (auto-dark-mode))
  (:with-function vlaci--load-theme-h
    (:hook-into window-setup-hook)))
(setup (:package repeat-help)
  (:hook-into repeat-mode-hook)
  (:hook (defun vlaci/reset-repeat-echo-function-h ()
           (setq repeat-echo-function repeat-help--echo-function))))

(setup repeat
  (:hook-into on-first-input-hook))
(setup emacs
  (:option display-line-numbers-type 'relative
           display-line-numbers-width 3
           display-line-numbers-widen t
           split-width-threshold 170
           truncate-lines t
           window-combination-resize t))

(setup prog
  (:hook #'display-line-numbers-mode))
(setup (:package lin)
  (:with-mode lin-global-mode
    (:hook-into on-first-buffer-hook)))
(setup (:package once)
  (:option once-shorthand t)
  (:require once once-conditions))

(setup (:package once-setup)
  (:require once-setup))
(setup emacs
  (defun vl/welcome ()
    (with-current-buffer (get-buffer-create "*scratch*")
      (insert (format ";;
;; ██╗   ██╗██╗        ███████╗███╗   ███╗ █████╗  ██████╗███████╗
;; ██║   ██║██║        ██╔════╝████╗ ████║██╔══██╗██╔════╝██╔════╝
;; ╚██╗ ██╔╝██║        █████╗  ██╔████╔██║███████║██║     ███████╗
;;  ╚████╔╝ ██║        ██╔══╝  ██║╚██╔╝██║██╔══██║██║     ╚════██║
;;   ╚██╔╝  ██████╗    ███████╗██║ ╚═╝ ██║██║  ██║╚██████╗███████║
;;    ╚═╝   ╚═════╝    ╚══════╝╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝
;;
;;    Loading time : %s
;;    Features     : %s
"
                      (emacs-init-time)
                      (length features))))

    (message (emacs-init-time)))
  (:with-function vl/welcome
    (:hook-into after-init-hook)))
(setup vlaci-emacs
  (:global [remap keyboard-quit] #'vlaci-keyboard-quit-dwim))
(setup (:package nerd-icons))

(setup (:package nerd-icons-completion)
  (:with-function nerd-icons-completion-marginalia-setup
    (:hook-into marginalia-mode-hook)))

(setup (:package nerd-icons-corfu)
  (:with-feature corfu
    (:when-loaded
      (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))))

(setup (:package nerd-icons-dired)
  (:hook-into dired-mode-hook))
(setup (:package undo-fu)
  (:option undo-limit (* 80 1024 1024)
           undo-strong-limit (* 120 1024 1024)
           undo-outer-limit (* 360 1024 1024)))

(setup (:package undo-fu-session)
  (:with-mode undo-fu-session-global-mode
    (:hook-into on-first-buffer-hook)))

(setup (:package vundo)
  (:option vundo-compact-display t)
  (:bind [remap keyboard-quit] #'vundo-quit))
(with-eval-after-load 'meow
  (defun isearch-exit-at-once ()
    "Exit search normally without nonincremental search if no input is given."
    (interactive)
    (isearch-done)
    (isearch-clean-overlays))

  (define-key isearch-mode-map (kbd "<return>") 'isearch-exit-at-once)

(defvar meow-isearch-state-keymap
  (let ((keymap (make-keymap)))
    (suppress-keymap keymap t)
    (define-key keymap [remap kmacro-start-macro] #'meow-start-kmacro)
    (define-key keymap [remap kmacro-start-macro-or-insert-counter] #'meow-start-kmacro-or-insert-counter)
    (define-key keymap [remap kmacro-end-or-call-macro] #'meow-end-or-call-kmacro)
    (define-key keymap [remap kmacro-end-macro] #'meow-end-kmacro)
    keymap)
  "Keymap for Meow isearch state.")

(defface meow-isearch-cursor
  '((((class color) (background dark))
     (:inherit cursor))
    (((class color) (background light))
     (:inherit cursor)))
  "Convert state cursor."
  :group 'meow)

(meow-define-state isearch
  "Meow ISEARCH state minor mode."
  :lighter " [S]"
  :keymap meow-isearch-state-keymap
  :cursor meow-isearch-cursor)

(defun meow-isearch-define-key (&rest keybinds)
  (apply #'meow-define-keys 'isearch keybinds))

(defun meow-isearch-exit ()
  "Switch to NORMAL state."
  (interactive)
  (cond
   ((meow-keypad-mode-p)
    (meow--exit-keypad-state))
   ((and (meow-isearch-mode-p)
         (eq meow--beacon-defining-kbd-macro 'quick))
    (setq meow--beacon-defining-kbd-macro nil)
    (meow-beacon-isearch-exit))
   ((meow-isearch-mode-p)
    (when overwrite-mode
      (overwrite-mode -1))
    (isearch-done)
    (meow--switch-state 'normal))))

(defun meow-isearch ()
  "Move to the start of selection, switch to SEARCH state."
  (interactive)
  (if meow--temp-normal
      (progn
        (message "Quit temporary normal mode")
        (meow--switch-state 'motion))
    (meow--switch-state 'isearch)
    (isearch-forward))))
(setup (:package meow)
  (require 'meow)
  (:option meow-cheatsheet-layout meow-cheatsheet-layout-qwerty)
  (defun vl/embark-describe-meow-keypad()
    (interactive)
    (minibuffer-with-setup-hook
        (lambda ()
          (let ((pt (- (minibuffer-prompt-end) 2)))
            (overlay-put (make-overlay pt pt) 'before-string
                         (format " under SPC %s" (meow--keypad-format-keys)))))
      (embark-bindings-in-keymap (meow--keypad-get-keymap-for-describe))))
  (define-key meow-keypad-state-keymap (kbd "C-h") #'vl/embark-describe-meow-keypad)
  (meow-motion-define-key
   '("j" . meow-next)
   '("k" . meow-prev)
   '("<escape>" . ignore))
  (meow-leader-define-key
   ;; Use SPC (0-9) for digit arguments.
   '("1" . meow-digit-argument)
   '("2" . meow-digit-argument)
   '("3" . meow-digit-argument)
   '("4" . meow-digit-argument)
   '("5" . meow-digit-argument)
   '("6" . meow-digit-argument)
   '("7" . meow-digit-argument)
   '("8" . meow-digit-argument)
   '("9" . meow-digit-argument)
   '("0" . meow-digit-argument)
   '("/" . meow-keypad-describe-key)
   '("?" . meow-cheatsheet)
   ;; Avy integration
   '("j c" . meow-avy-goto-char)
   '("j j" . meow-avy-goto-char-2)
   '("j w" . meow-avy-goto-word-1)
   '("j l" . meow-avy-goto-line))
  (meow-normal-define-key
   '("0" . meow-expand-0)
   '("9" . meow-expand-9)
   '("8" . meow-expand-8)
   '("7" . meow-expand-7)
   '("6" . meow-expand-6)
   '("5" . meow-expand-5)
   '("4" . meow-expand-4)
   '("3" . meow-expand-3)
   '("2" . meow-expand-2)
   '("1" . meow-expand-1)
   '("-" . negative-argument)
   '(";" . meow-reverse)
   '("," . meow-inner-of-thing)
   '("." . meow-bounds-of-thing)
   '("[" . meow-beginning-of-thing)
   '("]" . meow-end-of-thing)
   '("a" . meow-append)
   '("A" . meow-open-below)
   '("b" . meow-back-word)
   '("B" . meow-back-symbol)
   '("c" . meow-change)
   '("d" . meow-delete)
   '("D" . meow-backward-delete)
   '("e" . meow-next-word)
   '("E" . meow-next-symbol)
   '("f" . meow-find)
   '("g" . meow-cancel-selection)
   '("G" . meow-grab)
   '("h" . meow-left)
   '("H" . meow-left-expand)
   '("i" . meow-insert)
   '("I" . meow-open-above)
   '("j" . meow-next)
   '("J" . meow-next-expand)
   '("k" . meow-prev)
   '("K" . meow-prev-expand)
   '("l" . meow-right)
   '("L" . meow-right-expand)
   '("m" . meow-join)
   '("n" . meow-search)
   '("o" . meow-block)
   '("O" . meow-to-block)
   '("p" . meow-yank)
   '("q" . meow-quit)
   '("Q" . meow-goto-line)
   '("r" . meow-replace)
   '("R" . meow-swap-grab)
   '("s" . meow-kill)
   '("S" . meow-isearch)
   '("t" . meow-till)
   '("u" . meow-undo)
   '("U" . meow-undo-in-selection)
   '("v" . meow-visit)
   '("w" . meow-mark-word)
   '("W" . meow-mark-symbol)
   '("x" . meow-line)
   '("X" . meow-goto-line)
   '("y" . meow-save)
   '("Y" . meow-sync-grab)
   '("z" . meow-pop-selection)
   '("%" . meow-vim-percent)
   '("'" . repeat)
   '("<escape>" . ignore))
  (meow-isearch-define-key
   '("g" . meow-isearch-exit)
   '("n" . isearch-repeat-forward)
   '("p" . isearch-repeat-backward)
   '("s" . isearch-forward)
   '("<backspace>" . isearch-delete-char)
   '("w" . isearch-yank-word-or-char)
   '("y" . isearch-yank-kill)
   '("%" . isearch-query-replace)
   '("l" . isearch-yank-line)
   '("SPC" . isearch-toggle-lax-whitespace)
   '("c" . isearch-toggle-case-fold)
   '("o" . isearch-occur)
   '("r" . isearch-toggle-regexp)
   '("[" . isearch-beginning-of-buffer)
   '("]" . isearch-end-of-buffer)
   '("." . isearch-forward-thing-at-point))
  (meow-global-mode))
(setup (:package combobulate))

(setup (:package ace-window)
  (:option aw-keys '(?a ?r ?s ?t ?g ?n ?e ?i ?o)
           aw-dispatch-always t)
  (:global (kbd "M-o") #'ace-window))

(setup (:package avy)
  (:option avy-keys '(?a ?r ?s ?t ?d ?h ?n ?e ?i ?o ?w ?f ?p ?l ?u ?y))

  ;; Meow-avy integration functions
  (defun meow-avy-goto-char (char &optional arg)
    "Jump to CHAR using avy, creating or extending selection."
    (interactive (list (read-char "Goto char: " t)
                       current-prefix-arg))
    (let ((original-point (point)))
      (avy-goto-char char arg)
      (when (/= original-point (point))
        (if (region-active-p)
            ;; Region is active, just move point to extend selection
            nil
          ;; No region, create one from original point to new point
          (push-mark original-point t t)))))

  (defun meow-avy-goto-char-2 (char1 char2 &optional arg)
    "Jump to CHAR1 CHAR2 using avy, creating or extending selection."
    (interactive (list (read-char "Goto char 1: " t)
                       (read-char "Goto char 2: " t)
                       current-prefix-arg))
    (let ((original-point (point)))
      (avy-goto-char-2 char1 char2 arg)
      (when (/= original-point (point))
        (if (region-active-p)
            ;; Region is active, just move point to extend selection
            nil
          ;; No region, create one from original point to new point
          (push-mark original-point t t)))))

  (defun meow-avy-goto-word-1 (char &optional arg)
    "Jump to word starting with CHAR using avy, creating or extending selection."
    (interactive (list (read-char "Goto word starting with: " t)
                       current-prefix-arg))
    (let ((original-point (point)))
      (avy-goto-word-1 char arg)
      (when (/= original-point (point))
        (if (region-active-p)
            ;; Region is active, just move point to extend selection
            nil
          ;; No region, create one from original point to new point
          (push-mark original-point t t)))))

  (defun meow-avy-goto-line (&optional arg)
    "Jump to line using avy, creating or extending selection."
    (interactive "P")
    (let ((original-point (point)))
      (avy-goto-line arg)
      (when (/= original-point (point))
        (if (region-active-p)
            ;; Region is active, just move point to extend selection
            nil
          ;; No region, create one from original point to new point
          (push-mark original-point t t))))))

(setup (:package treesit-jump))

(defun meow-vim-percent ()
  "Jump between matching parentheses like vim's % command.
- When on opening parenthesis, jump to closing parenthesis
- When on closing parenthesis, jump to opening parenthesis
- Otherwise, find nearest bracket in current containing block and jump to its match
- If no bracket found to the right, jump to the containing block's opening parenthesis"
  (interactive)
  (let ((char (char-after))
        (opening-chars "([{")
        (closing-chars ")]}")
        (all-brackets "()[]{}")
        (pairs '((?( . ?)) (?[ . ?]) (?{ . ?}))))
    (cond
     ;; Point is on an opening bracket
     ((and char (cl-position char opening-chars))
      (forward-sexp 1)
      (backward-char 1))

     ;; Point is on a closing bracket
     ((and char (cl-position char closing-chars))
      (forward-char 1)
      (backward-sexp 1))

     ;; Default case: find nearest bracket within current containing block
     (t
      (let ((found-pos nil)
            (found-char nil)
            (search-bound nil)
            (containing-open-pos nil))

        ;; Determine the search boundary by finding the containing block
        (save-excursion
          (condition-case nil
              (progn
                (up-list)
                (setq search-bound (point))
                ;; Also record the position of the containing opening bracket
                (backward-sexp 1)
                (setq containing-open-pos (point)))
            (error nil)))

        ;; Look forward for the nearest bracket within the containing block
        (save-excursion
          (while (and (not found-pos)
                      (< (point) (point-max))
                      (or (not search-bound) (< (point) search-bound)))
            (forward-char 1)
            (let ((c (char-after)))
              (when (and c (cl-position c all-brackets))
                (setq found-pos (point))
                (setq found-char c)))))

        (if found-pos
            ;; Found a bracket, jump to its match
            (progn
              (goto-char found-pos)
              (if (cl-position found-char opening-chars)
                  ;; Opening bracket: jump to closing
                  (progn
                    (forward-sexp 1)
                    (backward-char 1))
                ;; Closing bracket: jump to opening
                (progn
                  (forward-char 1)
                  (backward-sexp 1))))
          ;; No bracket found to the right, jump to containing opening bracket if available
          (if containing-open-pos
              (goto-char containing-open-pos)
            ;; No containing block either, do nothing
            (message "No matching parenthesis found"))))))))
(setup (:package vertico vertico-posframe)
  (:with-mode (vertico-mode vertico-multiform-mode)
    (:hook-into on-first-input-hook))
  (:with-map minibuffer-local-map
    (:bind [escape] #'keyboard-quit))
  (:option vertico-scroll-margin 0
           vertico-count 17
           vertico-resize t
           vertico-cycle t
           vertico-multiform-categories  '((t
                                            posframe
                                            (vertico-posframe-poshandler . posframe-poshandler-frame-top-center)
                                            (vertico-posframe-fallback-mode . vertico-buffer-mode)))
           vertico-posframe-width 100))

;; A few more useful configurations...
(setup emacs
  (:option
   ;; Support opening new minibuffers from inside existing minibuffers.
   enable-recursive-minibuffers t
   ;; Hide commands in M-x which do not work in the current mode.  Vertico
   ;; commands are hidden in normal buffers. This setting is useful beyond
   ;; Vertico.
   read-extended-command-predicate #'command-completion-default-include-p)
  ;; Add prompt indicator to `completing-read-multiple'.
  ;; We display [CRM<separator>], e.g., [CRM,] if the separator is a comma.
  (defun crm-indicator (args)
    (cons (format "[CRM%s] %s"
                  (replace-regexp-in-string
                   "\\`\\[.*?]\\*\\|\\[.*?]\\*\\'" ""
                   crm-separator)
                  (car args))
          (cdr args)))
  (advice-add #'completing-read-multiple :filter-args #'crm-indicator)

  ;; Do not allow the cursor in the minibuffer prompt
  (setq minibuffer-prompt-properties
        '(read-only t cursor-intangible t face minibuffer-prompt))
  (add-hook 'minibuffer-setup-hook #'cursor-intangible-mode))
(setup (:package orderless)
  (defun vl/orderless--consult-suffix ()
    "Regexp which matches the end of string with Consult tofu support."
    (if (and (boundp 'consult--tofu-char) (boundp 'consult--tofu-range))
        (format "[%c-%c]*$"
                consult--tofu-char
                (+ consult--tofu-char consult--tofu-range -1))
      "$"))

  ;; Recognizes the following patterns:
  ;; * .ext (file extension)
  ;; * regexp$ (regexp matching at end)
  (defun vl/orderless-consult-dispatch (word _index _total)
    (cond
     ;; Ensure that $ works with Consult commands, which add disambiguation suffixes
     ((string-suffix-p "$" word)
      `(orderless-regexp . ,(concat (substring word 0 -1) (vl/orderless--consult-suffix))))
     ;; File extensions
     ((and (or minibuffer-completing-file-name
               (derived-mode-p 'eshell-mode))
           (string-match-p "\\`\\.." word))
      `(orderless-regexp . ,(concat "\\." (substring word 1) (vl/orderless--consult-suffix))))))

  (:once 'on-first-input-hook
         (:require orderless)
         ;; Define orderless style with initialism by default
         (orderless-define-completion-style vl/orderless-with-initialism
           (orderless-matching-styles '(orderless-initialism orderless-literal orderless-regexp))))

  ;; Certain dynamic completion tables (completion-table-dynamic) do not work
  ;; properly with orderless. One can add basic as a fallback.  Basic will only
  ;; be used when orderless fails, which happens only for these special
  ;; tables. Also note that you may want to configure special styles for special
  ;; completion categories, e.g., partial-completion for files.
  (:option completion-styles '(orderless basic)
           completion-category-defaults nil
        ;;; Enable partial-completion for files.
        ;;; Either give orderless precedence or partial-completion.
        ;;; Note that completion-category-overrides is not really an override,
        ;;; but rather prepended to the default completion-styles.
           ;; completion-category-overrides '((file (styles orderless partial-completion))) ;; orderless is tried first
           completion-category-overrides '((file (styles partial-completion)) ;; partial-completion is tried first
                                           ;; enable initialism by default for symbols
                                           (command (styles vl/orderless-with-initialism))
                                           (variable (styles vl/orderless-with-initialism))
                                           (symbol (styles vl/orderless-with-initialism)))
           orderless-component-separator #'orderless-escapable-split-on-space ;; allow escaping space with backslash!
           orderless-style-dispatchers (list #'vl/orderless-consult-dispatch
                                             #'orderless-affix-dispatch)))
(setup (:package marginalia)
  (:hook-into after-init-hook)
  (:with-map minibuffer-local-map
    (:bind "M-A" marginalia-cycle)))
(setup (:package consult)
  (:global ;; C-c bindings in `mode-specific-map'
   "C-c M-x" consult-mode-command
   "C-c h" consult-history
   "C-c k" consult-kmacro
   "C-c m" consult-man
   "C-c i" consult-info
   [remap Info-search] #'consult-info
   ;; C-x bindings in `ctl-x-map'
   "C-x M-:" consult-complex-command     ;; orig. repeat-complex-command
   "C-x b" consult-buffer                ;; orig. switch-to-buffer
   "C-x 4 b" consult-buffer-other-window ;; orig. switch-to-buffer-other-window
   "C-x 5 b" consult-buffer-other-frame  ;; orig. switch-to-buffer-other-frame
   "C-x t b" consult-buffer-other-tab    ;; orig. switch-to-buffer-other-tab
   "C-x r b" consult-bookmark            ;; orig. bookmark-jump
   "C-x p b" consult-project-buffer      ;; orig. project-switch-to-buffer
   ;; Custom M-# bindings for fast register access
   "M-#" consult-register-load
   "M-'" consult-register-store          ;; orig. abbrev-prefix-mark (unrelated
   "C-M-#" consult-register
   ;; Other custom bindings
   "M-y" consult-yank-pop                ;; orig. yank-pop
   ;; M-g bindings in `goto-map'
   "M-g e" consult-compile-error
   "M-g f" consult-flymake               ;; Alternative: consult-flycheck
   "M-g g" consult-goto-line             ;; orig. goto-line
   "M-g M-g" consult-goto-line           ;; orig. goto-line
   "M-g o" consult-outline               ;; Alternative: consult-org-heading
   "M-g m" consult-mark
   "M-g k" consult-global-mark
   "M-g i" consult-imenu
   "M-g I" consult-imenu-multi
   ;; M-s bindings in `search-map'
   "M-s d" consult-fd                  ;; Alternative: consult-find
   "M-s c" consult-locate
   "M-s g" consult-grep
   "M-s G" consult-git-grep
   "M-s r" consult-ripgrep
   "M-s l" consult-line
   "M-s L" consult-line-multi
   "M-s k" consult-keep-lines
   "M-s u" consult-focus-lines
   ;; Isearch integration
   "M-s e" consult-isearch-history)
  (:with-map isearch-mode-map
    (:bind
     "M-e" consult-isearch-history         ;; orig. isearch-edit-string
     "M-s e" consult-isearch-history       ;; orig. isearch-edit-string
     "M-s l" consult-line                  ;; needed by consult-line to detect isearch
     "M-s L" consult-line-multi))            ;; needed by consult-line to detect isearch
  ;; Minibuffer history
  (:with-map minibuffer-local-map
    (:bind
     "M-s" consult-history                 ;; orig. next-matching-history-element
     "M-r" consult-history))                ;; orig. previous-matching-history-element

  ;; Enable automatic preview at point in the *Completions* buffer. This is
  ;; relevant when you use the default completion UI.
  (:with-mode consult-preview-at-point-mode
    (:hook-into completion-list-mode))

  ;; Tweak the register preview for `consult-register-load',
  ;; `consult-register-store' and the built-in commands.  This improves the
  ;; register formatting, adds thin separator lines, register sorting and hides
  ;; the window mode line.
  (advice-add #'register-preview :override #'consult-register-window)
  (setq register-preview-delay 0.5)

  ;; Use Consult to select xref locations with preview
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref)

  (:when-loaded
    ;; Optionally configure preview. The default value
    ;; is 'any, such that any key triggers the preview.
    ;; (setq consult-preview-key 'any)
    ;; (setq consult-preview-key "M-.")
    ;; (setq consult-preview-key '("S-<down>" "S-<up>"))
    ;; For some commands and buffer sources it is useful to configure the
    ;; :preview-key on a per-command basis using the `consult-customize' macro.
    (consult-customize
     consult-theme :preview-key '(:debounce 0.2 any)
     consult-ripgrep consult-git-grep consult-grep
     consult-bookmark consult-recent-file consult-xref
     consult--source-bookmark consult--source-file-register
     consult--source-recent-file consult--source-project-recent-file
     ;; :preview-key "M-."
     :preview-key '(:debounce 0.4 any))

    ;; Optionally configure the narrowing key.
    ;; Both < and C-+ work reasonably well.
    (setq consult-narrow-key "<") ;; "C-+"

    ;; Optionally make narrowing help available in the minibuffer.
    ;; You may want to use `embark-prefix-help-command' or which-key instead.
    ;; (keymap-set consult-narrow-map (concat consult-narrow-key " ?") #'consult-narrow-help)
    ))
(setup (:package corfu)
  (:with-mode global-corfu-mode
    (:hook-into on-first-input-hook))
  (:with-mode corfu-popupinfo-mode
    (:hook-into on-first-input-hook)))

(setup emacs
  ;; TAB cycle if there are only few candidates
  ;; (completion-cycle-threshold 3)

  ;; Enable indentation+completion using the TAB key.
  ;; `completion-at-point' is often bound to M-TAB.
  (:option tab-always-indent 'complete
           ;; Emacs 30 and newer: Disable Ispell completion function.
           ;; Try `cape-dict' as an alternative.
           text-mode-ispell-word-completion nil
           ;; Hide commands in M-x which do not apply to the current mode.  Corfu
           ;; commands are hidden, since they are not used via M-x. This setting is
           ;; useful beyond Corfu.
           read-extended-command-predicate #'command-completion-default-include-p))

;; Use Dabbrev with Corfu!
(setup dabbrev
  ;; Swap M-/ and C-M-/
  (:global "M-/" dabbrev-completion
           "C-M-/" dabbrev-expand)
  (:when-loaded
    (add-to-list 'dabbrev-ignored-buffer-regexps "\\` ")
    ;; Since 29.1, use `dabbrev-ignored-buffer-regexps' on older.
    (add-to-list 'dabbrev-ignored-buffer-modes 'doc-view-mode)
    (add-to-list 'dabbrev-ignored-buffer-modes 'pdf-view-mode)
    (add-to-list 'dabbrev-ignored-buffer-modes 'tags-table-mode)))
(setup (:package embark)
  (:option embark-indicators
           '(embark-minimal-indicator  ; default is embark-mixed-indicator
             embark-highlight-indicator
             embark-isearch-highlight-indicator))

  (:with-feature vertico
    (:when-loaded
      (add-to-list 'vertico-multiform-categories '(embark-keybinding grid))))

  (setq prefix-help-command #'embark-prefix-help-command)
  (:global [remap describe-bindings] #'embark-bindings
           "C-;" #'embark-act
           "M-." #'embark-dwim)
  (:with-map minibuffer-local-map
    (:bind "C-;" #'embark-act)))
(setup-define :autoload
  (lambda (func)
    (let ((fn (if (memq (car-safe func) '(quote function))
                  (cadr func)
                func)))
      `(unless (fboundp (quote ,fn))
         (autoload (function ,fn) ,(symbol-name (setup-get 'feature)) nil t))))
  :documentation "Autoload COMMAND if not already bound."
  :repeatable t
  :signature '(FUNC ...))

(setup (:package treesit-auto)
  (:autoload 'global-treesit-auto-mode)
  (:with-mode global-treesit-auto-mode
    (:hook-into after-init-hook))
  (:when-loaded
    (delete 'dockerfile treesit-auto-langs)
    (delete 'rust treesit-auto-langs)
    (treesit-auto-add-to-auto-mode-alist 'all)))
(setup (:package lsp-mode)
  (:option lsp-use-plist t
           lsp-keymap-prefix "C-c l"
           lsp-diagnostics-provider :flymake
           lsp-completion-provider :none
           lsp-headerline-breadcrumb-enable nil
           lsp-inlay-hint-enable t)
  (:bind
   (kbd "C-.") #'lsp-execute-code-action)
  (:when-loaded
    (add-to-list 'lsp-file-watch-ignored-directories "[/\\\\]\\.jj\\'")))

(setup (:package lsp-ui)
  (:option lsp-ui-doc-position 'top
           lsp-ui-doc-show-with-cursor t
           lsp-ui-doc-show-with-mouse nil
           lsp-ui-sideline-enable nil)
  (:with-map lsp-ui-mode-map
    (:bind
     [remap xref-find-definitions] #'lsp-ui-peek-find-definitions
     [remap xref-find-references] #'lsp-ui-peek-find-references)))

(setup (:package yasnippet)
  (:with-mode yas-global-mode
    (:hook-into on-first-input-hook)))

(setup (:package consult-lsp)
  (:bind [remap xref-find-apropos] #'consult-lsp-symbols))

(setup-define :lsp
  (lambda ()
    `(:hook lsp-deferred))
  :documentation "Configure LSP")

(defun my-lsp-booster-bytecode-maybe (str-or-current-buffer)
  (let* ((char (if (stringp str-or-current-buffer)
                   (seq-elt str-or-current-buffer 0)
                 (following-char))))
    (when (equal ?# char)
      (let ((bytecode (read str-or-current-buffer)))
        (when (byte-code-function-p bytecode)
          (funcall bytecode))))))

(defvar my-lsp-booster-json-enable-code-execution nil)
(defun my-lsp--create-filter-function--json-code-a (oldfun &rest args)
  (let* ((filter-fn (apply oldfun args)))
    (lambda (&rest filter-fn-args)
      (dlet ((my-lsp-booster-json-enable-code-execution t))
        (apply filter-fn filter-fn-args)))))
(defun my-json-parse-buffer-bytecode-maybe-a (oldfun &rest args)
  (or (and my-lsp-booster-json-enable-code-execution
           (my-lsp-booster-bytecode-maybe (current-buffer)))
      (apply oldfun args)))

(advice-add #'lsp--create-filter-function :around #'my-lsp--create-filter-function--json-code-a)
(advice-add #'json-read :around #'my-json-parse-buffer-bytecode-maybe-a)
(advice-add #'json-parse-buffer :around #'my-json-parse-buffer-bytecode-maybe-a)

(defun lsp-booster--advice-final-command (old-fn cmd &optional test?)
  "Prepend emacs-lsp-booster command to lsp CMD."
  (let ((orig-result (funcall old-fn cmd test?)))
    (if (and (not test?)                             ;; for check lsp-server-present?
             (not (file-remote-p default-directory)) ;; see lsp-resolve-final-command, it would add extra shell wrapper
             lsp-use-plists
             (not (functionp 'json-rpc-connection))  ;; native json-rpc
             (executable-find "emacs-lsp-booster"))
        (progn
          (when-let ((command-from-exec-path (executable-find (car orig-result))))  ;; resolve command from exec-path (in case not found in $PATH)
            (setcar orig-result command-from-exec-path))
          (message "Using emacs-lsp-booster for %s!" orig-result)
          (cons "emacs-lsp-booster" orig-result))
      orig-result)))
(advice-add 'lsp-resolve-final-command :around #'lsp-booster--advice-final-command)
(setup dired
  (:option dired-listing-switches "-Alh --group-directories-first --time-style=iso"
           dired-kill-when-opening-new-dired-buffer t)
  (:global "M-i" vl/window-dired-vc-root-left)
  (:bind "C-<return>" vl/window-dired-open-directory)

  (defun vl/window-dired-vc-root-left (&optional directory-path)
    "Creates *Dired-Side* like an IDE side explorer"
    (interactive)
    (add-hook 'dired-mode-hook 'dired-hide-details-mode)

    (let ((dir (if directory-path
                   (dired-noselect directory-path)
                 (if (eq (vc-root-dir) nil)
                     (dired-noselect default-directory)
                   (dired-noselect (vc-root-dir))))))

      (display-buffer-in-side-window
       dir `((side . left)
             (slot . 0)
             (window-width . 30)
             (window-parameters . ((no-other-window . t)
                                   (no-delete-other-windows . t)
                                   (mode-line-format . (" "
                                                        "%b"))))))
      (with-current-buffer dir
        (let ((window (get-buffer-window dir)))
          (when window
            (select-window window)
            (rename-buffer "*Dired-Side*"))))))

  (defun vl/window-dired-open-directory ()
    "Open the current directory in *Dired-Side* side window."
    (interactive)
    (vl/window-dired-vc-root-left (dired-get-file-for-visit))))
(setup (:package dirvish)
  (:when-loaded (dirvish-override-dired-mode)))
(setup (:package polymode))

(add-to-list 'auto-mode-alist '("\\.nix" . ordenada-nix-polymode))

(setup (:package nix-ts-mode)
  (define-hostmode poly-nix-hostmode
    :mode 'nix-mode)
  (define-auto-innermode poly-nix-dynamic-innermode
                         :head-matcher (rx "#" blank (+ (any "a-z" "-")) (+ (any "\n" blank)) "''\n")
                         :tail-matcher (rx bol (+ blank) "'';")
                         :mode-matcher (cons (rx "#" blank (group (+ (any "a-z" "-"))) (* anychar)) 1)
                         :head-mode 'host
                         :tail-mode 'host)

  (define-innermode poly-nix-interpolation-innermode
                    :mode 'nix-mode
                    :head-matcher (rx "${")
                    :tail-matcher #'pm-forward-sexp-tail-matcher
                    :head-mode 'body
                    :tail-mode 'body
                    :can-nest t)

  (define-polymode poly-nix-mode
                   :hostmode 'poly-nix-hostmode
                   :innermodes '(poly-nix-dynamic-innermode))

  (:with-mode poly-nix-mode
    (:file-match "\\.nix\\'"))
  (defalias 'nix-mode 'nix-ts-mode) ;; For org-mode code blocks to work
  (:lsp))

(setup (:package rust-mode)
  (:lsp)
  (:option rust-mode-treesitter-derive t)
  (:hook (defun vl/remove-rust-ts-flymake-diagnostic-function-h()
           (remove-hook 'flymake-diagnostic-functions #'rust-ts-flymake 'local))))

(setup python-ts-mode
  (:lsp))

(setup c-or-c++-ts-mode
  (:lsp))

(setup (:package just-ts-mode)
  (define-hostmode poly-just-hostmode
    :mode 'just-ts-mode)

  (defun vlaci/poly-get-innermode-for-exe (re)
    (re-search-forward re (point-at-eol) t)
    (let ((exe (match-string-no-properties 1)))
      (cond ((equal exe "emacs") "emacs-lisp")
            (t exe))))

  (define-auto-innermode poly-just-innermode
                         :head-matcher (rx bol (+ (any blank)) "#!" (+ (any "a-z0-9_/ -")) "\n")
                         :tail-matcher #'pm-same-indent-tail-matcher
                         :mode-matcher (apply-partially #'vlaci/poly-get-innermode-for-exe (rx (+? anychar) "bin/env " (? "-S ") (group (+ (any "a-z-"))) (* anychar)))
                         :head-mode 'host
                         :tail-mode 'host)

  (define-auto-innermode poly-just-script-innermode
                         :head-matcher (rx bol "[script('" (+? anychar) ":" (* (not "\n")) "\n")
                         :tail-matcher #'pm-same-indent-tail-matcher
                         :mode-matcher (apply-partially #'vlaci/poly-get-innermode-for-exe (rx bol "[script('" (group (+ (not "'"))) (* anychar)))
                         :head-mode 'host
                         :tail-mode 'host)

  (define-polymode poly-just-mode
                   :hostmode 'poly-just-hostmode
                   :innermodes '(poly-just-innermode poly-just-script-innermode))

  (:with-mode poly-just-mode
    (:file-match (rx (or "justfile" ".just") string-end))))

(setup (:package markdown-mode))
(setup (:package envrc)
  (:with-mode envrc-global-mode
    (:hook-into on-first-file-hook))

  (defun vl/direnv-init-global-mode-earlier-h ()
    (let ((fn #'envrc-global-mode-enable-in-buffer))
      (if (not envrc-global-mode)
          (remove-hook 'change-major-mode-after-body-hook fn)
        (remove-hook 'after-change-major-mode-hook fn)
        (add-hook 'change-major-mode-after-body-hook fn 100))))
  (add-hook 'envrc-global-mode-hook #'vl/direnv-init-global-mode-earlier-h)

  (defvar vl/orig-exec-path exec-path)
  (define-advice envrc--update (:around (fn &rest args) vl/envrc--debounce-add-extra-path-a)
    "Update only on non internal envrc related buffers keeping original path entries as well"
    (when (not (string-prefix-p "*envrc" (buffer-name)))
      (apply fn args)
      (setq-local exec-path (append exec-path vl/orig-exec-path)))))
(setup (:package jinx)
  (:with-mode global-jinx-mode
    (:hook-into on-first-buffer-hook))
  (:option jinx-languages "en_US hu_HU")
  (:when-loaded
    (add-to-list 'vertico-multiform-categories
                 '(jinx grid (vertico-grid-annotate . 20)))))
(setup (:package magit)
  (:option magit-prefer-remote-upstream t
           magit-save-repository-buffers nil
           magit-diff-refine-hunk t
           magit-define-global-key-bindings 'recommended
           git-commit-major-mode 'markdown-mode)

  (:when-loaded
    (transient-append-suffix 'magit-pull "-r"
      '("-a" "Autostash" "--autostash"))
    (transient-append-suffix 'magit-commit "-n"
      '("-s" "Dont show status" "--no-status"))
    (add-to-list 'font-lock-ignore '(git-commit-mode markdown-fontify-headings)))

  (:with-feature magit-commit
    (:when-loaded
      (transient-replace-suffix 'magit-commit 'magit-commit-autofixup
        '("x" "Absorb changes" magit-commit-absorb))
      (setq transient-levels '((magit-commit (magit-commit-absorb . 1))))))

  (:with-feature project
    (:when-loaded
      (define-key project-prefix-map "m" #'magit-project-status)
      (add-to-list 'project-switch-commands '(magit-project-status "Magit") t)))

  (:with-feature smerge-mode
    (:when-loaded
      (map-keymap
       (lambda (_key cmd)
         (when (symbolp cmd)
           (put cmd 'repeat-map 'smerge-basic-map)))
       smerge-basic-map))))
(setup ediff
  (:option ediff-keep-variants nil
           ediff-split-window-function #'split-window-horizontally
           ediff-window-setup-function #'ediff-setup-windows-plain))
(setup emacs
  (:option indent-tabs-mode nil
           mouse-yank-at-point t)) ;; paste at keyboard cursor instead of mouse pointer location
(setup (:package apheleia)
  (:with-mode apheleia-global-mode
    (:hook-into on-first-file-hook))
  (:when-loaded
    ;; do not use apheleia-npx wrapper
    (dolist (key (list
                  'prettier
                  'prettier-css
                  'prettier-html
                  'prettier-graphql
                  'prettier-javascript
                  'prettier-json
                  'prettier-markdown
                  'prettier-ruby
                  'prettier-scss
                  'prettier-scsss
                  'prettier-svelte
                  'pretter-typescript
                  'prettier-yaml))
      (setf (alist-get key apheleia-formatters) (cdr (alist-get key apheleia-formatters))))
    (setf (alist-get 'ruff-check apheleia-formatters) (list "ruff" "check" "--fix" "--exit-zero" "-"))
    (setf (alist-get 'ruff-format apheleia-formatters) (list "ruff" "format" "-"))
    (setf (alist-get 'rustfmt apheleia-formatters) (list "rustfmt" "--quiet" "--emit" "stdout" "--edition" "2024"))
    (setf (alist-get 'python-mode apheleia-mode-alist) '(ruff-check ruff-format))
    (setf (alist-get 'python-ts-mode apheleia-mode-alist) '(ruff-check ruff-format))))
(setup (:package auth-source-1password)
  (:with-function auth-source-1password-enable
    (:hook-into on-first-buffer-hook))
  (:option auth-source-1password-vault "Emacs"))
(setup (:package chatgpt-shell)
  (:option
   chatgpt-shell-perplexity-api-key
   (lambda() (auth-source-pick-first-password :host "Perplexity" :user "credential"))))

(setup (:package gptel)
  (:when-loaded
    (:option gptel-model   'sonar
             gptel-backend (gptel-make-perplexity "Perplexity"
                                                  :key (lambda() (auth-source-pick-first-password :host "Perplexity" :user "credential"))
                                                  :stream t))))
(setup project
  (define-advice project-current (:around (fun &rest args) vl/project-current-per-frame-a)
    (let ((proj (frame-parameter nil 'vl/project-current)))
      (unless proj
        (setq proj (apply fun args))
        (modify-frame-parameters nil `((vl/project-current . ,proj))))
      proj))

  (define-advice project-switch-project (:before (&rest _) vl/project-switch-project-per-frame-a)
    (modify-frame-parameters nil '((vl/project-current . nil)))))
(setup (:package eat)
  (add-hook 'eshell-load-hook #'eat-eshell-mode))
