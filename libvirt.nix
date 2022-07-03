{ config, pkgs, lib, ... }:

with lib;

{
  virtualisation.libvirtd.enable = true;
  virtualisation.libvirtd.qemu.ovmf.enable = true;
  virtualisation.libvirtd.allowedBridges = [ "virbr0" ];

  programs.dconf.enable = true;

  users.users."${config.services.vars.user}".extraGroups = [ "libvirtd" ];

  # don't think this works
  environment.sessionVariables.LIBVIRT_DEFAULT_URI = [ "qemu:///system" ];

  environment.systemPackages = with pkgs; [
    qemu
    OVMF
    libvirt
    virt-manager
  ];

  # restart libvirtd to apply any configuration changes
  systemd.services.libvirtd = {
    # add bash to env
    # https://github.com/NixOS/nixpkgs/issues/51152
    path = let
      env = pkgs.buildEnv {
        name = "qemu-hook-env";
        paths = with pkgs; [
          bash
        ];
      };
    in [ env ];
    # create qemu hook helper script with proper bash location
    # https://github.com/PassthroughPOST/VFIO-Tools
    preStart =
      let
        hookHelper = pkgs.writeScriptBin "qemu" (builtins.readFile (pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/PassthroughPOST/VFIO-Tools/master/libvirt_hooks/qemu";
          sha256 = "a0b3a8754d8fb4eee75faed6f0fb9f9683d86a6f5acb2d305991a3625ff76d60";
        }));
      in
        ''  
          mkdir -p /var/lib/libvirt/hooks
          ln -sf ${hookHelper}/bin/qemu /var/lib/libvirt/hooks
        '';
  };
}
