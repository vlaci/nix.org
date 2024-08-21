# SPDX-FileCopyrightText: 2024 László Vaskó <vlaci@fastmail.com>
#
# SPDX-License-Identifier: EUPL-1.2

# For [script] to work
set unstable

default: tangle format

[script('emacs', '-Q', '--script')]
tangle:
    (require 'org-roam)
    (require 'project)
    (require 'el-patch)
    (require 'el-patch-template)

    (el-patch-define-and-eval-template
     (defun org-babel-expand-noweb-references)
     (el-patch-wrap 1 1 (org-babel-expand-body:generic (expand-body last) (nth 2 last)))
     (el-patch-wrap 1 1 (org-babel-expand-body:generic (expand-body i) (nth 2 i))))
    (el-patch-validate-all)

    (setq org-roam-directory (expand-file-name "./org"))
    (setq org-roam-db-location (expand-file-name "./org/org-roam.db"))

    (let (contents
          (export-file (concat (project-root (project-current)) (make-temp-name ".entangle.") ".org"))
          (files (org-roam-list-files)))
      (dolist (file files)
        (when (file-regular-p file)
          (push (with-temp-buffer (insert-file-contents file) (buffer-string))
                contents)))
      (write-region (mapconcat #'identity contents "\n") nil export-file)
      (unwind-protect
          (org-babel-tangle-file export-file)
        (delete-file export-file)))

format:
  treefmt --walk=git
  treefmt --walk=filesystem out


[private]
[script('bash', '-exuo', 'pipefail')]
quartz:
    mkdir -p quartz.git
    cd quartz.git
    git init || true
    git fetch --depth 1 https://github.com/jackyzha0/quartz.git
    git reset --hard FETCH_HEAD
    npm i
    npx quartz create --strategy new --links shortest
    ln -snf ../quartz/quartz.config.ts .
    ln -snf ../quartz/quartz.layout.ts .
    ln -snf ../../../quartz/custom.scss ./quartz/styles/custom.scss
    mkdir -p content/fonts
    unzip -p ../assets/berkeley-mono-typeface.zip \
      berkeley-mono/WEB/BerkeleyMono-Regular.woff \
      > content/fonts/BerkeleyMono-Regular.woff

    unzip -p ../assets/berkeley-mono-typeface.zip \
      berkeley-mono-variable/WEB/BerkeleyMonoVariable-Regular.woff \
      > content/fonts/BerkeleyMonoVariable-Regular.woff

[script('emacs', '-Q', '--script')]
export:
    (toggle-debug-on-error)
    (require 'org-roam)
    (require 'ox-hugo)
    (require 'el-patch)
    (require 'el-patch-template)

    (el-patch-define-and-eval-template
     (defun org-hugo--attachment-rewrite-maybe)
     (el-patch-swap "static" "content"))

    (el-patch-validate-all)

    (setq org-roam-directory (expand-file-name "./org"))
    (setq org-roam-db-location (expand-file-name "./org/org-roam.db"))
    (setq org-cite-export-processors `((t csl ,(expand-file-name "./ieee.csl"))))
    (setq org-cite-global-bibliography `(,(expand-file-name "references.bib" org-roam-directory)))
    (setq org-hugo-base-dir (expand-file-name "./quartz.git"))
    (setq org-coderef-label-format "#ref:%s")

    (defun +add-references (backend)
      (save-excursion
        (goto-char (point-max))
        (insert "#+print_bibliography:")))

    (add-hook 'org-export-before-parsing-functions #'+add-references)

    (mkdir user-emacs-directory :parents)

    (let ((files (org-roam-list-files)))
      (dolist (file files)
        (with-current-buffer (find-file-noselect file)
          (let ((org-id-extra-files files))
            (org-hugo-export-wim-to-md)))))

build cmd="build": tangle format
    nixos-rebuild {{ cmd }} -L --flake path:{{ justfile_directory() }}/out

serve: export
    cd quartz.git && npx quartz build --serve

[script('bash', '-exuo', 'pipefail')]
build-site: quartz export
    cd quartz.git && npx quartz build -o "{{ justfile_directory() }}/public"

rebuild action: tangle format
    nixos-rebuild {{ action }} -L --flake "path:{{ justfile_directory() }}?dir=out" --use-remote-sudo --override-input private path:./private.nix
