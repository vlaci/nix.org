// SPDX-FileCopyrightText: 2021 jackyzha0
// SPDX-FileCopyrightText: 2024 László Vaskó <vlaci@fastmail.com>
//
// SPDX-License-Identifier: MIT

import { QuartzConfig } from "./quartz/cfg"
import * as Plugin from "./quartz/plugins"
import fs from "fs"

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
          light: "#fbf1c7",
          lightgray: "#f2e5bc",
          gray: "#928374",
          darkgray: "#7c6f64",
          dark: "#4f3829",
          secondary: "#6c782e",
          tertiary: "#c35e0a",
          highlight: "#dee2b688",
          textHighlight: "#fae7b388",
        },
        darkMode: {
          light: "#282828",
          lightgray: "#504945",
          gray: "#928374",
          darkgray: "#a89984",
          dark: "#d4be98",
          secondary: "#a9b665",
          tertiary: "#e78a4e",
          highlight: "#3b443988",
          textHighlight: "#4f422e88",
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
        theme: {
          light: JSON.parse(fs.readFileSync("./gruvbox-material-light.json", "utf-8")),
          dark: JSON.parse(fs.readFileSync("./gruvbox-material-dark.json", "utf-8")),
        },
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
