packer {
  required_version = ">= 1.11.0"

  required_plugins {
    oracle = {
      source  = "github.com/hashicorp/oracle"
      version = "= 1.1.2"
    }
  }
}

variable "image_name" {
  type        = string
  default     = ""
  description = "Optional OCI image name; otherwise a timestamped name is generated."
}

variable "builder_ocpus" {
  type    = number
  default = 2
}

variable "builder_memory_in_gbs" {
  type    = number
  default = 16
}

variable "nixos_version" {
  type    = string
  default = "26.05"
}

variable "nixos_arch" {
  type    = string
  default = "aarch64"
}

variable "kexec_installer_url" {
  type    = string
  default = "https://github.com/nix-community/nixos-images/releases/download/nixos-26.05/nixos-kexec-installer-noninteractive-aarch64-linux.tar.gz"
}

variable "kexec_installer_sha256" {
  type        = string
  default     = "ead5a02f5a440354a3fe5576476817fb6dd9b2477efe5354bf0a62a5510b951c"
  description = "SHA-256 of the installer asset - update alongside `kexec_installer_url` when refreshing the installer."

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.kexec_installer_sha256))
    error_message = "Supply a lowercase, hexadecimal SHA-256 digest."
  }
}

variable "oci_profile" {
  type = string
}

variable "oci_compartment_id" {
  type = string
}

variable "public_subnet" {
  type = string
}

variable "availability_domain" {
  type = string
}

variable "base_image_ocid" {
  type = string
  # Canonical-Ubuntu-24.04-aarch64-2026.09.18-0
  default     = "ocid1.image.oc1.us-chicago-1.aaaaaaaadcv3pphkgnnwsulixcq3glryb4ljkgxnijfocsxarbg6fnru5sjq"
  description = "Bootstrap image - only used for starting the RAM installer."
}

locals {
  template_dir = abspath(path.root)
  image_name   = var.image_name != "" ? var.image_name : "nixos-${var.nixos_version}-${var.nixos_arch}-${formatdate("YYYYMMDD-hhmmss", timestamp())}"
  flake_lock   = jsondecode(file("${local.template_dir}/flake.lock"))
}

source "oracle-oci" "nixos-builder" {
  access_cfg_file_account = var.oci_profile
  availability_domain     = var.availability_domain
  base_image_ocid         = var.base_image_ocid
  compartment_ocid        = var.oci_compartment_id
  image_name              = local.image_name

  shape = "VM.Standard.A2.Flex"
  shape_config {
    ocpus         = var.builder_ocpus
    memory_in_gbs = var.builder_memory_in_gbs
  }

  # Keep one communicator account across Ubuntu, the RAM installer and the disk boot.
  # Oracle's plugin supplies a temporary key in instance metadata; no agent is needed.
  ssh_username                 = "root"
  ssh_agent_auth               = false
  ssh_disable_agent_forwarding = true
  ssh_clear_authorized_keys    = false
  ssh_timeout                  = "10m"
  ssh_handshake_attempts       = 100

  # Do not override metadata.ssh_authorized_keys: that would replace Packer's key.
  user_data = "#cloud-config\n${yamlencode({
    disable_root = false
    ssh_pwauth   = false
  })}"

  subnet_ocid         = var.public_subnet
  nic_attachment_type = "PARAVIRTUALIZED"
  image_launch_mode   = "PARAVIRTUALIZED"
}

build {
  sources = ["source.oracle-oci.nixos-builder"]

  provisioner "shell" {
    script = "${local.template_dir}/scripts/bootstrap.sh"
    environment_vars = [
      "KEXEC_INSTALLER_URL=${var.kexec_installer_url}",
      "KEXEC_INSTALLER_SHA256=${var.kexec_installer_sha256}"
    ]
    expect_disconnect = true
    skip_clean        = true
    timeout           = "20m"
  }

  provisioner "shell" {
    pause_before        = "30s"
    start_retry_timeout = "10m"
    inline = [
      ". /etc/os-release",
      "test \"$ID\" = nixos",
      "test \"$(id -u)\" = 0",
      "install -d -m 0755 /tmp/nixos-image"
    ]
  }

  # Upload only the image's source files, never local variable files or SSH keys.
  provisioner "file" {
    sources = [
      "${local.template_dir}/flake.nix",
      "${local.template_dir}/flake.lock",
      "${local.template_dir}/files",
      "${local.template_dir}/modules"
    ]
    destination = "/tmp/nixos-image/"
  }

  provisioner "shell" {
    script  = "${local.template_dir}/scripts/install.sh"
    timeout = "60m"
  }

  provisioner "shell" {
    inline = [
      "systemctl reboot",
      # Wait for the connection to close rather than returning before the reboot.
      "while true; do sleep 1; done"
    ]
    expect_disconnect = true
    skip_clean        = true
    timeout           = "10m"
  }

  provisioner "shell" {
    pause_before        = "30s"
    start_retry_timeout = "10m"
    inline              = ["nixos-version"]
    timeout             = "10m"
  }

  # This must be the last SSH provisioner. OCI handles shutdown/capture/restart.
  provisioner "shell" {
    script     = "${local.template_dir}/scripts/cleanup.sh"
    skip_clean = true
    timeout    = "5m"
  }

  post-processor "manifest" {
    output     = "${local.template_dir}/manifest.json"
    strip_path = true
    custom_data = {
      operating_system = "NixOS ${var.nixos_version}"
      architecture     = "${var.nixos_arch}-linux"
      nixpkgs_revision = local.flake_lock.nodes.nixpkgs.locked.rev
      disko_revision   = local.flake_lock.nodes.disko.locked.rev
    }
  }
}
