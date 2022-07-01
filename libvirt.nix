{ config, pkgs, ... }:

{
  virtualisation.libvirtd.enable = true;
  virtualisation.libvirtd.qemu.ovmf.enable = true;
  virtualisation.libvirtd.allowedBridges = [ "virbr0" ];

  programs.dconf.enable = true;

  users.users."${config.services.vars.user}".extraGroups = [ "libvirtd" ];

  environment.sessionVariables.LIBVIRT_DEFAULT_URI = [ "qemu:///system" ];
  environment.systemPackages = with pkgs; [
    qemu
    OVMF
    libvirt
    virt-manager
  ];

  systemd.services.libvirtd = {
    # add binaries to path so that hooks can use them
    # https://github.com/NixOS/nixpkgs/issues/51152
    path = let
      env = pkgs.buildEnv {
        name = "qemu-hook-env";
        paths = with pkgs; [
          bash
        ];
      };
    in [ env ];

    # fetch qemu hook helper script
    # https://github.com/PassthroughPOST/VFIO-Tools
    preStart =
      let
        hookHelper = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/PassthroughPOST/VFIO-Tools/master/libvirt_hooks/qemu";
          sha256 = "e6e561566395ffe1ee3d3615524637d001c4ea9a087bc46ef0bdd3328af9ad94";
        };
      in
        ''  
          mkdir -p /var/lib/libvirt/hooks
          ln -sf ${hookHelper} /var/lib/libvirt/hooks/qemu
        '';
  };
}
