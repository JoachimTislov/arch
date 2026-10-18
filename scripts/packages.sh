#!/usr/bin/env bash

packages=(
  ### yazi ###
  yazi
  file
  ffmpeg
  7zip
  jq
  poppler
  fd
  ripgrep
  fzf
  zoxide
  imagemagick
  ### nvim ###
  unzip
  make
  gcc
  neovim
  vim
  pnpm
  go
  lua51            # TODO: Upgrade
  lua51-filesystem # TODO: Upgrade
  luarocks
  tree-sitter-cli
  python-pip
  ### hyprland ###
  hyprland
  hyprpaper
  hyprlock
  hypridle
  kitty
  waybar
  mako
  pipewire
  pipewire-pulse
  wireplumber
  hyprpolkitagent
  rofi
  qt5-wayland
  qt6-wayland
  qt6ct
  qt5ct
  breeze-icons
  kvantum
  dolphin
  resvg
  ark
  xdg-desktop-portal-hyprland
  xdg-desktop-portal-gtk
  sddm
  qt6-svg
  qt6-virtualkeyboard
  qt6-multimedia-ffmpeg
  uwsm
  libnewt
  cliphist
  playerctl
  lm_sensors
  wf-recorder
  btrfs-progs
  snapper
  snap-pac
  gtk4
  gtk3
  ### fonts ###
  ttf-firacode-nerd
  ttf-font-awesome
  noto-fonts-emoji
  ### art ###
  fastfetch
  genact
  cava
  ### system monitor ###
  btop
  htop
  mission-center
  ### misc ###
  stow
  cronie # cron daemon, runs the backup job (dotfiles/crontab)
  less
  eza
  brightnessctl
  wget
  lsb-release
  man-pages
  base-devel
  tmux
  firefox
  bitwarden
  discord
  zsh
  thefuck
  github-cli
  gimp
  ncspot
  docker
  spotify-launcher
  bluez-utils
  bluez
  blueman
  usbutils
  speedtest-cli
  ripgrep
  grim
  slurp
  jdk-openjdk
  postgresql
  gradle
  # maven
  cmus
  lynx
  uv
  typst
  php
  php-sqlite
  sqlitebrowser
  lftp
  wireshark-qt
  yt-dlp # youtube-tui dependency
  docker-compose
)

user_packages=(
  waypaper
  postman-bin
  adwaita-dark
  adwaita-qt5-git
  youtube-tui
  cmatrix-git
  wlogout
  hollywood
  asciiquarium-transparent-git
  nordzy-cursors
)

if lsblk -f | grep -Eiq 'Windows|ntfs'; then
  packages+=(os-prober)
fi

if [ "$(hostnamectl chassis)" = "desktop" ]; then
  packages+=(
    xorg-xrandr
    xorg-xrdb
    linux-firmware-realtek # for bluetooth
  )
else
  packages+=(
    power-profiles-daemon
  )
fi

# Nvidia gpu configuration - https://wiki.hypr.land/Nvidia/
if lspci | grep -i nvidia >/dev/null; then
  packages+=(
    nvidia-utils
    nvidia-settings
    nvidia
    egl-wayland
  )
fi
