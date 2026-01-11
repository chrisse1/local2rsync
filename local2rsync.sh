#!/bin/bash

# ============================================================
# Initiales Setup
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

CONFIG_FILE="local2rsync.conf"

# ============================================================
# Argumente prüfen
# ============================================================

check_arguments() {
    if [[ "$1" == "--configure" ]]; then
        echo "Starte Konfigurationsdialog ..."
        first_start_wizard
        exit 0
    fi
}

# ============================================================
# First-Start-Wizard
# ============================================================

first_start_wizard() {
    echo "Willkommen zum First-Start-Wizard für local2rsync"
    echo

    read -rp "Titel des Backups [Server]: " BACKUP_TITLE
    BACKUP_TITLE=${BACKUP_TITLE:-Server}

    read -rp "Pushover-Token: " PUSHOVER_TOKEN
    read -rp "Pushover-User-ID: " PUSHOVER_USER

    # rsync Host
    while true; do
        read -rp "Backup-Server (Hostname oder IP): " RSYNC_HOST
        [[ -z $RSYNC_HOST ]] && continue
        if rsync "$RSYNC_HOST::" >/dev/null 2>&1; then
            break
        fi
        echo "Server nicht erreichbar."
    done

    # rsync User
    echo
    read -rp "rsync Benutzername (leer = anonymer Zugriff): " RSYNC_USER

    # rsync Modul
    echo
    echo "Verfügbare rsync-Module:"
    RSYNC_MODULES=$(rsync "$RSYNC_HOST::" 2>/dev/null | awk '{print $1}')
    echo "$RSYNC_MODULES"

    while true; do
        read -rp "rsync-Modul auswählen: " RSYNC_MODULE
        echo "$RSYNC_MODULES" | grep -qw "$RSYNC_MODULE" && break
    done

    # Passwortdatei
    echo
    read -rp "Pfad zur rsync Passwortdatei [~/.rsync_pass]: " RSYNC_PASSWORD_FILE
    RSYNC_PASSWORD_FILE=${RSYNC_PASSWORD_FILE:-"$HOME/.rsync_pass"}

    if [[ -n "$RSYNC_USER" && ! -f "$RSYNC_PASSWORD_FILE" ]]; then
        echo
        read -rp "Passwortdatei existiert nicht. Jetzt anlegen? (ja/nein): " create_pw
        if [[ $create_pw =~ ^(ja|j)$ ]]; then
            read -rsp "rsync Passwort: " RSYNC_PASSWORD
            echo
            echo "$RSYNC_PASSWORD" >"$RSYNC_PASSWORD_FILE"
            chmod 600 "$RSYNC_PASSWORD_FILE"
            echo "Passwortdatei angelegt: $RSYNC_PASSWORD_FILE"
        else
            echo "⚠️ WARNUNG: Benutzer gesetzt, aber keine Passwortdatei!"
        fi
    fi

    # rsync URL bauen
    if [[ -n "$RSYNC_USER" ]]; then
        BACKUP_SERVER="rsync://$RSYNC_USER@$RSYNC_HOST/$RSYNC_MODULE"
    else
        BACKUP_SERVER="rsync://$RSYNC_HOST/$RSYNC_MODULE"
    fi

    # MariaDB
    read -rp "MariaDB sichern? (ja/nein): " MARIADB_BACKUP
    if [[ $MARIADB_BACKUP =~ ^(ja|j)$ ]]; then
        read -rp "MariaDB Benutzer: " MARIADB_USER
        read -rsp "MariaDB Passwort: " MARIADB_PASSWORD
        echo
        MARIADB_BACKUP=true
    else
        MARIADB_BACKUP=false
    fi

    # Backup-Pfade
    echo
    echo "Backup-Pfade (name:path), leer beendet:"
    BACKUP_PATHS=()
    while true; do
        read -rp "Pfad: " entry
        [[ -z $entry ]] && break
        BACKUP_PATHS+=("$entry")
    done

    # Uhrzeit
    while true; do
        read -rp "Backup-Uhrzeit (HH:MM): " BACKUP_TIME
        [[ $BACKUP_TIME =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]] && break
    done

    # Konfig schreiben
    {
        echo "BACKUP_TITLE=\"$BACKUP_TITLE\""
        echo "PUSHOVER_TOKEN=\"$PUSHOVER_TOKEN\""
        echo "PUSHOVER_USER=\"$PUSHOVER_USER\""
        echo "RSYNC_HOST=\"$RSYNC_HOST\""
        echo "RSYNC_USER=\"$RSYNC_USER\""
        echo "RSYNC_MODULE=\"$RSYNC_MODULE\""
        echo "BACKUP_SERVER=\"$BACKUP_SERVER\""
        echo "RSYNC_PASSWORD_FILE=\"$RSYNC_PASSWORD_FILE\""
        echo "BACKUP_PATHS=("
        for p in "${BACKUP_PATHS[@]}"; do echo "  \"$p\""; done
        echo ")"
        echo "MARIADB_BACKUP=$MARIADB_BACKUP"
        [[ $MARIADB_BACKUP == true ]] && {
            echo "MARIADB_USER=\"$MARIADB_USER\""
            echo "MARIADB_PASSWORD=\"$MARIADB_PASSWORD\""
        }
        echo "BACKUP_TIME=\"$BACKUP_TIME\""
    } >"$CONFIG_FILE"

    setup_cronjob "${BACKUP_TIME#*:}" "${BACKUP_TIME%:*}"
}

# ============================================================
# Cronjob
# ============================================================

setup_cronjob() {
    (crontab -l 2>/dev/null; \
     echo "$1 $2 * * * /bin/bash $(realpath "$0") >> /var/log/local2rsync.log 2>&1") | crontab -
}

# ============================================================
# Konfig laden
# ============================================================

[[ ! -f $CONFIG_FILE ]] && first_start_wizard
check_arguments "$1"
source "$CONFIG_FILE"

# ============================================================
# rsync Passwortdatei prüfen
# ============================================================

RSYNC_PASSWORD_OPT=()

if [[ -n "$RSYNC_USER" ]]; then
    if [[ ! -f "$RSYNC_PASSWORD_FILE" ]]; then
        echo "❌ rsync Benutzer gesetzt, aber Passwortdatei fehlt."
        exit 1
    fi
    chmod 600 "$RSYNC_PASSWORD_FILE" 2>/dev/null
    RSYNC_PASSWORD_OPT=(--password-file="$RSYNC_PASSWORD_FILE")
fi

# ============================================================
# Backup
# ============================================================

errors=0

backup_path() {
    IFS=":" read -r name path <<<"$1"
    rsync -av --delete \
        "${RSYNC_PASSWORD_OPT[@]}" \
        "$path" \
        "$BACKUP_SERVER/$name/" || errors=$((errors + 1))
}

[[ $MARIADB_BACKUP == true ]] && echo "MariaDB-Backup hier wie gehabt"

for p in "${BACKUP_PATHS[@]}"; do
    backup_path "$p"
done

# ============================================================
# Push
# ============================================================

if [[ $errors -eq 0 ]]; then
    title="$BACKUP_TITLE-Backup erfolgreich"
    sound="cosmic"
else
    title="$BACKUP_TITLE-Backup FEHLER"
    sound="falling"
fi

curl -s \
  --form-string "token=$PUSHOVER_TOKEN" \
  --form-string "user=$PUSHOVER_USER" \
  --form-string "title=$title" \
  --form-string "sound=$sound" \
  --form-string "message=Backup beendet mit $errors Fehler(n)" \
  https://api.pushover.net/1/messages.json >/dev/null

exit $errors
