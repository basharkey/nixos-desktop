{ config, pkgs, lib, ... }:

with lib;

{
  nixpkgs.config.allowUnfree = true;

  # to search for packages run:
  # $ nix search nixpkgs vim

  # system packages
  environment.systemPackages = with pkgs; [
    wget                # retrieve files over HTTP/FTP
    git                 # version control system
    wireguard-tools     # vpn client
    usbutils            # usb utilities
    dig                 # dns query utility
    python3             # python language
    rsync               # file transfer utility
    file
    fd
    nixos-option
    (vim_configurable.customize {
      vimrcConfig.packages.myVimPackage = with pkgs.vimPlugins; {
        start = [ fugitive ];
      };
      vimrcConfig.customRC = builtins.readFile "/home/${config.services.vars.user}/.vimrc";
    })
  ];
}
