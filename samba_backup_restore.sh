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


# Ports requis pour Samba AD
REQUIRED_PORTS=(
    53    # DNS
    88    # Kerberos
    123	  # NTP
    139   # NetBIOS
    389   # LDAP
    445   # SMB
    464   # Kerberos password
    636   # LDAPS
    3268  # Global Catalog
    3269  # Global Catalog SSL
    8385  # Port utilisé par Syncthing pour l'interface du serveur de relais (STRelaySrv)  
    22000 # Port utilisé par Syncthing pour les transferts de fichiers  
    22001 # Port utilisé par Syncthing pour les connexions relayées  
    22027 # Port utilisé par Syncthing pour la découverte globale  
    161   # Port utilisé par SNMP (Simple Network Management Protocol) pour les requêtes de gestion 
)

# Couleurs pour le rapport HTML
COLOR_GREEN="#e6ffe6"
COLOR_RED="#ffe6e6"
COLOR_YELLOW="#fffae6"

# Fonction de logging
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Vérification des outils LDAP
check_ldap_tools() {
    local ldap_packages=("ldap-utils")
    local missing_packages=()

    for pkg in "${ldap_packages[@]}"; do
        if ! dpkg -s "$pkg" &> /dev/null; then
            missing_packages+=("$pkg")
        fi
    done

    if [ ${#missing_packages[@]} -gt 0 ]; then
        log_message "Installation des paquets LDAP manquants : ${missing_packages[*]}"
        apt-get update
apt-get install -y "${missing_packages[@]}"
    fi
}

# Vérification de la cohérence de la base de données
check_database_consistency() {
    local db_checks=()
    local temp_file="/tmp/dbcheck_output.txt"
    
    log_message "Début de la vérification de la base de données AD"
    
    # Vérification de la base de données avec dbcheck
    if samba-tool dbcheck --cross-ncs > "$temp_file" 2>&1; then
        db_checks+=("<tr style='background-color: $COLOR_GREEN;'><td>Base de données AD</td><td>Cohérente</td></tr>")
    else
        db_checks+=("<tr style='background-color: $COLOR_RED;'><td>Base de données AD</td><td>Problèmes détectés</td></tr>")
        
        # Extraction et formatage des erreurs
        local db_errors=$(cat "$temp_file" | sed 's/</\&lt;/g' | sed 's/>/\&gt;/g' | sed 's/\n/<br>/g')
        db_checks+=("<tr><td colspan='2'>Erreurs détectées:<br><pre>$db_errors</pre></td></tr>")
    fi

    # Vérification des objets supprimés
    local deleted_objects=$(samba-tool dbcheck --cross-ncs --fix --yes 2>&1 | grep "fix_all_deleted_objects")
    if [ -n "$deleted_objects" ]; then
        db_checks+=("<tr style='background-color: $COLOR_YELLOW;'><td>Objets supprimés</td><td>Nettoyage effectué</td></tr>")
    fi

    # Vérification de la réplication (si applicable dans votre environnement)
    if samba-tool drs showrepl 2>/dev/null | grep -q "failed"; then
        db_checks+=("<tr style='background-color: $COLOR_RED;'><td>Réplication AD</td><td>Erreurs de réplication détectées</td></tr>")
    else
        db_checks+=("<tr style='background-color: $COLOR_GREEN;'><td>Réplication AD</td><td>Fonctionnelle</td></tr>")
    fi

    # Nettoyage
    rm -f "$temp_file"

    echo "${db_checks[@]}"
}

# Vérification des processus Samba
check_samba_processes() {
    local processes_to_check=(
        "samba" 
        "winbind_server" 
        "ldap_server" 
        "dns" 
        "kdc_server" 
        "dreplsrv" 
        "rpc_server" 
        "cldap_server" 
        "nbt_server"
    )
    local process_status=()

    log_message "Début de la vérification des processus Samba"
    
    local samba_processes=$(samba-tool processes | tail -n +3 | awk '{print $1}' | sort | uniq)

    for proc in "${processes_to_check[@]}"; do
        if echo "$samba_processes" | grep -q "$proc"; then
            process_status+=("<tr style='background-color: $COLOR_GREEN;'><td>$proc</td><td>Actif</td></tr>")
        else
            process_status+=("<tr style='background-color: $COLOR_RED;'><td>$proc</td><td>Inactif</td></tr>")
        fi
    done

    echo "${process_status[@]}"
}

check_syncthing_processes() {
    local processes_to_check=(
        "syncthing" 
    )
    local process_status=()
    #log_message "Début de la vérification des processus Syncthing"
    
    # Correction: utilisation de ps ou pgrep pour vérifier les processus
    local syncthing_processes=$(ps aux | awk '{print $11}' | sort | uniq)
    for proc in "${processes_to_check[@]}"; do
        if echo "$syncthing_processes" | grep -q "$proc"; then
            process_status+=("<tr style='background-color: $COLOR_GREEN;'><td>$proc</td><td>Actif</td></tr>")
        else
            process_status+=("<tr style='background-color: $COLOR_RED;'><td>$proc</td><td>Inactif</td></tr>")
        fi
    done
    echo "${process_status[@]}"
}

check_tis_services() {
    local services_to_check=(
        "tis-sysvolsync"
        "tis-sysvolacl"
    )
    local service_status=()
    #log_message "Début de la vérification des services TIS"
    
    for service in "${services_to_check[@]}"; do
        # Vérifier si le service est activé (enabled au démarrage)
        if systemctl is-enabled "$service" &>/dev/null; then
            local enabled_status="Activé au démarrage"
            local enabled_color="$COLOR_GREEN"
        else
            local enabled_status="Non activé au démarrage"
            local enabled_color="$COLOR_RED"
        fi
        
        # Vérifier si le service est démarré (running)
        if systemctl is-active "$service" &>/dev/null; then
            local active_status="Démarré"
            local active_color="$COLOR_GREEN"
        else
            local active_status="Arrêté"
            local active_color="$COLOR_RED"
        fi
        
        service_status+=("<tr><td style='background-color: $enabled_color;'>$service</td><td style='background-color: $enabled_color;'>$enabled_status</td><td style='background-color: $active_color;'>$active_status</td></tr>")
    done
    
    echo "${service_status[@]}"
}

# Vérification détaillée Kerberos
check_kerberos() {
    local kerberos_checks=()
    local password="Linux741!"

    # Demander interactivement le mot de passe
    #read -s -p "Mot de passe pour $ADMIN_USER : " password
    echo

    local kdc_processes=$(samba-tool processes | grep "kdc_server")
    
    if [ -n "$kdc_processes" ]; then
        if echo "$password" | kinit "$ADMIN_USER" &> /dev/null; then
            kerberos_checks+=("<tr style='background-color: $COLOR_GREEN;'><td>Authentification Kerberos</td><td>Actif et Valide</td></tr>")
        else
            kerberos_checks+=("<tr style='background-color: $COLOR_RED;'><td>Authentification Kerberos</td><td>Problème détecté</td></tr>")
            kerberos_checks+=("<tr><td colspan='2'>Problème avec l'authentification Kerberos pour l'utilisateur '$ADMIN_USER'.</td></tr>")
        fi
    else
        kerberos_checks+=("<tr style='background-color: $COLOR_RED;'><td>Authentification Kerberos</td><td>Problème détecté</td></tr>")
        kerberos_checks+=("<tr><td colspan='2'>Service KDC inactif.</td></tr>")
    fi

    echo "${kerberos_checks[@]}"
}

# Vérification LDAP
check_ldap() {
    local ldap_checks=()
    
    # Vérifier la configuration LDAP via samba-tool
    if samba-tool domain info $(hostname -f) &> /dev/null; then
        ldap_checks+=("<tr style='background-color: $COLOR_GREEN;'><td>Annuaire LDAP</td><td>Configuré et Accessible</td></tr>")
    else
        ldap_checks+=("<tr style='background-color: $COLOR_RED;'><td>Annuaire LDAP</td><td>Problème de configuration</td></tr>")
        ldap_checks+=("<tr><td colspan='2'>Impossible de récupérer les informations du domaine.</td></tr>")
    fi

    echo "${ldap_checks[@]}"
}

# Vérification DNS
check_dns() {
    local dns_checks=()
    
    local dns_processes=$(samba-tool processes | grep "dns")
    
    if [ -n "$dns_processes" ] && host "$DOMAIN_NAME" &> /dev/null; then
        dns_checks+=("<tr style='background-color: $COLOR_GREEN;'><td>Serveur DNS</td><td>Actif et Fonctionnel</td></tr>")
    else
        dns_checks+=("<tr style='background-color: $COLOR_RED;'><td>Serveur DNS</td><td>Problème détecté</td></tr>")
        dns_checks+=("<tr><td colspan='2'>Problème avec le service DNS.</td></tr>")
    fi

    echo "${dns_checks[@]}"
}

# Vérification de la synchronisation de l'heure
check_time_sync() {
    local time_checks=()
    
    # Vérifier si ntpd ou chronyd est installé
    if ! command -v ntpstat &> /dev/null && ! command -v chronyc &> /dev/null; then
        time_checks+=("<tr style='background-color: $COLOR_RED;'><td>Service NTP</td><td>Non installé</td></tr>")
        return
    fi

    # Vérifier la synchronisation avec chronyd
    if command -v chronyc &> /dev/null; then
        if chronyc tracking | grep -q "^Leap status.*Normal"; then
            local offset=$(chronyc tracking | grep "Last offset" | awk '{print $4}')
           if [ "$(echo "$offset < 1.0" | bc -l)" -eq 1 ]; then
                time_checks+=("<tr style='background-color: $COLOR_GREEN;'><td>Synchronisation NTP (chronyd)</td><td>Synchronisé (offset: ${offset}s)</td></tr>")
            else
                time_checks+=("<tr style='background-color: $COLOR_YELLOW;'><td>Synchronisation NTP (chronyd)</td><td>Offset important: ${offset}s</td></tr>")
            fi
        else
            time_checks+=("<tr style='background-color: $COLOR_RED;'><td>Synchronisation NTP (chronyd)</td><td>Non synchronisé</td></tr>")
        fi
    fi

    # Vérifier la synchronisation avec ntpd
    if command -v ntpq &> /dev/null; then
        if ntpq -p &> /dev/null; then
            local offset=$(ntpq -c rv | grep offset | cut -d= -f2)
            if [ "$(echo "$offset < 1.0" | bc -l)" -eq 1 ]; then
                time_checks+=("<tr style='background-color: $COLOR_GREEN;'><td>Synchronisation NTP (ntpd)</td><td>Synchronisé (offset: ${offset}ms)</td></tr>")
            else
                time_checks+=("<tr style='background-color: $COLOR_YELLOW;'><td>Synchronisation NTP (ntpd)</td><td>Offset important: ${offset}ms</td></tr>")
            fi
        else
            time_checks+=("<tr style='background-color: $COLOR_RED;'><td>Synchronisation NTP (ntpd)</td><td>Non synchronisé</td></tr>")
        fi
    fi

    echo "${time_checks[@]}"
}

# Vérification des ports UFW
check_ufw_ports() {
    local ufw_checks=()
    
    # Vérifier si UFW est installé
    if ! command -v ufw &> /dev/null; then
        ufw_checks+=("<tr style='background-color: $COLOR_YELLOW;'><td>UFW</td><td>Non installé</td></tr>")
        return
    fi

    # Vérifier si UFW est actif
    if ! ufw status | grep -q "Status: active"; then
        ufw_checks+=("<tr style='background-color: $COLOR_YELLOW;'><td>UFW Status</td><td>Inactif</td></tr>")
        return
    fi

    # Vérifier chaque port requis
    for port in "${REQUIRED_PORTS[@]}"; do
        if ufw status | grep -qE "^$port/(tcp|udp).*ALLOW"; then
            ufw_checks+=("<tr style='background-color: $COLOR_GREEN;'><td>Port $port</td><td>Ouvert</td></tr>")
        else
            ufw_checks+=("<tr style='background-color: $COLOR_RED;'><td>Port $port</td><td>Fermé</td></tr>")
        fi
    done

    echo "${ufw_checks[@]}"
}

# Génération du rapport HTML
generate_html_report() {
    cat << EOF > "$REPORT_FILE"
<!DOCTYPE html>
<html>
<head>
    <title>Rapport Monitoring Samba AD DC - $SERVER_NAME</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        h2 { color: #333; margin-top: 20px; }
        pre { white-space: pre-wrap; word-wrap: break-word; }
    </style>
</head>
<body>
    <h1>Rapport de Monitoring Samba AD DC - $SERVER_NAME - $(date '+%d/%m/%Y %H:%M:%S')</h1>

    <h2>Processus Samba AD</h2>
    <table>
        $(check_samba_processes)
    </table>
    
    <h2>Processus Syncthing Sysvol</h2>
    <table>
        $(check_syncthing_processes)
    </table>
    
    <h2>Processus tis-sysvol services</h2>
    <table>
        $(check_tis_services)
    </table>
    
    <h2>Authentification Kerberos</h2>
    <table>
        $(check_kerberos)
    </table>

    <h2>Annuaire LDAP</h2>
    <table>
        $(check_ldap)
    </table>

    <h2>Serveur DNS</h2>
    <table>
        $(check_dns)
    </table>

     <h2>Synchronisation de l'heure</h2>
    <table>
        $(check_time_sync)
    </table>

    <h2>État des ports UFW</h2>
    <table>
        $(check_ufw_ports)
    </table>

    <h2>État de la Base de Données AD</h2>
    <table>
        $(check_database_consistency)
    </table>
</body>
</html>
EOF
}

# Envoi du rapport par email
send_email_report() {
    if [ -f "$REPORT_FILE" ]; then
        if command -v sendmail &> /dev/null; then
            (
                echo "To: $ADMIN_EMAIL"
                echo "Subject: Rapport Monitoring Samba AD DC - $SERVER_NAME - $(date '+%d/%m/%Y')"
                echo "Content-Type: text/html"
                echo ""
                cat "$REPORT_FILE"
            ) | sendmail -t
            log_message "Rapport envoyé via sendmail à $ADMIN_EMAIL"
        elif command -v ssmtp &> /dev/null; then
            (
                echo "To: $ADMIN_EMAIL"
                echo "Subject: Rapport Monitoring Samba AD DC - $SERVER_NAME - $(date '+%d/%m/%Y')"
                echo "Content-Type: text/html"
                echo ""
                cat "$REPORT_FILE"
            ) | ssmtp "$ADMIN_EMAIL"
            log_message "Rapport envoyé via ssmtp à $ADMIN_EMAIL"
        else
            log_message "Aucun outil d'envoi d'email (sendmail/ssmtp) trouvé. Le rapport n'a pas été envoyé."
        fi
    else
        log_message "Le fichier de rapport $REPORT_FILE n'existe pas. Impossible d'envoyer l'email."
    fi
}

# Démarrage du monitoring
log_message "Démarrage du script de monitoring"
check_ldap_tools
generate_html_report
send_email_report
log_message "Script terminé avec succès"
