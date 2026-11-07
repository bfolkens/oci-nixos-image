{
  description = "Reusable NixOS ARM64 base image for Oracle Cloud Infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, disko, ... }: {
    # Deployment flakes can reuse the platform contract without importing the
    # base image's hostname or packages. Disko is used only by the installer.
    nixosModules.oci = import ./modules/oci-platform.nix;

    nixosConfigurations.oci-base = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ./modules/oci-platform.nix
        ./modules/base.nix
      ];
    };

    packages.aarch64-linux.disko = disko.packages.aarch64-linux.disko;
  };
}
