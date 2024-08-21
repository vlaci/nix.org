;;; Directory Local Variables            -*- no-byte-compile: t -*-
;;; SPDX-FileCopyrightText: 2024 László Vaskó <vlaci@fastmail.com>
;;;
;;; SPDX-License-Identifier: EUPL-1.2

((nil . ((eval . (progn
                   (setq-local org-roam-directory
                             (expand-file-name
                              (concat
                               (locate-dominating-file default-directory
                                                       ".dir-locals.el")
                               "org")))
                   (setq-local org-roam-db-location
                               (expand-file-name "org-roam.db" org-roam-directory))
                   (setq-local org-coderef-label-format "#ref:%s")
                   (add-to-list 'org-cite-global-bibliography
                                (expand-file-name
                                 "references.bib"
                                 org-roam-directory))))
         (org-roam-capture-templates . (("d" "default" plain "%?" :target
                                          (file+head "${slug}.org" "#+title: ${title}\n")
                                          :unnarrowed t))))))
