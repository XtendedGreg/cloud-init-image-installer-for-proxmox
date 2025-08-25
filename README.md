# Cloud Init Image Installer for Proxmox
Written by: XtendedGreg May 10, 2025 [XtendedGreg Youtube Channel](https://www.youtube.com/@xtendedgreg)

## Description
- This script will install the latest version of the OS image to Proxmox and apply the specified preconfiguration using Cloud Init.
- This script and its use will be covered in this [XtendedGreg Youtube stream](https://youtube.com/live/fBK00EUrMIo).
[![Watch the video](https://img.youtube.com/vi/fBK00EUrMIo/maxresdefault.jpg)](https://youtube.com/live/fBK00EUrMIo)

## Usage
          ./cloud-init.sh <OS> <VMID> [Drive Size] [Network] [Storage] [Username] [SSH Key FIle]

          OS Options: 'ubuntu', 'alpine', 'arch', 'kali', 'fedora'
                        Specifying an OS Option is required.

                VMID: Integer ID that the VM will be be created under in Proxmox.
                        Specifying a VMID is required and must not be a VMID already in use.

          Drive Size: Either absolute size (32G) or relative size (+32G).
                        '+32G' default if omitted or blank ('').

             Network: Network to attach to VM.
                        'vmbr0' default if omitted or blank ('').

             Storage: Storage name for VM, imported image, and cloudinit YAML file snippet.
                        'local-btrfs' default if omitted or blank ('').

            Username: The username to use for the VM login.
                        OS name will be used by default if omitted or blank ('').

        SSH Key File: Path to a file containing the SSH public key to load to the VM.
                        '.ssh/authorized_keys' will be attempted by default if omitted.
                        - No key will be loaded if a valid file cannot be found.
                        - If a path that does not exist is specified, program will exit.
                        
       Usage Example: ./cloud-init.sh ubuntu 500 +32G
                        This example command will install ubuntu to VMID 500 and increase the image size by 32GB.

## Requirements
The following packages are required to run this script and should be installed through the Proxmox node shell: wget html-xml-utils p7zip libguestfs-tools.  
```
sudo apt -y install wget html-xml-utils p7zip libguestfs-tools
```

## Disclaimer
Software is provided "as-is" with no warranty expressed or implied.  Images are obtained directly from respective image developer provided websites at runtime under the user's responsibility.
