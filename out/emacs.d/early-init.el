;; -*- lexical-binding: t; -*-
(setq gc-cons-threshold most-positive-fixnum)

(add-hook 'after-init-hook
          `(lambda ()
             (setq file-name-handler-alist ',file-name-handler-alist))
          0)
(setq file-name-handler-alist nil)

(setq package-enable-at-startup nil
      frame-resize-pixelwise t
      frame-inhibit-implied-resize t
      frame-title-format '("%b")
      ring-bell-function 'ignore
      use-dialog-box nil
      use-file-dialog nil
      use-short-answers t
      inhibit-splash-screen t
      inhibit-startup-screen t
      inhibit-x-resources t
      inhibit-startup-echo-area-message user-login-name ; read the docstring
      inhibit-startup-buffer-menu t)

;; Prevent the glimpse of un-styled Emacs by disabling these UI elements early.
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)

(startup-redirect-eln-cache (expand-file-name "~/.cache/emacs/eln-cache"))
