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
  (defvar user-cache-directory "~/.cache/emacs/"
    "Location where files created by emacs are placed.")

  (defun vlaci/in-cache-directory (name)
    "Return NAME appended to cache directory"
    (expand-file-name name user-cache-directory))

  (:option
   custom-file (vlaci/in-cache-directory "custom.el")
   auto-save-interval 2400
   auto-save-timeout 300
   auto-save-list-file-prefix (vlaci/in-cache-directory "auto-save-list/.saves-")
   backup-directory-alist `(("." . ,(vlaci/in-cache-directory "backup")))
   backup-by-copying t
   version-control t
   delete-old-versions t
   kept-new-versions 10
   kept-old-versions 5)

  (load custom-file :no-error-if-file-is-missing))


(setup recentf
  (:option recentf-save-file (vlaci/in-cache-directory "recentf")
           recentf-max-saved-items 200
           recentf-auto-cleanup 300)
  (define-advice recentf-cleanup (:around (fun) silently)
    (let ((inhibit-message t)
          (message-log-max nil))
      (funcall fun)))
  (recentf-mode 1))

(setup savehist
  (:hook-into on-first-file-hook)
  (:option savehist-file (vlaci/in-cache-directory "savehist")
           history-length 1000
           history-delete-duplicates t
           savehist-save-minibuffer-history t))

(setup org
  (:option org-startup-indented t
           org-edit-src-content-indentation 0))

(setup (:package org-modern)
  (:hook-into org-mode-hook))
(setup (:package org-roam)
  (:defer-incrementally ansi-color dash f rx seq magit-section emacsql))
(setup emacs
  (:option help-window-keep-selected t)) ;; navigating to e.g. source from help window reuses said window
(setup (:package on)
  (:require on))
(setup (:package sticky-scroll-mode)
  (:hook-into prog-mode-hook))
(setup (:package doom-modeline auto-dark spacious-padding)
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
    (spacious-padding-mode)
    (doom-modeline-mode)
    (auto-dark-mode))
  (:with-function vlaci--load-theme-h
    (:hook-into window-setup-hook)))
(setup project
  (:option project-list-file (vlaci/in-cache-directory "project-list.ed")))
(setup (:package once)
  (:option once-shorthand t)
  (:require once once-conditions))

(setup (:package once-setup)
  (:require once-setup))
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
           undo-tree-strong-limit (* 120 1024 1024)
           undo-outer-limit (* 360 1024 1024)))

(setup (:package undo-fu-session)
  (:with-mode undo-fu-session-global-mode
    (:hook-into on-first-buffer-hook))
  (:option undo-fu-session-directory (vlaci/in-cache-directory "undo-fu-session")))
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
    (:with-feature devil
      (:when-loaded
        (devil-set-key (kbd "SPC"))))))


(setup-define :ebind
  (lambda (key command)
    `(evil-define-key ,(setup-get 'evil-state) ,(setup-get 'map) ,key ,command))
  :documentation "Bind KEY to COMMAND for the given EVIL state"
  :repeatable t)

(let* ((element (assoc :with-map setup-macros))
       (with-map-fn (cdr element)))
  (setcdr element (lambda (map &rest body)
                    (when (and (consp map) (eq (car map) 'quote))
                      (setq map (list map)))
                    (apply with-map-fn (cons map body)))))

(setup-define :with-state
  (lambda (state &rest body)
    (let (bodies)
      (push (setup-bind body (evil-state state)) bodies)
      (macroexp-progn (nreverse bodies))))
  :documentation "Use STATE for binding keys")

(setup-define :evil
  (lambda (&rest body)
    (require 'evil)
    `(:with-state 'motion ,@body))
  :documentation "Bind KEYs to COMMANDs for the given EVIL state"
  :ensure '(nil &rest kbd func))

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
     (:with-state 'normal (:ebind "r" nil))
     (:ebind"r/" #'vlaci/goto-char-timer-or-swiper-isearch))))

(setup (:package evil-ts-obj)
  (:hook-into
   bash-ts-mode-hook
   c-ts-mode-hook
   c++-ts-mode-hook
   nix-ts-mode-hook
   python-ts-mode-hook
   rust-ts-mode-hook
   yaml-ts-mode-hook))

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

  (:once 'on-first-input-hook
         (:require orderless)
         ;; Define orderless style with initialism by default
         (orderless-define-completion-style vlaci-orderless-with-initialism
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
                                           (command (styles vlaci-orderless-with-initialism))
                                           (variable (styles vlaci-orderless-with-initialism))
                                           (symbol (styles vlaci-orderless-with-initialism)))
           orderless-component-separator #'orderless-escapable-split-on-space ;; allow escaping space with backslash!
           orderless-style-dispatchers (list #'vlaci-orderless-consult-dispatch
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

  (setq prefix-help-command #'embark-prefix-help-command))
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
    (:hook-into after-init-hook)))
(setup (:package lsp-mode)
  (:option lsp-keymap-prefix "C-c l"
           lsp-completion-provider :none ;; we use Corfu!
           lsp-inlay-hint-enable t
           lsp-enable-suggest-server-download nil
           lsp-headerline-breadcrumb-enable nil
           lsp-semantic-tokens-enable t
           lsp-file-watch-threshold 4000
           lsp-keep-workspace-alive nil
           lsp-idle-delay 1.5
           lsp-session-file (vlaci/in-cache-directory "lsp-session")
           read-process-output-max (* 1024 1024))
  (defun vlaci/orderless-dispatch-flex-first-h (_pattern index _total)
    (and (eq index 0) 'orderless-flex))
  (defun vlaci/lsp-mode-completion-setup-h ()
    (setf (alist-get 'styles (alist-get 'lsp-capf completion-category-defaults))
          '(orderless))
    (add-hook 'orderless-style-dispatchers #'vlaci/orderless-dispatch-flex-first-h nil 'local)
    (setq-local completion-at-point-functions (list (cape-capf-buster #'lsp-completion-at-point))))
  (:with-function vlaci/lsp-mode-completion-setup-h
    (:hook-into lsp-completion-mode)))

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
          (cons "emacs-lsp-booster" (cons "--disable-bytecode" (cons "--" orig-result))))
      orig-result)))

(advice-add 'lsp-resolve-final-command :around #'lsp-booster--advice-final-command)

(setup-define :lsp
  (lambda ()
    `(:hook lsp-deferred))
  :documentation "Configure LSP for given mode.")

(setup (:package lsp-ui)
  (:hook-into lsp-mode-hook)
  (:option lsp-ui-doc-show-with-mouse nil
           lsp-ui-doc-show-with-cursor t
           lsp-ui-doc-delay 1.5))

(setup (:package lsp-pyright)
  (:option lsp-pyright-langserver-command "basedpyright")
  (:with-mode python-ts-mode
    (:also-load lsp-pyright)))
(setup (:package nix-ts-mode)
  (defalias 'nix-mode 'nix-ts-mode) ;; For org-mode code blocks to work
  (:lsp))

(setup (:package rust-ts-mode)
  (:lsp))

(setup python-ts-mode
  (:lsp))

(setup c-or-c++-ts-mode
  (:lsp))
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
(setup (:package magit))
(setup emacs
  (:option indent-tabs-mode nil
           mouse-yank-at-point t)) ;; paste at keyboard cursor instead of mouse pointer location
