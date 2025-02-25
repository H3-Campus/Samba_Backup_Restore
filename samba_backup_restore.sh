#!/bin/bash

# Variables 
SAMBA_PRIVATE="/var/lib/samba/private"
SAMBA_SYSVOL="/var/lib/samba/sysvol"
SAMBA_CONFIG="/etc/samba"
BACKUP_DIR="/mnt/Backups/srv-mtp-addc01/sauvegardes/samba"
BACKUP_MOUNT="/mnt/Backups"
BACKUP_SHARE="//192.168.1.100/Backups"  # Remplacez par votre partage réseau
BACKUP_USER="backup_user"               # Remplacez par votre utilisateur de sauvegarde
BACKUP_PASSWORD="backup_password"       # Remplacez par votre mot de passe
DATE=$(date +%Y%m%d_%H%M%S)
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
NC="\033[0m"
ADMIN_USER="Administrator"
DOMAIN="h3adm.lan"
LOG_FILE="/var/log/samba_backup.log"
MAIL_TO="admin@h3campus.fr"             # Adresse email pour les notifications

# Mode automatique (défaut à false)
AUTO_MODE=false
RETENTION_DAYS=30                      # Nombre de jours de conservation des backups

# Fonction de journalisation
log_message() {
    local message="$1"
    local level="$2"
    
    # Afficher le message sur la console
    if [[ "$level" == "ERROR" ]]; then
        echo -e "${RED}[ERROR] $message${NC}"
    elif [[ "$level" == "WARNING" ]]; then
        echo -e "${YELLOW}[WARNING] $message${NC}"
    else
        echo -e "${GREEN}[INFO] $message${NC}"
    fi
    
    # Enregistrer dans le fichier journal
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [$level] $message" >> "$LOG_FILE"
}

# Fonction d'envoi d'email
send_email() {
    local subject="$1"
    local body="$2"
    
    echo "$body" | mail -s "$subject" "$MAIL_TO"
    
    if [ $? -eq 0 ]; then
        log_message "Email envoyé à $MAIL_TO" "INFO"
    else
        log_message "Échec de l'envoi d'email à $MAIL_TO" "ERROR"
    fi
}

# Fonction pour vérifier et monter le partage réseau
check_mount() {
    # Vérifier si le point de montage existe
    if [ ! -d "$BACKUP_MOUNT" ]; then
        mkdir -p "$BACKUP_MOUNT"
        log_message "Création du point de montage $BACKUP_MOUNT" "INFO"
    fi
    
    # Vérifier si le partage est déjà monté
    if mountpoint -q "$BACKUP_MOUNT"; then
        log_message "Le partage est déjà monté sur $BACKUP_MOUNT" "INFO"
        return 0
    fi
    
    # Tenter de monter le partage
    mount -t cifs "$BACKUP_SHARE" "$BACKUP_MOUNT" -o username="$BACKUP_USER",password="$BACKUP_PASSWORD",vers=3.0
    
    if [ $? -eq 0 ]; then
        log_message "Partage $BACKUP_SHARE monté avec succès sur $BACKUP_MOUNT" "INFO"
        return 0
    else
        log_message "Impossible de monter le partage $BACKUP_SHARE sur $BACKUP_MOUNT" "ERROR"
        send_email "ERREUR: Échec du montage du partage pour la sauvegarde Samba" "Le script de sauvegarde n'a pas pu monter le partage réseau $BACKUP_SHARE sur $BACKUP_MOUNT. Veuillez vérifier la connectivité réseau et les identifiants."
        return 1
    fi
}

# Fonction de sauvegarde des GPO
backup_gpo() {
    log_message "Sauvegarde des GPO..." "INFO"
    GPO_BACKUP_DIR="$BACKUP_DIR/gpo_backup_$DATE"
    mkdir -p "$GPO_BACKUP_DIR"
    
    # Utiliser samba-tool pour sauvegarder les GPO
    samba-tool gpo backup "$GPO_BACKUP_DIR" -U "$ADMIN_USER" || {
        log_message "Erreur lors de la sauvegarde des GPO" "ERROR"
        send_email "ERREUR: Échec de la sauvegarde des GPO Samba" "Le script de sauvegarde n'a pas pu sauvegarder les GPO. Vérifiez les logs pour plus de détails."
        return 1
    }
    
    log_message "Sauvegarde des GPO terminée dans $GPO_BACKUP_DIR" "INFO"
    return 0
}

# Fonction de nettoyage des anciennes sauvegardes
cleanup_old_backups() {
    log_message "Nettoyage des anciennes sauvegardes (plus de $RETENTION_DAYS jours)..." "INFO"
    find "$BACKUP_DIR" -name "samba_backup_*" -type f -mtime +$RETENTION_DAYS -delete
    find "$BACKUP_DIR" -name "gpo_backup_*" -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null || true
    log_message "Nettoyage terminé" "INFO"
}

# Fonction principale de sauvegarde Samba
backup_samba() {
    log_message "Début de la sauvegarde Samba..." "INFO"
    
    # Vérifier et monter le partage
    check_mount || return 1
    
    # Vérifier que le répertoire de sauvegarde existe
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR" || {
            log_message "Impossible de créer le répertoire $BACKUP_DIR" "ERROR"
            send_email "ERREUR: Échec de création du répertoire de sauvegarde Samba" "Le script n'a pas pu créer le répertoire $BACKUP_DIR."
            return 1
        }
    fi
    
    # Mode automatique : génération automatique du nom de sauvegarde
    if [[ "$AUTO_MODE" = true ]]; then
        CUSTOM_NAME="samba_backup_$DATE"
        log_message "Mode automatique activé. Sauvegarde : $CUSTOM_NAME" "INFO"
    else
        echo -e "${YELLOW}Entrez un nom pour la sauvegarde (laisser vide pour générer automatiquement) :${NC}"
        read -r CUSTOM_NAME
        if [[ -z "$CUSTOM_NAME" ]]; then
            CUSTOM_NAME="samba_backup_$DATE"
        fi
    fi
    
    ARCHIVE="$BACKUP_DIR/${CUSTOM_NAME}.tar.gz"
    
    # Nettoyer les anciennes sauvegardes
    cleanup_old_backups
    
    # Sauvegarde des GPO
    backup_gpo || return 1
    
    # Vérifier l'espace disque disponible
    REQUIRED_SPACE=$(du -s "$SAMBA_PRIVATE" "$SAMBA_SYSVOL" "$SAMBA_CONFIG" | awk '{total += $1} END {print total}')
    AVAILABLE_SPACE=$(df -k "$BACKUP_DIR" | tail -1 | awk '{print $4}')
    
    if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
        log_message "Espace disque insuffisant pour la sauvegarde. Requis: $REQUIRED_SPACE KB, Disponible: $AVAILABLE_SPACE KB" "ERROR"
        send_email "ERREUR: Espace disque insuffisant pour la sauvegarde Samba" "L'espace disque est insuffisant pour effectuer la sauvegarde. Requis: $REQUIRED_SPACE KB, Disponible: $AVAILABLE_SPACE KB"
        return 1
    fi
    
    # Création de l'archive
    tar -czf "$ARCHIVE" "$SAMBA_PRIVATE" "$SAMBA_SYSVOL" "$SAMBA_CONFIG" || {
        log_message "Erreur lors de la création de l'archive $ARCHIVE" "ERROR"
        send_email "ERREUR: Échec de la création de l'archive Samba" "Le script n'a pas pu créer l'archive de sauvegarde $ARCHIVE."
        return 1
    }
    
    log_message "Fichiers sauvegardés dans $ARCHIVE" "INFO"
    
    # Sauvegarde des ACL
    ACL_FILE="$BACKUP_DIR/${CUSTOM_NAME}_acl.acl"
    getfacl -R "$SAMBA_SYSVOL" > "$ACL_FILE" || {
        log_message "Erreur lors de la sauvegarde des ACL dans $ACL_FILE" "WARNING"
        # On continue malgré cette erreur, car ce n'est pas critique
    }
    
    log_message "ACL sauvegardées dans $ACL_FILE" "INFO"
    
    # Vérifier la taille de l'archive créée
    if [ -f "$ARCHIVE" ]; then
        ARCHIVE_SIZE=$(du -h "$ARCHIVE" | cut -f1)
        log_message "Sauvegarde terminée. Taille de l'archive: $ARCHIVE_SIZE" "INFO"
        send_email "Sauvegarde Samba réussie" "La sauvegarde Samba a été effectuée avec succès.\nArchive: $ARCHIVE\nTaille: $ARCHIVE_SIZE"
    else
        log_message "L'archive $ARCHIVE n'existe pas après la sauvegarde" "ERROR"
        send_email "ERREUR: Échec de la sauvegarde Samba" "L'archive de sauvegarde $ARCHIVE n'a pas été créée correctement."
        return 1
    fi
    
    return 0
}

# Fonction de restauration
restore_samba() {
    log_message "Début de la restauration Samba..." "INFO"
    
    # Vérifier et monter le partage
    check_mount || return 1
    
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z $(ls -A "$BACKUP_DIR" | grep "tar.gz") ]]; then
        log_message "Aucune sauvegarde trouvée dans $BACKUP_DIR" "ERROR"
        return 1
    fi
    
    echo -e "${YELLOW}Liste des sauvegardes disponibles :${NC}"
    ls -1 "$BACKUP_DIR" | grep "tar.gz" | nl
    
    echo -e "${YELLOW}Choisissez le numéro de la sauvegarde à restaurer :${NC}"
    read -r BACKUP_CHOICE
    BACKUP_FILE=$(ls -1 "$BACKUP_DIR" | grep "tar.gz" | sed -n "${BACKUP_CHOICE}p")
    
    if [[ -z "$BACKUP_FILE" ]]; then
        log_message "Sélection invalide" "ERROR"
        return 1
    fi
    
    BACKUP_PATH="$BACKUP_DIR/$BACKUP_FILE"
    log_message "Sauvegarde sélectionnée : $BACKUP_FILE" "INFO"
    
    echo -e "${YELLOW}Arrêt du service Samba...${NC}"
    systemctl stop samba-ad-dc || {
        log_message "Erreur lors de l'arrêt du service samba-ad-dc" "ERROR"
        return 1
    }
    
    # Sauvegarde des fichiers actuels avant restauration
    BACKUP_ORIG_DIR="$BACKUP_DIR/original_$DATE"
    mkdir -p "$BACKUP_ORIG_DIR"
    log_message "Sauvegarde des fichiers originaux dans $BACKUP_ORIG_DIR" "INFO"
    
    tar -czf "$BACKUP_ORIG_DIR/original_samba_files.tar.gz" "$SAMBA_PRIVATE" "$SAMBA_SYSVOL" "$SAMBA_CONFIG" || {
        log_message "Erreur lors de la sauvegarde des fichiers originaux" "WARNING"
        echo -e "${YELLOW}Voulez-vous continuer la restauration quand même ? (o/n) :${NC}"
        read -r CONTINUE_RESTORE
        if [[ "$CONTINUE_RESTORE" != "o" ]]; then
            systemctl start samba-ad-dc
            log_message "Restauration annulée par l'utilisateur" "INFO"
            return 1
        fi
    }
    
    # Extraction de l'archive
    tar -xzf "$BACKUP_PATH" -C / || {
        log_message "Erreur lors de l'extraction de l'archive $BACKUP_PATH" "ERROR"
        echo -e "${RED}La restauration a échoué. Voulez-vous restaurer les fichiers originaux ? (o/n) :${NC}"
        read -r RESTORE_ORIG
        if [[ "$RESTORE_ORIG" == "o" ]]; then
            tar -xzf "$BACKUP_ORIG_DIR/original_samba_files.tar.gz" -C /
            log_message "Fichiers originaux restaurés" "INFO"
        fi
        systemctl start samba-ad-dc
        return 1
    }
    
    # Restauration des ACL
    ACL_FILE="$BACKUP_DIR/${BACKUP_FILE%.tar.gz}_acl.acl"
    if [[ -f "$ACL_FILE" ]]; then
        setfacl --restore="$ACL_FILE"
        log_message "ACL restaurées depuis $ACL_FILE" "INFO"
    else
        log_message "Fichier ACL introuvable. Les permissions SYSVOL doivent être réinitialisées." "WARNING"
    fi
    
    echo -e "${YELLOW}Réinitialisation des permissions SYSVOL...${NC}"
    samba-tool ntacl sysvolreset || log_message "Erreur lors de la réinitialisation des permissions SYSVOL" "WARNING"
    
    echo -e "${YELLOW}Redémarrage du service Samba...${NC}"
    systemctl start samba-ad-dc || {
        log_message "Erreur lors du redémarrage du service samba-ad-dc" "ERROR"
        send_email "ERREUR: Échec du redémarrage de Samba après restauration" "Le service samba-ad-dc n'a pas pu être redémarré après la restauration. Une intervention manuelle est requise."
        return 1
    }
    
    log_message "Restauration Samba terminée avec succès" "INFO"
    send_email "Restauration Samba réussie" "La restauration de Samba a été effectuée avec succès à partir de $BACKUP_PATH."
    return 0
}

# Vérification des privilèges root
if [[ $EUID -ne 0 ]]; then
    log_message "Ce script doit être exécuté en tant que root" "ERROR"
    exit 1
fi

# Parsing des arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            AUTO_MODE=true
            shift
            ;;
        --retention=*)
            RETENTION_DAYS="${1#*=}"
            shift
            ;;
        *)
            log_message "Option non reconnue: $1" "ERROR"
            exit 1
            ;;
    esac
done

# Menu principal modifié pour supporter le mode auto
if [[ "$AUTO_MODE" = true ]]; then
    backup_samba
    exit_code=$?
    exit $exit_code
else
    echo -e "${YELLOW}Samba Backup & Restore Script${NC}"
    echo -e "${GREEN}1. Sauvegarder Samba${NC}"
    echo -e "${GREEN}2. Restaurer Samba${NC}"
    echo -e "${GREEN}3. Quitter${NC}"
    echo -e "Choisissez une option :"
    read -r OPTION

    case $OPTION in
        1)
            backup_samba
            ;;
        2)
            restore_samba
            ;;
        3)
            echo -e "${GREEN}Quitter...${NC}"
            exit 0
            ;;
        *)
            log_message "Option invalide" "ERROR"
            exit 1
            ;;
    esac
fi
