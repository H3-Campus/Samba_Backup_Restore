# Samba Backup & Restore Script

## Description

Ce script Bash permet de sauvegarder et de restaurer les configurations et les données d'un serveur Samba Active Directory Domain Controller (ADDC). Il inclut également des fonctions pour mettre à jour les enregistrements DNS du serveur.

## Fonctionnalités

- **Sauvegarde complète** des répertoires privés, sysvol, gpo et de configuration de Samba.
- **Restauration complète** des sauvegardes avec réinitialisation des permissions ACL.
- **Mise à jour des enregistrements DNS** pour le serveur Samba ADDC.
- **Interface utilisateur interactive** avec des messages colorés pour une meilleure lisibilité.
- **L'option --auto permet de lancer un backup en automatique**
- **Lors du lancement d'un backup, les backups de plus de 30 jours sont supprimés**

## Installation

1. **Télécharger le script** :
   Clonez ce dépôt GitHub ou téléchargez le script directement.

   ```bash
   git clone https://github.com/votre-utilisateur/samba-backup-restore.git
   cd samba-backup-restore
   ```

2. **Rendre le script exécutable** :
   Assurez-vous que le script est exécutable.

   ```bash
   chmod +x samba_backup_restore.sh
   ```

3. **Exécuter le script en tant que root** :
   Le script doit être exécuté avec des privilèges root.

   ```bash
   sudo ./samba_backup_restore.sh
   ```

## Utilisation

Lorsque vous exécutez le script, un menu interactif s'affiche avec les options suivantes :

1. **Sauvegarder Samba** : Crée une sauvegarde des répertoires privés, sysvol et de configuration de Samba.
2. **Restaurer Samba** : Restaure une sauvegarde précédemment créée.
3. **Mise à jour du DNS** : Met à jour les enregistrements DNS pour le serveur Samba ADDC.
4. **Quitter** : Quitte le script.

### Configuration des IP et des noms de machine

Le script utilise des variables pour les noms de machine et les adresses IP. Voici les variables que vous devez modifier pour adapter le script à votre environnement :

- `ADMIN_USER` : Nom d'utilisateur administrateur (par défaut : `Administrator`)
- `DOMAIN` : Domaine Samba (par défaut : `example.lan`)
- `SERVER` : Nom du serveur Samba ADDC (par défaut : `srv-example-addc01`)
- `IP` : Adresse IP du serveur Samba ADDC (par défaut : `192.168.1.10`)
- `REVERSE_IP` : Adresse IP inversée pour les enregistrements PTR (par défaut : `1.168.192.in-addr.arpa`)
- `OLD_SERVER` : Ancien nom du serveur (par défaut : `srv-old-addc01`)
- `OLD_IP` : Ancienne adresse IP du serveur (par défaut : `192.168.2.210`)
- `OLD_REVERSE_IP` : Ancienne adresse IP inversée pour les enregistrements PTR (par défaut : `2.168.192.in-addr.arpa`)
- `ADMIN_EMAIL` : Adresse e-mail de l'administrateur (par défaut : `admin.example.com`)

Modifiez ces variables en haut du script pour correspondre à votre configuration spécifique.

## Exemple de modification

```bash
# Variables
ADMIN_USER="Administrator"
DOMAIN="example.lan"
SERVER="srv-example-addc01"
IP="192.168.1.10"
REVERSE_IP="1.168.192.in-addr.arpa"
OLD_SERVER="srv-old-addc01"
OLD_IP="192.168.2.10"
OLD_REVERSE_IP="2.168.192.in-addr.arpa"
ADMIN_EMAIL="admin.example.com"
```

## Avertissement

Ce script doit être utilisé avec précaution. Assurez-vous de tester les sauvegardes et les restaurations dans un environnement de test avant de les utiliser en production.

## Licence

Ce projet est sous licence MIT. Voir le fichier LICENSE pour plus de détails.

