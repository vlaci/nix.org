// SPDX-FileCopyrightText: 2021 jackyzha0
// SPDX-FileCopyrightText: 2024 László Vaskó <vlaci@fastmail.com>
//
// SPDX-License-Identifier: MIT

import { QuartzConfig } from "./quartz/cfg"
import * as Plugin from "./quartz/plugins"
import fs from "fs"

const theme = {
  light: JSON.parse(fs.readFileSync("./rose-pine-dawn-color-theme.json", "utf-8")),
  dark: JSON.parse(fs.readFileSync("./rose-pine-moon-color-theme.json", "utf-8")),
}

/**
 * Quartz 4.0 Configuration
 *
 * See https://quartz.jzhao.xyz/configuration for more information.
 */
const config: QuartzConfig = {
  configuration: {
    pageTitle: "nix.org",
    pageTitleSuffix: " - vlaci's nix knowledge base",
    enableSPA: true,
    enablePopovers: true,
    analytics: {
      provider: null,
    },
    locale: "en-US",
    baseUrl: "vlaci.github.io/nix.org",
    ignorePatterns: ["private", "templates", ".obsidian"],
    defaultDateType: "created",
    generateSocialImages: false,
    theme: {
      fontOrigin: "local",
      cdnCaching: false,
      typography: {
        header: "BerkeleyMonoVariable-Regular",
        body: "BerkeleyMonoVariable-Regular",
        code: "BerkeleyMono-Regular",
      },
      colors: {
        lightMode: {
          light: theme.light.colors["editor.background"],
          lightgray: theme.light.colors["selection.background"],
          gray: theme.light.colors["sideBar.foreground"],
          darkgray: theme.light.colors["foreground"],
          dark: theme.light.colors["terminal.ansiWhite"],
          secondary: theme.light.colors["editorLink.activeForeground"],
          tertiary: theme.light.colors["terminal.ansiGreen"],
          highlight: theme.light.colors["editor.lineHighlightBackground"],
          textHighlight: theme.light.colors["selection.background"],
        },
        darkMode: {
          light: theme.dark.colors["editor.background"],
          lightgray: theme.dark.colors["selection.background"],
          gray: theme.dark.colors["sideBar.foreground"],
          darkgray: theme.dark.colors["foreground"],
          dark: theme.dark.colors["terminal.ansiWhite"],
          secondary: theme.dark.colors["editorLink.activeForeground"],
          tertiary: theme.dark.colors["terminal.ansiGreen"],
          highlight: theme.dark.colors["editor.lineHighlightBackground"],
          textHighlight: theme.dark.colors["selection.background"],
        },
      },
    },
  },
  plugins: {
    transformers: [
      Plugin.FrontMatter({ delimiters: "+++", language: "toml" }),
      Plugin.CreatedModifiedDate({
        priority: ["frontmatter", "filesystem"],
      }),
      Plugin.SyntaxHighlighting({
        theme: theme,
        keepBackground: false,
      }),
      Plugin.ObsidianFlavoredMarkdown({ enableInHtmlEmbed: false }),
      Plugin.GitHubFlavoredMarkdown(),
      Plugin.OxHugoFlavouredMarkdown(),
      Plugin.OxHugoFigureCaptions(),
      Plugin.TableOfContents(),
      Plugin.CrawlLinks({ markdownLinkResolution: "shortest" }),
      Plugin.Description(),
    ],
    filters: [Plugin.RemoveDrafts()],
    emitters: [
      Plugin.AliasRedirects(),
      Plugin.ComponentResources(),
      Plugin.ContentPage(),
      Plugin.FolderPage(),
      Plugin.TagPage(),
      Plugin.ContentIndex({
        enableSiteMap: true,
        enableRSS: true,
      }),
      Plugin.Assets(),
      Plugin.Static(),
      Plugin.NotFoundPage(),
    ],
  },
}

export default config
