install
keyboard BOXES_KBD
lang BOXES_LANG
network --onboot yes --device eth0 --bootproto dhcp --noipv6 --activate
rootpw BOXES_PASSWORD
firewall --disabled
authconfig --enableshadow --enablemd5
selinux --enforcing
timezone --utc BOXES_TZ
bootloader --location=mbr
zerombr
clearpart --all --drives=sda

firstboot --disable

part biosboot --fstype=biosboot --size=1
part /boot --fstype ext4 --recommended --ondisk=sda
part pv.2 --size=1 --grow --ondisk=sda
volgroup VolGroup00 --pesize=32768 pv.2
logvol swap --fstype swap --name=LogVol01 --vgname=VolGroup00 --size=768 --grow --maxsize=1536
logvol / --fstype ext4 --name=LogVol00 --vgname=VolGroup00 --size=1024 --grow
reboot

user --name=BOXES_USERNAME --password=BOXES_PASSWORD

BOXES_FEDORA_REPOS

%packages
@base
@core
@hardware-support
@base-x
@gnome-desktop
@graphical-internet
@sound-and-video

# QXL video driver and SPICE vdagent
xorg-x11-drv-qxl
spice-vdagent

%end

%post --erroronfail

# Add user to admin group
usermod -a -G wheel BOXES_USERNAME

# Enable autologin
echo "[daemon]
AutomaticLoginEnable=true
AutomaticLogin=BOXES_USERNAME

[security]

[xdmcp]

[greeter]

[chooser]

[debug]
" > /etc/gdm/custom.conf

%end
