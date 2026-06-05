#!/bin/bash
# generate.sh — Générateur interactif autoinstall.yaml
# Ubuntu 26.04 LTS — Supporte LVM/Direct, ext4/btrfs/xfs
set -euo pipefail

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[1;34m'
CYN='\033[0;36m'
BLD='\033[1m'
RST='\033[0m'

# =============================================================
# PRÉREQUIS
# =============================================================
for cmd in openssl lsblk; do
    command -v "$cmd" &>/dev/null || {
        echo -e "${RED}✗ Commande requise manquante : $cmd${RST}" >&2
        exit 1
    }
done

# =============================================================
# DÉTECTION UEFI / LEGACY
# =============================================================
detect_firmware() {
    if [[ -d /sys/firmware/efi ]]; then
        echo "uefi"
    else
        echo "legacy"
    fi
}

banner() {
    echo -e "${BLU}${BLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║     Générateur autoinstall.yaml — Ubuntu 26.04 LTS       ║"
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
        if [[ -z "$pw1" ]]; then
            echo -e "${RED}  ✗ Le mot de passe ne peut pas être vide.${RST}"
            continue
        fi
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
    # Accepte ex: 512M, 1G, 30G  (pas -1, géré séparément)
    [[ "$1" =~ ^[0-9]+[MG]$ ]] && return 0
    echo -e "${RED}  ✗ Format invalide. Utiliser ex: 512M, 1G, 30G${RST}"
    return 1
}

validate_hostname() {
    # RFC 1123 : alphanum + tirets, max 63 chars, pas de tiret en début/fin
    [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$ ]] && return 0
    echo -e "${RED}  ✗ Hostname invalide (alphanum et tirets uniquement, max 63 chars).${RST}"
    return 1
}

validate_username() {
    # POSIX : commence par lettre ou _, alphanum _ - . uniquement
    [[ "$1" =~ ^[a-z_][a-z0-9_\-]{0,31}$ ]] && return 0
    echo -e "${RED}  ✗ Username invalide (minuscules, chiffres, _ ou -, max 32 chars).${RST}"
    return 1
}

validate_disk() {
    [[ -b "$1" ]] && return 0
    echo -e "${RED}  ✗ Périphérique '$1' introuvable ou non-bloc. Vérifiez le nom.${RST}"
    return 1
}

hash_password() {
    openssl passwd -6 "$1"
}

detect_lvm_on_disk() {
    local disk="$1"
    # Cherche des PV LVM sur le disque (partitions ou disque entier)
    if command -v pvs &>/dev/null; then
        pvs --noheadings -o pv_name 2>/dev/null | grep -q "^[[:space:]]*${disk}" && return 0
    fi
    # Fallback : lire les types de partitions via lsblk
    lsblk -pno NAME,FSTYPE "$disk" 2>/dev/null | grep -q "LVM2_member" && return 0
    return 1
}

list_disks() {
    echo -e "${BLD}  Disques détectés :${RST}"
    lsblk -dpno NAME,SIZE,MODEL 2>/dev/null | grep -v "loop" |
        awk '{printf "    %s  %-8s  %s\n", $1, $2, $3}' || echo "    (aucun disque détecté)"
}

banner

# =============================================================
# 1. SYSTÈME
# =============================================================
section "1. SYSTÈME"

while true; do
    ask "Nom d'hôte (hostname)" "Ubuntu"
    validate_hostname "$REPLY" && HOSTNAME="$REPLY" && break
done

while true; do
    ask "Nom d'utilisateur" "user"
    validate_username "$REPLY" && USERNAME="$REPLY" && break
done

ask "Nom complet (GECOS, laisser vide = même que username)" ""
REALNAME="${REPLY:-$USERNAME}"

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
while true; do
    ask "Disque cible" "/dev/sda"
    validate_disk "$REPLY" && DISK="$REPLY" && break
done

DETECTED_FW=$(detect_firmware)
echo ""
if [[ "$DETECTED_FW" == "uefi" ]]; then
    echo -e "  ${GRN}✓ Firmware détecté : ${BLD}UEFI${RST}${GRN} — partition EFI + table GPT${RST}"
else
    echo -e "  ${YLW}⚠ Firmware détecté : ${BLD}Legacy BIOS${RST}${YLW} — pas de partition EFI${RST}"
fi
echo -e "  ${CYN}  (détection via /sys/firmware/efi — normalement fiable sur la machine courante)${RST}"
echo ""
echo -e "  ${YLW}⚠ Forcer un mauvais mode génère un YAML incorrect → install plantera${RST}"
echo -e "  ${BLD}  Impact selon le mode choisi :${RST}"
echo -e "    ${BLD}UEFI${RST}        → disque entier : EFI vfat créée + GPT"
echo -e "                → dual-boot   : EFI existante réutilisée (preserve, non reformatée)"
echo -e "    ${BLD}Legacy GPT${RST}  → disque entier : bios_grub 1M créée + GPT (pas d'EFI)"
echo -e "                → dual-boot   : bios_grub 1M ajoutée + GPT preservée"
echo -e "    ${BLD}Legacy MBR${RST}  → disque entier : table msdos + flag boot sur /boot (pas d'EFI)"
echo -e "                → dual-boot   : table msdos preservée + flag boot sur /boot"
echo ""
yes_no "La détection est incorrecte, forcer un autre mode ?" "n" || true
if [[ "$REPLY" == "yes" ]]; then
    choose "Mode firmware à utiliser" \
        "UEFI (partition EFI vfat, table GPT)" \
        "Legacy BIOS + GPT (partition bios_grub 1M, table GPT)" \
        "Legacy BIOS + MBR (table msdos, flag boot)"
    case $CHOICE in
    1) FIRMWARE_MODE="uefi" ; LEGACY_PTABLE="" ;;
    2) FIRMWARE_MODE="legacy" ; LEGACY_PTABLE="gpt" ;;
    3) FIRMWARE_MODE="legacy" ; LEGACY_PTABLE="mbr" ;;
    esac
    echo -e "  ${YLW}⚠ Mode forcé : ${BLD}${FIRMWARE_MODE^^}${LEGACY_PTABLE:+ / ${LEGACY_PTABLE^^}}${RST}"
else
    FIRMWARE_MODE="$DETECTED_FW"
fi

if [[ "$FIRMWARE_MODE" == "legacy" ]]; then
    echo ""
    choose "Type de table de partitions (Legacy BIOS)" \
        "GPT  (recommandé, nécessite une partition bios_grub 1M — générée automatiquement)" \
        "MBR/msdos  (compatibilité maximale, anciens systèmes)"
    case $CHOICE in
    1) LEGACY_PTABLE="gpt" ;;
    2) LEGACY_PTABLE="mbr" ;;
    esac
else
    LEGACY_PTABLE=""
fi

LVM_DETECTED="no"
if detect_lvm_on_disk "$DISK"; then
    LVM_DETECTED="yes"
    echo ""
    echo -e "  ${RED}${BLD}⚠ ATTENTION : LVM détecté sur $DISK${RST}"
    echo -e "  ${YLW}Des volumes logiques (LV) existent déjà sur ce disque.${RST}"
    echo -e "  ${YLW}• Si vous installez en mode ${BLD}disque entier${RST}${YLW} : tous les VG/LV seront détruits.${RST}"
    echo -e "  ${YLW}• Si vous installez en mode ${BLD}dual-boot${RST}${YLW} : les LV non déclarés dans le YAML"
    echo -e "    ${YLW}  seront purgés par curtin (comportement natif d'autoinstall).${RST}"
    echo -e "  ${YLW}  Vérifiez vos VG/LV existants :${RST}"
    echo ""
    if command -v vgs &>/dev/null; then
        vgs --noheadings -o vg_name,lv_count,vg_size 2>/dev/null | awk '{printf "    VG: %-20s  LVs: %s  Taille: %s\n", $1, $2, $3}' || true
        echo ""
        lvs --noheadings -o lv_name,vg_name,lv_size,lv_path 2>/dev/null | awk '{printf "    LV: %-20s  VG: %-15s  Taille: %-8s  %s\n", $1, $2, $3, $4}' || true
    else
        lsblk -pno NAME,SIZE,FSTYPE "$DISK" 2>/dev/null | grep "LVM2_member" | awk '{printf "    PV: %s  (%s)\n", $1, $2}' || true
    fi
    echo ""
    yes_no "Confirmer : vous avez pris note des LV existants et acceptez leur suppression éventuelle ?" "n" || {
        echo -e "${RED}Annulé. Sauvegardez vos données LVM avant de relancer.${RST}"
        exit 1
    }
fi

# =============================================================
# 3bis. DUAL-BOOT
# =============================================================
section "3bis. DUAL-BOOT"

choose "Mode d'installation" \
    "Seul (disque entier effacé)" \
    "Dual-boot (conserver OS existant, utiliser espace libre)"
DUALBOOT=$CHOICE

if [[ $DUALBOOT -eq 2 ]]; then
    echo ""
    echo -e "  ${YLW}Partitions actuelles sur $DISK :${RST}"
    lsblk -pno NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$DISK" 2>/dev/null || true
    echo ""

    # Avertissement spécifique LVM + dual-boot
    if [[ "$LVM_DETECTED" == "yes" ]]; then
        echo -e "  ${RED}${BLD}⚠ DUAL-BOOT + LVM : risque de perte de données${RST}"
        echo -e "  ${YLW}  Curtin (autoinstall) purge les LV non explicitement déclarés dans le YAML.${RST}"
        echo -e "  ${YLW}  Tous les LV existants non listés seront ${BLD}détruits sans avertissement${RST}${YLW}.${RST}"
        echo -e "  ${YLW}  Assurez-vous d'avoir sauvegardé toutes les données LVM importantes.${RST}"
        echo ""
        yes_no "Confirmer la poursuite malgré le risque LVM en dual-boot ?" "n" || {
            echo -e "${RED}Annulé.${RST}"
            exit 1
        }
    fi

    DISK_P=""
    [[ "$DISK" =~ (nvme|mmcblk) ]] && DISK_P="p"
    if [[ "$FIRMWARE_MODE" == "uefi" ]]; then
        echo -e "  ${YLW}La partition EFI existante sera réutilisée (pas reformatée).${RST}"
        while true; do
            ask "Partition EFI existante (ex: ${DISK}${DISK_P}1)" "${DISK}${DISK_P}1"
            [[ -b "$REPLY" ]] && EFI_EXISTING="$REPLY" && break
            echo -e "${RED}  ✗ Partition introuvable.${RST}"
        done
    else
        EFI_EXISTING=""
        echo -e "  ${YLW}Mode Legacy : pas de partition EFI.${RST}"
        if [[ "$LEGACY_PTABLE" == "gpt" ]]; then
            echo -e "  ${GRN}  → Une partition bios_grub (1M) sera insérée automatiquement.${RST}"
        fi
    fi

    yes_no "Créer une partition /boot dédiée ?" "o" || true
    DUALBOOT_BOOT="$REPLY"

    echo -e "  ${YLW}Indiquez la partition (vide = créer dans l'espace libre) ou son numéro de début/fin.${RST}"
    echo -e "  ${YLW}Le plus simple : pré-allouer l'espace libre depuis l'OS existant avant de lancer l'install.${RST}"

    yes_no "Avez-vous une partition Linux vide pré-allouée pour / ?" "n" || true
    if [[ "$REPLY" == "yes" ]]; then
        while true; do
            ask "Partition pour / (root)" "${DISK}${DISK_P}3"
            [[ -b "$REPLY" ]] && DUALBOOT_ROOT_PART="$REPLY" && break
            echo -e "${RED}  ✗ Partition introuvable.${RST}"
        done
        DUALBOOT_ROOT_PREALLOC="yes"
    else
        DUALBOOT_ROOT_PREALLOC="no"
        DUALBOOT_ROOT_PART=""
    fi

    yes_no "Avez-vous une partition Linux vide pré-allouée pour /home ?" "n" || true
    if [[ "$REPLY" == "yes" ]]; then
        while true; do
            ask "Partition pour /home" "${DISK}${DISK_P}4"
            [[ -b "$REPLY" ]] && DUALBOOT_HOME_PART="$REPLY" && break
            echo -e "${RED}  ✗ Partition introuvable.${RST}"
        done
        DUALBOOT_HOME_PREALLOC="yes"
    else
        DUALBOOT_HOME_PREALLOC="no"
        DUALBOOT_HOME_PART=""
    fi

    yes_no "Avez-vous une partition swap Linux vide pré-allouée ?" "n" || true
    if [[ "$REPLY" == "yes" ]]; then
        while true; do
            ask "Partition swap" "${DISK}${DISK_P}5"
            [[ -b "$REPLY" ]] && DUALBOOT_SWAP_PART="$REPLY" && break
            echo -e "${RED}  ✗ Partition introuvable.${RST}"
        done
        DUALBOOT_SWAP_PREALLOC="yes"
    else
        DUALBOOT_SWAP_PREALLOC="no"
        DUALBOOT_SWAP_PART=""
    fi
fi

# =============================================================
# 4. PROFIL D'INSTALLATION
# =============================================================
section "4. PROFIL D'INSTALLATION"

choose "Profil" \
    "Desktop (GNOME, NetworkManager)" \
    "Serveur (sans GUI, networkd)"
PROFILE=$CHOICE

# =============================================================
# 5. TYPE DE STOCKAGE
# =============================================================
section "5. TYPE DE STOCKAGE"

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
# 6. TAILLES DES PARTITIONS
# =============================================================
section "6. TAILLES DES PARTITIONS"

echo -e "  ${YLW}Format attendu : 512M, 1G, 30G, etc. (/home prend le reste automatiquement)${RST}"

if [[ $DUALBOOT -eq 1 ]]; then
    if [[ "$FIRMWARE_MODE" == "uefi" ]]; then
        while true; do
            ask "Taille partition EFI" "512M"
            SIZE_EFI="$REPLY"
            validate_size "$SIZE_EFI" && break
        done
    else
        SIZE_EFI=""
        if [[ "$LEGACY_PTABLE" == "gpt" ]]; then
            echo -e "  ${GRN}  → EFI ignorée (Legacy) ; partition bios_grub 1M générée automatiquement${RST}"
        else
            echo -e "  ${GRN}  → EFI ignorée (Legacy MBR)${RST}"
        fi
    fi
else
    SIZE_EFI=""
    echo -e "  ${GRN}  → EFI : partition existante réutilisée (${EFI_EXISTING})${RST}"
fi

if [[ $DUALBOOT -eq 1 ]] || [[ $DUALBOOT -eq 2 && "${DUALBOOT_BOOT}" == "yes" ]]; then
    while true; do
        ask "Taille partition /boot" "1G"
        SIZE_BOOT="$REPLY"
        validate_size "$SIZE_BOOT" && break
    done
else
    SIZE_BOOT=""
    echo -e "  ${GRN}  → /boot : pas de partition dédiée (intégré à /)${RST}"
fi

if [[ $DUALBOOT -eq 1 ]] || [[ $DUALBOOT -eq 2 && "${DUALBOOT_SWAP_PREALLOC}" == "no" ]]; then
    while true; do
        ask "Taille partition swap" "4G"
        SIZE_SWAP="$REPLY"
        validate_size "$SIZE_SWAP" && break
    done
else
    SIZE_SWAP=""
    echo -e "  ${GRN}  → swap : partition existante réutilisée (${DUALBOOT_SWAP_PART})${RST}"
fi

if [[ $DUALBOOT -eq 1 ]] || [[ $DUALBOOT -eq 2 && "${DUALBOOT_ROOT_PREALLOC}" == "no" ]]; then
    while true; do
        ask "Taille partition / (root)" "30G"
        SIZE_ROOT="$REPLY"
        validate_size "$SIZE_ROOT" && break
    done
else
    SIZE_ROOT=""
    echo -e "  ${GRN}  → / : partition existante réutilisée (${DUALBOOT_ROOT_PART})${RST}"
fi

echo -e "  ${GRN}  → /home prendra automatiquement le reste du disque${RST}"

# =============================================================
# 7. LVM
# =============================================================
if [[ $STORAGE_TYPE -eq 1 ]]; then
    section "7. LVM"
    ask "Nom du Volume Group" "vg-ubuntu"
    LVM_VG="$REPLY"
    ask "Nom LV swap" "lv-swap"
    LVM_LV_SWAP="$REPLY"
    ask "Nom LV root" "lv-root"
    LVM_LV_ROOT="$REPLY"
    ask "Nom LV home" "lv-home"
    LVM_LV_HOME="$REPLY"
else
    LVM_VG=""
    LVM_LV_SWAP=""
    LVM_LV_ROOT=""
    LVM_LV_HOME=""
fi

# =============================================================
# 8. NOYAU & RÉSEAU
# =============================================================
section "8. NOYAU & RÉSEAU"

choose "Flaveur du noyau" \
    "hwe (Hardware Enablement — recommandé desktop)" \
    "generic"
case $CHOICE in
1) KERNEL_FLAVOR="hwe" ;;
2) KERNEL_FLAVOR="generic" ;;
esac

if [[ $PROFILE -eq 1 ]]; then
    NETWORK_RENDERER="NetworkManager"
    echo -e "  ${GRN}  → Profil Desktop : NetworkManager sélectionné automatiquement${RST}"
else
    NETWORK_RENDERER="networkd"
    echo -e "  ${GRN}  → Profil Serveur : networkd sélectionné automatiquement${RST}"
fi

# =============================================================
# 9. GRUB
# =============================================================
section "9. GRUB"

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

if [[ $DUALBOOT -eq 2 ]]; then
    yes_no "Désactiver la détection dual-boot (os-prober) ?" "n" || true
else
    yes_no "Désactiver la détection dual-boot (os-prober) ?" "o" || true
fi
[[ "$REPLY" == "yes" ]] && GRUB_DISABLE_OS_PROBER="true" || GRUB_DISABLE_OS_PROBER="false"

# =============================================================
# 10. SSH
# =============================================================
section "10. SSH"

yes_no "Autoriser login SSH en root ?" "o" || true
[[ "$REPLY" == "yes" ]] && SSH_ROOT_LOGIN="yes" || SSH_ROOT_LOGIN="no"

# =============================================================
# 11. MISES À JOUR AUTOMATIQUES
# =============================================================
section "11. MISES À JOUR AUTOMATIQUES"

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
# 12. OUTILS VMware
# =============================================================
section "12. OUTILS VMware"

yes_no "Installer open-vm-tools (machine virtuelle VMware/vSphere) ?" "n" || true
INSTALL_VMTOOLS="$REPLY"

# =============================================================
# 13. PAQUETS SUPPLÉMENTAIRES
# =============================================================
section "13. PAQUETS SUPPLÉMENTAIRES"

if [[ $PROFILE -eq 1 ]]; then
    echo -e "  ${YLW}Paquets déjà inclus (Desktop) — ne pas les re-déclarer en extras :${RST}"
    echo -e "  ${YLW}  ubuntu-desktop curl git vim htop net-tools openssh-server wget unzip zip${RST}"
    echo -e "  ${YLW}  bash-completion tree lsof dnsutils traceroute whois nmap tcpdump gnome-tweaks${RST}"
else
    echo -e "  ${YLW}Paquets déjà inclus (Serveur) — ne pas les re-déclarer en extras :${RST}"
    echo -e "  ${YLW}  curl git vim htop net-tools openssh-server wget unzip zip${RST}"
    echo -e "  ${YLW}  bash-completion tree lsof dnsutils traceroute whois nmap tcpdump${RST}"
fi

yes_no "Ajouter des paquets supplémentaires ?" "n" || true
EXTRA_PKG_LIST=""
if [[ "$REPLY" == "yes" ]]; then
    echo -e "  ${BLD}Entrez les paquets séparés par des espaces :${RST}"
    echo -ne "  ➜ "
    read -r extra_pkgs
    for pkg in $extra_pkgs; do
        EXTRA_PKG_LIST="${EXTRA_PKG_LIST}
    - ${pkg}"
    done
fi

if [[ $PROFILE -eq 1 ]]; then
    yes_no "Conserver le snap Firefox ET installer le .deb Mozilla APT ?" "n" || true
    KEEP_SNAP_FIREFOX="$REPLY"
    yes_no "Ajouter des snaps supplémentaires ?" "n" || true
    EXTRA_SNAP_LIST=""
    if [[ "$REPLY" == "yes" ]]; then
        echo -e "  ${BLD}Entrez les snaps séparés par des espaces :${RST}"
        echo -ne "  ➜ "
        read -r extra_snaps
        for snap in $extra_snaps; do
            EXTRA_SNAP_LIST="${EXTRA_SNAP_LIST}
    - name: ${snap}"
        done
    fi
else
    EXTRA_SNAP_LIST=""
fi

# =============================================================
# RÉCAPITULATIF
# =============================================================
echo ""
echo -e "${GRN}${BLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                     RÉCAPITULATIF                       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${RST}"
echo -e "  Profil          : ${BLD}$([[ $PROFILE -eq 1 ]] && echo "Desktop" || echo "Serveur")${RST}"
echo -e "  Firmware        : ${BLD}${FIRMWARE_MODE^^}${RST}$([[ "$FIRMWARE_MODE" == "legacy" ]] && echo "  Table: ${BLD}${LEGACY_PTABLE^^}${RST}" || echo "")"
echo -e "  Mode install    : ${BLD}$([[ $DUALBOOT -eq 1 ]] && echo "Seul (disque entier)" || echo "Dual-boot")${RST}"
echo -e "  Hostname        : ${BLD}$HOSTNAME${RST}"
echo -e "  Utilisateur     : ${BLD}$USERNAME${RST}"
echo -e "  Locale          : ${BLD}$LOCALE${RST}  Clavier: ${BLD}$KEYBOARD${KEYBOARD_VARIANT:+/$KEYBOARD_VARIANT}${RST}"
echo -e "  Timezone        : ${BLD}$TIMEZONE${RST}"
echo -e "  Disque          : ${BLD}$DISK${RST}"
echo -e "  Stockage        : ${BLD}$([[ $STORAGE_TYPE -eq 1 ]] && echo "LVM" || echo "Direct")${RST}  FS: ${BLD}$FS_MAIN${RST}"
echo -e "  Partitions      : EFI=${BLD}$SIZE_EFI${RST}  boot=${BLD}$SIZE_BOOT${RST}  swap=${BLD}$SIZE_SWAP${RST}  root=${BLD}$SIZE_ROOT${RST}  home=reste"
echo -e "  Noyau           : ${BLD}$KERNEL_FLAVOR${RST}  Réseau: ${BLD}$NETWORK_RENDERER${RST}"
echo -e "  SSH root        : ${BLD}$SSH_ROOT_LOGIN${RST}  Updates: ${BLD}$AUTO_UPDATES${RST}"
echo -e "  VMware tools    : ${BLD}$INSTALL_VMTOOLS${RST}"
echo ""

yes_no "Générer le fichier autoinstall.yaml ?" "o" || {
    echo -e "${RED}Annulé.${RST}"
    exit 0
}

# =============================================================
# HACHAGE DES MOTS DE PASSE (avant écriture, pas de sed)
# =============================================================
echo -e "  ${YLW}Calcul des hachages...${RST}"
HASH_USER=$(hash_password "$PASSWORD_USER")
HASH_ROOT=$(hash_password "$PASSWORD_ROOT")

# =============================================================
# CONSTRUCTION DU YAML
# =============================================================

if [[ $PROFILE -eq 1 ]]; then
    PROFILE_PKG="
    - ubuntu-desktop"
    if [[ "$INSTALL_VMTOOLS" == "yes" ]]; then
        PROFILE_PKG="${PROFILE_PKG}
    - open-vm-tools-desktop"
    fi
else
    PROFILE_PKG=""
    if [[ "$INSTALL_VMTOOLS" == "yes" ]]; then
        PROFILE_PKG="
    - open-vm-tools"
    fi
fi

BASE_PACKAGES="
    - curl
    - git
    - vim
    - htop
    - net-tools
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
    - tcpdump"

if [[ $PROFILE -eq 1 ]]; then
    BASE_PACKAGES="${BASE_PACKAGES}
    - gnome-tweaks"
fi

ALL_PACKAGES="${PROFILE_PKG}${BASE_PACKAGES}${EXTRA_PKG_LIST}"
if [[ $DUALBOOT -eq 2 ]]; then
    ALL_PACKAGES="${ALL_PACKAGES}
    - os-prober"
fi

if [[ $PROFILE -eq 1 ]]; then
    if [[ "$KEEP_SNAP_FIREFOX" == "yes" ]]; then
        BASE_SNAPS="
    - name: firefox
    - name: gtk-common-themes
    - name: snap-store
    - name: snapd-desktop-integration"
    else
        BASE_SNAPS="
    - name: gtk-common-themes
    - name: snap-store
    - name: snapd-desktop-integration"
    fi
    ALL_SNAPS="${BASE_SNAPS}${EXTRA_SNAP_LIST}"
fi

OUTPUT="$(dirname "$0")/autoinstall.yaml"

if [[ -f "$OUTPUT" ]]; then
    yes_no "⚠  $OUTPUT existe déjà. Écraser ?" "n" || {
        echo -e "${RED}Annulé.${RST}"
        exit 0
    }
fi

build_storage_dualboot() {
local efi_num

if [[ "$FIRMWARE_MODE" == "legacy" && "$LEGACY_PTABLE" == "mbr" ]]; then
cat <<STORAGE
  storage:
    version: 1
    config:
      - type: disk
        id: disk0
        path: ${DISK}
        ptable: msdos
        preserve: true
        grub_device: true
STORAGE
elif [[ "$FIRMWARE_MODE" == "legacy" && "$LEGACY_PTABLE" == "gpt" ]]; then
cat <<STORAGE
  storage:
    version: 1
    config:
      - type: disk
        id: disk0
        path: ${DISK}
        ptable: gpt
        preserve: true
        grub_device: false

      - type: partition
        id: part-bios
        device: disk0
        size: 1M
        flag: bios_grub
        grub_device: true
STORAGE
else
efi_num=$(lsblk -no KNAME "$EFI_EXISTING" | sed 's/[^0-9]//g')
cat <<STORAGE
  storage:
    version: 1
    config:
      - type: disk
        id: disk0
        path: ${DISK}
        ptable: gpt
        preserve: true
        grub_device: false

      - type: partition
        id: part-efi
        device: disk0
        number: ${efi_num}
        preserve: true
        grub_device: true
STORAGE
fi

if [[ "${DUALBOOT_BOOT}" == "yes" ]]; then
if [[ "$FIRMWARE_MODE" == "legacy" && "$LEGACY_PTABLE" == "mbr" ]]; then
cat <<STORAGE
      - type: partition
        id: part-boot
        device: disk0
        size: ${SIZE_BOOT}
        flag: boot
        wipe: superblock
STORAGE
else
cat <<STORAGE
      - type: partition
        id: part-boot
        device: disk0
        size: ${SIZE_BOOT}
        wipe: superblock
STORAGE
fi

cat <<STORAGE

      - type: format
        id: fmt-boot
        volume: part-boot
        fstype: ${FS_BOOT}
        label: boot

      - type: mount
        id: mnt-boot
        device: fmt-boot
        path: /boot
STORAGE
fi

if [[ "${DUALBOOT_SWAP_PREALLOC}" == "yes" ]]; then
local swap_num
swap_num=$(lsblk -no KNAME "$DUALBOOT_SWAP_PART" | sed 's/[^0-9]//g')
cat <<STORAGE
      - type: partition
        id: part-swap
        device: disk0
        number: ${swap_num}
        preserve: false
        wipe: superblock
STORAGE
else
cat <<STORAGE
      - type: partition
        id: part-swap
        device: disk0
        size: ${SIZE_SWAP}
        wipe: superblock
STORAGE
fi

if [[ "${DUALBOOT_ROOT_PREALLOC}" == "yes" ]]; then
local root_num
root_num=$(lsblk -no KNAME "$DUALBOOT_ROOT_PART" | sed 's/[^0-9]//g')
cat <<STORAGE
      - type: partition
        id: part-root
        device: disk0
        number: ${root_num}
        preserve: false
        wipe: superblock
STORAGE
else
cat <<STORAGE
      - type: partition
        id: part-root
        device: disk0
        size: ${SIZE_ROOT}
        wipe: superblock
STORAGE
fi

if [[ "${DUALBOOT_HOME_PREALLOC}" == "yes" ]]; then
local home_num
home_num=$(lsblk -no KNAME "$DUALBOOT_HOME_PART" | sed 's/[^0-9]//g')
cat <<STORAGE
      - type: partition
        id: part-home
        device: disk0
        number: ${home_num}
        preserve: false
        wipe: superblock
STORAGE
else
cat <<STORAGE
      - type: partition
        id: part-home
        device: disk0
        size: -1
        wipe: superblock
STORAGE
fi

cat <<STORAGE
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
STORAGE

if [[ "$FIRMWARE_MODE" == "uefi" ]]; then
cat <<STORAGE

      - type: format
        id: fmt-efi
        volume: part-efi
        fstype: ${FS_EFI}
        label: EFI
        preserve: true

      - type: mount
        id: mnt-efi
        device: fmt-efi
        path: /boot/efi
STORAGE
fi

cat <<STORAGE

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

build_storage_lvm() {
if [[ "$FIRMWARE_MODE" == "legacy" && "$LEGACY_PTABLE" == "mbr" ]]; then
cat <<STORAGE
  storage:
    version: 1
    config:
      - type: disk
        id: disk0
        path: ${DISK}
        ptable: msdos
        wipe: superblock
        grub_device: true

      - type: partition
        id: part-boot
        device: disk0
        size: ${SIZE_BOOT}
        flag: boot
        wipe: superblock

      - type: partition
        id: part-lvm
        device: disk0
        size: -1
        flag: linux-lvm
        wipe: superblock
STORAGE
elif [[ "$FIRMWARE_MODE" == "legacy" && "$LEGACY_PTABLE" == "gpt" ]]; then
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
        id: part-bios
        device: disk0
        size: 1M
        flag: bios_grub
        grub_device: true

      - type: partition
        id: part-boot
        device: disk0
        size: ${SIZE_BOOT}
        wipe: superblock

      - type: partition
        id: part-lvm
        device: disk0
        size: -1
        flag: linux-lvm
        wipe: superblock
STORAGE
else
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
        wipe: superblock

      - type: partition
        id: part-lvm
        device: disk0
        size: -1
        flag: linux-lvm
        wipe: superblock
STORAGE
fi

cat <<STORAGE

      - type: lvm_volgroup
        id: vg0
        name: ${LVM_VG}
        devices:
          - part-lvm

      - type: lvm_partition
        id: lv-swap-id
        volgroup: vg0
        name: ${LVM_LV_SWAP}
        size: ${SIZE_SWAP}

      - type: lvm_partition
        id: lv-root-id
        volgroup: vg0
        name: ${LVM_LV_ROOT}
        size: ${SIZE_ROOT}

      - type: lvm_partition
        id: lv-home-id
        volgroup: vg0
        name: ${LVM_LV_HOME}
        size: -1
STORAGE

if [[ "$FIRMWARE_MODE" == "uefi" ]]; then
cat <<STORAGE

      - type: format
        id: fmt-efi
        volume: part-efi
        fstype: ${FS_EFI}
        label: EFI
STORAGE
fi

cat <<STORAGE

      - type: format
        id: fmt-boot
        volume: part-boot
        fstype: ${FS_BOOT}
        label: boot

      - type: format
        id: fmt-swap
        volume: lv-swap-id
        fstype: swap
        label: swap

      - type: format
        id: fmt-root
        volume: lv-root-id
        fstype: ${FS_ROOT}
        label: root

      - type: format
        id: fmt-home
        volume: lv-home-id
        fstype: ${FS_HOME}
        label: home
STORAGE

if [[ "$FIRMWARE_MODE" == "uefi" ]]; then
cat <<STORAGE

      - type: mount
        id: mnt-efi
        device: fmt-efi
        path: /boot/efi
STORAGE
fi

cat <<STORAGE

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
if [[ "$FIRMWARE_MODE" == "legacy" && "$LEGACY_PTABLE" == "mbr" ]]; then
cat <<STORAGE
  storage:
    version: 1
    config:
      - type: disk
        id: disk0
        path: ${DISK}
        ptable: msdos
        wipe: superblock
        grub_device: true

      - type: partition
        id: part-boot
        device: disk0
        size: ${SIZE_BOOT}
        flag: boot
        wipe: superblock

      - type: partition
        id: part-swap
        device: disk0
        size: ${SIZE_SWAP}
        wipe: superblock

      - type: partition
        id: part-root
        device: disk0
        size: ${SIZE_ROOT}
        wipe: superblock

      - type: partition
        id: part-home
        device: disk0
        size: -1
        wipe: superblock
STORAGE
elif [[ "$FIRMWARE_MODE" == "legacy" && "$LEGACY_PTABLE" == "gpt" ]]; then
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
        id: part-bios
        device: disk0
        size: 1M
        flag: bios_grub
        grub_device: true

      - type: partition
        id: part-boot
        device: disk0
        size: ${SIZE_BOOT}
        wipe: superblock

      - type: partition
        id: part-swap
        device: disk0
        size: ${SIZE_SWAP}
        wipe: superblock

      - type: partition
        id: part-root
        device: disk0
        size: ${SIZE_ROOT}
        wipe: superblock

      - type: partition
        id: part-home
        device: disk0
        size: -1
        wipe: superblock
STORAGE
else
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
        wipe: superblock

      - type: partition
        id: part-swap
        device: disk0
        size: ${SIZE_SWAP}
        wipe: superblock

      - type: partition
        id: part-root
        device: disk0
        size: ${SIZE_ROOT}
        wipe: superblock

      - type: partition
        id: part-home
        device: disk0
        size: -1
        wipe: superblock
STORAGE
fi

if [[ "$FIRMWARE_MODE" == "uefi" ]]; then
cat <<STORAGE

      - type: format
        id: fmt-efi
        volume: part-efi
        fstype: ${FS_EFI}
        label: EFI
STORAGE
fi

cat <<STORAGE

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
STORAGE

if [[ "$FIRMWARE_MODE" == "uefi" ]]; then
cat <<STORAGE

      - type: mount
        id: mnt-efi
        device: fmt-efi
        path: /boot/efi
STORAGE
fi

cat <<STORAGE

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

{
cat <<HEADER
#cloud-config
# -------------------------------------------------------
# Généré par generate.sh — NE PAS MODIFIER DIRECTEMENT
# Ubuntu 26.04 LTS Resolute Raccoon
# Profil  : $([[ $PROFILE -eq 1 ]] && echo "Desktop" || echo "Serveur")
# Stockage: $([[ $STORAGE_TYPE -eq 1 ]] && echo "LVM" || echo "Direct") / FS : ${FS_MAIN}
# -------------------------------------------------------
autoinstall:
  version: 1

  early-commands:
      # Désactive multipathd avant la détection des disques pour éviter
      # l'erreur "failed to run cmd multipathd, show path raw format"
      - systemctl stop multipathd || true
      - systemctl mask multipathd || true

  packages:${ALL_PACKAGES}

HEADER

if [[ $PROFILE -eq 1 ]]; then
cat <<SNAPS
  snaps:${ALL_SNAPS}

SNAPS
fi

cat <<IDENTITY
  identity:
    realname: '${REALNAME}'
    username: ${USERNAME}
    password: "${HASH_USER}"
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

IDENTITY

if [[ $DUALBOOT -eq 2 ]]; then
    build_storage_dualboot
elif [[ $STORAGE_TYPE -eq 1 ]]; then
    build_storage_lvm
else
    build_storage_direct
fi

cat <<USERDATA

  user-data:
    chpasswd:
      users:
        - name: root
          password: "${HASH_ROOT}"
          type: text
      expire: false
    users:
      - name: root
        lock_passwd: false

  kernel:
    flavor: ${KERNEL_FLAVOR}

USERDATA

cat <<'LATECOMMANDS_OPEN'
  late-commands:
      - curtin in-target -- add-apt-repository universe -y
      - curtin in-target -- add-apt-repository multiverse -y
      - curtin in-target -- add-apt-repository restricted -y
LATECOMMANDS_OPEN

printf "      - >-\n"
printf "        sh -c 'printf %%s\\\\n \"%s\" > /target/etc/default/grub.d/99-autoinstall.cfg'\n" \
    "GRUB_CMDLINE_LINUX_DEFAULT=\"${GRUB_CMDLINE}\""

cat <<LATECOMMANDS_GRUB
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
      - rm -f /target/etc/netplan/00-installer-config*.yaml
      - >-
        printf "network:\n  version: 2\n  renderer: ${NETWORK_RENDERER}\n"
        > /target/etc/netplan/01-network.yaml
      - >-
        curtin in-target -- sed -i
        's/^#\?PermitRootLogin.*/PermitRootLogin ${SSH_ROOT_LOGIN}/'
        /etc/ssh/sshd_config
      - >-
        curtin in-target -- apt-get remove -y
        motd-news-config lxd-agent-loader landscape-common || true
      - curtin in-target -- apt-get autoremove -y
LATECOMMANDS_GRUB

if [[ $PROFILE -eq 1 && "$KEEP_SNAP_FIREFOX" == "no" ]]; then
cat <<'FIREFOX_CMDS'
      - install -d -m 0755 /target/etc/apt/keyrings
      - >-
        wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg
        -O /target/etc/apt/keyrings/packages.mozilla.org.asc
      - >-
        sh -c 'gpg -n -q --import --import-options import-show
        /target/etc/apt/keyrings/packages.mozilla.org.asc 2>&1
        | awk "/pub/{getline; gsub(/^ +| +\$/,\"\");
        if(\$0==\"35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3\")
        print \"Mozilla GPG fingerprint OK\";
        else print \"WARNING: mismatch: \"\$0}"'
      - >-
        printf 'Types: deb\nURIs: https://packages.mozilla.org/apt\nSuites: mozilla\nComponents: main\nSigned-By: /etc/apt/keyrings/packages.mozilla.org.asc\n'
        > /target/etc/apt/sources.list.d/mozilla.sources
      - >-
        printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n'
        > /target/etc/apt/preferences.d/mozilla
      - curtin in-target -- apt-get update || true
      - curtin in-target -- apt-get install -y firefox
FIREFOX_CMDS
fi

cat <<LATECOMMANDS_END

  error-commands:
      - echo "=== ERREUR AUTOINSTALL ===" >> /var/log/autoinstall-error.log
      - journalctl -n 100 >> /var/log/autoinstall-error.log || true

  updates: ${AUTO_UPDATES}

  shutdown: reboot
LATECOMMANDS_END

} > "$OUTPUT"

echo ""
echo -e "${GRN}${BLD}✓ autoinstall.yaml généré avec succès !${RST}"
echo -e "  Fichier : ${BLD}$OUTPUT${RST}"
echo -e "  Profil  : ${BLD}$([[ $PROFILE -eq 1 ]] && echo "Desktop" || echo "Serveur")${RST}"
echo -e "  Hostname: ${BLD}$HOSTNAME${RST}  User: ${BLD}$USERNAME${RST}  Disque: ${BLD}$DISK${RST}"
echo -e "  Stockage: ${BLD}$([[ $STORAGE_TYPE -eq 1 ]] && echo "LVM" || echo "Direct")${RST}  FS: ${BLD}$FS_MAIN${RST}"
echo ""
