# SPDX-FileCopyrightText: 2024 László Vaskó <vlaci@fastmail.com>
#
# SPDX-License-Identifier: EUPL-1.2

# This file is to let "legacy" nix-shell command work in addition to `nix develop`
let
  flakeManifest = [
    ./flake.lock
    ./flake.nix
  ];

  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  flake-compat = fetchTarball {
    url = "https://github.com/edolstra/flake-compat/archive/${lock.nodes.flake-compat.locked.rev}.tar.gz";
    sha256 = lock.nodes.flake-compat.locked.narHash;
  };

  startsWith = pref: str: with builtins; substring 0 (stringLength pref) str == pref;

  src = builtins.path {
    path = ./.;
    name = "source";
    filter = path: _type: builtins.any (x: startsWith (toString x) path) flakeManifest;
  };
in
(import flake-compat { inherit src; }).shellNix.default
