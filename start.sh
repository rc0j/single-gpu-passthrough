#!/bin/bash
#                       ______
#                    .-"      "-.
#                   /            \
#                  |              |
#                  |,  .-.  .-.  ,|
#                  | )(_o/  \o_)( |
#                  |/     /\     \|
#        (@_       (_     ^^     _)
#   _     ) \_______\__|IIIIII|__/__________________________
#  (_)@8@8{}<________|-\IIIIII/-|_______<3 Linux____________>
#         )_/        \          /
#        (@           `--------`
# Created by raif.coonjah
# Last updated: Jul 25 2026. 
# 1.0: Added nvidia-persistenced to prevent nvidia from start the KDE/Linux desktop if the gpu is detached. 
set -x

# 1. Stop display manager and nvidia-persistenced
systemctl stop display-manager
systemctl stop nvidia-persistenced

# 2. Terminate session and kill GPU processes
loginctl terminate-user raif
fuser -k -9 /dev/nvidia*
fuser -k -9 /dev/dri/*
sleep 2

# 5. Unbind vtconsoles and efi-framebuffer
echo 0 > /sys/class/vtconsole/vtcon0/bind 2>/dev/null
echo 0 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null
echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind 2>/dev/null
sleep 1

# 7. Unload NVIDIA modules
modprobe -r nvidia_drm
modprobe -r nvidia_modeset
modprobe -r nvidia_uvm
modprobe -r nvidia
sleep 1

# 9. Load vfio-pci FIRST, then detach GPU + audio function
modprobe vfio-pci
virsh nodedev-detach pci_0000_01_00_0
virsh nodedev-detach pci_0000_01_00_1