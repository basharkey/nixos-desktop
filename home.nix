{ config, pkgs, ... }:
let
  home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/master.tar.gz";

  wayweather = pkgs.stdenv.mkDerivation {
    name = "wayweather";
    # disable unpack phase
    dontUnpack = true;
    buildInputs = [
      (pkgs.python3.withPackages (pythonPackages: with pythonPackages; [
        requests
        beautifulsoup4
        pyyaml
      ]))
    ];
    src = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/basharkey/wayweather/f25d2f34ff0d25cd8a026e8e2c59139b3a6b2cce/wayweather.py";
      sha256 = "03e78855605daf28e83a45d102389629f5953335b6d0122dbdb66513a941d35f";
    };
    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/wayweather
      chmod +x $out/bin/wayweather
    '';
  };

  nas-backup-include = pkgs.writeTextFile {
    name = "nas-backup-include";
    text = ''
      Documents/
      Pictures/
      Videos/
      Nextcloud/
      Notebooks/
      projects/
    '';
  };

  nas-backup-exclude = pkgs.writeTextFile {
    name = "nas-backup-exclude";
    text = ''
      .*
      */bin/
      include/
      lib/
      lib64/
      __pycache__/
    '';
  };

in
{
  imports = [
    (import "${home-manager}/nixos")
  ];

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users = {
    "${config.services.vars.user}" = {
      isNormalUser = true;
      uid = 1000;
      extraGroups = [
        "users"
        "wheel"
        "networkmanager"
      ];
    };
  };

  home-manager.users."${config.services.vars.user}" = {
    programs.home-manager.enable = true;
    home.homeDirectory = "/home/${config.services.vars.user}";

    home.packages = with pkgs; [
      wayweather                 # waybar weather widget
      wl-clipboard               # wayland copy/paste utility
      firefox-wayland            # web browser
      easyeffects                # pipewire equalizer
      playerctl                  # media player utility
      pavucontrol                # pulseaudio volume control
      xfce.thunar                # file manager
      xfce.thunar-volman         # thunar automount
      xfce.thunar-archive-plugin # thunar archive
      xfce.xfconf                # thunar configuration
      xfce.exo                   # thunar "open terminal here"
      gvfs                       # thunar remote mounts, trash
      xfce.ristretto             # picture viewer
      libreoffice                # office suite
      evince                     # pdf viewer
      qalculate-gtk              # calculator
      gimp                       # photo editor
      nextcloud-client           # cloud file hosting client
      #etcher                     # usb image writer (insecure electron version)
      gnome.seahorse
      keepassxc
      discord
      spotify
      freetube
    ];

    home.file = {
      ".config/sway/wallpaper.png".source = pkgs.fetchurl {
        url = "https://github.com/NixOS/nixos-artwork/blob/master/wallpapers/nix-wallpaper-simple-blue.png";
        sha256 = "badadc8f37de26814ea546c563678850d08acb9ae32ede7bc48a1452cb0999d2";
      };
    };

    home.stateVersion = config.system.stateVersion;
  };

  fonts.fonts = with pkgs; [
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
  ];

  services.gvfs.enable = true; # thunar network mounts, trash
  services.tumbler.enable = true; # thunar thumbnail image support
  programs.ssh.startAgent = true; # ssh agent
  # programs.ssh.enableAskPassword = true; # currently doesn't work on sway

  systemd.tmpfiles.rules = [
    "d /home/${config.services.vars.user}/nas 0755 ${config.services.vars.user} users"
  ];

  fileSystems."/home/${config.services.vars.user}/nas" = {
      device = "//${config.services.vars.smbServer}/${config.services.vars.user}";
      fsType = "cifs";
      options = let
        # this line prevents hanging on network split
        automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";
        permissions_opts = "uid=${builtins.toString config.users.users.${config.services.vars.user}.uid},gid=${builtins.toString config.users.groups.users.gid}";

      in ["${automount_opts},${permissions_opts},iocharset=utf8,vers=3.0,credentials=/etc/nixos/smb-secrets"];
  };

  systemd.user.services.nas-backup = {
    description = "NAS rsync backup";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    wantedBy = [ ];
    startAt = "daily";
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.rsync}/bin/rsync -rtsv --info progress2 --exclude-from ${nas-backup-exclude} --files-from ${nas-backup-include} %h/ %h/nas/desktop-backup/";
    };
  };

  systemd.user.services.nas-prune = {
    description = "NAS rsync prune";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    wantedBy = [ ];
    # uncomment to enable (creates systemd timer)
    #startAt = "monthly";
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.rsync}/bin/rsync -rtsv --delete --info progress2 --exclude-from ${nas-backup-exclude} --files-from ${nas-backup-include} %h/ %h/nas/desktop-backup/";
    };
  };
}
