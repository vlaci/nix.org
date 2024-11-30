{
  disko.devices = {
    disk = {
      nvme = {
        type = "disk";
        device = "/dev/nvme0n1";
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
                  "umask=0077"
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
                  vg = "mainpool";
                };
              };
            };
          };
        };
      };
    };
    lvm_vg = {
      mainpool = {
        type = "lvm_vg";
        lvs = {
          thinpool = {
            size = "128G";
            lvm_type = "thin-pool";
          };
          swap = {
            size = "48G";
            content = {
              type = "swap";
            };
          };
          root = {
            size = "64G";
            lvm_type = "thinlv";
            pool = "thinpool";
            content = {
              type = "filesystem";
              format = "xfs";
              mountpoint = "/";
              mountOptions = [ "defaults" ];
              postCreateHook = "lvcreate -s mainpool/root --name root-blank";
            };
          };
          nix = {
            size = "128G";
            content = {
              type = "filesystem";
              format = "xfs";
              mountpoint = "/nix";
              mountOptions = [ "defaults" ];
            };
          };
          persist = {
            size = "512G";
            content = {
              type = "filesystem";
              format = "xfs";
              mountpoint = "/persist";
              mountOptions = [ "defaults" ];
            };
          };
        };
      };
    };
  };
}
