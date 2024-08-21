{
  disko.devices = {
    disk = {
      nvme = {
        type = "disk";
        device = "/dev/nvmn0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "defaults"
                ];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypt-root";
                extraOpenArgs = [ "--allow-discards" ];
                content = {
                  type = "lvm_pv";
                  vg = "pool";
                };
              };
            };
          };
        };
      };
    };
    lvm_vg = {
      pool = {
        type = "lvm_vg";
        lvs = {
          swap = {
            size = "32G";
            content = {
              type = "swap";
            };
          };
          rpool = {
            size = "100%FREE";
            content = {
              type = "zfs";
              pool = "rpool";
            };
          };
        };
      };
    };
    zpool = {
      rpool = {
        type = "zpool";
        postCreateHook = "zfs snapshot rpool/razorback/root@blank && zfs snapshot -r rpool/razorback/home@blank";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          acltype = "posixacl";
          canmount = "off";
          normalization = "formD";
          mountpoint = "none";
          relatime = "on";
          xattr = "sa";
        };
        datasets = {
          "razorback" = {
            type = "zfs_fs";
            mountpoint = "/persist";
            options.mountpoint = "legacy";
            options.compression = "zstd";
          };
          "razorback/root" = {
            type = "zfs_fs";
            mountpoint = "/";
            options.mountpoint = "legacy";
            options.compression = "zstd";
          };
          "razorback/nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options.mountpoint = "legacy";
            options.compression = "zstd";
          };
          "razorback/home" = {
            type = "zfs_fs";
            options.canmount = "off";
            options.mountpoint = "legacy";
          };
          "razorback/home/vlaci" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/persist/home/vlaci";
          };
          "razorback/var" = {
            type = "zfs_fs";
            options.canmount = "off";
            options.mountpoint = "legacy";
          };
          "razorback/var/lib" = {
            type = "zfs_fs";
            options.canmount = "off";
            options.mountpoint = "legacy";
          };
          "razorback/var/lib/libvirt" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/persist/var/lib/libvirt";
          };
        };
      };
    };
  };
}
