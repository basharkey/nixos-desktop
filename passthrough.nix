{ config, pkgs, lib, ... }:

with lib;

let
  cpuInfo = builtins.readFile /proc/cpuinfo;

  name = "win10-vfio";
  cores = 4;
  threads = 2;
  memory = 16;
  disk = "/dev/disk/by-id/wwn-0x500a0751e14b33a3";
  mouse = "/dev/input/by-id/usb-Primax_Kensington_Eagle_Trackball-event-mouse";
  keyboard = "/dev/input/by-id/usb-t.m.k._PS_2_keyboard_converter-event-kbd";

  vfioBindIds = [
    "10de:1b80"
    "10de:10f0"
    "1102:0012"
  ];

  pciPassIds = [
    "9:00.0"
    "9:00.1"
    "5:00.0"
    "0b:00.3"
  ];

in {
  # set intel_iommu=on for Intel CPUs and amd_iommu=on for AMD CPUs
  boot.kernelParams =  if builtins.match ".*vendor_id\t: GenuineIntel.*" cpuInfo == [ ] then [ "intel_iommu=on" ] else if builtins.match ".*vendor_id\t: AuthenticAMD.*" cpuInfo == [ ] then [ "amd_iommu=on" ] else null;

  boot.kernelModules = [ "vfio" "vfio_iommu_type1" "vfio_pci" "vfio_virqfd" ];
  boot.extraModprobeConfig ="options vfio-pci ids=${builtins.concatStringsSep "," vfioBindIds}";

  environment.systemPackages = with pkgs; [
    win-virtio # use ${pkgs.win-virtio.src} to access raw iso
    pciutils
    gawk
  ];

  # libvirt vm definition
  # https://nixos.wiki/wiki/NixOps/Virtualization
  # cant use mkDerivation as virsh requires libvirtd.service running
  systemd.services."${name}" = {
    after = [ "libvirtd.service" ];
    requires = [ "libvirtd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
    };
    script =
      let
        xml = pkgs.writeText "${name}.xml" ''
          <domain type="kvm">
            <name>${name}</name>
            <uuid>UUID</uuid>
            <memory unit="GiB">${builtins.toString memory}</memory>
            <vcpu placement='static'>${builtins.toString (cores * threads)}</vcpu>
            <os>
              <type arch="x86_64" machine="q35">hvm</type>
              <loader readonly="yes" type="pflash">/run/libvirt/nix-ovmf/OVMF_CODE.fd</loader>
              <nvram>/var/lib/libvirt/qemu/nvram/${name}_VARS.fd</nvram>
            </os>
            <features>
              <acpi/>
              <hyperv>
                <vendor_id state='on' value='1234567879ab'/>
              </hyperv>
              <kvm>
                <hidden state='on'/>
              </kvm>
              <vmport state='off'/>
            </features>
            <cpu mode="host-model" check="partial">
              <topology sockets="1" dies="1" cores="${builtins.toString cores}" threads="${builtins.toString threads}"/>
            </cpu>
            <clock offset='localtime'>
              <timer name='rtc' tickpolicy='catchup'/>
              <timer name='pit' tickpolicy='delay'/>
              <timer name='hpet' present='no'/>
            </clock>
            <devices>
              <disk type="block" device="disk">
                <driver name="qemu" type="raw" cache="none" io="native"/>
                <source dev="${disk}"/>
                <target dev="vda" bus="virtio"/>
                <boot order="1"/>
              </disk>
              <disk type="file" device="cdrom">
                <driver name="qemu" type="raw"/>
                <source file="${pkgs.win-virtio.src}"/>
                <target dev='sda' bus='sata'/>
                <readonly/>
              </disk>
              <interface type='network'>
                <source network='default'/>
                <model type='virtio'/>
              </interface>
              <input type="evdev">
                <source dev="${keyboard}" grab="all" repeat="on"/>
              </input>
              <input type="evdev">
                <source dev="${mouse}"/>
              </input>
            </devices>
          </domain>
        '';
      in
        ''
          # set $uuid to vm uuid if it has already been defined, other set it to blank string
          uuid="$(${pkgs.libvirt}/bin/virsh domuuid '${name}' || true)"

          # replace "UUID" string in xml with $uuid if it exists, otherwise remove "UUID" string from xml
          # vm will always be redefined as uuid is specified in xml
          ${pkgs.libvirt}/bin/virsh define <(sed "s/UUID/$uuid/" '${xml}')
        '';
      # don't start service if the vm is already defined in libvirt
      # /var/lib/libvirt/qemu/
      # disabling this so vm is rebuilt on system/service restart (this is the nix way!)
      #unitConfig.ConditionPathExists = "!/var/lib/libvirt/qemu/${name}.xml";
  };

  # libvirt pci passthrough definitions
  systemd.services."${name}-pci" = {
    after = [ "libvirtd.service" "${name}.service" ];
    requires = [ "libvirtd.service" "${name}.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script =
      let
        xml = pkgs.writeText "${name}-pci.xml" ''
          <hostdev mode="subsystem" type="pci" managed="yes">
            <source>
              <address domain="0" bus="BUS" slot="SLOT" function="FUNCTION"/>
            </source>
          </hostdev>
        '';
      in
        ''
          for pciId in ${builtins.concatStringsSep " " pciPassIds}
          do
             # awk get first field with delimeter ":"
             bus=$(echo "$pciId" | ${pkgs.gawk}/bin/awk -F":" '{print "0x"$1}')
             xml=$(sed -e "s/BUS/$bus/" ${xml})

             # awk get string between ":" and "."
             slot=$(echo "$pciId" | ${pkgs.gawk}/bin/awk -F"[:.]" '{print "0x"$2}')
             xml=$(echo "$xml" | sed -e "s/SLOT/$slot/")

             # awk get string between "." and " "
             function=$(echo "$pciId" | ${pkgs.gawk}/bin/awk -F"[. ]" '{print "0x"$2}')
             xml=$(echo "$xml" | sed -e "s/FUNCTION/$function/")
             ${pkgs.libvirt}/bin/virsh attach-device --config ${name} <(echo "$xml")
          done
        '';
  };


  # libvirt vm hooks
  systemd.services."${name}-hooks" = {
    after = [ "libvirtd.service" "${name}.service" ];
    requires = [ "libvirtd.service" "${name}.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script =
      let
        beginScript = pkgs.writeShellScript "poweron.sh" ''
          # enable cpu governor performance mode
          for file in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo "performance" > $file; done
        '';

        endScript = pkgs.writeShellScript "shutdown.sh" ''
          # enable cpu governor ondemand mode
          for file in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo "ondemand" > $file; done
        '';

        beginDir = "/var/lib/libvirt/hooks/qemu.d/${name}/prepare/begin";
        endDir = "/var/lib/libvirt/hooks/qemu.d/${name}/release/end";
      in
        ''
          mkdir -p ${beginDir}
          ln -sf ${beginScript} ${beginDir}/poweron.sh

          mkdir -p ${endDir}
          ln -sf ${endScript} ${endDir}/shutdown.sh
        '';
  };
}
