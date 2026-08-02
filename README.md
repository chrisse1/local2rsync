# local2rsync

Bash-Skript zur Sicherung lokaler Verzeichnisse (und optional einer MariaDB-Datenbank) auf einen rsync-Server, mit Statusmeldung per Pushover.

---

## **Funktionen**
- **Backup von Verzeichnissen** per `rsync`, alte/überschriebene Dateien werden dabei versioniert unter `_old/` auf dem Server abgelegt statt einfach gelöscht.
- **Optionales MariaDB-Backup**: `mysqldump --all-databases`, Upload per rsync.
- **Pushover-Benachrichtigung** nach jedem Lauf, bei Fehlern inklusive Details.
- **First-Start-Wizard** bei der ersten Ausführung, erneut aufrufbar mit `--configure`.
- **Täglicher Cronjob** wird automatisch eingerichtet (Uhrzeit im Wizard wählbar).

---

## **Systemanforderungen**
- **Bash**
- **rsync** – Backup und Datenübertragung
- **curl** – Pushover-Benachrichtigungen
- **mysqldump** – nur falls MariaDB-Backup aktiviert wird
- **Pushover-Konto**
- **rsync-Server** als Backup-Ziel

---

## **Installation**
1. Repository klonen:
   `git clone https://github.com/chrisse1/local2rsync.git`
2. `cd local2rsync`
3. `chmod +x local2rsync.sh`
4. `./local2rsync.sh`
5. Den Anweisungen des Wizards folgen.

Zum späteren Anpassen der Konfiguration: `./local2rsync.sh --configure`
