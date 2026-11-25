#!/bin/bash
# Scheduled Proxmox VE shutdown utility (23:00 daily) with calendar exception support.
# Installation:
#   cp proxmox-auto-shutdown.sh /usr/local/bin/auto-shutdown && chmod +x /usr/local/bin/auto-shutdown
#   echo "0 23 * * * root /usr/local/bin/auto-shutdown check" > /etc/cron.d/auto-shutdown

CONF_FILE="/etc/auto-shutdown-exceptions"
touch "$CONF_FILE"

to_iso() {
    if [[ "$1" =~ ^([0-9]{2})-([0-9]{2})-([0-9]{4})$ ]]; then
        local iso="${BASH_REMATCH[3]}-${BASH_REMATCH[2]}-${BASH_REMATCH[1]}"
        date -d "$iso" "+%Y-%m-%d" 2>/dev/null
    else
        return 1
    fi
}

from_iso() {
    date -d "$1" "+%d-%m-%Y" 2>/dev/null
}

cleanup_old() {
    local today
    today=$(date "+%Y-%m-%d")
    local tmp
    tmp=$(mktemp)
    while read -r s e; do
        [ -z "$s" ] && continue
        if [[ ! "$e" < "$today" ]]; then
            echo "$s $e" >> "$tmp"
        fi
    done < "$CONF_FILE"
    sort -u "$tmp" > "$CONF_FILE"
    rm -f "$tmp"
}

is_exempt_today() {
    local today
    today=$(date "+%Y-%m-%d")
    while read -r s e; do
        [ -z "$s" ] && continue
        if [[ ! "$today" < "$s" && ! "$today" > "$e" ]]; then
            return 0
        fi
    done < "$CONF_FILE"
    return 1
}

cleanup_old

case "$1" in
    ""|status)
        echo "=== Proxmox Auto-Shutdown Schedule (23:00) ==="
        if is_exempt_today; then
            echo "Today ($(date '+%d-%m-%Y')): EXEMPT - server will NOT shut down at 23:00."
        else
            echo "Today ($(date '+%d-%m-%Y')): ACTIVE - server will shut down at 23:00."
        fi
        echo ""
        echo "Saved exceptions (shutdown skipped):"
        if [ ! -s "$CONF_FILE" ]; then
            echo "  (none)"
        else
            while read -r s e; do
                [ -z "$s" ] && continue
                if [ "$s" = "$e" ]; then
                    echo "  - $(from_iso "$s")"
                else
                    echo "  - from $(from_iso "$s") to $(from_iso "$e")"
                fi
            done < "$CONF_FILE"
        fi
        ;;
    today)
        TODAY_ISO=$(date "+%Y-%m-%d")
        echo "$TODAY_ISO $TODAY_ISO" >> "$CONF_FILE"
        cleanup_old
        echo "Added exception for today ($(date '+%d-%m-%Y')). Shutdown skipped at 23:00."
        ;;
    del|remove)
        if [ -z "$2" ]; then
            echo "Provide a date to remove, e.g.: auto-shutdown del 28-11-2026"
            exit 1
        fi
        TARGET_ISO=$(to_iso "$2")
        if [ -z "$TARGET_ISO" ]; then
            echo "Invalid date format. Use DD-MM-YYYY (e.g., 28-11-2026)."
            exit 1
        fi
        grep -v "$TARGET_ISO" "$CONF_FILE" > "${CONF_FILE}.tmp" && mv "${CONF_FILE}.tmp" "$CONF_FILE"
        echo "Removed exceptions matching $2."
        ;;
    clear)
        : > "$CONF_FILE"
        echo "Cleared all scheduled exceptions."
        ;;
    check)
        if is_exempt_today; then
            logger -t auto-shutdown "Active calendar exception - skipping 23:00 shutdown."
            exit 0
        fi
        logger -t auto-shutdown "No exceptions for today - shutting down Proxmox at 23:00."
        /sbin/shutdown -h now
        ;;
    *)
        START_ISO=$(to_iso "$1")
        if [ -z "$START_ISO" ]; then
            echo "Usage:"
            echo "  auto-shutdown status                - check status and exception list"
            echo "  auto-shutdown 28-11-2026            - skip shutdown on a specific day"
            echo "  auto-shutdown 27-11-2026 29-11-2026 - skip shutdown across a date range (inclusive)"
            echo "  auto-shutdown today                 - quick exception for today"
            echo "  auto-shutdown del 28-11-2026        - remove entry containing given date"
            echo "  auto-shutdown clear                 - remove all exceptions"
            exit 1
        fi
        if [ -n "$2" ]; then
            END_ISO=$(to_iso "$2")
            if [ -z "$END_ISO" ]; then
                echo "Invalid end date format. Use DD-MM-YYYY."
                exit 1
            fi
            if [[ "$END_ISO" < "$START_ISO" ]]; then
                echo "End date cannot be earlier than start date."
                exit 1
            fi
            echo "$START_ISO $END_ISO" >> "$CONF_FILE"
            cleanup_old
            echo "Added exception range: from $1 to $2 (inclusive)."
        else
            echo "$START_ISO $START_ISO" >> "$CONF_FILE"
            cleanup_old
            echo "Added exception for: $1."
        fi
        ;;
esac