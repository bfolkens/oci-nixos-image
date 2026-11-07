{
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [ "${modulesPath}/virtualisation/oci-common.nix" ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  oci.efi = true;
  boot.loader.grub.enable = lib.mkDefault true;
  boot.initrd.availableKernelModules = [ "nvme" ];

  # oci-common uses filesystem labels nixos/ESP and enables root partition growth.
  fileSystems."/boot".options = [ "umask=0077" ];
  swapDevices = [ { device = "/dev/disk/by-label/swap"; } ];
  networking.useDHCP = lib.mkDefault true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = lib.mkDefault "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
    # Keep the usual per-user/declarative key files as well as this runtime file.
    authorizedKeysFiles = lib.mkAfter [ "/run/oci-ssh-keys/%u" ];
  };

  # Fetch the NEW instance's launch key on every boot. /run is never captured in
  # the image, so Packer's metadata key cannot become a permanent image key.
  systemd.services.oci-ssh-keys = {
    description = "Fetch root SSH keys from OCI instance metadata";
    wantedBy = [ "sshd.service" ];
    before = [ "sshd.service" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [
      pkgs.coreutils
      pkgs.curl
      pkgs.openssh
    ];
    script = builtins.readFile ./fetch-ssh-keys.sh;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "oci-ssh-keys";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = "5s";
      TimeoutStartSec = "150s";
    };
  };
}
