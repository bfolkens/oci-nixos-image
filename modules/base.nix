{ lib, pkgs, ... }:
{
  networking.hostName = lib.mkDefault "nixos";
  time.timeZone = lib.mkDefault "UTC";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  environment.systemPackages = [
    pkgs.gitMinimal
    pkgs.curl
  ];
  users.users.root.initialHashedPassword = "!";

  # Preserve the installation config in /etc/nixos; deployment flakes can replace it.
  system.stateVersion = "26.05";
}
