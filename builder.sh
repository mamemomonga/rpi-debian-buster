#!/bin/bash
set -eu

# ----------------------------------------------------------
# Raspberry Pi3用 Debian10 aarch64セットアップツール
# ----------------------------------------------------------
#   ./builder.sh apt              必要なパッケージを導入
#   ./builder.sh rootfs           rootfsの作成
#   ./builder.sh setup            各種セットアップ
#   ./builder.sh install /dev/sdX 特定のディスクへインストール(元のディスクは消えます!)

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
COMMANDS="apt rootfs setup install image"
ROOTFS="$BASEDIR/var/rootfs"

do_apt() {
	apt-get install -y qemu-user-static cdebootstrap dosfstools
}

do_rootfs() {
	mkdir -p $ROOTFS
	cdebootstrap \
	  --arch=arm64 \
	  -f standard \
	  --foreign buster \
	  --include=ntp,lvm2,openssh-server,net-tools \
	  -v $ROOTFS
}

do_setup() {

	if [ -e 'authorized_keys' ]; then
		mkdir -p "$ROOTFS/home/admin/.ssh"
		cp authorized_keys "$ROOTFS/home/admin/.ssh/authorized_keys"
	fi
	chroot $ROOTFS /bin/bash << 'END_OF_CHROOT'

# セットアップ時のロケール
export LC_ALL=C

# fstab
cat > /etc/fstab << 'EOS'
proc            /proc   proc    defaults                0       0
/dev/mmcblk0p1  /boot   vfat    defaults                0       2
/dev/mmcblk0p2  /       ext4    errors=remount-ro       0       1
EOS

# 空のファイル
touch /etc/network/interfaces
touch /etc/networks
touch /etc/hosts
touch /etc/hostname
touch /etc/mailname
touch /etc/resolve.conf

# apt
cat > /etc/apt/sources.list << 'EOS'
deb http://deb.debian.org/debian/ buster main contrib non-free
deb-src http://deb.debian.org/debian/ buster main contrib non-free

deb http://security.debian.org/debian-security buster/updates main contrib non-free
deb-src http://security.debian.org/debian-security buster/updates main contrib non-free

# buster-updates, previously known as 'volatile'
deb http://deb.debian.org/debian/ buster-updates main contrib non-free
deb-src http://deb.debian.org/debian/ buster-updates main contrib non-free
EOS

apt-get update
apt-get install -y gpg wget locales

# ロケール
perl -i -nlpE 's!^# (en_US.UTF-8 UTF-8)!$1!;' /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

# Raspberry Piリポジトリ
wget -O - http://archive.raspberrypi.org/debian/raspberrypi.gpg.key | apt-key add -

cat > /etc/apt/sources.list.d/archive.raspberrypi.org.list << 'EOS'
deb http://archive.raspberrypi.org/debian/ buster main
# Uncomment line below then 'apt-get update' to enable 'apt-get source'
#deb-src http://archive.raspberrypi.org/debian/ buster main
EOS

apt-get update
apt-get install -y raspberrypi-archive-keyring
rm /etc/apt/trusted.gpg

cat > /etc/apt/preferences << 'EOS'
Package: *
Pin: release a=testing
Pin-Priority: 105
EOS

# 日本時間
rm -f /etc/localtime
ln -s /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
echo 'Asia/Tokyo' > /etc/timezone

# インストール
apt-get install -y \
	raspi-config \
	libraspberrypi-bin \
	fake-hwclock \
	raspberrypi-bootloader \
	raspberrypi-kernel \
	dosfstools \
	e2fsck-static \
	build-essential \
	sudo \
	vim \
	ntp

# カーネル
NEWKERNEL=$(ls /lib/modules | grep v8)
update-initramfs -c -k $NEWKERNEL

# cmdline
cat > /boot/cmdline.txt << 'EOS'
console=serial0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline rootwait quiet splash plymouth.ignore-serial-consoles net.ifnames=0 biosdevname=0
EOS

# config
cat > /boot/config.txt << EOS
arm_64bit=1
dtoverlay=pi3-miniuart-bt
gpu_mem=16

initramfs initrd.img-$NEWKERNEL followkernel
EOS

# ネットワーク
cat > /etc/network/interfaces << 'EOS'
allow-hotplug eth0
iface eth0 inet dhcp
#  address 192.168.11.100
#  netmask 255.255.255.0
#  gateway 192.168.11.1
#  dns-domain example.com
#  dns-nameservers 192.168.11.1
EOS

# sshd
systemctl enable ssh.service
cat >> cat /etc/ssh/sshd_config << 'EOS'

PasswordAuthentication no
PermitRootLogin no
EOS

# adminユーザ

useradd -m -s /bin/bash admin
chown -R admin:admin /home/admin/.ssh
chmod 700 /home/admin/.ssh
chmod 600 /home/admin/.ssh/authorized_keys

echo 'admin:debian' | chpasswd

# sudo
cat > /etc/sudoers.d/wheel_user << EOS
admin ALL=(ALL) NOPASSWD:ALL
EOS
chmod 600 /etc/sudoers.d/wheel_user

# vim
cat > /etc/vim/vimrc.local << 'EOS'
syntax on
set wildmenu
set history=100
set number
set scrolloff=5
set autowrite
set tabstop=4
set shiftwidth=4
set softtabstop=0
set termencoding=utf-8
set encoding=utf-8
set fileencodings=utf-8,cp932,euc-jp,iso-2022-jp,ucs2le,ucs-2
set fenc=utf-8
set enc=utf-8
EOS
update-alternatives --set editor /usr/bin/vim.basic

# ntpd
mv /etc/ntp.conf /etc/ntp.conf.orig

cat > /etc/ntp.conf << 'EOS'
driftfile /var/lib/ntp/drift
statistics loopstats peerstats clockstats
filegen loopstats file loopstats type day enable
filegen peerstats file peerstats type day enable
filegen clockstats file clockstats type day enable

restrict -4 default kod notrap nomodify nopeer noquery
restrict -6 default kod nomodify notrap nopeer noquery
restrict 127.0.0.1 
restrict ::1

server ntp1.jst.mfeed.ad.jp iburst
server ntp2.jst.mfeed.ad.jp iburst
server ntp3.jst.mfeed.ad.jp iburst
EOS

echo "FINISH!"
END_OF_CHROOT
}

do_install() {
	local drive=$1

	echo "Install Disk: $drive"
	read -p "Ready? (y/N): " yn; case "$yn" in [yY]*) ;; *) echo "abort"; exit 1;; esac

	dd if=/dev/zero of=$drive bs=1M count=1
echo "n
p
1

+256M
t
b
n
p



a
1
w" | fdisk $drive
	echo "p\nq\n" | fdisk $drive

	mkfs.vfat $drive'1'
	mkfs.ext4 $drive'2'

	mount $drive'2' /mnt
	mkdir -p /mnt/boot
	mount $drive'1' /mnt/boot
	tar cC $ROOTFS . | tar xvpC /mnt
	echo "sync...."
	sync
	umount /mnt/boot
	umount /mnt

}

do_image() {
	local filename="$BASEDIR/var/image.img"
	if [ -e $filename ]; then rm -f $filename; fi
	fallocate -l 2G $filename
echo "n
p
1

+256M
t
b
n
p



a
1
w" | fdisk $filename
	echo "p\nq\n" | fdisk $filename

	local loopback=$(losetup -f -P --show $filename)
	echo "Loopback Device: $loopback"

	mkfs.vfat $loopback'p1'
	mkfs.ext4 $loopback'p2'

	mount $loopback'p2' /mnt
	mkdir -p /mnt/boot
	mount $loopback'p1' /mnt/boot
	tar cC $ROOTFS . | tar xvpC /mnt
	echo "sync...."
	sync
	umount /mnt/boot
	umount /mnt
	losetup -d $loopback
}

run() {
    if [ "$(id -u)" != "0" ]; then exec sudo $0 $@; fi

    for i in $COMMANDS; do
    if [ "$i" == "${1:-}" ]; then
        shift
        do_$i $@
        exit 0
    fi
    done
    echo "USAGE: $( basename $0 ) COMMAND"
    echo "COMMANDS:"
    for i in $COMMANDS; do
    echo "   $i"
    done
    exit 1
}

run $@
