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

# 1. Reattach GPU + audio function back to the host
virsh nodedev-reattach pci_0000_01_00_0
virsh nodedev-reattach pci_0000_01_00_1
sleep 1

# 3. Reload NVIDIA modules (reverse order from unload)
modprobe nvidia
modprobe nvidia_uvm
modprobe nvidia_modeset
modprobe nvidia_drm

# lets wait a little bit just to be safe
# I noticed proceed with rebind too quickly things get a bit messy and unorganised in a sense. 
sleep 1

# 5. Rebind vtconsoles and efi-framebuffer
echo 1 > /sys/class/vtconsole/vtcon0/bind 2>/dev/null
echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null

# 6. Restart nvidia-persistenced and display manager
systemctl start nvidia-persistenced
systemctl start display-manager