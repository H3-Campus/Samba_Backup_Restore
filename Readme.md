# Samba Backup & Restore Script

## Description

Ce script Bash permet de sauvegarder et de restaurer les configurations et les données d'un serveur Samba Active Directory Domain Controller (ADDC). Il inclut également des fonctions pour mettre à jour les enregistrements DNS du serveur.

## Fonctionnalités

- **Sauvegarde complète** des répertoires privés, sysvol, gpo et de configuration de Samba.
- **Restauration complète** des sauvegardes avec réinitialisation des permissions ACL.
- **Interface utilisateur interactive** avec des messages colorés pour une meilleure lisibilité.
- **L'option --auto permet de lancer un backup en automatique**
- **L'option --dry-run permet simuler les operations**
- **L'option --retention permet choissir le nombre de jour de retention des backups**
- **Par défaut lors du lancement d'un backup, les backups de plus de 30 jours sont supprimés**

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
5. **Quitter** : Quitte le script.

### Configuration des IP et des noms de machine

Le script utilise des variables pour les noms de machine et les adresses IP. Voici les variables que vous devez modifier pour adapter le script à votre environnement :

| Variable             | Description                                      | Valeur par défaut |
|----------------------|--------------------------------------------------|-------------------|
| `BACKUP_DIR`        | Répertoire où seront stockées les sauvegardes    | `/mnt/Backups/srv-AD/sauvegardes/samba` |
| `BACKUP_MOUNT`      | Point de montage du partage distant              | `/mnt/Backups` |
| `BACKUP_SHARE`      | Chemin réseau du partage de sauvegarde           | `//nashitema/Backups` |
| `BACKUP_USER`       | Nom d'utilisateur pour accéder au partage        | `backup-srv` |
| `BACKUP_PASSWORD`   | Mot de passe pour accéder au partage             | `***************` |
| `ADMIN_CREDS_FILE`  | Fichier contenant les identifiants Samba         | `/root/.creds/smb_bcks` |
| `MAIL_TO`           | Adresse email pour les notifications             | `admin@domain.fr` |
| `AUTO_MODE`         | Mode automatique (`true` ou `false`)             | `false` |
| `RETENTION_DAYS`    | Nombre de jours de rétention des sauvegardes     | `30` |
| `DRY_RUN`           | Mode simulation (`true` ou `false`)              | `false` |


## Avertissement

Ce script doit être utilisé avec précaution. Assurez-vous de tester les sauvegardes et les restaurations dans un environnement de tests avant de les utiliser en production.

## Licence

Ce projet est sous licence MIT. Voir le fichier LICENSE pour plus de détails.

