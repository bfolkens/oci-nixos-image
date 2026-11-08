# NixOS OCI image

Oracle doesn't ship an official image for NixOS. This project provides a
template for building a reusable NixOS image for Oracle Cloud Infrastructure,
with SSH access and Nix flakes enabled.

## Build

Requires Packer 1.11+, OCI credentials in `~/.oci/config`, and a public subnet
that allows SSH from your machine and outbound access to GitHub and Nix caches.

Set the OCI profile, compartment, subnet, availability domain, and Ubuntu base
image in `nixos.pkr.hcl`. The default builder is `VM.Standard.A2.Flex` with 2
OCPUs and 16 GiB RAM.

Run from this directory:

```sh
packer init .
packer validate nixos.pkr.hcl
packer build nixos.pkr.hcl
```

Set `image_name`, `builder_ocpus`, or `builder_memory_in_gbs` with `-var` as
needed. Other variables my be more convenient with environment variables like
`PKR_VAR_oci_profile`, etc.  The image OCID appears in Packer's output and
`manifest.json`.

## Use the image

1. Launch an OCI instance from the custom image.
   ```bash
   oci compute instance launch \
       --compartment-id "${PKR_VAR_oci_compartment_id}" \
       --availability-domain "${PKR_VAR_availability_domain}" \
       --subnet-id "${PKR_VAR_public_subnet}" \
       --image-id IMAGE_ID \
       --shape VM.Standard.A2.Flex \
       --shape-config '{"ocpus":1,"memoryInGBs":8}' \
       --display-name nixos \
       --assign-public-ip true \
       --ssh-authorized-keys-file ~/.ssh/id_ed25519.pub \
       --wait-for-state RUNNING \
       --query data.id \
       --raw-output
   ```
2. Supply your public SSH key through OCI's SSH-key field
   (`metadata.ssh_authorized_keys`).
3. Choose a boot volume at least as large as the source image. Root expands
   automatically on larger volumes.

```sh
ssh root@INSTANCE_IP 'nixos-version'
ssh root@INSTANCE_IP 'nixos-rebuild switch --flake github:ORG/REPO#HOST'
```

The deployment flake must define `nixosConfigurations.HOST` for the given arch
and retain the OCI boot, filesystem, networking, and SSH configuration. Reuse
this flake's `nixosModules.oci`, or copy `modules/oci-platform.nix` and
`modules/fetch-ssh-keys.sh` into your deployment repository.

The base configuration remains in `/etc/nixos` for local rebuilds.

## Example

An simple flake may look like the following:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    oci-image.url = "github:bfolkens/oci-nixos-image/master";
  };

  outputs = { nixpkgs, oci-image, ... }: {
    nixosConfigurations.my-oci-vm = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        oci-image.nixosModules.oci
        {
          networking.hostName = "my-oci-vm";
          nix.settings.experimental-features = [ "nix-command" "flakes" ];
          system.stateVersion = "26.05";
        }
      ];
    };
  };
}
```

Which you could then apply with:

```bash
nixos-rebuild switch --flake .#my-oci-vm
```

Or apply remotely with:

```bash
nix --extra-experimental-features 'nix-command flakes' \
  run 'github:NixOS/nixpkgs/nixos-26.05#nixos-rebuild-ng' -- \
  switch --flake '.#my-oci-vm' --no-reexec \
  --build-host root@INSTANCE_IP \
  --target-host root@INSTANCE_IP
```
