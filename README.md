# Générateur `autoinstall.yaml` — Ubuntu 26.04 LTS

![Platform](https://img.shields.io/badge/platform-Linux-brightgreen)
![Language](https://img.shields.io/badge/language-Bash-blue)
![Ubuntu](https://img.shields.io/badge/Ubuntu-26.04%20LTS-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![Stars](https://img.shields.io/github/stars/ps81frt/autoinstall-gen-ubuntu)
![Last commit](https://img.shields.io/github/last-commit/ps81frt/autoinstall-gen-ubuntu)
![Issues](https://img.shields.io/github/issues/ps81frt/autoinstall-gen-ubuntu)
![Repo size](https://img.shields.io/github/repo-size/ps81frt/autoinstall-gen-ubuntu)

Génère un fichier `autoinstall.yaml` (cloud-init/subiquity) pour une installation sans surveillance d'Ubuntu 26.04 LTS.

---

## Prérequis

- Bash 4+
- `openssl` (hachage des mots de passe SHA-512)
- `lsblk` (détection et listage des disques)
- `pvs` / `lvs` *(optionnel — détection LVM existant)*

---

## Utilisation

```bash
chmod +x generate.sh
sudo ./generate.sh
```

Chaque paramètre est proposé avec une valeur par défaut entre crochets. Le fichier `autoinstall.yaml` est généré dans le répertoire courant.

---

## Paramètres configurés

Le script couvre 13 sections :

| # | Section | Ce qui est configuré |
|---|---------|----------------------|
| 1 | **Système** | Hostname, nom d'utilisateur, nom complet (GECOS), mot de passe utilisateur, mot de passe root |
| 2 | **Localisation** | Locale système, disposition clavier (+ variante), fuseau horaire |
| 3 | **Disque** | Sélection du disque cible, détection UEFI/Legacy, type de table GPT/MBR |
| 3bis | **Dual-boot** | Installation seule ou dual-boot, réutilisation des partitions existantes |
| 4 | **Profil** | Desktop (GNOME + NetworkManager) ou Serveur (sans GUI + networkd) |
| 5 | **Stockage** | LVM ou partitions directes, système de fichiers (ext4 / btrfs / xfs) |
| 6 | **Tailles** | EFI, /boot, swap, / (root) — /home prend automatiquement le reste |
| 7 | **LVM** | Noms du Volume Group et des Logical Volumes (swap, root, home) |
| 8 | **Noyau & Réseau** | Flaveur du noyau (hwe / generic), renderer réseau |
| 9 | **GRUB** | Options kernel, délai, style timeout (hidden/menu), terminal (console/gfxterm), os-prober |
| 10 | **SSH** | Autorisation du login root via SSH |
| 11 | **Mises à jour** | security / all / none |
| 12 | **VMware** | Installation de `open-vm-tools` |
| 13 | **Paquets** | Paquets APT supplémentaires, snaps supplémentaires (Desktop), Firefox APT Mozilla |

---

## Modes de partitionnement

### Firmware
Le script détecte automatiquement UEFI ou Legacy via `/sys/firmware/efi`. Il est possible de forcer un mode différent si la détection ne correspond pas à la machine cible.

| Mode | Table | Particularité |
|------|-------|---------------|
| UEFI | GPT | Partition EFI vfat créée |
| Legacy | GPT | Partition `bios_grub` 1 Mo générée automatiquement |
| Legacy | MBR | Table msdos, flag `boot` sur `/boot` |

### Stockage
- **LVM** : VG créé sur une partition dédiée, LV pour swap/root/home, noms personnalisables.
- **Direct** : partitions physiques (EFI → /boot → swap → / → /home).

### Dual-boot
Le script demande quelles partitions existantes réutiliser (EFI, root, home, swap) et préserve le reste du disque.

> ⚠ En dual-boot avec LVM : curtin purge les LV non déclarés dans le YAML sans avertissement. Sauvegarder les données avant de procéder.

---

## Paquets inclus par défaut

### Paquets communs (Serveur + Desktop)
`curl git vim htop net-tools openssh-server bash-completion wget unzip zip tree lsof dnsutils traceroute whois nmap tcpdump`

### Desktop uniquement
`ubuntu-desktop gnome-tweaks`

### VMware (optionnel)
- Serveur : `open-vm-tools`
- Desktop : `open-vm-tools-desktop`

### Dual-boot (ajouté automatiquement)
`os-prober`

### Snaps Desktop par défaut
`gtk-common-themes` `snap-store` `snapd-desktop-integration`
— `firefox` inclus uniquement si l'option "Conserver snap Firefox" est activée à l'étape 13.

---

## Suivi de l'installation

Deux terminaux en parallèle.

### Espace disque — LVM
```bash
watch -n 3 df -hTx devtmpfs /dev/mapper/*
```

### Espace disque — NVMe
```bash
watch -n 3 df -hTx devtmpfs /dev/nvme0n*
```

### Espace disque — SATA
```bash
watch -n 3 df -hTx devtmpfs /dev/sda*
```

### Logs subiquity (installeur)
```bash
sudo tail -F /var/log/installer/subiquity-server-*
```

---

## Contrôles post-installation

```bash
efibootmgr
```
```bash
sudo reboot -f
```

---

## Notes

- Les mots de passe sont hachés en SHA-512 via `openssl passwd -6` avant d'être écrits dans le YAML. Ils ne sont jamais stockés en clair.
- Le fichier généré contient un en-tête `# NE PAS MODIFIER DIRECTEMENT` — pour le régénérer, relancer `generate.sh`.
- `multipathd` est masqué en `early-commands` pour éviter l'erreur `failed to run cmd multipathd` lors de la détection des disques.
- Le renderer réseau est fixé automatiquement selon le profil (NetworkManager pour Desktop, networkd pour Serveur) et écrit dans `/etc/netplan/01-network.yaml` en `late-commands`.
