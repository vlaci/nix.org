;; -*- lexical-binding: t; -*-

;; Use font from Gsettings from /org/gnome/desktop/interface/
;; The keys read are:
;;  - ‘font-name’
;;  - 'monospace-font-name’
(setq font-use-system-font t)
(set-face-attribute 'fixed-pitch nil :height 1.0)
(set-face-attribute 'variable-pitch nil :height 1.0)

(setq use-package-always-defer t)

(use-package emacs
  :config
  (defvar user-cache-directory "~/.cache/emacs/"
  "Location where files created by emacs are placed.")

  (defun vlaci/in-cache-directory (name)
    "Return NAME appended to cache directory"
    (expand-file-name name user-cache-directory))

  (setq custom-file (vlaci/in-cache-directory "custom.el"))
  (load custom-file :no-error-if-file-is-missing)

  (setq auto-save-interval 2400)
  (setq auto-save-timeout 300)
  (setq auto-save-list-file-prefix
        (vlaci/in-cache-directory "auto-save-list/.saves-"))
  (setq backup-directory-alist
        `(("." . ,(vlaci/in-cache-directory "backup")))
        backup-by-copying t
        version-control t
        delete-old-versions t
        kept-new-versions 10
        kept-old-versions 5))

(use-package recentf
  :config
  (setq recentf-save-file (vlaci/in-cache-directory "recentf")
        recentf-max-saved-items 200
        recentf-auto-cleanup 300)
  (define-advice recentf-cleanup (:around (fun) silently)
    (let ((inhibit-message t)
          (message-log-max nil))
      (funcall fun)))
  (recentf-mode 1))

(use-package savehist
  :defer 2
  :hook (after-init . savehist-mode)
  :config
  (setq savehist-file (vlaci/in-cache-directory "savehist"))
  (setq history-length 1000)
  (setq history-delete-duplicates t)
  (setq savehist-save-minibuffer-history t))

(use-package org
  :init
  (setq org-startup-indented t
        org-edit-src-content-indentation 0))

(use-package org-modern
  :hook (org-mode . org-modern-mode))
(use-package on
  :demand t)
(use-package edwina
  :disabled
  :hook (after-init . edwina-mode)
  :config
  (setq display-buffer-base-action '(display-buffer-below-selected))
  (edwina-setup-dwm-keys))
(use-package sticky-scroll-mode
  :hook prog-mode)
(use-package spacious-padding
  :defer t)

(use-package doom-modeline
  :defer t)

(add-hook 'window-setup-hook
          (defun vlaci--load-theme-h ()
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
                  '((builtin magenta)
                    ;;(comment red-faint)
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
            (spacious-padding-mode)
            (doom-modeline-mode)) -100)
(use-package project
  :init
  (setq project-list-file (vlaci/in-cache-directory "project-list.ed")))
(use-package vlaci-emacs
  :bind (([remap keyboard-quit] . vlaci-keyboard-quit-dwim)))
(use-package nerd-icons
  :ensure t)

(use-package nerd-icons-completion
  :ensure t
  :after marginalia
  :config
  (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup))

(use-package nerd-icons-corfu
  :ensure t
  :after corfu
  :config
  (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

(use-package nerd-icons-dired
  :ensure t
  :hook
  (dired-mode . nerd-icons-dired-mode))
(use-package undo-fu
  :defer t)

(use-package undo-fu-session
  :hook (on-first-buffer . global-undo-fu-session-mode)
  :init (setq undo-fu-session-directory (vlaci/in-cache-directory "undo-fu-session")))
(use-package evil
  :hook (after-init . evil-mode)
  :init
  (setq
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
  :config
  (require 'evil-collection)
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
     tab-bar)))

(use-package devil
  :after evil
  :commands (devil)
  :init
  (evil-global-set-key 'normal (kbd "SPC") #'devil)
  :config
  (devil-set-key (kbd "SPC")))
(use-package general
  :init
  (general-auto-unbind-keys))

(eval-when-compile
  (general-create-definer general-r
    :states 'motion
    :prefix "r"))

(use-package avy
  :after evil
  :init
  (setq avy-keys '(?a ?r ?s ?t ?d ?h ?n ?e ?i ?o ?w ?f ?p ?l ?u ?y))

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

  (general-r "/" #'vlaci/goto-char-timer-or-swiper-isearch)

  (advice-add 'avy-resume :after #'evil-normal-state))
(use-package vertico
  :hook (on-first-input . vertico-mode)
  :bind (:map minibuffer-local-map
              ([escape] . keyboard-quit))
  :config
  (setq vertico-scroll-margin 0)
  (setq vertico-count 17)
  (setq vertico-resize t)
  (setq vertico-cycle t)
  (setq vertico-multiform-categories
      '((t
         posframe
         (vertico-posframe-poshandler . posframe-poshandler-frame-top-center)
         (vertico-posframe-fallback-mode . vertico-buffer-mode))))
  (vertico-multiform-mode 1))

(use-package vertico-posframe
  :defer t
  :config
  (setq vertico-posframe-width 100))

;; A few more useful configurations...
(use-package emacs
  :custom
  ;; Support opening new minibuffers from inside existing minibuffers.
  (enable-recursive-minibuffers t)
  ;; Hide commands in M-x which do not work in the current mode.  Vertico
  ;; commands are hidden in normal buffers. This setting is useful beyond
  ;; Vertico.
  (read-extended-command-predicate #'command-completion-default-include-p)
  :init
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
(use-package orderless
  :demand t
  :config

  (defun vlaci-orderless--consult-suffix ()
    "Regexp which matches the end of string with Consult tofu support."
    (if (and (boundp 'consult--tofu-char) (boundp 'consult--tofu-range))
        (format "[%c-%c]*$"
                consult--tofu-char
                (+ consult--tofu-char consult--tofu-range -1))
      "$"))

  ;; Recognizes the following patterns:
  ;; * .ext (file extension)
  ;; * regexp$ (regexp matching at end)
  (defun vlaci-orderless-consult-dispatch (word _index _total)
    (cond
     ;; Ensure that $ works with Consult commands, which add disambiguation suffixes
     ((string-suffix-p "$" word)
      `(orderless-regexp . ,(concat (substring word 0 -1) (+orderless--consult-suffix))))
     ;; File extensions
     ((and (or minibuffer-completing-file-name
               (derived-mode-p 'eshell-mode))
           (string-match-p "\\`\\.." word))
      `(orderless-regexp . ,(concat "\\." (substring word 1) (+orderless--consult-suffix))))))

  ;; Define orderless style with initialism by default
  (orderless-define-completion-style vlaci-orderless-with-initialism
    (orderless-matching-styles '(orderless-initialism orderless-literal orderless-regexp)))

  ;; Certain dynamic completion tables (completion-table-dynamic) do not work
  ;; properly with orderless. One can add basic as a fallback.  Basic will only
  ;; be used when orderless fails, which happens only for these special
  ;; tables. Also note that you may want to configure special styles for special
  ;; completion categories, e.g., partial-completion for files.
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        ;;; Enable partial-completion for files.
        ;;; Either give orderless precedence or partial-completion.
        ;;; Note that completion-category-overrides is not really an override,
        ;;; but rather prepended to the default completion-styles.
        ;; completion-category-overrides '((file (styles orderless partial-completion))) ;; orderless is tried first
        completion-category-overrides '((file (styles partial-completion)) ;; partial-completion is tried first
                                        ;; enable initialism by default for symbols
                                        (command (styles vlaci-orderless-with-initialism))
                                        (variable (styles vlaci-orderless-with-initialism))
                                        (symbol (styles vlaci-orderless-with-initialism)))
        orderless-component-separator #'orderless-escapable-split-on-space ;; allow escaping space with backslash!
        orderless-style-dispatchers (list #'vlaci-orderless-consult-dispatch
                                          #'orderless-affix-dispatch)))
(use-package marginalia
  :hook (after-init . marginalia-mode)
  :bind (:map minibuffer-local-map
              ("M-A" . marginalia-cycle)))
(use-package consult
  ;; Replace bindings. Lazily loaded by `use-package'.
  :bind (;; C-c bindings in `mode-specific-map'
         ("C-c M-x" . consult-mode-command)
         ("C-c h" . consult-history)
         ("C-c k" . consult-kmacro)
         ("C-c m" . consult-man)
         ("C-c i" . consult-info)
         ([remap Info-search] . consult-info)
         ;; C-x bindings in `ctl-x-map'
         ("C-x M-:" . consult-complex-command)     ;; orig. repeat-complex-command
         ("C-x b" . consult-buffer)                ;; orig. switch-to-buffer
         ("C-x 4 b" . consult-buffer-other-window) ;; orig. switch-to-buffer-other-window
         ("C-x 5 b" . consult-buffer-other-frame)  ;; orig. switch-to-buffer-other-frame
         ("C-x t b" . consult-buffer-other-tab)    ;; orig. switch-to-buffer-other-tab
         ("C-x r b" . consult-bookmark)            ;; orig. bookmark-jump
         ("C-x p b" . consult-project-buffer)      ;; orig. project-switch-to-buffer
         ;; Custom M-# bindings for fast register access
         ("M-#" . consult-register-load)
         ("M-'" . consult-register-store)          ;; orig. abbrev-prefix-mark (unrelated)
         ("C-M-#" . consult-register)
         ;; Other custom bindings
         ("M-y" . consult-yank-pop)                ;; orig. yank-pop
         ;; M-g bindings in `goto-map'
         ("M-g e" . consult-compile-error)
         ("M-g f" . consult-flymake)               ;; Alternative: consult-flycheck
         ("M-g g" . consult-goto-line)             ;; orig. goto-line
         ("M-g M-g" . consult-goto-line)           ;; orig. goto-line
         ("M-g o" . consult-outline)               ;; Alternative: consult-org-heading
         ("M-g m" . consult-mark)
         ("M-g k" . consult-global-mark)
         ("M-g i" . consult-imenu)
         ("M-g I" . consult-imenu-multi)
         ;; M-s bindings in `search-map'
         ("M-s d" . consult-fd)                  ;; Alternative: consult-find
         ("M-s c" . consult-locate)
         ("M-s g" . consult-grep)
         ("M-s G" . consult-git-grep)
         ("M-s r" . consult-ripgrep)
         ("M-s l" . consult-line)
         ("M-s L" . consult-line-multi)
         ("M-s k" . consult-keep-lines)
         ("M-s u" . consult-focus-lines)
         ;; Isearch integration
         ("M-s e" . consult-isearch-history)
         :map isearch-mode-map
         ("M-e" . consult-isearch-history)         ;; orig. isearch-edit-string
         ("M-s e" . consult-isearch-history)       ;; orig. isearch-edit-string
         ("M-s l" . consult-line)                  ;; needed by consult-line to detect isearch
         ("M-s L" . consult-line-multi)            ;; needed by consult-line to detect isearch
         ;; Minibuffer history
         :map minibuffer-local-map
         ("M-s" . consult-history)                 ;; orig. next-matching-history-element
         ("M-r" . consult-history))                ;; orig. previous-matching-history-element

  ;; Enable automatic preview at point in the *Completions* buffer. This is
  ;; relevant when you use the default completion UI.
  :hook (completion-list-mode . consult-preview-at-point-mode)

  ;; The :init configuration is always executed (Not lazy)
  :init

  ;; Tweak the register preview for `consult-register-load',
  ;; `consult-register-store' and the built-in commands.  This improves the
  ;; register formatting, adds thin separator lines, register sorting and hides
  ;; the window mode line.
  (advice-add #'register-preview :override #'consult-register-window)
  (setq register-preview-delay 0.5)

  ;; Use Consult to select xref locations with preview
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref)

  ;; Configure other variables and modes in the :config section,
  ;; after lazily loading the package.
  :config

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
)
(use-package corfu
  :init
  (global-corfu-mode))

(use-package emacs
  :init
  ;; TAB cycle if there are only few candidates
  ;; (completion-cycle-threshold 3)

  ;; Enable indentation+completion using the TAB key.
  ;; `completion-at-point' is often bound to M-TAB.
  (setq tab-always-indent 'complete
	;; Emacs 30 and newer: Disable Ispell completion function.
	;; Try `cape-dict' as an alternative.
	text-mode-ispell-word-completion nil
	;; Hide commands in M-x which do not apply to the current mode.  Corfu
	;; commands are hidden, since they are not used via M-x. This setting is
	;; useful beyond Corfu.
	read-extended-command-predicate #'command-completion-default-include-p))

;; Use Dabbrev with Corfu!
(use-package dabbrev
  ;; Swap M-/ and C-M-/
  :bind (("M-/" . dabbrev-completion)
         ("C-M-/" . dabbrev-expand))
  :config
  (add-to-list 'dabbrev-ignored-buffer-regexps "\\` ")
  ;; Since 29.1, use `dabbrev-ignored-buffer-regexps' on older.
  (add-to-list 'dabbrev-ignored-buffer-modes 'doc-view-mode)
  (add-to-list 'dabbrev-ignored-buffer-modes 'pdf-view-mode)
  (add-to-list 'dabbrev-ignored-buffer-modes 'tags-table-mode))
(use-package embark
  :init
  (setq embark-indicators
        '(embark-minimal-indicator  ; default is embark-mixed-indicator
          embark-highlight-indicator
          embark-isearch-highlight-indicator))

  (with-eval-after-load 'vertico
    (add-to-list 'vertico-multiform-categories '(embark-keybinding grid)))

  (setq prefix-help-command #'embark-prefix-help-command))
(use-package nix-ts-mode
  :mode "\\.nix\\'")

(use-package rust-ts-mode
  :mode "\\.rs\\'")

(use-package python-ts-mode
  :mode "\\.py\\'" "\\.pyi\\'")
(use-package lsp-mode
  :init
  (setq lsp-keymap-prefix "C-c l"
        lsp-completion-provider :none ;; we use Corfu!
        lsp-inlay-hint-enable t
        lsp-session-file (vlaci/in-cache-directory "lsp-session"))
  (defun vlaci/orderless-dispatch-flex-first-h (_pattern index _total)
    (and (eq index 0) 'orderless-flex))
  (defun vlaci/lsp-mode-completion-setup-h ()
    (setf (alist-get 'styles (alist-get 'lsp-capf completion-category-defaults))
          '(orderless))
    (add-hook 'orderless-style-dispatchers #'vlaci/orderless-dispatch-flex-first-h nil 'local)
    (setq-local completion-at-point-functions (list (cape-capf-buster #'lsp-completion-at-point))))
  :hook ((lsp-completion-mode . vlaci/lsp-mode-completion-setup-h)
         (rust-ts-mode . lsp-deferred)))

(use-package lsp-ui
  :hook (lsp-mode . lsp-ui-mode)
  :init
  (setq lsp-ui-doc-position 'top))

(use-package lsp-pyright
  :hook (python-ts-mode . (lambda ()
                          (require 'lsp-pyright)
                          (lsp-deferred)))
  :init
  (setq lsp-pyright-langserver-command "basedpyright"))
(use-package envrc
  :hook (on-first-file . envrc-global-mode)
  :init
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
