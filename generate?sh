#!/bin/bash
# generate.sh — Générateur interactif autoinstall.yaml
# Ubuntu 26.04 LTS — Supporte LVM/Direct, ext4/btrfs/xfs

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[1;34m'
CYN='\033[0;36m'
BLD='\033[1m'
RST='\033[0m'

banner() {
    echo -e "${BLU}${BLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║     Générateur autoinstall.yaml — Ubuntu 26.04 LTS      ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${RST}"
}

section() {
    echo ""
    echo -e "${CYN}${BLD}┌─ $1 ─────────────────────────────────────────────${RST}"
}

ask() {
    local prompt="$1"
    local default="$2"
    if [[ -n "$default" ]]; then
        echo -ne "${BLD}  ➜ $prompt ${YLW}[$default]${RST} : "
    else
        echo -ne "${BLD}  ➜ $prompt${RST} : "
    fi
    read -r input
    REPLY="${input:-$default}"
}

ask_password() {
    local prompt="$1"
    local pw1 pw2
    while true; do
        echo -ne "${BLD}  ➜ $prompt${RST} : "
        read -rs pw1
        echo
        echo -ne "${BLD}  ➜ Confirmer${RST} : "
        read -rs pw2
        echo
        if [[ "$pw1" == "$pw2" ]]; then
            REPLY="$pw1"
            break
        else
            echo -e "${RED}  ✗ Les mots de passe ne correspondent pas, réessayez.${RST}"
        fi
    done
}

choose() {
    local prompt="$1"
    shift
    local opts=("$@")
    echo -e "${BLD}  ➜ $prompt${RST}"
    for i in "${!opts[@]}"; do
        echo -e "    ${YLW}$((i + 1)))${RST} ${opts[$i]}"
    done
    while true; do
        echo -ne "    Choix [1-${#opts[@]}] : "
        read -r input
        if [[ "$input" =~ ^[0-9]+$ ]] && ((input >= 1 && input <= ${#opts[@]})); then
            CHOICE=$input
            REPLY="${opts[$((input - 1))]}"
            break
        fi
        echo -e "${RED}  ✗ Choix invalide.${RST}"
    done
}

yes_no() {
    local prompt="$1"
    local default="${2:-o}"
    while true; do
        if [[ "$default" == "o" ]]; then
            echo -ne "${BLD}  ➜ $prompt ${YLW}[O/n]${RST} : "
        else
            echo -ne "${BLD}  ➜ $prompt ${YLW}[o/N]${RST} : "
        fi
        read -r input
        input="${input:-$default}"
        case "${input,,}" in
        o | oui | y | yes)
            REPLY="yes"
            return 0
            ;;
        n | non | no)
            REPLY="no"
            return 1
            ;;
        esac
        echo -e "${RED}  ✗ Répondre o ou n.${RST}"
    done
}

validate_size() {
    [[ "$1" =~ ^[0-9]+[MG]$ ]] && return 0
    echo -e "${RED}  ✗ Format invalide. Utiliser ex: 512M, 1G, 30G${RST}"
    return 1
}

list_disks() {
    echo -e "${BLD}  Disques détectés :${RST}"
    if command -v lsblk &>/dev/null; then
        lsblk -dpno NAME,SIZE,MODEL 2>/dev/null | grep -v "loop" |
            awk '{printf "    %s  %-8s  %s\n", $1, $2, $3}' || true
    fi
}

banner

# =============================================================
# 1. SYSTÈME
# =============================================================
section "1. SYSTÈME"

ask "Nom d'hôte (hostname)" "ubuntoutou"
HOSTNAME="$REPLY"

ask "Nom d'utilisateur" "cyber"
USERNAME="$REPLY"

ask "Nom complet (GECOS, laisser vide si inutile)" ""
REALNAME="$REPLY"

ask_password "Mot de passe utilisateur"
PASSWORD_USER="$REPLY"

ask_password "Mot de passe root"
PASSWORD_ROOT="$REPLY"

# =============================================================
# 2. LOCALISATION
# =============================================================
section "2. LOCALISATION"

choose "Locale système" \
    "fr_FR.UTF-8" \
    "en_US.UTF-8" \
    "en_GB.UTF-8" \
    "de_DE.UTF-8" \
    "es_ES.UTF-8" \
    "Autre (saisie manuelle)"
if [[ $CHOICE -eq 6 ]]; then
    ask "Locale (ex: ja_JP.UTF-8)" "fr_FR.UTF-8"
    LOCALE="$REPLY"
else
    LOCALE="$REPLY"
fi

choose "Disposition clavier" \
    "fr" \
    "fr (latin9)" \
    "us" \
    "de" \
    "es" \
    "Autre (saisie manuelle)"
case $CHOICE in
1)
    KEYBOARD="fr"
    KEYBOARD_VARIANT=""
    ;;
2)
    KEYBOARD="fr"
    KEYBOARD_VARIANT="latin9"
    ;;
3)
    KEYBOARD="us"
    KEYBOARD_VARIANT=""
    ;;
4)
    KEYBOARD="de"
    KEYBOARD_VARIANT=""
    ;;
5)
    KEYBOARD="es"
    KEYBOARD_VARIANT=""
    ;;
6)
    ask "Layout clavier (ex: fr)" "fr"
    KEYBOARD="$REPLY"
    ask "Variante (laisser vide si aucune)" ""
    KEYBOARD_VARIANT="$REPLY"
    ;;
esac

choose "Fuseau horaire" \
    "Europe/Paris" \
    "Europe/London" \
    "America/New_York" \
    "America/Los_Angeles" \
    "Asia/Tokyo" \
    "Autre (saisie manuelle)"
if [[ $CHOICE -eq 6 ]]; then
    ask "Timezone (ex: Asia/Tokyo)" "Europe/Paris"
    TIMEZONE="$REPLY"
else
    TIMEZONE="$REPLY"
fi

# =============================================================
# 3. DISQUE
# =============================================================
section "3. DISQUE"

list_disks
ask "Disque cible" "/dev/sda"
DISK="$REPLY"

# =============================================================
# 4. TYPE DE STOCKAGE
# =============================================================
section "4. TYPE DE STOCKAGE"

choose "Type de partitionnement" \
    "LVM (Logical Volume Manager)" \
    "Direct (partitions physiques classiques)"
STORAGE_TYPE=$CHOICE

choose "Système de fichiers principal (/, /home)" \
    "ext4" \
    "btrfs" \
    "xfs"
FS_MAIN="$REPLY"

FS_EFI="vfat"
FS_BOOT="ext4"
FS_ROOT="$FS_MAIN"
FS_HOME="$FS_MAIN"

# =============================================================
# 5. TAILLES DES PARTITIONS
# =============================================================
section "5. TAILLES DES PARTITIONS"

echo -e "  ${YLW}Format attendu : 512M, 1G, 30G, etc. (-1 = reste du disque)${RST}"

while true; do
    ask "Taille partition EFI" "512M"
    SIZE_EFI="$REPLY"
    validate_size "$SIZE_EFI" && break
done

while true; do
    ask "Taille partition /boot" "1G"
    SIZE_BOOT="$REPLY"
    validate_size "$SIZE_BOOT" && break
done

while true; do
    ask "Taille partition swap" "4G"
    SIZE_SWAP="$REPLY"
    validate_size "$SIZE_SWAP" && break
done

while true; do
    ask "Taille partition / (root)" "30G"
    SIZE_ROOT="$REPLY"
    validate_size "$SIZE_ROOT" && break
done

echo -e "  ${GRN}  → /home prendra automatiquement le reste du disque${RST}"

# =============================================================
# 6. LVM
# =============================================================
section "6. LVM (si applicable)"

if [[ $STORAGE_TYPE -eq 1 ]]; then
    ask "Nom du Volume Group" "vg-ubuntu"
    LVM_VG="$REPLY"
    ask "Nom LV swap" "lv-swap"
    LVM_LV_SWAP="$REPLY"
    ask "Nom LV root" "lv-root"
    LVM_LV_ROOT="$REPLY"
    ask "Nom LV home" "lv-home"
    LVM_LV_HOME="$REPLY"
fi

# =============================================================
# 7. NOYAU & RÉSEAU
# =============================================================
section "7. NOYAU & RÉSEAU"

choose "Flaveur du noyau" \
    "hwe (Hardware Enablement — recommandé desktop)" \
    "generic"
case $CHOICE in
1) KERNEL_FLAVOR="hwe" ;;
2) KERNEL_FLAVOR="generic" ;;
esac

choose "Gestionnaire réseau" \
    "NetworkManager (desktop/laptop)" \
    "networkd (serveur)"
case $CHOICE in
1) NETWORK_RENDERER="NetworkManager" ;;
2) NETWORK_RENDERER="networkd" ;;
esac

# =============================================================
# 8. GRUB
# =============================================================
section "8. GRUB"

ask "Options kernel (GRUB_CMDLINE_LINUX_DEFAULT)" "quiet splash"
GRUB_CMDLINE="$REPLY"

ask "Délai menu GRUB en secondes" "5"
GRUB_TIMEOUT="$REPLY"

choose "Style timeout GRUB" \
    "hidden (menu masqué, maintenir Shift pour afficher)" \
    "menu (menu toujours visible)"
case $CHOICE in
1) GRUB_TIMEOUT_STYLE="hidden" ;;
2) GRUB_TIMEOUT_STYLE="menu" ;;
esac

choose "Terminal GRUB" \
    "console" \
    "gfxterm (graphique)"
case $CHOICE in
1) GRUB_TERMINAL="console" ;;
2) GRUB_TERMINAL="gfxterm" ;;
esac

yes_no "Désactiver la détection dual-boot (os-prober) ?" "o"
GRUB_DISABLE_OS_PROBER="$REPLY"
[[ "$REPLY" == "yes" ]] && GRUB_DISABLE_OS_PROBER="true" || GRUB_DISABLE_OS_PROBER="false"

# =============================================================
# 9. SSH
# =============================================================
section "9. SSH"

yes_no "Autoriser login SSH en root ?" "o"
[[ "$REPLY" == "yes" ]] && SSH_ROOT_LOGIN="yes" || SSH_ROOT_LOGIN="no"

# =============================================================
# 10. MISES À JOUR AUTOMATIQUES
# =============================================================
section "10. MISES À JOUR AUTOMATIQUES"

choose "Mises à jour automatiques" \
    "security (sécurité uniquement — recommandé)" \
    "all (toutes les mises à jour)" \
    "none (désactivé)"
case $CHOICE in
1) AUTO_UPDATES="security" ;;
2) AUTO_UPDATES="all" ;;
3) AUTO_UPDATES="none" ;;
esac

# =============================================================
# 11. PAQUETS SUPPLÉMENTAIRES
# =============================================================
section "11. PAQUETS SUPPLÉMENTAIRES"

echo -e "  ${YLW}Paquets de base inclus : curl git vim htop net-tools openssh-server wget unzip${RST}"
echo -e "  ${YLW}bash-completion tree lsof dnsutils nmap tcpdump open-vm-tools-desktop gnome-tweaks${RST}"

yes_no "Ajouter des paquets supplémentaires ?" "n"
EXTRA_PKG_LIST=""
if [[ "$REPLY" == "yes" ]]; then
    echo -e "  ${BLD}Entrez les paquets séparés par des espaces :${RST}"
    echo -ne "  ➜ "
    read -r extra_pkgs
    for pkg in $extra_pkgs; do
        EXTRA_PKG_LIST="${EXTRA_PKG_LIST}\n    - ${pkg}"
    done
fi

yes_no "Ajouter des snaps supplémentaires ?" "n"
EXTRA_SNAP_LIST=""
if [[ "$REPLY" == "yes" ]]; then
    echo -e "  ${BLD}Entrez les snaps séparés par des espaces :${RST}"
    echo -ne "  ➜ "
    read -r extra_snaps
    for snap in $extra_snaps; do
        EXTRA_SNAP_LIST="${EXTRA_SNAP_LIST}\n    - name: ${snap}"
    done
fi

echo ""
echo -e "${GRN}${BLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                     RÉCAPITULATIF                       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${RST}"
echo -e "  Hostname        : ${BLD}$HOSTNAME${RST}"
echo -e "  Utilisateur     : ${BLD}$USERNAME${RST}"
echo -e "  Locale          : ${BLD}$LOCALE${RST}  Clavier: ${BLD}$KEYBOARD${KEYBOARD_VARIANT:+/$KEYBOARD_VARIANT}${RST}"
echo -e "  Timezone        : ${BLD}$TIMEZONE${RST}"
echo -e "  Disque          : ${BLD}$DISK${RST}"
echo -e "  Stockage        : ${BLD}$([[ $STORAGE_TYPE -eq 1 ]] && echo "LVM" || echo "Direct")${RST}  FS: ${BLD}$FS_MAIN${RST}"
echo -e "  Partitions      : EFI=${BLD}$SIZE_EFI${RST}  boot=${BLD}$SIZE_BOOT${RST}  swap=${BLD}$SIZE_SWAP${RST}  root=${BLD}$SIZE_ROOT${RST}  home=reste"
echo -e "  Noyau           : ${BLD}$KERNEL_FLAVOR${RST}  Réseau: ${BLD}$NETWORK_RENDERER${RST}"
echo -e "  SSH root        : ${BLD}$SSH_ROOT_LOGIN${RST}  Updates: ${BLD}$AUTO_UPDATES${RST}"
echo ""

yes_no "Générer le fichier autoinstall.yaml ?" "o" || {
    echo -e "${RED}Annulé.${RST}"
    exit 0
}

HASH_USER=$(openssl passwd -6 "$PASSWORD_USER")
HASH_ROOT=$(openssl passwd -6 "$PASSWORD_ROOT")

build_storage_lvm() {
    cat <<STORAGE
  storage:
    version: 1
    config:
      - type: disk
        id: disk0
        path: ${DISK}
        ptable: gpt
        wipe: superblock
        grub_device: false

      - type: partition
        id: part-efi
        device: disk0
        size: ${SIZE_EFI}
        flag: boot
        grub_device: true

      - type: partition
        id: part-boot
        device: disk0
        size: ${SIZE_BOOT}

      - type: partition
        id: part-lvm
        device: disk0
        size: -1
        flag: linux-lvm

      - type: lvm_volgroup
        id: vg0
        name: ${LVM_VG}
        devices:
          - part-lvm

      - type: lvm_partition
        id: ${LVM_LV_SWAP}
        volgroup: vg0
        name: ${LVM_LV_SWAP}
        size: ${SIZE_SWAP}

      - type: lvm_partition
        id: ${LVM_LV_ROOT}
        volgroup: vg0
        name: ${LVM_LV_ROOT}
        size: ${SIZE_ROOT}

      - type: lvm_partition
        id: ${LVM_LV_HOME}
        volgroup: vg0
        name: ${LVM_LV_HOME}
        size: -1

      - type: format
        id: fmt-efi
        volume: part-efi
        fstype: ${FS_EFI}
        label: EFI

      - type: format
        id: fmt-boot
        volume: part-boot
        fstype: ${FS_BOOT}
        label: boot

      - type: format
        id: fmt-swap
        volume: ${LVM_LV_SWAP}
        fstype: swap
        label: swap

      - type: format
        id: fmt-root
        volume: ${LVM_LV_ROOT}
        fstype: ${FS_ROOT}
        label: root

      - type: format
        id: fmt-home
        volume: ${LVM_LV_HOME}
        fstype: ${FS_HOME}
        label: home

      - type: mount
        id: mnt-efi
        device: fmt-efi
        path: /boot/efi

      - type: mount
        id: mnt-boot
        device: fmt-boot
        path: /boot

      - type: mount
        id: mnt-swap
        device: fmt-swap
        path: none

      - type: mount
        id: mnt-root
        device: fmt-root
        path: /

      - type: mount
        id: mnt-home
        device: fmt-home
        path: /home
STORAGE
}

build_storage_direct() {
    cat <<STORAGE
  storage:
    version: 1
    config:
      - type: disk
        id: disk0
        path: ${DISK}
        ptable: gpt
        wipe: superblock
        grub_device: false

      - type: partition
        id: part-efi
        device: disk0
        size: ${SIZE_EFI}
        flag: boot
        grub_device: true

      - type: partition
        id: part-boot
        device: disk0
        size: ${SIZE_BOOT}

      - type: partition
        id: part-swap
        device: disk0
        size: ${SIZE_SWAP}

      - type: partition
        id: part-root
        device: disk0
        size: ${SIZE_ROOT}

      - type: partition
        id: part-home
        device: disk0
        size: -1

      - type: format
        id: fmt-efi
        volume: part-efi
        fstype: ${FS_EFI}
        label: EFI

      - type: format
        id: fmt-boot
        volume: part-boot
        fstype: ${FS_BOOT}
        label: boot

      - type: format
        id: fmt-swap
        volume: part-swap
        fstype: swap
        label: swap

      - type: format
        id: fmt-root
        volume: part-root
        fstype: ${FS_ROOT}
        label: root

      - type: format
        id: fmt-home
        volume: part-home
        fstype: ${FS_HOME}
        label: home

      - type: mount
        id: mnt-efi
        device: fmt-efi
        path: /boot/efi

      - type: mount
        id: mnt-boot
        device: fmt-boot
        path: /boot

      - type: mount
        id: mnt-swap
        device: fmt-swap
        path: none

      - type: mount
        id: mnt-root
        device: fmt-root
        path: /

      - type: mount
        id: mnt-home
        device: fmt-home
        path: /home
STORAGE
}

BASE_PACKAGES="
    - curl
    - git
    - vim
    - htop
    - net-tools
    - open-vm-tools-desktop
    - openssh-server
    - bash-completion
    - wget
    - unzip
    - zip
    - tree
    - lsof
    - dnsutils
    - traceroute
    - whois
    - nmap
    - tcpdump
    - gnome-tweaks"

ALL_PACKAGES="${BASE_PACKAGES}${EXTRA_PKG_LIST}"

BASE_SNAPS="
    - name: firefox
    - name: gtk-common-themes
    - name: snap-store
    - name: snapd-desktop-integration"

ALL_SNAPS="${BASE_SNAPS}${EXTRA_SNAP_LIST}"

OUTPUT="$(dirname "$0")/autoinstall.yaml"

{
    cat <<HEADER
#cloud-config
# -------------------------------------------------------
# Généré par generate.sh — NE PAS MODIFIER DIRECTEMENT
# Ubuntu 26.04 LTS Resolute Raccoon
# Stockage : $([[ $STORAGE_TYPE -eq 1 ]] && echo "LVM" || echo "Direct") / FS : ${FS_MAIN}
# -------------------------------------------------------
autoinstall:
  version: 1

  packages:
    - ubuntu-desktop${ALL_PACKAGES}

  snaps:${ALL_SNAPS}

  identity:
    realname: '${REALNAME}'
    username: ${USERNAME}
    password: "USERHASHPLACEHOLDER"
    hostname: ${HOSTNAME}

  keyboard:
    layout: ${KEYBOARD}
    variant: '${KEYBOARD_VARIANT}'

  locale: ${LOCALE}

  timezone: ${TIMEZONE}

  network:
    ethernets:
      any-eth:
        match:
          name: "e*"
        dhcp4: true
    version: 2

HEADER

    if [[ $STORAGE_TYPE -eq 1 ]]; then
        build_storage_lvm
    else
        build_storage_direct
    fi

    cat <<FOOTER

  user-data:
    chpasswd:
      list: |
        root:ROOTHASHPLACEHOLDER
      expire: false
    users:
      - name: root
        lock_passwd: false

  kernel:
    flavor: ${KERNEL_FLAVOR}

  late-commands:
      - curtin in-target -- add-apt-repository universe -y
      - curtin in-target -- add-apt-repository multiverse -y
      - curtin in-target -- add-apt-repository restricted -y
      - >-
        curtin in-target --
        sed -i /etc/default/grub -e
        's/GRUB_CMDLINE_LINUX_DEFAULT=".*/GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE}"/'
      - >-
        curtin in-target --
        sed -i /etc/default/grub -e
        's/^#\?GRUB_TIMEOUT=.*/GRUB_TIMEOUT=${GRUB_TIMEOUT}/'
      - >-
        curtin in-target --
        sed -i /etc/default/grub -e
        's/^#\?GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=${GRUB_TIMEOUT_STYLE}/'
      - >-
        curtin in-target --
        sed -i /etc/default/grub -e
        's/^#\?GRUB_TERMINAL=.*/GRUB_TERMINAL=${GRUB_TERMINAL}/'
      - >-
        curtin in-target --
        sed -i /etc/default/grub -e
        's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=${GRUB_DISABLE_OS_PROBER}/'
      - curtin in-target -- update-grub
      - rm /target/etc/netplan/00-installer-config*yaml
      - >-
        printf "network:\n  version: 2\n  renderer: ${NETWORK_RENDERER}"
        > /target/etc/netplan/01-network-manager-all.yaml
      - >-
        curtin in-target -- sed -i
        's/^#\?PermitRootLogin.*/PermitRootLogin ${SSH_ROOT_LOGIN}/'
        /etc/ssh/sshd_config
      - >-
        curtin in-target -- apt-get remove -y
        ubuntu-server
        motd-news-config lxd-agent-loader
        landscape-common
      - curtin in-target -- apt-get autoremove -y

  updates: ${AUTO_UPDATES}

  shutdown: reboot
FOOTER
} >"$OUTPUT"

sed -i "s|USERHASHPLACEHOLDER|${HASH_USER}|g" "$OUTPUT"
sed -i "s|ROOTHASHPLACEHOLDER|${HASH_ROOT}|g" "$OUTPUT"

echo ""
echo -e "${GRN}${BLD}✓ autoinstall.yaml généré avec succès !${RST}"
echo -e "  Fichier : ${BLD}$OUTPUT${RST}"
echo -e "  Hostname: ${BLD}$HOSTNAME${RST}  User: ${BLD}$USERNAME${RST}  Disque: ${BLD}$DISK${RST}"
echo -e "  Stockage: ${BLD}$([[ $STORAGE_TYPE -eq 1 ]] && echo "LVM" || echo "Direct")${RST}  FS: ${BLD}$FS_MAIN${RST}"
echo ""
