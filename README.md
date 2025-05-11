# Cloud Init Image Installer for Proxmox
Written by: XtendedGreg May 10, 2025

## Description
This script will install the latest version of the OS image to Proxmox and apply the specified preconfiguration using Cloud Init.
This script and its use will be covered in an upcoming XtendedGreg Youtube stream.

## Usage: ./cloud-init.sh <OS> <VMID> [Drive Size] [Network] [Storage] [Username] [SSH Key FIle]

          OS Options: 'ubuntu', 'alpine', 'arch', 'kali', 'fedora'
                        Specifying an OS Option is required.

                VMID: Integer ID that the VM will be be created under in Proxmox.
                        Specifying a VMID is required

          Drive Size: Either absolute size (32G) or relative size (+32G).
                        '+32G' default if omitted.

             Network: Network to attach to VM.
                        'vmbr0' default if omitted.

             Storage: Storage name for VM, imported image, and cloudinit YAML file snippet.
                        'local-btrfs' default if omitted.

            Username: The username to use for the VM login.
                        OS name will be used by default if omitted.

        SSH Key File: Path to a file containing the SSH public key to load to the VM.
                        '.ssh/authorized_keys' will be attempted by default if omitted.
                        - No key will be loaded if a valid file cannot be found.
                        - If a path that does not exist is specified, program will exit.
                        
      Usage Example: ./cloud-init.sh ubuntu 500 +32G
                        This example command will install ubuntu to VMID 500 and increase the image size by 32GB.

## Disclaimer
Software is provided "as-is" with no warranty expressed or implied.  Images are obtained directly from respective image developer provided websites at runtime under the user's responsibility.
