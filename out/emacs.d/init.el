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
(setup eshell
  (:option eshell-aliases-file (vlaci/in-init-directory "eshell/alias")
           eshell-visual-options '("git" "--help" "--paginate")
           eshell-visual-subcommands '("git" "log" "diff" "show")
           eshell-prompt-function #'vl/esh-prompt-func)
  (:when-loaded
    (add-to-list 'eshell-modules-list 'eshell-smart)))
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
             '(:foreground "MediumPurple4" :bold ultra-bold :underline t))

(vl/esh-section esh-git
             (nerd-icons-faicon "nf-fa-git")
             (magit-get-current-branch)
             '(:foreground "green"))

(vl/esh-section esh-python
             (nerd-icons-faicon "nf-fa-python")
             pyvenv-virtual-env-name)

(vl/esh-section esh-exit-code
             (nerd-icons-faicon "nf-fa-warning")
             (let ((rc eshell-last-command-status))
               (when (not (eq rc 0)) (number-to-string rc)))
             '(:foreground "dark red"))

;; Choose which eshell-funcs to enable
(setq vl/eshell-funcs (list esh-dir esh-git esh-exit-code))

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
  (:hook-into on-first-input-hook)
  (:with-feature embark
    (:when-loaded
      (defun embark-which-key-indicator ()
        "An embark indicator that displays keymaps using which-key.
The which-key help message will show the type and value of the
current target followed by an ellipsis if there are further
targets."
        (lambda (&optional keymap targets prefix)
          (if (null keymap)
              (which-key--hide-popup-ignore-command)
            (which-key--show-keymap
             (if (eq (plist-get (car targets) :type) 'embark-become)
                 "Become"
               (format "Act on %s '%s'%s"
                       (plist-get (car targets) :type)
                       (embark--truncate-target (plist-get (car targets) :target))
                       (if (cdr targets) "…" "")))
             (if prefix
                 (pcase (lookup-key keymap prefix 'accept-default)
                   ((and (pred keymapp) km) km)
                   (_ (key-binding prefix 'accept-default)))
               keymap)
             nil nil t (lambda (binding)
                         (not (string-suffix-p "-argument" (cdr binding))))))))

      (setq embark-indicators
            '(embark-which-key-indicator
              embark-highlight-indicator
              embark-isearch-highlight-indicator))

      (defun embark-hide-which-key-indicator (fn &rest args)
        "Hide the which-key indicator immediately when using the completing-read prompter."
        (which-key--hide-popup-ignore-command)
        (let ((embark-indicators
               (remq #'embark-which-key-indicator embark-indicators)))
          (apply fn args)))

      (advice-add #'embark-completing-read-prompter
                  :around #'embark-hide-which-key-indicator))))
(setup (:package on)
  (:require on))
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
  (:option repeat-help-popup-type 'which-key)
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
(setup (:package evil evil-collection devil)
  (:hook-into after-init-hook)
  (:option
   ;; Will be handled by evil-collections
   evil-want-keybinding nil
   ;; Make `Y` behave like `D`
   evil-want-Y-yank-to-eol t
   ;; Do not extend visual selection to whole lines for ex commands
   evil-ex-visual-char-range t
   ;; `*` and `#` selects symbols instead of words
   evil-symbol-word-search t
   ;; Only highlight in the current window
   evil-ex-interactive-search-highlight 'selected-window
   ;; Use vim-emulated search implementation
   evil-search-module 'evil-search
   ;; Do not spam with error messages
   evil-kbd-macro-suppress-motion-error t
   evil-undo-system 'undo-fu
   evil-visual-state-cursor 'hollow
   evil-visual-update-x-selection-p nil
   evil-move-cursor-back nil
   evil-move-beyond-eol t)
  (:also-load evil-collection)
  (:also-load devil)
  (:when-loaded
    ;;; delay loading evil-collection modules until they are needed
    (dolist (mode evil-collection-mode-list)
      (dolist (req (or (cdr-safe mode) (list mode)))
        (with-eval-after-load req
          (message "Loading evil-collection for mode %s" req)
          (evil-collection-init (list mode)))))

    (evil-collection-init
     '(help
       (buff-menu "buff-menu")
       calc
       image
       elisp-mode
       replace
       (indent "indent")
       (process-menu simple)
       shortdoc
       tabulated-list
       tab-bar))

    (evil-global-set-key 'normal (kbd "SPC") #'devil)
    (evil-global-set-key 'insert [remap evil-complete-next] #'complete-symbol)
    (evil-global-set-key 'motion (kbd ",") nil)
    (:with-feature devil
      (:when-loaded
        (devil-set-key (kbd "SPC"))))))


(setup-define :ebind
  (lambda (key command)
    `(evil-define-key ,(setup-get 'evil-state) ,(setup-get 'map) ,key ,command))
  :documentation "Bind KEY to COMMAND for the given EVIL state"
  :repeatable t
  :indent 0)

(setup-define :with-state
  (lambda (state &rest body)
    (let (bodies)
      (push (setup-bind body (evil-state state)) bodies)
      (macroexp-progn (nreverse bodies))))
  :documentation "Use STATE for binding keys"
  :indent 1)

(setup-define :evil
  (lambda (&rest body)
    (require 'evil)
    `(:with-state 'motion ,@body))
  :documentation "Bind KEYs to COMMANDs for the given EVIL state"
  :ensure '(nil &rest kbd func)
  :indent 0)

(setup (:package avy)
  (:option avy-keys '(?a ?r ?s ?t ?d ?h ?n ?e ?i ?o ?w ?f ?p ?l ?u ?y))

  (:evil
   (defvar avy-all-windows)
   (defvar swiper-goto-start-of-match)
   (evil-define-motion vlaci/goto-char-timer-or-swiper-isearch (_count)
     :type inclusive
     :jump t
     :repat abort
     (evil-without-repeat
       (evil-enclose-avy-for-motion
         (when (eq (avy-goto-char-timer) t)
           (let ((swiper-goto-start-of-match (not evil-this-operator)))
             (swiper-isearch avy-text))))))

   (advice-add 'avy-resume :after #'evil-normal-state)
   (:with-map 'global
     (:with-state 'normal
       (:ebind
         "r" nil))
     (:ebind
       "r/" #'vlaci/goto-char-timer-or-swiper-isearch))))

(setup (:package evil-ts-obj)
  (:hook-into
   bash-ts-mode-hook
   c-ts-mode-hook
   c++-ts-mode-hook
   nix-ts-mode-hook
   python-ts-mode-hook
   rust-ts-mode-hook
   yaml-ts-mode-hook)
  (:when-loaded
    ;; Free-up M-s prefix
    (evil-define-key 'normal 'evil-ts-obj-mode
      (kbd "M-s") nil
      (kbd "M-S") nil
      (kbd "M-i") #'evil-ts-obj-inject-down-dwim
      (kbd "M-I") #'evil-ts-obj-inject-up-dwim)))

(setup (:package treesit-jump)
  (:evil
   (:with-map 'global
     (:ebind "zj" #'treesit-jump-jump))))

(setup (:package evil-snipe)
  (:hook-into on-first-input-hook)
  (:with-mode evil-snipe-override-mode
    (:hook-into on-first-input-hook))
  (:option evil-snipe-override-evil-repeat-keys nil
           evil-snipe-scope 'visible
           evil-snipe-repeat-scope 'whole-visible
           evil-snipe-smart-case t
           evil-snipe-tab-increment t))
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
    (treesit-auto-add-to-auto-mode-alist 'all)))
(setup (:package eglot-booster)
  (:option eglot-booster-io-only t))

(setup eglot
  (:also-load eglot-booster)
  (:also-load eglot-x)
  (:when-loaded
    (setq completion-category-defaults nil))
  (advice-add 'eglot-completion-at-point :around #'cape-wrap-buster)
  (defun vlaci/eglot-capf ()
    (setq-local completion-at-point-functions
                (list (cape-capf-super
                       #'eglot-completion-at-point
                       #'cape-dabbrev)))
    (add-hook 'completion-at-point-functions #'cape-file))
  (:with-function vlaci/eglot-capf
    (:hook-into eglot-managed-mode-hook))
  (:evil
    (:ebind
      ",r" #'eglot-rename
      ",a" #'eglot-code-actions)
    (:with-state 'insert
      (:ebind
        (kbd "C-.") #'eglot-code-actions))))

(setup (:package eglot-x)
  (:when-loaded
    (eglot-x-setup)))

(setup-define :lsp
  (lambda ()
    `(:hook eglot-ensure))
  :documentation "Configure LSP")

(setup (:package dape)
  (:option
   dape-repl-use-shorthand t))

(setup (:package sideline sideline-flymake sideline-eglot)
  (:option sideline-backends-right '(sideline-flymake sideline-eglot))
  (:hook-into prog-mode-hook))
(setup dired
  (:option dired-listing-switches "-al --group-directories-first"
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

(setup (:package rust-ts-mode)
  (:lsp))

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
  (:evil
    (:ebind
      [remap evil-next-flyspell-error] #'jinx-next
      [remap evil-prev-flyspell-error] #'jinx-previous
      [remap ispell-word] #'jinx-correct))
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
