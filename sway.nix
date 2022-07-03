{ config, pkgs, ... }:

let
  # bash script to let dbus know about important env variables and
  # propogate them to relevent services run at the end of sway config
  # see
  # https://github.com/emersion/xdg-desktop-portal-wlr/wiki/"It-doesn't-work"-Troubleshooting-Checklist
  # note: this is pretty much the same as  /etc/sway/config.d/nixos.conf but also restarts  
  # some user services to make sure they have the correct environment variables
  dbus-sway-environment = pkgs.writeTextFile {
    name = "dbus-sway-environment";
    destination = "/bin/dbus-sway-environment";
    executable = true;

    text = ''
  dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway
  systemctl --user stop pipewire pipewire-media-session xdg-desktop-portal xdg-desktop-portal-wlr
  systemctl --user start pipewire pipewire-media-session xdg-desktop-portal xdg-desktop-portal-wlr
      '';
  };

  # currently, there is some friction between sway and gtk:
  # https://github.com/swaywm/sway/wiki/GTK-3-settings-on-Wayland
  # the suggested way to set gtk settings is with gsettings
  # for gsettings to work, we need to tell it where the schemas are
  # using the XDG_DATA_DIR environment variable
  # run at the end of sway config
  configure-gtk = pkgs.writeTextFile {
      name = "configure-gtk";
      destination = "/bin/configure-gtk";
      executable = true;
      text = let
        schema = pkgs.gsettings-desktop-schemas;
        datadir = "${schema}/share/gsettings-schemas/${schema.name}";
      in ''
        export XDG_DATA_DIRS=${datadir}:$XDG_DATA_DIRS
        gnome_schema=org.gnome.desktop.interface
        gsettings set $gnome_schema gtk-theme 'Adwaita-dark'
        gsettings set $gnome_schema icon-theme 'Adwaita'
        '';
  };

in
{
  environment.systemPackages = with pkgs; [
    dbus-sway-environment
    configure-gtk
    wayland
    pipewire
    sway
    swaylock                    # wayland screen locker
    swayidle                    # wayland idle managament daemon
    mako                        # notification daemon
    alacritty                   # terminal emulator
    fuzzel                      # wayland native application launcher
    waybar                      # status bar
    glib                        # gsettings
    gnome-themes-extra          # gtk themes including adwaita-dark
    gnome3.adwaita-icon-theme   # default gnome cursors
    adwaita-qt                  # gtk adwaita themes for qt
    qt5ct                       # qt5 configuration utility
  ];

  services.greetd = {
    enable = true;
    settings = rec {
      initial_session = {
        command = "${pkgs.sway}/bin/sway";
        user = config.services.vars.user;
      };
      default_session = initial_session;
    };
  };

  # rtkit is optional but recommended
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # xdg-desktop-portal works by exposing a series of D-Bus interfaces
  # known as portals under a well-known name
  # (org.freedesktop.portal.Desktop) and object path
  # (/org/freedesktop/portal/desktop).
  # The portal interfaces include APIs for file access, opening URIs,
  # printing and others.
  services.dbus.enable = true;
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    # gtk portal needed to make gtk apps happy
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    gtkUsePortal = true;
  };

  # enable sway window manager
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  environment.sessionVariables = {
    # fixes cursor disappearing issues in VMs
    WLR_NO_HARDWARE_CURSORS = "1";
    # control qt theme with qt5ct
    QT_QPA_PLATFORMTHEME = "qt5ct";
    # fixes gtk theme not applying to certain apps (maybe its gtk4 apps? evince/seahorse)
    GTK_THEME = "Adwaita:dark";
  };
}
