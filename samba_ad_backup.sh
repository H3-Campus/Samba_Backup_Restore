#!/bin/bash

#----------------------------------------------------------------
### Attention MSMTPRC doit être configuré sur le poste client ###
#----------------------------------------------------------------

# Variables
SAMBA_PRIVATE="/var/lib/samba/private"
SAMBA_SYSVOL="/var/lib/samba/sysvol"
SAMBA_CONFIG="/etc/samba"
BACKUP_DIR="/mnt/Backups/srv-AD/sauvegardes/samba"
BACKUP_MOUNT="/mnt/Backups"
BACKUP_SHARE="//nashitema/Backups"
BACKUP_USER="backup"
BACKUP_PASSWORD="**********"
DATE=$(date +%Y%m%d_%H%M%S)
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
NC="\033[0m"
ADMIN_CREDS_FILE="/root/.creds/smb_bcks"
LOG_FILE="/var/log/samba_backup.log"
MAIL_TO="admin@domain.fr"

# Mode automatique (défaut à false)
AUTO_MODE=false
RETENTION_DAYS=30
DRY_RUN=false

# Fonction de journalisation
log_message() {
    local message="$1"
    local level="$2"

    if [[ "$level" == "ERROR" ]]; then
        echo -e "${RED}[ERROR] $message${NC}"
    elif [[ "$level" == "WARNING" ]]; then
        echo -e "${YELLOW}[WARNING] $message${NC}"
    else
        echo -e "${GREEN}[INFO] $message${NC}"
    fi

    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [$level] $message" >> "$LOG_FILE"
}

# Fonction pour gérer les identifiants administrateur
setup_admin_credentials() {
    if [ ! -f "$ADMIN_CREDS_FILE" ]; then
        mkdir -p "$(dirname "$ADMIN_CREDS_FILE")"

        if [ -z "$ADMIN_PASSWORD" ]; then
            echo -e "${YELLOW}Entrez le mot de passe Administrateur pour Samba AD :${NC}"
            read -s ADMIN_PASSWORD
            echo
        fi

        echo "username = Administrator" > "$ADMIN_CREDS_FILE"
        echo "password = $ADMIN_PASSWORD" >> "$ADMIN_CREDS_FILE"

        chmod 600 "$ADMIN_CREDS_FILE"
        log_message "Fichier d'identifiants créé: $ADMIN_CREDS_FILE" "INFO"
    fi

    ADMIN_USER=$(grep -oP '(?<=username = ).+' "$ADMIN_CREDS_FILE")
    ADMIN_PASSWORD=$(grep -oP '(?<=password = ).+' "$ADMIN_CREDS_FILE")

    if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASSWORD" ]; then
        log_message "Impossible de lire les identifiants depuis $ADMIN_CREDS_FILE" "ERROR"
        return 1
    fi

    return 0
}

# Fonction d'envoi d'email avec msmtp
send_email() {
    local subject="$1"
    local body="$2"
    local status="${3:-info}"

    TEMP_EMAIL=$(mktemp)

    local message_class="info"
    local bg_color="#4a86e8"

    if [[ "$status" == "ERROR" ]]; then
        message_class="error"
        bg_color="#cc0000"
    elif [[ "$status" == "SUCCESS" ]]; then
        message_class="success"
        bg_color="#007700"
    fi

    body=$(echo -e "$body" | sed 's/$/\<br\>/g')

    cat > "$TEMP_EMAIL" << EOF
From: Système de sauvegarde Samba <backups@domain.fr>
To: $MAIL_TO
Subject: $subject
MIME-Version: 1.0
Content-Type: text/html; charset=UTF-8

<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 0; background-color: #f5f5f5; }
        .container { max-width: 600px; margin: 0 auto; border: 1px solid #ddd; border-radius: 5px; overflow: hidden; }
        .header { background-color: ${bg_color}; color: white; padding: 15px; text-align: center; }
        .content { padding: 20px; background-color: white; }
        .footer { background-color: #eee; padding: 10px; text-align: center; font-size: 12px; color: #666; }
        .error { color: #cc0000; font-weight: bold; }
        .success { color: #007700; font-weight: bold; }
        .info { color: #0066cc; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        table, th, td { border: 1px solid #ddd; }
        th, td { padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2>Notification de sauvegarde Samba</h2>
        </div>
        <div class="content">
            <div class="${message_class}">
                ${body}
            </div>
            <div style="margin-top: 20px;">
                <table>
                    <tr>
                        <th>Serveur</th>
                        <td>$(hostname)</td>
                    </tr>
                    <tr>
                        <th>Date</th>
                        <td>$(date)</td>
                    </tr>
                    <tr>
                        <th>Script</th>
                        <td>samba_ad_backup.sh</td>
                    </tr>
                </table>
            </div>
        </div>
        <div class="footer">
            Ce message est généré automatiquement, merci de ne pas y répondre.
        </div>
    </div>
</body>
</html>
EOF

    msmtp -a Backups -t < "$TEMP_EMAIL"

    if [ $? -eq 0 ]; then
        log_message "Email envoyé à $MAIL_TO" "INFO"
    else
        log_message "Échec de l'envoi d'email à $MAIL_TO" "ERROR"
    fi

    rm -f "$TEMP_EMAIL"
}

# Fonction de test d'envoi d'email
test_send_email() {
    log_message "Test d'envoi d'email..." "INFO"
    send_email "Test d'envoi d'email" "Ceci est un email de test envoyé par le script de sauvegarde Samba." "info"
}

# Fonction pour vérifier et monter le partage réseau
check_mount() {
    if [ ! -d "$BACKUP_MOUNT" ]; then
        mkdir -p "$BACKUP_MOUNT"
        log_message "Création du point de montage $BACKUP_MOUNT" "INFO"
    fi

    if mountpoint -q "$BACKUP_MOUNT"; then
        log_message "Le partage est déjà monté sur $BACKUP_MOUNT" "INFO"
        return 0
    fi

    mount -t cifs "$BACKUP_SHARE" "$BACKUP_MOUNT" -o username="$BACKUP_USER",password="$BACKUP_PASSWORD",vers=3.0

    if [ $? -eq 0 ]; then
        log_message "Partage $BACKUP_SHARE monté avec succès sur $BACKUP_MOUNT" "INFO"
        return 0
    else
        log_message "Impossible de monter le partage $BACKUP_SHARE sur $BACKUP_MOUNT" "ERROR"
        send_email "ERREUR: Échec du montage du partage pour la sauvegarde Samba" "Le script de sauvegarde n'a pas pu monter le partage réseau $BACKUP_SHARE sur $BACKUP_MOUNT. Veuillez vérifier la connectivité réseau et les identifiants." "ERROR"
        return 1
    fi
}

# Fonction de sauvegarde des GPO
backup_gpo() {
    local custom_name="$1"
    local gpo_dir=""

    if [[ -z "$custom_name" ]]; then
        gpo_dir="$BACKUP_DIR/gpo_backup_$DATE"
    else
        gpo_dir="$BACKUP_DIR/gpo_backup_${custom_name}"
    fi

    log_message "Sauvegarde des GPO dans $gpo_dir..." "INFO"
    mkdir -p "$gpo_dir"

    gpo_list=$(samba-tool gpo listall 2>/dev/null)

    if [ $? -ne 0 ]; then
        log_message "Erreur lors de la récupération de la liste des GPO" "ERROR"
        return 1
    fi

    while IFS= read -r line; do
        gpo_guid=$(echo "$line" | grep -o -P '\{[0-9A-Fa-f\-]+\}')
        if [[ -n "$gpo_guid" ]]; then
            if [[ "$DRY_RUN" = true ]]; then
                log_message "DRY RUN: Simulation de sauvegarde du GPO $gpo_guid dans $gpo_dir" "INFO"
            else
                samba-tool gpo backup "$gpo_guid" -H "$gpo_dir/$gpo_guid" -U "${ADMIN_USER}%${ADMIN_PASSWORD}" 2>/dev/null

                if [ $? -ne 0 ]; then
                    log_message "Erreur lors de la sauvegarde du GPO $gpo_guid" "ERROR"
                    send_email "ERREUR: Échec de la sauvegarde du GPO $gpo_guid" "Le script n'a pas pu sauvegarder le GPO $gpo_guid. Vérifiez les logs pour plus de détails." "ERROR"
                    return 1
                fi
            fi
        fi
    done <<< "$gpo_list"

    log_message "Sauvegarde des GPO terminée dans $gpo_dir" "INFO"
    return 0
}

# Fonction de nettoyage des anciennes sauvegardes
cleanup_old_backups() {
    if [[ "$DRY_RUN" = true ]]; then
        log_message "DRY RUN: Simulation de nettoyage des anciennes sauvegardes (plus de $RETENTION_DAYS jours)" "INFO"
        find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +$RETENTION_DAYS -print
        find "$BACKUP_DIR" -name "gpo_backup_*" -type d -mtime +$RETENTION_DAYS -print
    else
        log_message "Nettoyage des anciennes sauvegardes (plus de $RETENTION_DAYS jours)..." "INFO"
        find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete
        find "$BACKUP_DIR" -name "gpo_backup_*" -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null || true
    fi
    log_message "Nettoyage terminé" "INFO"
}

# Fonction principale de sauvegarde Samba
backup_samba() {
    log_message "Début de la sauvegarde Samba..." "INFO"

    setup_admin_credentials || return 1
    check_mount || return 1

    if [ ! -d "$BACKUP_DIR" ]; then
        if [[ "$DRY_RUN" = true ]]; then
            log_message "DRY RUN: Création du répertoire $BACKUP_DIR" "INFO"
        else
            mkdir -p "$BACKUP_DIR" || {
                log_message "Impossible de créer le répertoire $BACKUP_DIR" "ERROR"
                send_email "ERREUR: Échec de création du répertoire de sauvegarde Samba" "Le script n'a pas pu créer le répertoire $BACKUP_DIR." "ERROR"
                return 1
            }
        fi
    fi

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

    cleanup_old_backups

    backup_gpo "$CUSTOM_NAME" || return 1

    REQUIRED_SPACE=$(du -sb "$SAMBA_PRIVATE" "$SAMBA_SYSVOL" "$SAMBA_CONFIG" | awk '{total += $1} END {print total}')
    AVAILABLE_SPACE=$(df -B1 "$BACKUP_DIR" | tail -1 | awk '{print $4}')

    if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
        log_message "Espace disque insuffisant pour la sauvegarde. Requis: $(numfmt --to=iec-i --suffix=B $REQUIRED_SPACE), Disponible: $(numfmt --to=iec-i --suffix=B $AVAILABLE_SPACE)" "ERROR"
        send_email "ERREUR: Espace disque insuffisant pour la sauvegarde Samba" "L'espace disque est insuffisant pour effectuer la sauvegarde.\n\nRequis: $(numfmt --to=iec-i --suffix=B $REQUIRED_SPACE)\nDisponible: $(numfmt --to=iec-i --suffix=B $AVAILABLE_SPACE)" "ERROR"
        return 1
    fi

    if [[ "$DRY_RUN" = true ]]; then
        log_message "DRY RUN: Création de l'archive $ARCHIVE" "INFO"
        log_message "DRY RUN: Sauvegarde des ACL dans $BACKUP_DIR/${CUSTOM_NAME}_acl.acl" "INFO"
    else
        tar --exclude="*/ldap_priv/ldapi" --exclude="*/ldapi" -czf "$ARCHIVE" "$SAMBA_PRIVATE" "$SAMBA_SYSVOL" "$SAMBA_CONFIG" || {
            log_message "Erreur lors de la création de l'archive $ARCHIVE" "ERROR"
            send_email "ERREUR: Échec de la création de l'archive Samba" "Le script n'a pas pu créer l'archive de sauvegarde $ARCHIVE." "ERROR"
            return 1
        }

        log_message "Fichiers sauvegardés dans $ARCHIVE" "INFO"

        ACL_FILE="$BACKUP_DIR/${CUSTOM_NAME}_acl.acl"
        getfacl -R "$SAMBA_SYSVOL" > "$ACL_FILE" || {
            log_message "Erreur lors de la sauvegarde des ACL dans $ACL_FILE" "WARNING"
        }

        log_message "ACL sauvegardées dans $ACL_FILE" "INFO"

        if [ -f "$ARCHIVE" ]; then
            ARCHIVE_SIZE=$(du -h "$ARCHIVE" | cut -f1)
            log_message "Sauvegarde terminée. Taille de l'archive: $ARCHIVE_SIZE" "INFO"
            send_email "Sauvegarde Samba réussie" "La sauvegarde Samba a été effectuée avec succès.\n\nArchive: $ARCHIVE\nTaille: $ARCHIVE_SIZE" "SUCCESS"
        else
            log_message "L'archive $ARCHIVE n'existe pas après la sauvegarde" "ERROR"
            send_email "ERREUR: Échec de la sauvegarde Samba" "L'archive de sauvegarde $ARCHIVE n'a pas été créée correctement." "ERROR"
            return 1
        fi
    fi

    return 0
}

# Fonction de restauration
restore_samba() {
    log_message "Début de la restauration Samba..." "INFO"

    setup_admin_credentials || return 1
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

    if [[ "$DRY_RUN" = true ]]; then
        log_message "DRY RUN: Simulation de restauration de $BACKUP_PATH" "INFO"
        echo -e "${GREEN}En mode DRY RUN, les étapes suivantes seraient exécutées :${NC}"
        echo "1. Arrêt du service samba-ad-dc"
        echo "2. Sauvegarde des fichiers actuels dans $BACKUP_DIR/original_$DATE/"
        echo "3. Extraction de l'archive $BACKUP_PATH"
        echo "4. Restauration des ACL si disponibles"
        echo "5. Réinitialisation des permissions SYSVOL"
        echo "6. Redémarrage du service samba-ad-dc"
        return 0
    fi

    echo -e "${YELLOW}Arrêt du service Samba...${NC}"
    systemctl stop samba-ad-dc || {
        log_message "Erreur lors de l'arrêt du service samba-ad-dc" "ERROR"
        return 1
    }

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
        send_email "ERREUR: Échec du redémarrage de Samba après restauration" "Le service samba-ad-dc n'a pas pu être redémarré après la restauration. Une intervention manuelle est requise." "ERROR"
        return 1
    }

    log_message "Restauration Samba terminée avec succès" "INFO"
    send_email "Restauration Samba réussie" "La restauration de Samba a été effectuée avec succès à partir de $BACKUP_PATH." "SUCCESS"
    return 0
}

# Fonction d'affichage de l'aide
show_help() {
    echo -e "${GREEN}Usage: $0 [options]${NC}"
    echo
    echo "Options:"
    echo "  --auto               Mode automatique (sans interaction)"
    echo "  --retention=JOURS    Définir la durée de rétention (défaut: 30 jours)"
    echo "  --dry-run            Simuler les opérations sans les exécuter"
    echo "  --test-email         Tester l'envoi d'email"
    echo "  --help               Afficher cette aide"
    echo
    echo "Exemples:"
    echo "  $0                   Exécution interactive"
    echo "  $0 --auto            Exécution automatique de la sauvegarde"
    echo "  $0 --dry-run         Simulation de sauvegarde"
    echo "  $0 --retention=60    Conserver les sauvegardes pendant 60 jours"
    echo "  $0 --test-email      Tester l'envoi d'email"
}

if [[ $EUID -ne 0 ]]; then
    log_message "Ce script doit être exécuté en tant que root" "ERROR"
    exit 1
fi

# Traitement des arguments
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
        --dry-run)
            DRY_RUN=true
            log_message "Mode DRY RUN activé - aucune modification ne sera effectuée" "INFO"
            shift
            ;;
        --test-email)
            test_send_email
            exit 0
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_message "Option non reconnue: $1" "ERROR"
            show_help
            exit 1
            ;;
    esac
done

if [[ "$AUTO_MODE" = true ]]; then
    backup_samba
    exit_code=$?
    exit $exit_code
else
    echo -e "${YELLOW}Samba Backup & Restore Script${NC}"
    echo -e "${GREEN}1. Sauvegarder Samba${NC}"
    echo -e "${GREEN}2. Restaurer Samba${NC}"
    echo -e "${GREEN}5. Quitter${NC}"
    echo -e "Choisissez une option :"
    read -r OPTION

    case $OPTION in
        1)
            backup_samba
            ;;
        2)
            restore_samba
            ;;
        5)
            echo -e "${GREEN}Quitter...${NC}"
            exit 0
            ;;
        *)
            log_message "Option invalide" "ERROR"
            exit 1
            ;;
    esac
fi
