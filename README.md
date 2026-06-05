# Penser a modifier les variable dans generate.sh

mot de passe
disque taille ect...

# Suivre évolution de l'installation

# Ouvrir 2 terminal
### Espace Disque LVM
```bash
watch -n 3 df -hTx devtmpfs /dev/mapper/*
```
### Espace Disque nvme
```bash
watch -n 3 df -hTx devtmpfs /dev/nvme0n*
```
### Espace Disque sata
```bash
watch -n 3 df -hTx devtmpfs /dev/sda*
```
_____________________________________________________
## Log 
```bash
sudo tail -F /var/log/installer/subiquity-server-*
```
## Controle

```bash
efibootmgr
```
```bash
sudo reboot -f
```
