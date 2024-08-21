// SPDX-FileCopyrightText: 2024 László Vaskó <vlaci@fastmail.com>
//
// SPDX-License-Identifier: EUPL-1.2

import { PluggableList } from "unified";
import { visit } from "unist-util-visit";

import { QuartzTransformerPlugin } from "../quartz.git/quartz/types";

export const OxHugoFigureCaptions: QuartzTransformerPlugin = () => {
  return {
    name: "OxHugoFigureCaptions",
    htmlPlugins(ctx) {
      const plugins: PluggableList = [];
      plugins.push(() => {
        return (tree, _file) => {
          visit(tree, "element", (node, index, parent) => {
            if (
              node.tagName === "div" &&
              node.properties?.className.includes("src-block-caption")
            ) {
              const caption = node.children.at(-1).value.trim();
              const figure = parent.children[index - 2];
              // <figcaption data-rehype-pretty-code-caption="" data-language="nix" data-theme="Gruvbox Material Light Gruvbox Material Dark">nixos</figcaption>
              figure.children.push({
                type: "element",
                tagName: "figcaption",
                properties: {},
                children: [{ type: "text", value: caption }],
              });
              parent.children.splice(index, 1);
            }
          });
        };
      });

      return plugins;
    },
  };
};
