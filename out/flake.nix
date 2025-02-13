{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    stylix.url = "github:danth/stylix";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    nix-index-database.url = "github:Mic92/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    lix-module.url = "https://git.lix.systems/lix-project/nixos-module/archive/2.92.0.tar.gz";
    lix-module.inputs.nixpkgs.follows = "nixpkgs";
    niri.url = "github:sodiboo/niri-flake";
    impermanence.url = "github:nix-community/impermanence";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    private.url = "github:vlaci/empty-flake";
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    once = {
      url = "github:emacs-magus/once";
      flake = false;
    };
    evil-ts-obj = {
      url = "github:vlaci/evil-ts-obj";
      flake = false;
    };
    treesit-jump = {
      url = "github:vlaci/treesit-jump";
      flake = false;
    };
    emacs-lsp-booster = {
      url = "github:blahgeek/emacs-lsp-booster";
      flake = false;
    };
    eglot-booster = {
      url = "github:jdtsmith/eglot-booster";
      flake = false;
    };
    eglot-x = {
      url = "github:nemethf/eglot-x";
      flake = false;
    };
    sideline-eglot = {
      url = "github:emacs-sideline/sideline-eglot";
      flake = false;
    };
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, ... }@inputs:
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
            hardware.enableRedistributableFirmware = true; # wifi
            _.persist.directories = [ "/etc/NetworkManager/system-connections" ];
          }
          {
            boot.tmp = {
              useTmpfs = true;
              tmpfsSize = "100%";
            };
            boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

            system.stateVersion = "24.11";

            home-manager.sharedModules = [
              (
                { pkgs, ... }:

                {
                  home.packages = with pkgs; [
                    slack
                  ];
                  programs.foot.enable = true;
                }
              )
              (
                { pkgs, ... }:

                {
                  home.packages = with pkgs; [
                    (vivaldi.overrideAttrs (super: {
                      postFixup =
                        (super.postFixup or "")
                        + ''
                          substituteInPlace $out/share/applications/vivaldi-stable.desktop \
                            --replace "Exec=$out/bin/vivaldi" "Exec=$out/bin/vivaldi --ozone-platform-hint=auto" \
                        '';
                    }))
                  ];
                }
              )
            ];
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

              services.printing.enable = true;
              _.persist.directories = [ "/var/lib/docker" ];
              _.persist.users.vlaci.files = [ ".docker/config.json" ];
            }
          )
          {
            _.persist.users.vlaci.directories = [ ".config/slack" ];
          }
          {
            _.persist.users.vlaci.directories = [
              ".config/vivaldi"
              ".cache/vivaldi"
            ];
          }
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
        inputs.nixpkgs.lib.nixosSystem {
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
            (
              {
                config,
                pkgs,
                lib,
                ...
              }:
              with lib;

              let
                postProcess = pkgs.writeShellScript "post-process-pam-service.sh" ''
                  set -eu

                  IN="$1"
                  OUT="$2"
                  USE_2FACTOR="$3"
                  U2F_ARGS="$4"

                  if [ -n "$USE_2FACTOR" ]; then
                      sed -n "/^auth.*pam_u2f/{
                          # add pattern space to hold space
                          h
                          :loop
                          # print pattern space and fetch next line
                          n
                          # if we find pam_unix as sufficient we must change it to required
                          # because this rule will go above pam_u2f in that case pam_u2f must be
                          # sufficient as it will go after pam_unix
                          /^auth sufficient.*pam_unix/{
                                      s/auth sufficient/auth required/
                                      p
                                      # exchange pattern space with hold space
                                      x
                                      s#\(auth sufficient .*pam_u2f.so\)#\1 $U2F_ARGS#
                                      bexit
                          }
                          # pam_unix was required, this means that there will be a followup rule
                          # which is sufficient in that case pam_u2f must be required as it will
                          # go before a sufficient rule
                          /^auth required.*pam_unix/{
                                      p
                                      # exchange pattern space with hold space
                                      x
                                      s#auth sufficient \(.*pam_u2f.so\)#auth required \1 $U2F_ARGS#
                                      bexit
                          }
                          # if we haven't found a pam_unix rule processing is aborted
                          \$q1

                          # append line to hold space with newline prepended
                          H
                          # exchange pattern space with hold space
                          x
                          # bubble the first matching rule to the bottom of the hold space
                          s/\([^\n]*\)\n\([^\n]*\)\$/\2\n\1/
                          # exchange pattern space with hold space
                          x
                          bloop
                          }
                          # print remaining contents
                          :exit
                          p" $IN > $OUT || cp $IN $OUT
                  else
                      sed "s#\(^auth .*pam_u2f.so\)#\1 $U2F_ARGS#" $IN > $OUT
                  fi
                '';

                parentConfig = config;
                overrideServices =
                  { name, config, ... }:
                  {
                    options = {
                      use2Factor = mkOption {
                        description = "If set to true u2f is used as 2nd factor.";
                        default = parentConfig.security.pam.use2Factor;
                      };
                      u2fModuleArgs = mkOption {
                        description = "Additional arguments to pass to pam_u2f.so";
                        default = parentConfig.security.pam.u2fModuleArgs;
                      };
                      text = mkOption {
                        apply =
                          svc:
                          builtins.readFile (
                            pkgs.runCommand "pam-${name}-u2f"
                              {
                                inherit svc;
                                passAsFile = [ "svc" ];
                              }
                              ''
                                ${postProcess} \
                                  $svcPath \
                                  $out \
                                  ${
                                    escapeShellArgs [
                                      config.use2Factor
                                      config.u2fModuleArgs
                                    ]
                                  }
                              ''
                          );
                      };
                    };
                  };
              in
              {
                options = {
                  security.pam.services = mkOption {
                    type = with types; attrsOf (submodule overrideServices);
                  };
                  security.pam.u2fModuleArgs = mkOption {
                    description = ''
                      Additional arguments to pass to pam_u2f.so in all pam services.
                      A service definition may override this setting.
                    '';
                    example = ''"cue"'';
                    default = "cue";
                  };
                  security.pam.use2Factor = mkOption {
                    description = ''
                      If set to true u2f is used as 2nd factor in all pam services.
                      A service definition may override this setting.
                    '';
                    default = true;
                  };
                };

                config = {
                  environment.systemPackages = with pkgs; [
                    yubikey-personalization
                    yubikey-personalization-gui
                  ];

                  services.pcscd.enable = true;
                  services.udev.packages = with pkgs; [
                    yubikey-personalization
                  ];

                  security.pam.u2f.enable = true;
                  security.pam.use2Factor = false;
                  security.pam.services."polkit-1".use2Factor = false;
                  security.pam.services."sudo".use2Factor = false;
                };
              }
            )
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
            inputs.stylix.nixosModules.stylix
            (
              { lib, pkgs, ... }:

              {
                stylix = {
                  enable = true;
                  base16Scheme = "${pkgs.base16-schemes}/share/themes/rose-pine-moon.yaml";
                  image = ../assets/aerial-photography-of-mountain-and-river.jpg;
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

                home-manager.sharedModules = [
                  {
                    dconf.settings."org/gnome/desktop/interface".color-scheme = lib.mkForce "prefer-dark";
                  }
                ];

                specialisation.day.configuration = {
                  stylix = {
                    polarity = lib.mkForce "light";
                    base16Scheme = lib.mkForce "${pkgs.base16-schemes}/share/themes/rose-pine-dawn.yaml";
                    cursor.name = lib.mkForce "cz-Hickson-black";
                  };
                  home-manager.sharedModules = [
                    {
                      dconf.settings."org/gnome/desktop/interface".color-scheme = lib.mkOverride 49 "prefer-light";
                    }
                  ];
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
            {
              security.sudo.extraRules = [
                {
                  groups = [ "wheel" ];
                  commands = [
                    {
                      command = "/nix/var/nix/profiles/system/bin/switch-to-configuration test";
                      options = [
                        "SETENV"
                        "NOPASSWD"
                      ];
                    }
                    {
                      command = "/nix/var/nix/profiles/system/specialisation/day/bin/switch-to-configuration test";
                      options = [
                        "SETENV"
                        "NOPASSWD"
                      ];
                    }
                  ];
                }
              ];
            }
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
            inputs.sops-nix.nixosModules.sops
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
            inputs.nix-index-database.nixosModules.nix-index
            {
              programs.command-not-found.enable = false;
              programs.nix-index-database.comma.enable = true;
            }
            inputs.lix-module.nixosModules.default
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
            (
              { pkgs, ... }:

              {
                imports = [ inputs.niri.nixosModules.niri ];
                nixpkgs.overlays = [ inputs.niri.overlays.niri ];
                programs.niri = {
                  enable = true;
                  package = pkgs.niri-unstable;
                };
              }
            )
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
              nixpkgs.config.packageOverrides = self.lib.mkPackages;
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
                  layout = "col-lv,altgr-ceur,us,hu";
                  options = "grp:alt_altgr_toggle, compose:rctrl, caps:escape";
                  extraLayouts."col-lv" = {
                    description = "English/Hungarian (Colemak-DH Ortholinear)";
                    languages = [
                      "eng"
                      "hun"
                    ];
                    symbolsFile = ./keymaps/symbols/col-lv;
                  };
                  extraLayouts."altgr-ceur" = {
                    description = "English/Hungarian (Central European AltGr dead keys)";
                    languages = [
                      "eng"
                      "hun"
                    ];
                    symbolsFile = ./keymaps/symbols/altgr-ceur;
                  };
                };
              }
            )
            inputs.impermanence.nixosModules.impermanence
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
                  submodule (
                    _:
                    {
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
                    }
                  );
                usersPersistModule =
                  with types;
                  submodule (
                    _:
                    {
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
                    }
                  );
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
            inputs.home-manager.nixosModules.home-manager
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
                    # Do history expansion on space:
                    bind2maps emacs viins       -- -s ' ' magic-space
                    #k# Trigger menu-complete
                    bind2maps emacs viins       -- -s '\ei' menu-complete  # menu completion via esc-i
                    #k# Insert a timestamp on the command line (yyyy-mm-dd)

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
                  _:

                  {
                    services.darkman = {
                      enable = true;
                      settings.usegeoclue = true;

                      darkModeScripts.color-scheme-dark = ''
                        sudo /nix/var/nix/profiles/system/bin/switch-to-configuration test
                        echo dark > $XDG_RUNTIME_DIR/color-scheme
                      '';

                      lightModeScripts.color-scheme-light = ''
                        sudo /nix/var/nix/profiles/system/specialisation/day/bin/switch-to-configuration test
                        echo light > $XDG_RUNTIME_DIR/color-scheme
                      '';
                    };
                  }
                )
                (
                  { nixosConfig, config, ... }:

                  {
                    programs.ssh = {
                      enable = true;
                      userKnownHostsFile = "${nixosConfig._.persist.root}${config.home.homeDirectory}/.ssh/known_hosts";
                      controlMaster = "auto";
                      controlPersist = "10m";
                      serverAliveInterval = 300;
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
                            "custom/notification"
                            "tray"
                            "clock"
                          ];

                          "niri/workspaces" = {
                            format = "{icon} {value}";
                            format-icons = {
                              active = "";
                              default = "";
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
                            format = "{short} <sup>{variant}</sup>";
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
                              mode = "year";
                              mode-mon-col = 3;
                              weeks-pos = "right";
                              on-scroll = 1;
                              on-click-right = "mode";
                              format = {
                                months = "<span color='#ffead3'><b>{}</b></span>";
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

                          "custom/notification" = {
                            format = "{icon}  {}  ";
                            tooltip-format = "Left: Open Notification Center\nRight: Toggle Do not Disturb\nMiddle: Clear Notifications";
                            format-icons = {
                              notification = "<span foreground='red'><sup></sup></span>";
                              none = "";
                              dnd-notification = "<span foreground='red'><sup></sup></span>";
                              dnd-none = "";
                              inhibited-notification = "<span foreground='red'><sup></sup></span>";
                              inhibited-none = "";
                              dnd-inhibited-notification = "<span foreground='red'><sup></sup></span>";
                              dnd-inhibited-none = "";
                            };
                            return-type = "json";
                            exec-if = "which swaync-client";
                            exec = "swaync-client -swb";
                            on-click = "swaync-client -t -sw";
                            on-click-right = "swaync-client -d -sw";
                            on-click-middle = "swaync-client -C";
                            escape = true;
                          };

                          tray = {
                            icon-size = 21;
                            spacing = 10;
                          };
                        }
                      ];
                      style = ''
                        #workspaces button {
                            color: @base05;
                        }
                      '';
                    };
                  }
                )
                {
                  programs.fuzzel.enable = true;
                }
                {
                  services.swaync.enable = true;
                }
                (
                  { pkgs, ... }:

                  {
                    home.packages = with pkgs; [
                      wl-clipboard
                    ];
                  }
                )
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
                (
                  { pkgs, ... }:

                  {
                    programs.git = {
                      enable = true;
                      lfs.enable = true;
                      delta.enable = true;
                      aliases = {
                        lol = ''log --graph --pretty=format:"%C(yellow)%h%Creset%C(cyan)%C(bold)%d%Creset %C(cyan)(%cr)%Creset %C(green)%ae%Creset %s"'';
                      };
                      extraConfig = {
                        absorb.maxStack = 50;
                        merge.conflictStyle = "diff3";
                        init.defaultBranch = "main";
                        diff.submodule = "diff";
                        diff.colorMoved = "default";
                        status.submoduleSummary = true;
                      };
                    };

                    home.packages = with pkgs.gitAndTools; [
                      git-absorb
                      git-filter-repo
                      git-remote-gcrypt
                    ];

                    home.shellAliases = {
                      gco = "git checkout";
                      gcp = "git cherry-pick";
                      grb = "git rebase";
                      gst = "git status";
                      gb = "git branch";
                    };
                  }
                )
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
                (
                  { pkgs, ... }:

                  {
                    home.packages = [ pkgs.vlaci-emacs ];
                  }
                )
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
                        ListenStream = "%t/atuin.sock";
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
            (inputs.private.nixosModules.default or { })
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
            {
              _.persist.allUsers.directories = [ ".cache/emacs" ];
            }
            inputs.disko.nixosModules.disko
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
      lib.mkPackages =
        pkgs:
        (builtins.foldl' (acc: v: acc // v) { } [
          {
            vlaci-emacs =
              let
                inherit (pkgs) lib;
                pwd = builtins.getEnv "PWD";
                initDirectory = "${pwd}/out/emacs.d";
                dicts = with pkgs.hunspellDicts; [
                  # See jinx below
                  hu-hu
                  en-us-large
                ];
                dictSearchPath = lib.makeSearchPath "share/hunspell" dicts;
                emacsWithPackages = inputs.emacs-overlay.lib.${pkgs.system}.emacsPackagesFor pkgs.emacs30-pgtk;

                emacs =
                  (emacsWithPackages.overrideScope (
                    lib.composeManyExtensions [
                      (final: _prev: {
                        mkPackage =
                          {
                            pname,
                            src,
                            files ? [ "*.el" ],
                            ...
                          }@args:

                          let
                            files' =
                              let
                                list = lib.concatStringsSep " " (map (f: ''"${lib.escape [ ''"'' ] f}"'') files);
                              in
                              "(${list})";
                            version =
                              let
                                ver = src.lastModifiedDate or inputs.self.lastModifiedDate;
                                removeLeadingZeros =
                                  s:
                                  let
                                    s' = lib.removePrefix "0" s;
                                  in
                                  if lib.hasPrefix "0" s' then removeLeadingZeros s' else s';
                                major = removeLeadingZeros (builtins.substring 0 8 ver);
                                minor = removeLeadingZeros (builtins.substring 8 6 ver);
                              in
                              "${major}.${minor}";
                          in
                          final.melpaBuild (
                            {
                              inherit version src;
                              commit =
                                src.rev or inputs.self.sourceInfo.rev or inputs.self.sourceInfo.dirtyRev
                                  or "00000000000000000000000000000000";
                              recipe = pkgs.writeText "recipe" ''
                                (${pname}
                                :fetcher git
                                :url "nohost.nodomain"
                                :files ${files'})
                              '';
                            }
                            // removeAttrs args [ "files" ]
                          );
                      })
                      (_final: prev: {
                        setup = prev.setup.overrideAttrs (_: {
                          ignoreCompilationError = true;
                        });
                      })
                      (
                        final: _prev:

                        {
                          eglot-booster = final.mkPackage {
                            pname = "eglot-booster";
                            src = inputs.eglot-booster;
                          };
                          eglot-x = final.mkPackage {
                            pname = "eglot-x";
                            src = inputs.eglot-x;
                          };
                          sideline-eglot = final.mkPackage {
                            pname = "sideline-eglot";
                            src = inputs.sideline-eglot;
                            packageRequires = [ final.sideline ];
                          };
                          emacs-lsp-booster = pkgs.rustPlatform.buildRustPackage rec {
                            pname = "emacs-lsp-booster";
                            version = "0.2.1";
                            src = inputs.emacs-lsp-booster;
                            cargoLock = {
                              lockFile = "${src}/Cargo.lock";
                            };
                            doCheck = false;
                          };
                        })
                    ]
                  )).withPackages
                    (
                      epkgs: with epkgs; [
                        org-modern
                        org-roam
                        setup
                        gcmh
                        (mkPackage {
                          pname = "vlaci-emacs";
                          src = pkgs.writeText "vlaci-emacs.el" ''
                            ;;; vlaci-emacs.el --- local extensions -*- lexical-binding: t; -*-

                            (defvar vlaci-incremental-packages '(t)
                              "A list of packages to load incrementally after startup. Any large packages
                            here may cause noticeable pauses, so it's recommended you break them up into
                            sub-packages. For example, `org' is comprised of many packages, and can be
                            broken up into:
                              (vlaci-load-packages-incrementally
                               '(calendar find-func format-spec org-macs org-compat
                                 org-faces org-entities org-list org-pcomplete org-src
                                 org-footnote org-macro ob org org-clock org-agenda
                                 org-capture))
                            This is already done by the lang/org module, however.
                            If you want to disable incremental loading altogether, either remove
                            `doom-load-packages-incrementally-h' from `emacs-startup-hook' or set
                            `doom-incremental-first-idle-timer' to nil.")

                            (defvar vlaci-incremental-first-idle-timer 2.0
                              "How long (in idle seconds) until incremental loading starts.
                            Set this to nil to disable incremental loading.")

                            (defvar vlaci-incremental-idle-timer 0.75
                              "How long (in idle seconds) in between incrementally loading packages.")

                            (defvar vlaci-incremental-load-immediately nil
                              ;; (daemonp)
                              "If non-nil, load all incrementally deferred packages immediately at startup.")

                            (defun vlaci-load-packages-incrementally (packages &optional now)
                              "Registers PACKAGES to be loaded incrementally.
                            If NOW is non-nil, load PACKAGES incrementally, in `doom-incremental-idle-timer'
                            intervals."
                              (if (not now)
                                  (setq vlaci-incremental-packages (append vlaci-incremental-packages packages))
                                (while packages
                                  (let ((req (pop packages)))
                                    (unless (featurep req)
                                      (message "Incrementally loading %s" req)
                                      (condition-case e
                                          (or (while-no-input
                                                ;; If `default-directory' is a directory that doesn't exist
                                                ;; or is unreadable, Emacs throws up file-missing errors, so
                                                ;; we set it to a directory we know exists and is readable.
                                                (let ((default-directory user-emacs-directory)
                                                      (gc-cons-threshold most-positive-fixnum)
                                                      file-name-handler-alist)
                                                  (require req nil t))
                                                t)
                                              (push req packages))
                                        ((error debug)
                                         (message "Failed to load '%s' package incrementally, because: %s"
                                                  req e)))
                                      (if (not packages)
                                          (message "Finished incremental loading")
                                        (run-with-idle-timer vlaci-incremental-idle-timer
                                                             nil #'vlaci-load-packages-incrementally
                                                             packages t)
                                        (setq packages nil)))))))

                            ;;;###autoload
                            (defun vlaci-load-packages-incrementally-h ()
                              "Begin incrementally loading packages in `vlaci-incremental-packages'.
                            If this is a daemon session, load them all immediately instead."
                              (if vlaci-incremental-load-immediately
                                  (mapc #'require (cdr vlaci-incremental-packages))
                                (when (numberp vlaci-incremental-first-idle-timer)
                                  (run-with-idle-timer vlaci-incremental-first-idle-timer
                                                       nil #'vlaci-load-packages-incrementally
                                                       (cdr vlaci-incremental-packages) t))))

                            (add-hook 'emacs-startup-hook #'vlaci-load-packages-incrementally-h)

                            (require 'setup)

                            (setup-define :package
                              (lambda (package))
                              :documentation "Fake installation of PACKAGE."
                              :repeatable t
                              :shorthand #'cadr)

                            (setup-define :defer-incrementally
                              (lambda (&rest targets)
                              (vlaci-load-packages-incrementally targets)
                               :documentation "Load TARGETS incrementally"))
                            ;;;###autoload
                            (defun vlaci-keyboard-quit-dwim ()
                              "Do-What-I-Mean behaviour for a general `keyboard-quit'.

                            The generic `keyboard-quit' does not do the expected thing when
                            the minibuffer is open.  Whereas we want it to close the
                            minibuffer, even without explicitly focusing it.

                            The DWIM behaviour of this command is as follows:

                            - When the region is active, disable it.
                            - When a minibuffer is open, but not focused, close the minibuffer.
                            - When the Completions buffer is selected, close it.
                            - In every other case use the regular `keyboard-quit'."
                              (interactive)
                              (cond
                               ((region-active-p)
                                (keyboard-quit))
                               ((derived-mode-p 'completion-list-mode) ;; Do I need this?
                                (delete-completion-window))
                               ((> (minibuffer-depth) 0)
                                (abort-recursive-edit))
                               (t
                                (keyboard-quit))))
                            (provide 'vlaci-emacs)
                          '';

                          packageRequires = [
                            setup
                          ];
                        })
                        on
                        auto-dark
                        spacious-padding
                        ef-themes
                        doom-modeline
                        repeat-help
                        helpful
                        elisp-demos
                        (mkPackage {
                          pname = "once";
                          src = inputs.once;
                          files = [
                            "*.el"
                            "once-setup/*.el"
                          ];
                          packageRequires = [
                            (setup.overrideAttrs (_: {
                              ignoreCompilationError = true;
                            }))
                          ];
                        })
                        nerd-icons
                        nerd-icons-completion
                        nerd-icons-corfu
                        nerd-icons-dired
                        undo-fu
                        undo-fu-session
                        vundo
                        evil
                        evil-collection
                        devil
                        ace-window
                        avy
                        swiper
                        evil-snipe
                        (mkPackage {
                          pname = "evil-ts-obj";
                          src = inputs.evil-ts-obj;
                          files = [ "lisp/*.el" ];
                          packageRequires = [
                            avy
                            evil
                          ];
                        })
                        (mkPackage {
                          pname = "treesit-jump";
                          src = inputs.treesit-jump;
                          files = [
                            "treesit-jump.el"
                            "treesit-queries"
                          ];
                          packageRequires = [ avy ];
                        })
                        vertico
                        vertico-posframe
                        orderless
                        marginalia
                        consult
                        corfu
                        cape
                        embark
                        embark-consult
                        wgrep
                        (treesit-grammars.with-grammars (
                          grammars:
                          with pkgs.lib;
                          pipe grammars [
                            (filterAttrs (name: _: name != "recurseForDerivations"))
                            builtins.attrValues
                          ]
                        ))
                        treesit-auto
                        eglot-booster
                        eglot-x
                        emacs-lsp-booster
                        dape
                        sideline-flymake
                        sideline-eglot
                        eldev
                        nix-ts-mode
                        markdown-mode
                        just-ts-mode
                        polymode
                        rust-mode
                        dockerfile-mode
                        envrc
                        jinx
                        magit
                        apheleia
                        auth-source-1password
                        gptel
                        chatgpt-shell
                      ]
                    );
                binaries = with pkgs; [
                  basedpyright
                  nil
                  llvmPackages.clang-tools
                  rust-analyzer
                  nixfmt-rfc-style
                  nodePackages.prettier
                ];
              in
              assert lib.assertMsg (pwd != "") "Use --impure flag for building";
              emacs.overrideAttrs (super: {
                # instead of relyiong on `package.el` to wire-up autoloads, do it build-time
                deps = super.deps.overrideAttrs (
                  dsuper:
                  let
                    genAutoloadsCommand = ''
                      echo "-- Generating autoloads..."
                      autoloads=$out/share/emacs/site-lisp/autoloads.el
                      for pkg in "''${requires[@]}"; do
                        autoload=("$pkg"/share/emacs/site-lisp/*/*/*-autoloads.el)
                        if [[ -e "$autoload" ]]; then
                          cat "$autoload" >> "$autoloads"
                        fi
                      done
                      echo "(load \"''$autoloads\")" >> "$siteStart"

                      # Byte-compiling improves start-up time only slightly, but costs nothing.
                      $emacs/bin/emacs --batch -f batch-byte-compile "$autoloads" "$siteStart"

                      $emacs/bin/emacs --batch \
                        --eval "(add-to-list 'native-comp-eln-load-path \"$out/share/emacs/native-lisp/\")" \
                        -f batch-native-compile "$autoloads" "$siteStart"
                    '';
                  in
                  {
                    buildCommand = ''
                      ${dsuper.buildCommand}
                      ${genAutoloadsCommand}
                    '';
                  }
                );
                buildCommand = ''
                  ${super.buildCommand}
                  wrapProgram $out/bin/emacs \
                    --append-flags "--init-directory ${initDirectory}" \
                    --suffix PATH : ${
                      with lib;
                      pipe binaries [
                        makeBinPath
                        escapeShellArg
                      ]
                    } \
                    --prefix DICPATH : ${lib.escapeShellArg dictSearchPath}
                '';
              });
          }
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
      packages.x86_64-linux =
        let
          pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
        in
        self.lib.mkPackages pkgs;
    };
}
