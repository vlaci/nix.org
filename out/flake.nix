{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    stylix.url = "github:danth/stylix";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    nix-index-database.url = "github:Mic92/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    lix-module.url = "https://git.lix.systems/lix-project/nixos-module/archive/2.91.1-1.tar.gz";
    lix-module.inputs.nixpkgs.follows = "nixpkgs";
    niri.url = "github:sodiboo/niri-flake";
    impermanence.url = "github:nix-community/impermanence";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    private.url = "github:vlaci/empty-flake";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      stylix,
      sops-nix,
      nix-index-database,
      lix-module,
      niri,
      impermanence,
      home-manager,
      private,
      disko,
      ...
    }:
    {
      nixosModules.tachi = {
        networking.hostName = "tachi";
        imports = [
          ./hosts/tachi/disko-config.nix
          (
            {
              lib,
              pkgs,
              ...
            }:

            {
              boot.initrd.systemd = {
                enable = true;
                emergencyAccess = true;
                services.revert-root = {
                  after = [
                    "cryptsetup.target"
                    "systemd-udev-settle.service"
                    "systemd-modules-load.service"
                  ];
                  wants = [ "systemd-udev-settle.service" ];
                  before = [
                    "sysroot.mount"
                  ];
                  wantedBy = [ "initrd.target" ];
                  path = with pkgs; [
                    lvm2
                  ];
                  unitConfig = {
                    DefaultDependencies = "no";
                    ConditionKernelCommandLine = [ "!no_rollback" ];
                  };
                  serviceConfig.Type = "oneshot";

                  script = ''
                    lvconvert --mergethin mainpool/root-blank || true
                    lvcreate -s mainpool/root --name root-blank
                  '';
                };

                services.create-needed-for-boot-dirs = {
                  after = lib.mkForce [ "revert-root.service" ];
                };
              };
            }
          )
          {
            boot.loader.systemd-boot.enable = true;
            boot.loader.efi.canTouchEfiVariables = true;
          }
          {
            networking.networkmanager.enable = true;
            _.persist.directories = [ "/etc/NetworkManager/system-connections" ];
          }
          {
            boot.tmp = {
              useTmpfs = true;
              tmpfsSize = "100%";
            };
            boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

            system.stateVersion = "24.11";
          }
          (
            { pkgs, ... }:

            {
              virtualisation.docker = {
                enable = true;
                autoPrune.enable = true;
                extraPackages = [ pkgs.openssh ];
              };
              environment.systemPackages = with pkgs; [
                docker-compose
              ];

              _.persist.users.vlaci.files = [ ".docker/config.json" ];
            }
          )
        ];
      };
      nixosConfigurations.tachi = self.lib.mkNixOS {
        modules = [ self.nixosModules.tachi ];
      };
      nixosModules.razorback = {
        networking.hostName = "razorback";
        imports = [
          ./hosts/razorback/hardware-configuration.nix
          ./hosts/razorback/disko-config.nix
          (
            {
              lib,
              pkgs,
              config,
              ...
            }:

            {
              boot.initrd.systemd = {
                enable = true;
                emergencyAccess = true;
                services.revert-root = {
                  after = [
                    "zfs-import-rpool.service"
                  ];
                  wantedBy = [ "initrd.target" ];
                  before = [
                    "sysroot.mount"
                  ];
                  path = with pkgs; [
                    zfs
                  ];
                  unitConfig = {
                    DefaultDependencies = "no";
                    ConditionKernelCommandLine = [ "!zfs_no_rollback" ];
                  };
                  serviceConfig.Type = "oneshot";

                  script = ''
                    zfs rollback -r rpool/${config.networking.hostName}/root@blank
                  '';
                };
                # HACK: do not try to import pool before LUKS is opened. Otherwise
                # if passphrase is not entered in time, importing will time out.
                services.zfs-import-rpool.after = [ "cryptsetup.target" ];

                services.create-needed-for-boot-dirs = {
                  after = lib.mkForce [ "revert-root.service" ];
                };
              };
            }
          )
          {
            networking.hostId = "8425e349";
            boot.supportedFilesystems = [ "zfs" ];

            boot.zfs = {
              allowHibernation = true;
              devNodes = "/dev/mapper";
              forceImportRoot = false;
            };

            services.zfs.autoScrub.enable = true;

            virtualisation.docker.storageDriver = "zfs";

            boot.loader.systemd-boot.enable = true;
            boot.loader.efi.canTouchEfiVariables = true;
          }
          {
            networking.networkmanager.enable = true;
            _.persist.directories = [ "/etc/NetworkManager/system-connections" ];
          }
          {
            boot.tmp = {
              useTmpfs = true;
              tmpfsSize = "100%";
            };
            boot.kernelParams = [
              "pcie_acs_override=downstream,multifunction"
              "intel_iommu=on"
              "pci=noaer"
              "acpi_enforce_resources=lax"
              "thermal.off=1"
              "module_blacklist=eeepc_wmi"
            ];
            boot.extraModprobeConfig = ''
              options vfio-pci ids=10de:1b81,10de:10f0,1b21:2142
            '';
            boot.kernelModules = [
              "vfio_pci"
              "vfio"
              "vfio_iommu_type1"
              "vfio_virqfd"
            ];
            boot.blacklistedKernelModules = [ "nouveau" ];
            boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

            system.stateVersion = "24.11";
          }
        ];
      };
      nixosConfigurations.razorback = self.lib.mkNixOS {
        modules = [ self.nixosModules.razorback ];
      };
      lib.mkNixOS =
        { modules }:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            (
              { pkgs, ... }:

              {
                programs.zsh = {
                  enable = true;
                  enableGlobalCompInit = false; # We'll do it ourselves, making startup faster
                };

                users.defaultUserShell = pkgs.zsh;
              }
            )
            {
              _.persist.allUsers.directories = [ ".local/share/zoxide" ];
            }
            {
              _.persist.allUsers.directories = [
                "Desktop"
                "Documents"
                "Downloads"
                "Music"
                "Pictures"
                "Videos"
              ];
            }
            (
              { pkgs, ... }:

              {
                virtualisation.libvirtd.enable = true;
                virtualisation.spiceUSBRedirection.enable = true;
                services.dbus.packages = with pkgs; [ dconf ];
                _.persist.directories = [
                  "/var/lib/libvirt"
                ];
              }
            )
            (
              { lib, config, ... }:

              {
                users.users.vlaci = {
                  uid = 1000;
                  isNormalUser = true;
                  extraGroups =
                    lib.optional config.security.sudo.enable "wheel"
                    ++ lib.optional config.networking.networkmanager.enable "networkmanager"
                    ++ lib.optional config.virtualisation.docker.enable "docker"
                    ++ lib.optional config.virtualisation.libvirtd.enable "libvirtd";
                };
              }
            )
            (
              { config, ... }:

              {
                users.mutableUsers = false;
                sops.secrets."vlaci/local_password" = {
                  neededForUsers = true;
                  sopsFile = ../secrets/vlaci.yaml;
                };
                users.users.vlaci.hashedPasswordFile = config.sops.secrets."vlaci/local_password".path;
              }
            )
            {
              home-manager.users.vlaci = { };
            }
            {
              _.persist.users.vlaci.directories = [ "devel" ];
            }
            stylix.nixosModules.stylix
            (
              { pkgs, ... }:

              {
                stylix = {
                  enable = true;
                  base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-material-dark-medium.yaml";
                  image = ../assets/serenity_gruvbox.png;
                  cursor = {
                    package = pkgs.cz-Hickson-cursors;
                    name = "cz-Hickson-white";
                  };
                  fonts = {
                    monospace = {
                      package = pkgs.berkeley-mono-typeface;
                      name = "Berkeley Mono";
                    };
                  };
                };
              }
            )
            (
              { pkgs, ... }:

              {
                fonts.packages = [
                  pkgs.nerd-fonts.symbols-only
                ];
              }
            )
            (
              { config, ... }:

              {
                services.openssh = {
                  enable = true;
                  startWhenNeeded = true;
                  settings = {
                    PasswordAuthentication = true;
                    PermitRootLogin = "no";
                    X11Forwarding = true;
                  };
                };

                _.persist.files = map (key: key.path) config.services.openssh.hostKeys;
              }
            )
            sops-nix.nixosModules.sops
            (
              { lib, config, ... }:

              let
                secretsFile = ../secrets/${config.networking.hostName}.yaml;
                hasHostSecrets = builtins.pathExists secretsFile;
              in
              lib.mkMerge [
                {
                  sops.age.sshKeyPaths =
                    map (k: "/persist" + k.path) (
                      builtins.filter (k: k.type == "ed25519") config.services.openssh.hostKeys
                    )
                    ++ [ "/persist/home/vlaci/.ssh/id_ed25519" ];
                }
                (lib.mkIf hasHostSecrets {
                  sops.defaultSopsFile = secretsFile;
                })
              ]
            )
            (
              { config, ... }:

              {
                virtualisation.vmVariant = {
                  boot.kernelParams = [
                    "systemd.log_target=kmsg"
                    "systemd.journald.forward_to_console=1"
                    "console=ttyS0,115200"
                    "zfs_no_rollback"
                  ];
                };
                virtualisation.vmVariantWithBootLoader.boot = {
                  inherit (config.virtualisation.vmVariant.boot) kernelParams;
                };
              }
            )
            (
              {
                lib,
                options,
                config,
                ...
              }:

              {
                options = {

                };

                config = lib.mkMerge [

                ];
              }
            )
            nix-index-database.nixosModules.nix-index
            {
              programs.command-not-found.enable = false;
              programs.nix-index-database.comma.enable = true;
            }
            lix-module.nixosModules.default
            {
              nix = {
                daemonCPUSchedPolicy = "idle";
                daemonIOSchedClass = "idle";

                gc = {
                  automatic = true;
                  dates = "weekly";
                  options = "--delete-older-than 14d";
                };

                optimise = {
                  automatic = true;
                  dates = [ "weekly" ];
                };

                settings = {
                  experimental-features = [
                    "nix-command"
                    "flakes"
                  ];
                  keep-outputs = true;
                  keep-env-derivations = true;
                  keep-derivations = true;
                  trusted-users = [
                    "root"
                    "@wheel"
                  ];
                };
              };

              nixpkgs.config.allowUnfree = true;
            }
            {
              imports = [ niri.nixosModules.niri ];
              programs.niri.enable = true;
            }
            (
              { pkgs, ... }:

              {
                services.dbus.packages = [ pkgs.nautilus ];
              }
            )
            {
              _.persist.users.vlaci.files = [ ".cache/fuzzel" ];
            }
            {
              location.provider = "geoclue2";
              services.automatic-timezoned.enable = true;
              services.geoclue2 = {
                enable = true;
                # From Arch Linux
                geoProviderUrl = "https://www.googleapis.com/geolocation/v1/geolocate?key=AIzaSyDwr302FpOSkGRpLlUpPThNTDPbXcIn_FM";
              };
            }
            {
              nixpkgs.config.packageOverrides =
                pkgs:
                (builtins.foldl' (acc: v: acc // v) { } [
                  {
                    cz-Hickson-cursors = pkgs.stdenvNoCC.mkDerivation rec {
                      pname = "cz-Hickson-cursors";
                      version = "3.0";
                      src = pkgs.fetchFromGitHub {
                        owner = "charakterziffer";
                        repo = "cursor-toolbox";
                        rev = "ec5e7e582be059996c0405070494ae9ed7834d4d";
                        hash = "sha256-jJvtV0+Ytnu/gLyvSX+/mqZeunnN5PCDypYRSAc+jJw=";
                      };

                      strictDeps = true;

                      nativeBuildInputs = with pkgs; [
                        xorg.xcursorgen
                      ];
                      prePatch = ''
                        substituteInPlace make.sh --replace-fail "'My Cursor Theme'" '"$1"'
                      '';
                      buildPhase = ''
                        cd more-themes/cz-Hickson
                        ln -snf pngs-black pngs
                        ../../make.sh cz-Hickson-black
                        ln -snf pngs-white pngs
                        ../../make.sh cz-Hickson-white
                      '';
                      installPhase = ''
                        mkdir -p $out/share/icons
                        cp -r cz-Hickson-* $out/share/icons
                      '';
                    };
                  }
                  {
                    berkeley-mono-typeface = pkgs.stdenvNoCC.mkDerivation {
                      pname = "berkeley-mono-typeface";
                      version = "1.009";

                      src = ../assets/berkeley-mono-typeface.zip;

                      unpackPhase = ''
                        runHook preUnpack

                        ${pkgs.unzip}/bin/unzip $src

                        runHook postUnpack
                      '';

                      installPhase = ''
                        runHook preInstall

                        install -Dm644 berkeley-mono/OTF/*.otf -t $out/share/fonts/truetype
                        install -Dm644 berkeley-mono-variable/TTF/*.ttf -t $out/share/fonts/truetype

                        runHook postInstall
                      '';
                    };
                  }
                ]);
            }
            (
              { pkgs, ... }:

              {
                console.font = "${pkgs.terminus_font}/share/consolefonts/ter-220b.psf.gz"; # ISO-8859-2 10x20 bold
                console.earlySetup = true;
                console.useXkbConfig = true;
                i18n.defaultLocale = "hu_HU.UTF-8";

                environment.systemPackages = [ pkgs.colemak-dh ];

                services.xserver.xkb = {
                  layout = "col-lv,us,hu";
                  options = "grp:alt_altgr_toggle, compose:rctrl, caps:escape";
                  extraLayouts."col-lv" = {
                    description = "English/Hungarian (Colemak-DH Ortholinear)";
                    languages = [
                      "eng"
                      "hun"
                    ];
                    symbolsFile = ./keymaps/symbols/col-lv;
                  };
                };
              }
            )
            impermanence.nixosModules.impermanence
            (
              { lib, config, ... }:

              let
                inherit (lib) mkOption types;
                cfg = config._.persist;
              in
              {
                options._.persist = {
                  root = mkOption {
                    type = types.str;
                    default = "/persist";
                  };
                  directories = mkOption {
                    type = with types; listOf anything;
                    default = [ ];
                  };
                  files = mkOption {
                    type = with types; listOf anything;
                    default = [ ];
                  };
                };
                config = {
                  environment.persistence.${cfg.root} = {
                    enable = true;
                    hideMounts = true;
                    inherit (cfg) directories files;
                  };
                };
              }
            )
            {
              _.persist.directories = [
                "/var/lib/nixos"
                "/var/lib/systemd/coredump"
                "/var/log"
              ];
            }
            (
              { lib, config, ... }:

              let
                inherit (lib) hasPrefix mkOption types;
                inherit (config._.persist) root;
              in
              {
                options.fileSystems = mkOption {
                  type =
                    with types;
                    attrsOf (
                      submodule (
                        { config, ... }:
                        {
                          options.neededForBoot = mkOption {
                            apply = orig: orig || config.mountPoint == root || hasPrefix "${root}/" config.mountPoint;
                          };
                        }
                      )
                    );
                };
              }
            )
            (
              { config, ... }:

              {
                virtualisation.vmVariant = {
                  virtualisation.sharedDirectories.persist = {
                    source = config._.persist.root;
                    target = config._.persist.root;
                  };
                };
                virtualisation.vmVariantWithBootLoader.virtualisation = {
                  inherit (config.virtualisation.vmVariant.virtualisation) sharedDirectories;
                };
              }
            )
            (
              { lib, config, ... }:

              let
                inherit (lib) mkOption types;
                cfg = config._.persist;
                allUsersPersistModule =
                  with types;
                  submodule (_: {
                    options = {
                      directories = mkOption {
                        type = listOf str;
                        default = [ ];
                      };
                      files = mkOption {
                        type = listOf str;
                        default = [ ];
                      };
                    };
                  });
                usersPersistModule =
                  with types;
                  submodule (_: {
                    options = {
                      directories = mkOption {
                        type = listOf str;
                        apply = orig: orig ++ cfg.allUsers.directories;
                      };
                      files = mkOption {
                        type = listOf str;
                        apply = orig: orig ++ cfg.allUsers.files;
                      };
                    };
                  });
              in
              {
                options._.persist = {
                  users = mkOption {
                    type = types.attrsOf usersPersistModule;
                  };
                  allUsers = mkOption {
                    type = allUsersPersistModule;
                  };
                };
                config = {
                  environment.persistence.${cfg.root} = {
                    inherit (cfg) users;
                  };
                };
              }
            )
            home-manager.nixosModules.home-manager
            {
              home-manager.sharedModules = [
                (
                  { pkgs, ... }:

                  {
                    programs.zsh.initExtraFirst = ''
                      # Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
                      # Initialization code that may require console input (password prompts, [y/n]
                      # confirmations, etc.) must go above this block; everything else may go below.
                      if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
                        source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
                      fi

                      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
                      source ${./p10k.zsh}
                    '';
                  }
                )
                (
                  {
                    pkgs,
                    ...
                  }:

                  {
                    programs.zsh = {
                      enable = true;
                      enableVteIntegration = true;
                      autosuggestion.enable = true;
                      autocd = true;
                      dotDir = ".config/zsh";
                      plugins = [
                        {
                          name = "fast-syntax-highlighting";
                          src = "${pkgs.zsh-fast-syntax-highlighting}/share/zsh/site-functions";
                        }
                      ];
                    };

                    home.packages = with pkgs; [
                      meslo-lgs-nf
                    ];
                  }
                )
                (
                  { nixosConfig, config, ... }:

                  {
                    programs.zsh.history = {
                      append = true;
                      expireDuplicatesFirst = true;
                      extended = true;
                      save = 100000;
                      size = 100000;
                      # we write the history immediately to our persistence directory
                      path = "${nixosConfig._.persist.root}${config.home.homeDirectory}/${config.programs.zsh.dotDir}/.zsh_history";
                    };
                  }
                )
                {
                  programs.zsh.initExtra = ''
                    # in order to use #, ~ and ^ for filename generation grep word
                    # *~(*.gz|*.bz|*.bz2|*.zip|*.Z) -> searches for word not in compressed files
                    # don't forget to quote '^', '~' and '#'!
                    setopt extendedglob

                    # display PID when suspending processes as well
                    setopt longlistjobs

                    # report the status of backgrounds jobs immediately
                    setopt notify

                    # whenever a command completion is attempted, make sure the entire command path
                    # is hashed first.
                    setopt hash_list_all

                    # not just at the end
                    setopt completeinword

                    # Don't send SIGHUP to background processes when the shell exits.
                    setopt nohup

                    # make cd push the old directory onto the directory stack.
                    setopt auto_pushd

                    # avoid "beep"ing
                    setopt nobeep

                    # don't push the same dir twice.
                    setopt pushd_ignore_dups

                    # * shouldn't match dotfiles. ever.
                    setopt noglobdots

                    # use zsh style word splitting
                    setopt noshwordsplit

                    # don't error out when unset parameters are used
                    setopt unset

                    # allow one error for every three characters typed in approximate completer
                    zstyle ':completion:*:approximate:'    max-errors 'reply=( $((($#PREFIX+$#SUFFIX)/3 )) numeric )'

                    # don't complete backup files as executables
                    zstyle ':completion:*:complete:-command-::commands' ignored-patterns '(aptitude-*|*\~)'

                    # start menu completion only if it could find no unambiguous initial string
                    zstyle ':completion:*:correct:*'       insert-unambiguous true
                    zstyle ':completion:*:corrections'     format $'%{\e[0;31m%}%d (errors: %e)%{\e[0m%}'
                    zstyle ':completion:*:correct:*'       original true

                    # activate color-completion
                    zstyle ':completion:*:default'         list-colors ''${(s.:.)LS_COLORS}

                    # format on completion
                    zstyle ':completion:*:descriptions'    format $'%{\e[0;31m%}completing %B%d%b%{\e[0m%}'

                    # automatically complete 'cd -<tab>' and 'cd -<ctrl-d>' with menu
                    # zstyle ':completion:*:*:cd:*:directory-stack' menu yes select

                    # insert all expansions for expand completer
                    zstyle ':completion:*:expand:*'        tag-order all-expansions
                    zstyle ':completion:*:history-words'   list false

                    # activate menu
                    zstyle ':completion:*:history-words'   menu yes

                    # ignore duplicate entries
                    zstyle ':completion:*:history-words'   remove-all-dups yes
                    zstyle ':completion:*:history-words'   stop yes

                    # match uppercase from lowercase
                    zstyle ':completion:*'                 matcher-list 'm:{a-z}={A-Z}'

                    # separate matches into groups
                    zstyle ':completion:*:matches'         group 'yes'
                    zstyle ':completion:*'                 group-name ""

                    # if there are more than 5 options allow selecting from a menu
                    zstyle ':completion:*'                 menu select=5

                    zstyle ':completion:*:messages'        format '%d'
                    zstyle ':completion:*:options'         auto-description '%d'

                    # describe options in full
                    zstyle ':completion:*:options'         description 'yes'

                    # on processes completion complete all user processes
                    zstyle ':completion:*:processes'       command 'ps -au$USER'

                    # offer indexes before parameters in subscripts
                    zstyle ':completion:*:*:-subscript-:*' tag-order indexes parameters

                    # provide verbose completion information
                    zstyle ':completion:*'                 verbose true

                    # recent (as of Dec 2007) zsh versions are able to provide descriptions
                    # for commands (read: 1st word in the line) that it will list for the user
                    # to choose from. The following disables that, because it's not exactly fast.
                    zstyle ':completion:*:-command-:*:'    verbose false

                    # set format for warnings
                    zstyle ':completion:*:warnings'        format $'%{\e[0;31m%}No matches for:%{\e[0m%} %d'

                    # define files to ignore for zcompile
                    zstyle ':completion:*:*:zcompile:*'    ignored-patterns '(*~|*.zwc)'
                    zstyle ':completion:correct:'          prompt 'correct to: %e'

                    # Ignore completion functions for commands you don't have:
                    zstyle ':completion::(^approximate*):*:functions' ignored-patterns '_*'

                    # Provide more processes in completion of programs like killall:
                    zstyle ':completion:*:processes-names' command 'ps c -u ''${USER} -o command | sort -u'

                    # complete manual by their section
                    zstyle ':completion:*:manuals'    separate-sections true
                    zstyle ':completion:*:manuals.*'  insert-sections   true
                    zstyle ':completion:*:man:*'      menu yes select

                    function bind2maps () {
                        local i sequence widget
                        local -a maps

                        while [[ "$1" != "--" ]]; do
                            maps+=( "$1" )
                            shift
                        done
                        shift

                        if [[ "$1" == "-s" ]]; then
                            shift
                            sequence="$1"
                        else
                            sequence="''${key[$1]}"
                        fi
                        widget="$2"

                        [[ -z "$sequence" ]] && return 1

                        for i in "''${maps[@]}"; do
                            bindkey -M "$i" "$sequence" "$widget"
                        done
                    }

                    typeset -A key
                    key=(
                        Home     "''${terminfo[khome]}"
                        End      "''${terminfo[kend]}"
                        Insert   "''${terminfo[kich1]}"
                        Delete   "''${terminfo[kdch1]}"
                        Up       "''${terminfo[kcuu1]}"
                        Down     "''${terminfo[kcud1]}"
                        Left     "''${terminfo[kcub1]}"
                        Right    "''${terminfo[kcuf1]}"
                        PageUp   "''${terminfo[kpp]}"
                        PageDown "''${terminfo[knp]}"
                        BackTab  "''${terminfo[kcbt]}"
                    )

                    # Guidelines for adding key bindings:
                    #
                    #   - Do not add hardcoded escape sequences, to enable non standard key
                    #     combinations such as Ctrl-Meta-Left-Cursor. They are not easily portable.
                    #
                    #   - Adding Ctrl characters, such as '^b' is okay; note that '^b' and '^B' are
                    #     the same key.
                    #
                    #   - All keys from the $key[] mapping are obviously okay.
                    #
                    #   - Most terminals send "ESC x" when Meta-x is pressed. Thus, sequences like
                    #     '\ex' are allowed in here as well.

                    bind2maps emacs             -- Home   beginning-of-somewhere
                    bind2maps       viins vicmd -- Home   vi-beginning-of-line
                    bind2maps emacs             -- End    end-of-somewhere
                    bind2maps       viins vicmd -- End    vi-end-of-line
                    bind2maps emacs viins       -- Insert overwrite-mode
                    bind2maps             vicmd -- Insert vi-insert
                    bind2maps emacs             -- Delete delete-char
                    bind2maps       viins vicmd -- Delete vi-delete-char
                    bind2maps emacs viins vicmd -- Up     up-line-or-search
                    bind2maps emacs viins vicmd -- Down   down-line-or-search
                    bind2maps emacs             -- Left   backward-char
                    bind2maps       viins vicmd -- Left   vi-backward-char
                    bind2maps emacs             -- Right  forward-char
                    bind2maps       viins vicmd -- Right  vi-forward-char
                    #k# Perform abbreviation expansion
                    bind2maps emacs viins       -- -s '^x.' zleiab
                    #k# Display list of abbreviations that would expand
                    bind2maps emacs viins       -- -s '^xb' help-show-abk
                    #k# mkdir -p <dir> from string under cursor or marked area
                    bind2maps emacs viins       -- -s '^xM' inplaceMkDirs
                    #k# display help for keybindings and ZLE
                    bind2maps emacs viins       -- -s '^xz' help-zle
                    #k# Insert files and test globbing
                    bind2maps emacs viins       -- -s "^xf" insert-files
                    #k# Edit the current line in \kbd{\$EDITOR}
                    bind2maps emacs viins       -- -s '\ee' edit-command-line
                    #k# search history backward for entry beginning with typed text
                    bind2maps emacs viins       -- -s '^xp' history-beginning-search-backward-end
                    #k# search history forward for entry beginning with typed text
                    bind2maps emacs viins       -- -s '^xP' history-beginning-search-forward-end
                    #k# search history backward for entry beginning with typed text
                    bind2maps emacs viins       -- PageUp history-beginning-search-backward-end
                    #k# search history forward for entry beginning with typed text
                    bind2maps emacs viins       -- PageDown history-beginning-search-forward-end
                    bind2maps emacs viins       -- -s "^x^h" commit-to-history
                    #k# Kill left-side word or everything up to next slash
                    bind2maps emacs viins       -- -s '\ev' slash-backward-kill-word
                    #k# Kill left-side word or everything up to next slash
                    bind2maps emacs viins       -- -s '\e^h' slash-backward-kill-word
                    #k# Kill left-side word or everything up to next slash
                    bind2maps emacs viins       -- -s '\e^?' slash-backward-kill-word
                    # Do history expansion on space:
                    bind2maps emacs viins       -- -s ' ' magic-space
                    #k# Trigger menu-complete
                    bind2maps emacs viins       -- -s '\ei' menu-complete  # menu completion via esc-i
                    #k# Insert a timestamp on the command line (yyyy-mm-dd)
                    bind2maps emacs viins       -- -s '^xd' insert-datestamp
                    #k# Insert last typed word
                    bind2maps emacs viins       -- -s "\em" insert-last-typed-word
                    #k# A smart shortcut for \kbd{fg<enter>}
                    bind2maps emacs viins       -- -s '^z' grml-zsh-fg
                    #k# prepend the current command with "sudo"
                    bind2maps emacs viins       -- -s "^os" sudo-command-line
                    #k# jump to after first word (for adding options)
                    bind2maps emacs viins       -- -s '^x1' jump_after_first_word
                    #k# complete word from history with menu
                    bind2maps emacs viins       -- -s "^x^x" hist-complete

                    zmodload -i zsh/complist
                    #m# k Shift-tab Perform backwards menu completion
                    bind2maps menuselect -- BackTab reverse-menu-complete

                    #k# menu selection: pick item but stay in the menu
                    bind2maps menuselect -- -s '\e^M' accept-and-menu-complete
                    # also use + and INSERT since it's easier to press repeatedly
                    bind2maps menuselect -- -s '+' accept-and-menu-complete
                    bind2maps menuselect -- Insert accept-and-menu-complete

                    # accept a completion and try to complete again by using menu
                    # completion; very useful with completing directories
                    # by using 'undo' one's got a simple file browser
                    bind2maps menuselect -- -s '^o' accept-and-infer-next-history

                    bind2maps emacs viins vicmd -- -s '\e[1;5C' forward-word
                    bind2maps emacs viins vicmd -- -s '\e[1;5D' backward-word
                  '';
                }
                {
                  programs.zsh.initExtra = ''
                    go-up () {
                      cd ..
                      _p9k_on_widget_send-break
                    }; zle -N go-up

                    bindkey '^[u' go-up
                  '';
                }
                {
                  programs.zoxide.enable = true;
                }
                {
                  xdg.userDirs = {
                    enable = true;
                    createDirectories = true;
                  };
                }
                (
                  { pkgs, ... }:

                  {
                    home.packages = with pkgs; [
                      virt-manager
                      virt-viewer
                    ];
                    dconf.settings."org/virt-manager/virt-manager/connections" = {
                      autoconnect = [ "qemu:///system" ];
                      uris = [ "qemu:///system" ];
                    };
                  }
                )
                (
                  {
                    lib,
                    pkgs,
                    config,
                    ...
                  }:

                  {
                    programs.niri.settings = {
                      spawn-at-startup = [
                        {
                          command = [
                            (lib.getExe pkgs.swaybg)
                            "--image"
                            "${config.stylix.image}"
                            "--mode"
                            config.stylix.imageScalingMode
                          ];
                        }
                      ];
                    };
                  }
                )
                (
                  { nixosConfig, config, ... }:

                  {
                    programs.ssh = {
                      enable = true;
                      userKnownHostsFile = "${nixosConfig._.persist.root}${config.home.homeDirectory}/.ssh/known_hosts";
                    };
                  }
                )
                {
                  programs.ripgrep = {
                    enable = true;
                    arguments = [
                      "--smart-case"
                      "--no-heading"
                    ];
                  };
                }
                (
                  {
                    lib,
                    pkgs,
                    config,
                    nixosConfig,
                    ...
                  }:

                  {
                    programs.niri.settings = {
                      prefer-no-csd = true;
                      input = {
                        focus-follows-mouse = {
                          enable = true;
                          max-scroll-amount = "0%";
                        };
                        keyboard.xkb = with nixosConfig.services.xserver.xkb; {
                          inherit variant layout options;
                        };
                      };
                      binds =
                        with config.lib.niri.actions;
                        let
                          mod = if nixosConfig.virtualisation ? qemu then "Alt" else "Mod";
                        in
                        {
                          "${mod}+Shift+Slash".action = show-hotkey-overlay;
                          "${mod}+D".action = spawn "fuzzel";
                          "${mod}+Return".action = spawn "kitty";
                          "Super+Alt+L".action =
                            spawn "sh" "-c"
                              "systemctl --user kill --signal SIGUSR1 swayidle.service && niri msg action power-off-monitors";
                          XF86AudioRaiseVolume.action = spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1+";
                          XF86AudioLowerVolume.action = spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1-";
                          XF86AudioMute.action = spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle";
                          XF86AudioMicMute.action = spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle";

                          "${mod}+Shift+Q".action = close-window;
                          "${mod}+Left".action = focus-column-left;
                          "${mod}+Down".action = focus-window-down;
                          "${mod}+Up".action = focus-window-up;
                          "${mod}+Right".action = focus-column-right;
                          "${mod}+H".action = focus-column-left;
                          "${mod}+J".action = focus-window-down;
                          "${mod}+K".action = focus-window-up;
                          "${mod}+L".action = focus-column-right;

                          "${mod}+Ctrl+Left".action = move-column-left-or-to-monitor-left;
                          "${mod}+Ctrl+Down".action = move-window-down-or-to-workspace-down;
                          "${mod}+Ctrl+Up".action = move-window-up-or-to-workspace-up;
                          "${mod}+Ctrl+Right".action = move-column-right-or-to-monitor-right;
                          "${mod}+Ctrl+H".action = move-column-left-or-to-monitor-left;
                          "${mod}+Ctrl+J".action = move-window-down-or-to-workspace-down;
                          "${mod}+Ctrl+K".action = move-window-up-or-to-workspace-up;
                          "${mod}+Ctrl+L".action = move-column-right-or-to-monitor-right;

                          "${mod}+Home".action = focus-column-first;
                          "${mod}+End".action = focus-column-last;
                          "${mod}+Ctrl+Home".action = move-column-to-first;
                          "${mod}+Ctrl+End".action = move-column-to-last;

                          "${mod}+Shift+Left".action = focus-monitor-left;
                          "${mod}+Shift+Down".action = focus-monitor-down;
                          "${mod}+Shift+Up".action = focus-monitor-up;
                          "${mod}+Shift+Right".action = focus-monitor-right;
                          "${mod}+Shift+H".action = focus-monitor-left;
                          "${mod}+Shift+J".action = focus-monitor-down;
                          "${mod}+Shift+K".action = focus-monitor-up;
                          "${mod}+Shift+L".action = focus-monitor-right;

                          "${mod}+Shift+Ctrl+Left".action = move-column-to-monitor-left;
                          "${mod}+Shift+Ctrl+Down".action = move-column-to-monitor-down;
                          "${mod}+Shift+Ctrl+Up".action = move-column-to-monitor-up;
                          "${mod}+Shift+Ctrl+Right".action = move-column-to-monitor-right;
                          "${mod}+Shift+Ctrl+H".action = move-column-to-monitor-left;
                          "${mod}+Shift+Ctrl+J".action = move-column-to-monitor-down;
                          "${mod}+Shift+Ctrl+K".action = move-column-to-monitor-up;
                          "${mod}+Shift+Ctrl+L".action = move-column-to-monitor-right;

                          # // Alternatively, there are commands to move just a single window:
                          # // ${mod}+Shift+Ctrl+Left  { move-window-to-monitor-left; }
                          # // ...

                          # // And you can also move a whole workspace to another monitor:
                          # // ${mod}+Shift+Ctrl+Left  { move-workspace-to-monitor-left; }
                          # // ...

                          "${mod}+Page_Down".action = focus-workspace-down;
                          "${mod}+Page_Up".action = focus-workspace-up;
                          "${mod}+U".action = focus-workspace-down;
                          "${mod}+I".action = focus-workspace-up;
                          "${mod}+Ctrl+Page_Down".action = move-column-to-workspace-down;
                          "${mod}+Ctrl+Page_Up".action = move-column-to-workspace-up;
                          "${mod}+Ctrl+U".action = move-column-to-workspace-down;
                          "${mod}+Ctrl+I".action = move-column-to-workspace-up;
                          # // Alternatively, there are commands to move just a single window:
                          # // ${mod}+Ctrl+Page_Down { move-window-to-workspace-down; }
                          # // ...

                          "${mod}+Shift+Page_Down".action = move-workspace-down;
                          "${mod}+Shift+Page_Up".action = move-workspace-up;
                          "${mod}+Shift+U".action = move-workspace-down;
                          "${mod}+Shift+I".action = move-workspace-up;

                          # // You can bind mouse wheel scroll ticks using the following syntax.
                          # // These binds will change direction based on the natural-scroll setting.
                          # //
                          # // To avoid scrolling through workspaces really fast, you can use
                          # // the cooldown-ms property. The bind will be rate-limited to this value.
                          # // You can set a cooldown on any bind, but it's most useful for the wheel.
                          "${mod}+WheelScrollDown" = {
                            action = focus-workspace-down;
                            cooldown-ms = 150;
                          };
                          "${mod}+WheelScrollUp" = {
                            action = focus-workspace-up;
                            cooldown-ms = 150;
                          };
                          "${mod}+Ctrl+WheelScrollDown" = {
                            action = move-column-to-workspace-down;
                            cooldown-ms = 150;
                          };
                          "${mod}+Ctrl+WheelScrollUp" = {
                            action = move-column-to-workspace-up;
                            cooldown-ms = 150;
                          };

                          "${mod}+WheelScrollRight".action = focus-column-right;
                          "${mod}+WheelScrollLeft".action = focus-column-left;
                          "${mod}+Ctrl+WheelScrollRight".action = move-column-right;
                          "${mod}+Ctrl+WheelScrollLeft".action = move-column-left;

                          # // Usually scrolling up and down with Shift in applications results in
                          # // horizontal scrolling; these binds replicate that.
                          "${mod}+Shift+WheelScrollDown".action = focus-column-right;
                          "${mod}+Shift+WheelScrollUp".action = focus-column-left;
                          "${mod}+Ctrl+Shift+WheelScrollDown".action = move-column-right;
                          "${mod}+Ctrl+Shift+WheelScrollUp".action = move-column-left;

                          # // Similarly, you can bind touchpad scroll "ticks".
                          # // Touchpad scrolling is continuous, so for these binds it is split into
                          # // discrete intervals.
                          # // These binds are also affected by touchpad's natural-scroll, so these
                          # // example binds are "inverted", since we have natural-scroll enabled for
                          # // touchpads by default.
                          # // ${mod}+TouchpadScrollDown { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.02+"; }
                          # // ${mod}+TouchpadScrollUp   { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.02-"; }

                          # // You can refer to workspaces by index. However, keep in mind that
                          # // niri is a dynamic workspace system, so these commands are kind of
                          # // "best effort". Trying to refer to a workspace index bigger than
                          # // the current workspace count will instead refer to the bottommost
                          # // (empty) workspace.
                          # //
                          # // For example, with 2 workspaces + 1 empty, indices 3, 4, 5 and so on
                          # // will all refer to the 3rd workspace.
                          "${mod}+1".action = focus-workspace 1;
                          "${mod}+2".action = focus-workspace 2;
                          "${mod}+3".action = focus-workspace 3;
                          "${mod}+4".action = focus-workspace 4;
                          "${mod}+5".action = focus-workspace 5;
                          "${mod}+6".action = focus-workspace 6;
                          "${mod}+7".action = focus-workspace 7;
                          "${mod}+8".action = focus-workspace 8;
                          "${mod}+9".action = focus-workspace 9;
                          "${mod}+Ctrl+1".action = move-column-to-workspace 1;
                          "${mod}+Ctrl+2".action = move-column-to-workspace 2;
                          "${mod}+Ctrl+3".action = move-column-to-workspace 3;
                          "${mod}+Ctrl+4".action = move-column-to-workspace 4;
                          "${mod}+Ctrl+5".action = move-column-to-workspace 5;
                          "${mod}+Ctrl+6".action = move-column-to-workspace 6;
                          "${mod}+Ctrl+7".action = move-column-to-workspace 7;
                          "${mod}+Ctrl+8".action = move-column-to-workspace 8;
                          "${mod}+Ctrl+9".action = move-column-to-workspace 9;

                          # // Alternatively, there are commands to move just a single window:
                          # // ${mod}+Ctrl+1 { move-window-to-workspace 1; }

                          # // Switches focus between the current and the previous workspace.
                          # // ${mod}+Tab { focus-workspace-previous; }

                          "${mod}+Comma".action = consume-window-into-column;
                          "${mod}+Period".action = expel-window-from-column;

                          # There are also commands that consume or expel a single window to the side.
                          "${mod}+BracketLeft".action = consume-or-expel-window-left;
                          "${mod}+BracketRight".action = consume-or-expel-window-right;

                          "${mod}+R".action = switch-preset-column-width;
                          "${mod}+Shift+R".action = reset-window-height;
                          "${mod}+F".action = maximize-column;
                          "${mod}+Shift+F".action = fullscreen-window;
                          "${mod}+C".action = center-column;

                          # // Finer width adjustments.
                          # // This command can also:
                          # // * set width in pixels: "1000"
                          # // * adjust width in pixels: "-5" or "+5"
                          # // * set width as a percentage of screen width: "25%"
                          # // * adjust width as a percentage of screen width: "-10%" or "+10%"
                          # // Pixel sizes use logical, or scaled, pixels. I.e. on an output with scale 2.0,
                          # // set-column-width "100" will make the column occupy 200 physical screen pixels.
                          "${mod}+Minus".action = set-column-width "-10%";
                          "${mod}+Equal".action = set-column-width "+10%";

                          # // Finer height adjustments when in column with other windows.
                          "${mod}+Shift+Minus".action = set-window-height "-10%";
                          "${mod}+Shift+Equal".action = set-window-height "+10%";

                          # // Actions to switch layouts.
                          # // Note: if you uncomment these, make sure you do NOT have
                          # // a matching layout switch hotkey configured in xkb options above.
                          # // Having both at once on the same hotkey will break the switching,
                          # // since it will switch twice upon pressing the hotkey (once by xkb, once by niri).
                          # // ${mod}+Space       { switch-layout "next"; }
                          # // ${mod}+Shift+Space { switch-layout "prev"; }

                          "Print".action = screenshot;
                          "Ctrl+Print".action = screenshot-screen;
                          "Alt+Print".action = screenshot-window;

                          # // The quit action will show a confirmation dialog to avoid accidental exits.
                          "${mod}+Shift+E".action = quit;

                          # // Powers off the monitors. To turn them back on, do any input like
                          # // moving the mouse or pressing any other key.
                          "${mod}+Shift+P".action = power-off-monitors;
                        };
                      spawn-at-startup = [
                        { command = [ "waybar" ]; }
                        { command = [ "${lib.getExe pkgs.xwayland-satellite}" ]; }
                      ];
                      environment."DISPLAY" = ":0";
                    };
                  }
                )
                (
                  { lib, pkgs, ... }:

                  {
                    programs.waybar = {
                      enable = true;
                      settings = [
                        {
                          layer = "top";
                          position = "top";

                          modules-left = [ "niri/workspaces" ];
                          modules-center = [ "niri/window" ];
                          modules-right = [
                            "idle_inhibitor"
                            "niri/language"
                            "pulseaudio"
                            "disk"
                            "battery"
                            "tray"
                            "clock"
                          ];

                          "niri/workspaces" = {
                            format = "{icon}";
                            format-icons = {
                              active = "󰪥";
                              default = "󰄰";
                            };
                          };

                          "niri/window" = {
                            icon = true;
                          };

                          idle_inhibitor = {
                            format = "{icon}";
                            format-icons = {
                              activated = "";
                              deactivated = "";
                            };
                          };

                          "niri/language" = {
                            format = "{short} {variant}";
                          };

                          "pulseaudio" = {
                            format = "{icon}";
                            format-bluetooth = "{icon} ";
                            format-muted = "󰝟";
                            format-icons = {
                              headphone = "";
                              default = [
                                ""
                                ""
                              ];
                            };
                            scroll-step = 1;
                            on-click = "${lib.getExe pkgs.pwvucontrol}";
                          };

                          clock = {
                            format = "{:%H:%M}  ";
                            format-alt = "{:%A; %B %d, %Y (%R)}  ";
                            tooltip-format = "<tt><small>{calendar}</small></tt>";
                            calendar = {
                              "mode" = "year";
                              mode-mon-col = 3;
                              weeks-pos = "right";
                              on-scroll = 1;
                              on-click-right = "mode";
                              format = {
                                "months" = "<span color='#ffead3'><b>{}</b></span>";
                                days = "<span color='#ecc6d9'><b>{}</b></span>";
                                weeks = "<span color='#99ffdd'><b>W{}</b></span>";
                                weekdays = "<span color='#ffcc66'><b>{}</b></span>";
                                today = "<span color='#ff6699'><b><u>{}</u></b></span>";
                              };
                            };
                            actions = {
                              on-click-right = "mode";
                              on-click-forward = "tz_up";
                              on-click-backward = "tz_down";
                              on-scroll-up = "shift_up";
                              on-scroll-down = "shift_down";
                            };
                          };

                          battery = {
                            format = "{icon}";

                            format-icons = [
                              "󰁺"
                              "󰁻"
                              "󰁼"
                              "󰁽"
                              "󰁾"
                              "󰁿"
                              "󰂀"
                              "󰂁"
                              "󰂂"
                              "󰁹"
                            ];
                            states = {
                              battery-10 = 10;
                              battery-20 = 20;
                              battery-30 = 30;
                              battery-40 = 40;
                              battery-50 = 50;
                              battery-60 = 60;
                              battery-70 = 70;
                              battery-80 = 80;
                              battery-90 = 90;
                              battery-100 = 100;
                            };

                            format-plugged = "󰚥";
                            format-charging-battery-10 = "󰢜";
                            format-charging-battery-20 = "󰂆";
                            format-charging-battery-30 = "󰂇";
                            format-charging-battery-40 = "󰂈";
                            format-charging-battery-50 = "󰢝";
                            format-charging-battery-60 = "󰂉";
                            format-charging-battery-70 = "󰢞";
                            format-charging-battery-80 = "󰂊";
                            format-charging-battery-90 = "󰂋";
                            format-charging-battery-100 = "󰂅";
                            tooltip-format = "{capacity}% {timeTo}";
                          };

                          tray = {
                            icon-size = 21;
                            spacing = 10;
                          };
                        }
                      ];
                    };
                  }
                )
                {
                  programs.fuzzel.enable = true;
                }
                {
                  programs.swaylock.enable = true;
                }
                (
                  {
                    lib,
                    pkgs,
                    config,
                    ...
                  }:

                  {
                    services.swayidle =
                      let
                        lock = "${lib.getExe config.programs.swaylock.package} --daemonize";
                        dpms = "${lib.getExe config.programs.niri.package} msg action power-off-monitors";
                        notify = "${pkgs.libnotify}/bin/notify-send -u critical -t 10000 -i system-lock-screen 'Screen will be locked in 10 seconds...'";
                      in
                      {
                        enable = true;
                        events = [
                          {
                            event = "lock";
                            command = lock;
                          }
                          {
                            event = "before-sleep";
                            command = lock;
                          }
                        ];
                        timeouts = [
                          {
                            timeout = 290;
                            command = notify;
                          }
                          {
                            timeout = 300;
                            command = lock;
                          }
                          {
                            timeout = 310;
                            command = dpms;
                          }
                        ];
                        systemdTarget = "graphical-session.target";
                      };
                    # make sure, that graphical-session is actually started _before_ trying to activate swayidle
                    systemd.user.services.swayidle.Unit.After = [ "graphical-session.target" ];
                  }
                )
                (
                  { lib, pkgs, ... }:

                  {
                    programs.kitty = {
                      enable = true;
                      keybindings."ctrl+shift+p>n" = ''kitten hints --type=linenum --linenum-action=window ${lib.getExe pkgs.bat} --pager "less --RAW-CONTROL-CHARS +{line}" -H {line} {path}'';
                      settings = {
                        select_by_word_characters = "@-./_~?&%+#";
                        scrollback_lines = 20000;
                        scrollback_pager_history_size = 20; # 10k line / MiB
                      };
                    };

                    programs.zsh.initExtra = ''
                      ssh() {
                        TERM=''${TERM/-kitty/-256color} command ssh "$@"
                      }
                    '';
                  }
                )
                {
                  stylix.targets.kitty.variant256Colors = true;
                }
                (
                  { config, ... }:
                  {
                    programs.jujutsu = {
                      enable = true;
                      settings = {
                        user.name = config.programs.git.userName;
                        user.email = config.programs.git.userEmail;
                      };
                    };
                  }
                )
                {
                  home.stateVersion = "24.11";
                }
                (
                  { pkgs, ... }:

                  {
                    programs.gpg.enable = true;
                    services.gpg-agent = {
                      enable = true;
                      enableSshSupport = true;
                      pinentryPackage = pkgs.pinentry-gnome3;
                    };
                  }
                )
                {
                  programs.git = {
                    enable = true;
                    lfs.enable = true;
                  };
                }
                (
                  { pkgs, ... }:

                  {
                    programs.firefox = {
                      enable = true;
                      package =
                        with pkgs;
                        firefox.override {
                          nativeMessagingHosts = [
                            tridactyl-native
                          ];
                        };
                    };
                  }
                )
                {
                  programs.fd.enable = true;
                }
                {
                  programs.direnv = {
                    enable = true;
                    nix-direnv.enable = true;
                  };
                }
                {
                  programs.bat.enable = true;
                }
                {
                  programs.atuin = {
                    enable = true;
                    flags = [ "--disable-up-arrow" ];
                    settings = {
                      filter_mode = "directory";
                      inline_height = 30;
                      search_mode_shell_up_key_binding = "prefix";
                      filter_mode_shell_up_key_binding = "directory";
                      show_preview = true;
                      style = "compact";
                    };
                  };
                }
                (
                  { lib, pkgs, ... }:

                  {
                    programs.atuin.settings.daemon = {
                      enabled = true;
                      systemd_socket = true;
                    };

                    systemd.user.services."atuin-daemon" = {
                      Service = {
                        ExecStart = "${lib.getExe pkgs.atuin} daemon";
                      };
                    };
                    systemd.user.sockets."atuin-daemon" = {
                      Socket = {
                        ListenStream = "%D/atuin/atuin.sock";
                      };
                      Install = {
                        WantedBy = [ "sockets.target" ];
                      };
                    };
                  }
                )
              ];
            }
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
            (
              { lib, config, ... }:

              {
                system.extraSystemBuilderCmds = ''
                  mkdir -p $out/home-manager
                  ${lib.concatStringsSep "\n" (
                    map (cfg: "ln -sn ${cfg.home.activationPackage} $out/home-manager/${cfg.home.username}") (
                      lib.attrValues config.home-manager.users
                    )
                  )}
                '';
              }
            )
            (private.nixosModules.default or { })
            (
              {
                config,
                lib,
                pkgs,
                ...
              }:

              {
                services.greetd = {
                  enable = true;
                  settings.default_session.command =
                    let
                      niri-config = pkgs.writeText "niri-greeter.kdl" ''
                        input {
                            keyboard {
                                xkb {
                                    layout "${config.services.xserver.xkb.layout}"
                                    options "${config.services.xserver.xkb.options}"
                                }
                            }

                        }
                        hotkey-overlay {
                            skip-at-startup
                        }
                      '';
                    in
                    "${lib.getExe pkgs.niri} -c ${niri-config} -- ${lib.getExe config.programs.regreet.package}";
                };
                programs.regreet.enable = true;
              }
            )
            {
              _.persist.allUsers.directories = [ ".mozilla" ];
            }
            disko.nixosModules.disko
            {
              _.persist.allUsers.directories = [ ".local/share/direnv" ];
            }
            {
              _.persist.allUsers.directories = [ ".local/share/atuin" ];
            }
            {
              programs._1password.enable = true;
              programs._1password-gui = {
                enable = true;
                polkitPolicyOwners = [ "vlaci" ];
              };

              _.persist.allUsers.directories = [
                ".config/1Password"
                ".config/op"
              ];
            }
          ] ++ modules;
        };
    };
}
