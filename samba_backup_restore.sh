#!/bin/bash

# Variables 
SAMBA_PRIVATE="/var/lib/samba/private"
SAMBA_SYSVOL="/var/lib/samba/sysvol"
SAMBA_CONFIG="/etc/samba"
BACKUP_DIR="/sauvegardes/samba"
DATE=$(date +%Y%m%d_%H%M%S)
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
NC="\033[0m"
ADMIN_USER="Administrator"
DOMAIN="h3adm.lan"
SERVER="srv-*-*"
IP="192.168.*.*"
REVERSE_IP="*.168.192.in-addr.arpa"
OLD_SERVER="srv-poi-addc01"
OLD_IP="192.168.*.*"
OLD_REVERSE_IP="*.168.192.in-addr.arpa"
ADMIN_EMAIL="*.h3campus.fr"

# Mode automatique (défaut à false)
AUTO_MODE=false

# Parsing des arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            AUTO_MODE=true
            shift
            ;;
        *)
            echo -e "${RED}Option non reconnue: $1${NC}"
            exit 1
            ;;
    esac
done

# Vérification des privilèges root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Ce script doit être exécuté en tant que root.${NC}"
    exit 1
fi

# fonction asauvegarde des GPO
backup_gpo() {
    echo -e "${YELLOW}Sauvegarde des GPO...${NC}"
    GPO_BACKUP_DIR="$BACKUP_DIR/gpo_backup_$DATE"
    mkdir -p "$GPO_BACKUP_DIR"
    
    # Utiliser samba-tool pour sauvegarder les GPO
    samba-tool gpo backup "$GPO_BACKUP_DIR" -U "$ADMIN_USER"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Sauvegarde des GPO terminée dans $GPO_BACKUP_DIR${NC}"
    else
        echo -e "${RED}Erreur lors de la sauvegarde des GPO${NC}"
    fi
}

# Fonction de sauvegarde Samba
backup_samba() {
    echo -e "${YELLOW}Début de la sauvegarde Samba...${NC}"
    mkdir -p "$BACKUP_DIR"
    
    # Mode automatique : génération automatique du nom de sauvegarde
    if [[ "$AUTO_MODE" = true ]]; then
        CUSTOM_NAME="samba_backup_$DATE"
        echo -e "${GREEN}Mode automatique activé. Sauvegarde : $CUSTOM_NAME${NC}"
    else
        echo -e "${YELLOW}Entrez un nom pour la sauvegarde (laisser vide pour générer automatiquement) :${NC}"
        read -r CUSTOM_NAME
        if [[ -z "$CUSTOM_NAME" ]]; then
            CUSTOM_NAME="samba_backup_$DATE"
        fi
    fi
    
    ARCHIVE="$BACKUP_DIR/${CUSTOM_NAME}.tar.gz"
    
    # Suppression des anciennes sauvegardes
    find "$BACKUP_DIR" -name "samba_backup_*" -type f -mtime +30 -delete

    # Sauvegarde des GPO
    backup_gpo
    
    # Création de l'archive
    tar -czvf "$ARCHIVE" "$SAMBA_PRIVATE" "$SAMBA_SYSVOL" "$SAMBA_CONFIG"
    echo -e "${GREEN}Fichiers sauvegardés dans $ARCHIVE${NC}"
    
    # Sauvegarde des ACL
    ACL_FILE="$BACKUP_DIR/${CUSTOM_NAME}_acl.acl"
    getfacl -R "$SAMBA_SYSVOL" > "$ACL_FILE"
    echo -e "${GREEN}ACL sauvegardées dans $ACL_FILE${NC}"
    
    # En mode automatique, on ajoute des logs si nécessaire
    if [[ "$AUTO_MODE" = true ]]; then
        echo "[$(date)] Sauvegarde Samba automatique : $ARCHIVE" >> /var/log/samba_backup.log
    fi
}

restore_gpo() {
    local BACKUP_PATH="$1"
    echo -e "${YELLOW}Début de la restauration des GPO...${NC}"
    
    # Chercher le répertoire de sauvegarde des GPO
    local GPO_BACKUP_DIR=$(find "$BACKUP_DIR" -type d -name "gpo_backup_*" | sort -r | head -n 1)
    
    if [[ -z "$GPO_BACKUP_DIR" ]]; then
        echo -e "${RED}Aucune sauvegarde de GPO trouvée.${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Restauration des GPO depuis $GPO_BACKUP_DIR${NC}"
    
    # Lister les GPO disponibles dans le répertoire de sauvegarde
    local GPO_LIST=$(ls "$GPO_BACKUP_DIR")
    
    # Utiliser samba-tool pour restaurer les GPO
    for gpo in $GPO_LIST; do
        samba-tool gpo restore "$gpo" "$GPO_BACKUP_DIR" -U "$ADMIN_USER" --password="$ADMIN_PASS"
    done
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Restauration des GPO terminée.${NC}"
    else
        echo -e "${RED}Erreur lors de la restauration des GPO${NC}"
        return 1
    fi
}

# Fonction de restauration Samba
restore_samba() {
    echo -e "${YELLOW}Début de la restauration Samba...${NC}"
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z $(ls -A "$BACKUP_DIR" | grep "tar.gz") ]]; then
        echo -e "${RED}Aucune sauvegarde trouvée dans $BACKUP_DIR.${NC}"
        exit 1
    fi
    echo -e "${YELLOW}Liste des sauvegardes disponibles :${NC}"
    ls -1 "$BACKUP_DIR" | grep "tar.gz" | nl
    echo -e "${YELLOW}Choisissez le numéro de la sauvegarde à restaurer :${NC}"
    read -r BACKUP_CHOICE
    BACKUP_FILE=$(ls -1 "$BACKUP_DIR" | grep "tar.gz" | sed -n "${BACKUP_CHOICE}p")
    if [[ -z "$BACKUP_FILE" ]]; then
        echo -e "${RED}Sélection invalide.${NC}"
        exit 1
    fi
    BACKUP_PATH="$BACKUP_DIR/$BACKUP_FILE"
    echo -e "${GREEN}Sauvegarde sélectionnée : $BACKUP_FILE${NC}"
    echo -e "${YELLOW}Arrêt du service Samba...${NC}"
    systemctl stop samba-ad-dc
    
    BACKUP_ORIG_DIR="$BACKUP_DIR/original_$DATE"
    mkdir -p "$BACKUP_ORIG_DIR"
    tar -czvf "$BACKUP_ORIG_DIR/original_samba_files.tar.gz" "$SAMBA_PRIVATE" "$SAMBA_SYSVOL" "$SAMBA_CONFIG"
    echo -e "${GREEN}Sauvegarde des fichiers originaux dans $BACKUP_ORIG_DIR${NC}"
    
    tar -xzvf "$BACKUP_PATH" -C /
    
    # Demander le mot de passe admin pour la restauration des GPO
    read -sp "Entrez le mot de passe administrateur pour restaurer les GPO : " ADMIN_PASS
    echo
    
    # Appeler la fonction de restauration des GPO
    restore_gpo "$BACKUP_PATH"
    
    echo -e "${GREEN}Fichiers restaurés depuis $BACKUP_PATH${NC}"
    ACL_FILE="$BACKUP_DIR/${BACKUP_FILE%.tar.gz}_acl.acl"
    if [[ -f "$ACL_FILE" ]]; then
        setfacl --restore="$ACL_FILE"
        echo -e "${GREEN}ACL restaurées depuis $ACL_FILE${NC}"
    else
        echo -e "${RED}Fichier ACL introuvable. Les permissions SYSVOL doivent être réinitialisées.${NC}"
    fi
    echo -e "${YELLOW}Réinitialisation des permissions SYSVOL...${NC}"
    samba-tool ntacl sysvolreset
    echo -e "${YELLOW}Mise à jour des fichiers de configuration Samba...${NC}"
    echo -e "${YELLOW}Entrez le nouveau nom du serveur :${NC}"
    read -r NEW_HOSTNAME
    echo -e "${YELLOW}Entrez la nouvelle adresse IP du serveur :${NC}"
    read -r NEW_IP
    sed -i "s/$(hostname)/$NEW_HOSTNAME/" "$SAMBA_CONFIG/smb.conf"
    hostnamectl set-hostname "$NEW_HOSTNAME"
    echo "$NEW_IP $(hostname)" >> /etc/hosts
    echo -e "${GREEN}Configuration mise à jour avec le nom $NEW_HOSTNAME et l'adresse $NEW_IP.${NC}"
    echo -e "${YELLOW}Redémarrage du service Samba...${NC}"
    systemctl start samba-ad-dc
    echo -e "${GREEN}Restauration Samba terminée.${NC}"
}

# Fonction pour ajouter des enregistrements DNS
add_dns_records() {
    samba-tool dns add $SERVER $DOMAIN _ldap._tcp SRV "$SERVER.$DOMAIN 389 0 100" -U $ADMIN_USER --password=$ADMIN_PASS
    samba-tool dns add $SERVER $DOMAIN _kerberos._tcp SRV "$SERVER.$DOMAIN 88 0 100" -U $ADMIN_USER --password=$ADMIN_PASS
    samba-tool dns add $SERVER $DOMAIN _kerberos._udp SRV "$SERVER.$DOMAIN 88 0 100" -U $ADMIN_USER --password=$ADMIN_PASS
    samba-tool dns add $SERVER $DOMAIN _kpasswd._tcp SRV "$SERVER.$DOMAIN 464 0 100" -U $ADMIN_USER --password=$ADMIN_PASS
    samba-tool dns add $SERVER $DOMAIN _kpasswd._udp SRV "$SERVER.$DOMAIN 464 0 100" -U $ADMIN_USER --password=$ADMIN_PASS
    samba-tool dns add $SERVER $REVERSE_IP 210 PTR "$SERVER.$DOMAIN" -U $ADMIN_USER --password=$ADMIN_PASS
    samba-tool dns add $SERVER $DOMAIN $SERVER A $IP -U $ADMIN_USER --password=$ADMIN_PASS
    samba-tool dns add $SERVER $DOMAIN @ NS "$SERVER.$DOMAIN" -U $ADMIN_USER --password=$ADMIN_PASS
}

# Fonction pour supprimer les anciens enregistrements DNS
delete_old_dns_records() {
    samba-tool dns delete $SERVER $DOMAIN _ldap._tcp SRV "$OLD_SERVER.$DOMAIN 389 0 100" -U $ADMIN_USER --password=$ADMIN_PASS
    samba-tool dns delete $SERVER $DOMAIN _kerberos._tcp SRV "$OLD_SERVER.$DOMAIN 88 0 100" -U $ADMIN_USER --password=$ADMIN_PASS
    samba-tool dns delete $SERVER $DOMAIN _kerberos._udp SRV "$OLD_SERVER.$DOMAIN 88 0 100" -U $ADMIN_USER --password=$ADMIN_PASS
    samba-tool dns delete $SERVER $DOMAIN _kpasswd._tcp SRV "$OLD_SERVER.$DOMAIN 464 0 100" -U $ADMIN_USER --password=$ADMIN_PASS
    samba-tool dns delete $SERVER $DOMAIN _kpasswd._udp SRV "$OLD_SERVER.$DOMAIN 464 0 100" -U $ADMIN_USER --password=$ADMIN_PASS
    samba-tool dns delete $SERVER $OLD_REVERSE_IP 210 PTR "$OLD_SERVER.$DOMAIN" -U $ADMIN_USER --password=$ADMIN_PASS
    samba-tool dns delete $SERVER $DOMAIN $OLD_SERVER A $OLD_IP -U $ADMIN_USER --password=$ADMIN_PASS
    samba-tool dns delete $SERVER $DOMAIN @ NS "$OLD_SERVER.$DOMAIN" -U $ADMIN_USER --password=$ADMIN_PASS
}

# Fonction pour mettre à jour l'enregistrement SOA
update_soa_record() {
    samba-tool dns update $SERVER $DOMAIN @ SOA "$OLD_SERVER.$DOMAIN. admin.$DOMAIN. 62646 900 600 86400 3600" "$SERVER.$DOMAIN. $ADMIN_EMAIL. 2024120901 900 600 86400 3600" -U $ADMIN_USER --password=$ADMIN_PASS
}

# Fonction pour vérifier les enregistrements DNS
verify_dns_records() {
    host -t A $SERVER.$DOMAIN
    host -t SRV _ldap._tcp.$DOMAIN
    host -t SRV _kerberos._tcp.$DOMAIN
    host -t SRV _kerberos._udp.$DOMAIN
    host -t SRV _kpasswd._tcp.$DOMAIN
    host -t SRV _kpasswd._udp.$DOMAIN
}

# Menu principal modifié pour supporter le mode auto
if [[ "$AUTO_MODE" = true ]]; then
    backup_samba
else
    echo -e "${YELLOW}Samba Backup & Restore Script${NC}"
    echo -e "${GREEN}1. Sauvegarder Samba${NC}"
    echo -e "${GREEN}2. Restaurer Samba${NC}"
    echo -e "${GREEN}3. Mise à jour du DNS${NC}"
    echo -e "${GREEN}4. Quitter${NC}"
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
            read -sp "Enter password for $ADMIN_USER: " ADMIN_PASS
            echo
            echo -e "\e[34mSuppression des anciens enregistrements DNS...\e[0m"
            delete_old_dns_records
            echo -e "\e[32mAjout des nouveaux enregistrements DNS...\e[0m"
            add_dns_records
            echo -e "\e[35mMise à jour de l'enregistrement SOA...\e[0m"
            update_soa_record
            echo -e "\e[33mVérification des enregistrements DNS...\e[0m"
            verify_dns_records
            echo -e "\e[36mMise à jour du DNS terminée.\e[0m"
            ;;
        4)
            echo -e "${GREEN}Quitter...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Option invalide.${NC}"
            exit 1
            ;;
    esac
fi
