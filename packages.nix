{ config, pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;

  # to search for packages run:
  # $ nix search nixpkgs vim

  # system packages
  environment.systemPackages = with pkgs; [
    vim                 # text editor
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
  ];
}
