#!/bin/bash

# Requires: wget html-xml-utils p7zip libguestfs-tools

#############################################
################## Utility ##################

function usage {
	echo ""
	echo "Cloud Init Image Installer for Proxmox"
	echo "	Written by: XtendedGreg 5-10-2025"
	echo ""
	echo "  Description: This script will install the latest version of the OS image to Proxmox"
	echo "			and apply the specified preconfiguration using Cloud Init."
	echo ""
	echo "  Usage: $0 <OS> <VMID> [Drive Size] [Network] [Storage] [Username] [SSH Key FIle]"
	echo ""
	echo "	  OS Options: 'ubuntu', 'alpine', 'arch', 'kali', 'fedora'"
	echo "			Specifying an OS Option is required."
	echo ""
	echo "	        VMID: Integer ID that the VM will be be created under in Proxmox."
	echo "			Specifying a VMID is required"
	echo ""
	echo "	  Drive Size: Either absolute size (32G) or relative size (+32G)."
	echo "			'+32G' default if omitted."
	echo ""
	echo "	     Network: Network to attach to VM."
	echo "			'vmbr0' default if omitted."
	echo ""
	echo "	     Storage: Storage name for VM, imported image, and cloudinit YAML file snippet."
	echo "			'local-btrfs' default if omitted."
	echo ""
	echo "	    Username: The username to use for the VM login."
	echo "			OS name will be used by default if omitted."
	echo ""
	echo "	SSH Key File: Path to a file containing the SSH public key to load to the VM."
	echo "			'.ssh/authorized_keys' will be attempted by default if omitted."
	echo "			- No key will be loaded if a valid file cannot be found."
	echo "			- If a path that does not exist is specified, program will exit."
	echo ""
	echo "  Example: $0 ubuntu 500 +32G"
	echo "	This example command will install ubuntu to VMID 500 and increase the image size by 32GB."
	echo ""

}

#############################################
################## Config ###################

OS=$1
if [[ "$OS" == "" ]]; then echo "Error: Missing OS as first argument."; usage; exit 1; fi

VMID=$2
if [[ "$VMID" == "" ]]; then echo "Error: Missing VMID as second argument."; usage; exit 1; fi

SIZE=$3
if [[ "$SIZE" == "" ]]; then SIZE="+32G"; fi

NETWORK=$4
if [[ "$NETWORK" == "" ]]; then NETWORK="vmbr0"; fi

STORAGE=$5
if [[ "$STORAGE" == "" ]]; then STORAGE="local-btrfs"; fi

USERNAME=$6
if [[ "$USERNAME" == "" ]]; then USERNAME=""; fi
# Blank username uses image name by default

SSHFILE=$7
if [[ "$SSHFILE" != "" ]]; then
	if [ -e "$SSHFILE" ]; then
		SSHKEY="$(cat $SSHFILE)"
	else
		echo "Error: Requested SSH Key File does not exist."
		usage
		exit 1;
	fi
else
	if [ -e .ssh/authorized_keys ]; then
		SSHKEY="$(cat .ssh/authorized_keys)"
	else
		echo "Warning: Unable to use '.ssh/authorized_keys' as SSH Key."
		usage
	fi
fi

USERPASS="$(tr -dc A-Z0-9 </dev/urandom | head -c 12; echo)"
bios="ovmf"
serialPort=0

currentDirectory=$(pwd)

##############################################
################### Images ###################

######### Ubuntu ######### 
function download_ubuntu {
	if [[ "$USERNAME" == "" ]]; then USERNAME="ubuntu"; fi
	bios="ovmf"

	ubuntuVersion=$(wget -qO- https://cloud-images.ubuntu.com/releases/ | hxclean | hxselect -cs "\n" "a" | cut -d/ -f1 | grep -E "^[0-9][02468]." | grep -E ".04" | sort | tail -n1)
	image="https://cloud-images.ubuntu.com/releases/${ubuntuVersion}/release/ubuntu-${ubuntuVersion}-server-cloudimg-amd64.img"
	echo $image
	if [ ! -e $(echo $image | rev | cut -d/ -f1 | rev) ]; then
		wget $image
		virt-customize -a ubuntu-${ubuntuVersion}-server-cloudimg-amd64.img --install qemu-guest-agent
	fi
	name="ubuntu-server-${ubuntuVersion}-amd64"

}

######### Alpine ######### 
function download_alpine {
	if [[ "$USERNAME" == "" ]]; then USERNAME="alpine"; fi
	bios="ovmf"

	alpineFile=$(wget -qO- https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/ | grep "generic" | grep "x86_64" | grep "uefi" | grep "cloudinit" | grep -v metal | grep ".qcow2" | grep -v ".asc" | grep -v ".sha" | sort | tail -n1 | cut -d'"' -f2)
	image="https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/${alpineFile}"
	echo $image
        if [ ! -e $(echo $image | rev | cut -d/ -f1 | rev) ]; then
                wget $image
		virt-customize -a $alpineFile --install qemu-guest-agent
		virt-customize -a $alpineFile --run-command "rc-update add qemu-guest-agent default"
        fi
	name="alpine-$(echo $image | rev | cut -d/ -f1 | rev | cut -d_ -f2 | cut -d- -f2)-amd64"

	# Force Change Password Workaround
	cat <<EOF >>/tmp/changePassword
#!/sbin/openrc-run

description="Force Reset User Password"

depend() {
  after cloud-config
  after cloud-final
}

start() {
	rm -f /etc/runlevels/*/\$RC_SVCNAME
	passwd -e ${USERNAME}
	chage -l ${USERNAME}
	usermod -s /bin/forceChangePassword ${USERNAME}
}

EOF

	cat <<EOF >>/tmp/forceChangePassword
#!/bin/sh

continue=1
while [ \$continue -eq 1 ]; do
	echo "You are required to change your password."
	doas passwd ${USERNAME} && continue=0
done

doas /usr/sbin/usermod -s /bin/sh ${USERNAME}
cat /etc/motd
/bin/sh -l
exit 0

EOF

	virt-customize -a $alpineFile --copy-in /tmp/changePassword:/etc/init.d
	virt-customize -a $alpineFile --chmod 0755:/etc/init.d/changePassword
	virt-customize -a $alpineFile --run-command "rc-update add changePassword default"
	rm /tmp/changePassword

	virt-customize -a $alpineFile --copy-in /tmp/forceChangePassword:/bin
        virt-customize -a $alpineFile --chmod 0755:/bin/forceChangePassword
	rm /tmp/forceChangePassword
}

######### Arch ######### 
function download_arch {
        if [[ "$USERNAME" == "" ]]; then USERNAME="arch"; fi
	bios="ovmf"

	archVersion=$(wget -qO- https://geo.mirror.pkgbuild.com/images/latest/ | grep ".qcow2" | awk '{print $2}' | grep '.qcow2"' | grep "cloudimg" | sort -r | tail -n1 | cut -d'"' -f2 | rev | cut -d- -f1 | rev | awk -F "." -v OFS="." '{print $1, $2}')
        image="https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg-${archVersion}.qcow2"
        echo $image
        if [ ! -e $(echo $image | rev | cut -d/ -f1 | rev) ]; then
                wget $image
        fi
        name="arch-${archVersion}-amd64"

}

######### Kali ######### 
function download_kali {
        if [[ "$USERNAME" == "" ]]; then USERNAME="kali"; fi
	bios="seabios"

        kaliFile=$(wget -qO- https://cdimage.kali.org/current/ | hxnormalize | grep "href=kali" | grep -v "torrent" | grep "amd64" | grep "qemu" | cut -d= -f3)
        image="https://cdimage.kali.org/current/${kaliFile}"
        echo $image
        if [ ! -e ${kaliFile%.*}.qcow2 ]; then
                wget $image
		7zr e $kaliFile
		rm $kaliFile
		virt-customize -a ${kaliFile%.*}.qcow2 --install cloud-init
        	virt-customize -a ${kaliFile%.*}.qcow2 --install qemu-guest-agent
	        virt-customize -a ${kaliFile%.*}.qcow2 --run-command 'systemctl enable ssh.service'
        fi
	image=${image%.*}.qcow2
        name="kali-$(echo $kaliFile | cut -d- -f3)-amd64"

	virt-customize -a ${kaliFile%.*}.qcow2 --run-command "echo '@reboot root while [ \$(systemctl status cloud-config.service | grep \"Active:\" | grep \"(exited)\" | wc -l) -eq 0 ]; do sleep 1; done; passwd -e ${USERNAME} && rm /etc/cron.d/runOnce' > /etc/cron.d/runOnce"
}

######### Fedora ######### 
function download_fedora {
        if [[ "$USERNAME" == "" ]]; then USERNAME="fedora"; fi
        bios="seabios"

        fedoraFile=$(wget -qO- https://fedoraproject.org/cloud/download/_payload.json | jq -r '.[]' | grep ".qcow2" | grep "x86_64" | grep "Cloud" | grep "Generic")
        image="https://download.fedoraproject.org/pub/fedora/linux/releases/$(echo $fedoraFile | cut -d- -f5)/${fedoraFile}"
        echo $image
        if [ ! -e $(echo $image | rev | cut -d/ -f1 | rev) ]; then
                wget $image
        fi
	local version=$(echo $fedoraFile | cut -d- -f5)-$(echo $fedoraFile | cut -d- -f6 | cut -dx -f1)
	version="${version::-1}"
        name="fedora-${version}-amd64"
	serialPort=1
}


######################################################
############# Cloudinit Config #######################

STORAGECONFIG=/etc/pve/storage.cfg
function readStorageConfig {
        local counter=0
        local drive=""
        while IFS= read -r line; do
                if [[ "$line" =~ ^[[:space:]] ]] || [[ "$line" =~ ^[[:tab:]] ]]; then
                        # Line indented
                        if [[ "$drive" != "" ]]; then
                                if [[ "$(echo $line | awk '{print $1}')" == "path" ]]; then
                                        path="$(echo $line | awk '{print $2}')"
                                elif [[ "$(echo $line | awk '{print $1}')" == "content" ]]; then
                                        content="$(echo $line | awk '{print $2}')"
                                elif [[ "$(echo $line | awk '{print $1}')" == "disable" ]]; then
                                        disabled=1
                                fi
                        fi
                else
                        if [[ "$drive" != "" ]] && [[ "$path" != "" ]] && [[ "$content" != "" ]] && [ $disabled -eq 0 ]; then
                                info="$drive $path $content"
                                drives["$counter"]=$info
                                counter=$(($counter+1))
                        fi
                        # Drive Key
                        drive=$(echo $line | awk '{print $2}')
                        local path=""
                        local content=""
                        local disabled=0
                fi
        done < $STORAGECONFIG

        for drive in ${!drives[@]}; do
		if [[ "$1" == "" ]] || [[ "$1" == "$(echo ${drives[$drive]} | awk '{print $1}')" ]]; then 
                        echo ${drives[$drive]}
                fi
        done
}

function cloudinit {

        if [ $(readStorageConfig $STORAGE | awk '{print $3}' | grep "snippet" | wc -l) -eq 1 ]; then
                path=$(readStorageConfig $STORAGE | grep "snippet" | awk '{print$2}')
        else
                echo "Error: '$STORAGE' does not have 'snippets' enabled in Proxmox config."
                exit 1
        fi

        fail=0
        qm cloudinit dump $1 user > $path/snippets/user-cloudinit-$1.yaml || fail=1
	if [[ "$2" == "" ]]; then
	        qm cloudinit dump $1 network > $path/snippets/network-cloudinit-$1.yaml || fail=1
        	qm cloudinit dump $1 meta > $path/snippets/meta-cloudinit-$1.yaml || fail=1
	fi

        if [ $fail -eq 1 ]; then
                echo "Error: CloudInit yaml files failed to export from VMID '$VMID'."
        else
                echo "CloudInit yaml files exported from VMID '$VMID' to '$path/snippets' successfully."
        fi

	if [[ "$OS" == "" ]] || [[ "$OS" != "kali" ]]; then
		sed -i -e 's/expire: False/expire: True/g' $path/snippets/user-cloudinit-$1.yaml
	fi

}

######################################################
######################### Main #######################

# VMID Check
for i in $(qm list | awk '{print $1}'); do
        if [[ "$i" == "$VMID" ]] && [[ "$OS" != "cloudinit" ]]; then
                echo "Error: VMID '$VMID' already exists."
                exit;
        fi
done

if [ $(readStorageConfig $STORAGE | awk '{print $3}' | grep "import" | wc -l) -eq 1 ]; then
        IMAGESTORAGE=$(readStorageConfig $STORAGE | grep "import" | awk '{print $2}')
	if [ ! -e $IMAGESTORAGE/import ]; then mkdir $IMAGESTORAGE/import; fi
	echo "Notice: Images are being saved to $IMAGESTORAGE/import"
	cd $IMAGESTORAGE/import
else
	echo "Warning: '$STORAGE' does not have 'import' enabled in Proxmox config. Using current directory."
	echo "'$(readStorageConfig $STORAGE | awk '{print $3}' | grep "import")' does not contain 'import'"
fi

# OS Selection and Image Download
if [[ "$OS" == "ubuntu" ]]; then
	download_ubuntu
elif [[ "$OS" == "alpine" ]]; then
	download_alpine
elif [[ "$OS" == "arch" ]]; then
	download_arch
elif [[ "$OS" == "kali" ]]; then
	download_kali
elif [[ "$OS" == "fedora" ]]; then
	download_fedora
elif [[ "$OS" == "cloudinit" ]]; then
	cloudinit $2
	cd $currentDirectory
	exit 0
else
	echo "Error: Unknown OS."
	usage
	exit
fi
echo $name

## VM Creation
# create a new VM with VirtIO SCSI controller
qm create $VMID --name "${name}" --cores 4 --memory 8196 --net0 virtio,bridge=${NETWORK} --scsihw virtio-scsi-pci --machine q35

# import the downloaded disk to the local-btrfs storage, attaching it as a SCSI drive
qm importdisk $VMID $(echo $image | rev | cut -d/ -f1 | rev) ${STORAGE} --format qcow2 --target-disk scsi0
qm resize $VMID scsi0 $SIZE

qm set $VMID --ide2 ${STORAGE}:cloudinit
qm set $VMID --boot order=scsi0

qm set $VMID --agent enabled=1
qm set $VMID --bios $bios

if [ $serialPort -eq 1 ]; then
	qm set $VMID -serial0 socket
fi

qm set $VMID --ipconfig0 ip=dhcp
qm set $VMID --ciuser "$USERNAME"
qm set $VMID --cipassword "$USERPASS"
qm set $VMID --ciupgrade 1

keytemp="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8; echo)"
echo "$SSHKEY" > /tmp/$keytemp
qm set $VMID --sshkeys /tmp/$keytemp
rm /tmp/$keytemp

cloudinit $VMID "user"

qm set $VMID --cicustom "user=local-btrfs:snippets/user-cloudinit-$VMID.yaml"
qm cloudinit update $VMID

echo "################################################################"
echo ""
echo "           Created VM '${name}' with ID '${VMID}'."
echo ""
echo "                       Username: '${USERNAME}'"
echo "             Temporary Password: '${USERPASS}'"
echo ""
echo "  You will be required to change your password on first login."
echo ""

cd $currentDirectory

exit

