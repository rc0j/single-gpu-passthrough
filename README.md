<img src="https://external-content.duckduckgo.com/iu/?u=https%3A%2F%2Fmedia2.dev.to%2Fdynamic%2Fimage%2Fwidth%3D1000%2Cheight%3D420%2Cfit%3Dcover%2Cgravity%3Dauto%2Cformat%3Dauto%2Fhttps%3A%2F%2Fdev-to-uploads.s3.amazonaws.com%2Fuploads%2Farticles%2F725eh3qsu33te93f7ohi.png&f=1&nofb=1&ipt=fa9aaa5c1c0c9a1d0ccd3ce487f642a475f29e11456c7149764b4208385ff516"/>

# Single GPU Passthrough

Made with the help of Local LLM `gemma4.`

To start, this is not a guide. Please do not consider it as one. I'm creating this solely
for my personal use. If you want to use it, please modify or fork this project.

This is v2 — updated after actually getting it working, with the real bugs and their fixes
included so future-me (or a local LLM) doesn't have to rediscover them.

## Getting started & Specs

```shell
           .-------------------------:                    root@overlord
          .+=========================.                    -------------
         :++===++==================-       :++-           OS: CachyOS x86_64
        :*++====+++++=============-        .==:           Kernel: Linux 7.1.4-1-cachyos
       -*+++=====+***++==========:                        Uptime: 33 mins
      =*++++========------------:                         Packages: 1353 (pacman)
     =*+++++=====-                     ...                Shell: bash 5.3.15
   .+*+++++=-===:                    .=+++=:              Display (MSI MP341CQ): 3440x1440 in 34", 100 Hz [External]
  :++++=====-==:                     -*****+              Display (LG ULTRAWIDE): 2560x1080 in 29", 100 Hz [External]
 :++========-=.                      .=+**+.              Terminal: /dev/pts/0 10.4p1
.+==========-.                          .                 CPU: 11th Gen Intel(R) Core(TM) i7-11700K (16) @ 5.00 GHz
 :+++++++====-                                .--==-.     GPU: NVIDIA GeForce RTX 3070 Ti [Discrete]
  :++==========.                             :+++++++:    Memory: 1.93 GiB / 31.13 GiB (6%)
   .-===========.                            =*****+*+    Swap: 4.01 MiB / 31.13 GiB (0%)
    .-===========:                           .+*****+:    Disk (/): 21.91 GiB / 465.76 GiB (5%) - btrfs
      -=======++++:::::::::::::::::::::::::-:  .---:      Disk (/mnt/Game_1): 335.83 GiB / 915.82 GiB (37%) - ext4
       :======++++====+++******************=.             Disk (/mnt/Game_2): 471.80 GiB / 915.82 GiB (52%) - ext4
        :=====+++==========++++++++++++++*-               Local IP (enp4s0): 192.168.100.72/24
         .====++==============++++++++++*-                Locale: en_US.UTF-8
          .===+==================+++++++:
           .-=======================+++:
             ..........................
```

Single physical GPU, no usable iGPU offload path taken (11700K does have one — could be
used to host the desktop separately, but this setup keeps the 3070 Ti fully dynamic
between host and guest instead).

## 1. Install packages

```shell
sudo pacman -S tpm2-tools qemu libvirt edk2-ovmf virt-manager dnsmasq ebtables qemu-hw-usb-host swtpm
```

`swtpm` is required if you use emulated TPM (recommended — see TPM section below).

## 2. Enable IOMMU

```shell
vim /etc/default/grub
```

Add to `GRUB_CMDLINE_LINUX_DEFAULT`:
```shell
intel_iommu=on iommu=pt
```

Regenerate:
```shell
grub-mkconfig -o /boot/grub/grub.cfg
```

## 3. Enable libvirt + networking

```shell
systemctl enable --now libvirtd
virsh net-start default
virsh net-autostart default
usermod -aG kvm,input,libvirt $(whoami)
```

Note: the default libvirt network is **NAT**, reachable only from the host itself.
Other devices on your LAN (phone, laptop) can't reach the VM's IP directly — see the
Networking section below for how to work around this or switch to bridged. You can use tailscale to resolve this issue. 

## 4. Create the VM

Launch `virt-manager`, create a new VM, select **Customize before install**.

- **Overview**: Chipset = Q35, Firmware = UEFI
- **CPU**: model = `host-passthrough`, topology = match your physical cores/threads (see
  CPU Pinning section below for a full pinning config once installed)
- **Disk**: bus = virtio
- **NIC**: model = virtio
- **TPM**: use **emulated** TPM 2.0, not passthrough (see TPM section — passthrough caused
  a real hardware lockout during testing)
- Add a CDROM with `virtio-win.iso` for drivers

Begin installation. Windows won't see the virtio disk — Load Driver → select
`virtio-iso/amd64/w11` (or `win11` depending on your ISO) when prompted. After install,
run the virtio driver installer from the CDROM, then remove the ISO.

Now add PCI Host devices for your GPU's VGA function and its HDMI/DP audio function.

## 5. GPU vbios (required for single-GPU passthrough)

If your GPU was the primary boot GPU, its ROM was already consumed by host firmware and
QEMU can't reliably re-read it live — you'll hit `vfio-pci: No more image in the PCI ROM`
without a dumped copy. Dump it **before** running the passthrough script, while the GPU
is still driven by the host driver:

```shell
echo 1 > /sys/bus/pci/devices/0000:01:00.0/rom
cat /sys/bus/pci/devices/0000:01:00.0/rom > /root/vbios.rom
echo 0 > /sys/bus/pci/devices/0000:01:00.0/rom
```
Should start with `55 aa`. If the dump is empty, use a matching vbios from
[TechPowerUp's VGA BIOS database](https://www.techpowerup.com/vgabios/) instead, matched
to your exact card + board partner (check subsystem ID via `lspci -vvv -s 01:00.0`).

**Important — where you put the file matters.** Libvirt runs QEMU in a private mount
namespace; a file under `/root/` or `/home/<user>/` is invisible to QEMU even as root,
causing `failed to find romfile`. Put it alongside your VM's disk image instead, since
that path is already whitelisted:

```shell
cp /root/vbios.rom /mnt/Game_1/KVMS/vbios.rom
```

Only reference it on the **GPU** hostdev, not the audio one:
```xml
<hostdev mode="subsystem" type="pci" managed="yes">
  <source>
    <address domain="0x0000" bus="0x01" slot="0x00" function="0x0"/>
  </source>
  <rom file="/mnt/Game_1/KVMS/vbios.rom" bar="on"/>
  <address type="pci" domain="0x0000" bus="0x04" slot="0x00" function="0x0"/>
</hostdev>
```

## 6. First driver install — temporary virtual display

Use a SSH tunnel and use RDP client. 
```shell
ssh -L 3389:192.168.122.162:3389 root@<Linux_host_IP>
```

## 7. Hide the hypervisor from NVIDIA (avoid Code 43)

```xml
<features>
  <acpi/>
  <apic/>
  <hyperv mode="custom">
    <relaxed state="on"/>
    <vapic state="on"/>
    <spinlocks state="on" retries="8191"/>
    <vpindex state="on"/>
    <runtime state="on"/>
    <synic state="on"/>
    <stimer state="on"/>
    <vendor_id state="on" value="fuckwindows"/>
    <frequencies state="on"/>
    <tlbflush state="on"/>
    <ipi state="on"/>
    <evmcs state="on"/>
    <avic state="on"/>
  </hyperv>
  <kvm>
    <hidden state="on"/>
  </kvm>
  <smm state="on"/>
</features>
```

Consumer NVIDIA GPUs refuse to initialize properly if they detect they're in a VM — this is the intended fix.

## 8. TPM — use emulated, not passthrough (If windows 11)

```xml
<tpm model="tpm-crb">
  <backend type="emulator" version="2.0"/>
</tpm>
```

This satisfies Windows 11's TPM requirement via `swtpm` (a per-VM software TPM libvirt
manages itself) — no `/dev/tpm0` permission issues, no exclusivity conflicts.

**Avoid real hardware TPM passthrough** (`<backend type="passthrough"><device
path="/dev/tpm0"/></backend>`) unless you specifically need hardware-backed TPM state.
Repeated/failed passthrough attempts on this hardware put the physical fTPM into a bad
state (`Tss2_Tcti_Device_Init() ... errno 5: Input/output error`), which cascaded into
**libvirtd itself failing to start** (systemd's credential-import step also talks to
`/dev/tpm0`). Recovery required a full host reboot. Emulated TPM avoids this whole class
of problem.

## 9. CPU pinning & memory

Example for a 16-thread / 8-core CPU, giving 6 physical cores (12 threads) to the guest
and keeping 2 physical cores (4 threads) for the host, with 24GB RAM:

```xml
<memory unit="KiB">25165824</memory>
<currentMemory unit="KiB">25165824</currentMemory>

<vcpu placement="static">12</vcpu>
<iothreads>1</iothreads>

<cputune>
  <vcpupin vcpu="0" cpuset="2"/>
  <vcpupin vcpu="1" cpuset="10"/>
  <vcpupin vcpu="2" cpuset="3"/>
  <vcpupin vcpu="3" cpuset="11"/>
  <vcpupin vcpu="4" cpuset="4"/>
  <vcpupin vcpu="5" cpuset="12"/>
  <vcpupin vcpu="6" cpuset="5"/>
  <vcpupin vcpu="7" cpuset="13"/>
  <vcpupin vcpu="8" cpuset="6"/>
  <vcpupin vcpu="9" cpuset="14"/>
  <vcpupin vcpu="10" cpuset="7"/>
  <vcpupin vcpu="11" cpuset="15"/>
  <emulatorpin cpuset="0-1,8-9"/>
  <iothreadpin iothread="1" cpuset="0-1,8-9"/>
</cputune>

<numatune>
  <memory mode="strict" nodeset="0"/>
</numatune>

<cpu mode="host-passthrough" check="none" migratable="off">
  <topology sockets="1" dies="1" clusters="1" cores="6" threads="2"/>
  <numa>
    <cell id="0" cpus="0-11" memory="25165824" unit="KiB"/>
  </numa>
</cpu>
```

Adjust core/thread numbers, memory, and pinning to match your own `lstopo` output.

## 10. Keyboard/mouse
```shell
<input type='tablet' bus='usb'>
<input type='mouse' bus='ps2'/>
<input type='keyboard' bus='ps2'/>
```


## 11. Hooks

```shell
mkdir /etc/libvirt/hooks
touch /etc/libvirt/hooks/qemu
chmod +x /etc/libvirt/hooks/qemu
```

```shell
vim /etc/libvirt/hooks/qemu
```
```shell
#!/bin/bash

GUEST_NAME="$1"
HOOK_NAME="$2"
STATE_NAME="$3"
MISC="${@:4}"

BASEDIR="$(dirname $0)"

HOOKPATH="$BASEDIR/qemu.d/$GUEST_NAME/$HOOK_NAME/$STATE_NAME"
set -e

if [ -f "$HOOKPATH" ]; then
eval \""$HOOKPATH"\" "$@"
elif [ -d "$HOOKPATH" ]; then
while read file; do
  eval \""$file"\" "$@"
done <<< "$(find -L "$HOOKPATH" -maxdepth 1 -type f -executable -print;)"
fi
```

```shell
# Script directory structure
[root@overlord hooks]# tree
.
├── qemu
└── qemu.d
    └── win11
        ├── prepare
        │   └── begin
        │       └── start.sh
        └── release
            └── end
                └── stop.sh
```

```shell
mkdir -p /etc/libvirt/hooks/qemu.d/win11/prepare/begin
mkdir -p /etc/libvirt/hooks/qemu.d/win11/release/end
chmod +x /etc/libvirt/hooks/qemu.d/win11/prepare/begin/start.sh
chmod +x /etc/libvirt/hooks/qemu.d/win11/release/end/stop.sh
```

## 12. Networking — reaching the VM from other devices

The default libvirt network is NAT'd behind `virbr0` — only the host can reach the VM's
IP directly. To RDP in from another device (phone, laptop):

```shell
ssh -L 3389:<vm-ip>:3389 root@<host-ip>
```
then RDP to `localhost:3389` on the client device.

Get the VM's current IP:
```shell
virsh domifaddr win11
# or
cat /var/lib/libvirt/dnsmasq/virbr0.status
```
