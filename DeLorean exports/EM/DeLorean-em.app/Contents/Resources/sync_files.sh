#!/bin/bash
# ----------------------------------------------------------------------
# CLEANUP TRAP
# Ensure child processes (rsync) are terminated when this script exits
# ----------------------------------------------------------------------
cleanup() {
    kill -TERM -- -$$ 2>/dev/null
    sleep 0.5
    kill -KILL -- -$$ 2>/dev/null
    [ -f "$HOME/delorean_error_check.tmp" ] && rm "$HOME/delorean_error_check.tmp"
    exit 130
}
trap cleanup SIGINT SIGTERM

# ----------------------------------------------------------------------
# CONFIGURATION
# ----------------------------------------------------------------------
scheduledBackupTime="8:10"
rangeStart="07:00"
rangeEnd="21:00"
frequencyCheck="3600"
maxDayAttemptNotification=6

# Define source directories
SOURCES=("$HOME/Pictures" "$HOME/Documents" "$HOME/Downloads" "$HOME/Desktop")

# Define destination directory
# DEST="/Volumes/SFA-All/User Data/$(whoami)/"
DEST="/Volumes/$(whoami)/SYSTEM/delorean/"
mkdir -p "$DEST"

# Log files
LOG_FILE="$HOME/delorean.log"
mkdir -p "$(dirname "$LOG_FILE")"
ERROR_TEMP="$HOME/delorean_error_check.tmp"
# Clean up any leftover temp file from previous interrupted run
[ -f "$ERROR_TEMP" ] && rm "$ERROR_TEMP"

# ----------------------------------------------------------------------
# RSYNC OPTIONS & EXCLUDES
# ----------------------------------------------------------------------
# Using -rltD instead of --archive to avoid permission/ownership issues on NTFS
# --inplace: Write directly to destination (avoids temp file length issues)
# --no-p/o/g: Don't try to preserve permissions/owner/group (NTFS compatibility)
OPTIONS=(-rltD --inplace --verbose --partial --progress --stats --delete --no-p --no-o --no-g)

EXCLUDES=(
    --exclude='Photos Library.photoslibrary'
    --exclude='.DS_Store'
    --exclude='~$*'
    --exclude='*.download'
    --exclude='*.crdownload'
    --exclude='*.part'
    --exclude='*.icloud'
    --exclude='*-shm'
    --exclude='*-wal'
    --exclude='*.tmp'
#    --exclude='*.wav'
#    --exclude='*.aup3'
#    --exclude='*.mp3'
#    --exclude='*.m4a'
#    --exclude='*.mp4'
#    --exclude='*.mov'
#    --exclude='*.jpg'
    --exclude='*.dmg'
    --exclude='*.pkg'
    --exclude='*.iso'
    --exclude='*.app'
    --exclude='*.pvm'
    --exclude='*.pvmp'
)

# ----------------------------------------------------------------------
# LOGGING FUNCTIONS
# ----------------------------------------------------------------------
log_entry() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_success() {
    local backup_type="${BACKUP_TYPE:-scheduled}"
    log_entry "Backup completed successfully ($backup_type)"
}

# ----------------------------------------------------------------------
# EXECUTION
# ----------------------------------------------------------------------
# Run rsync, capturing ALL output to temp file for analysis
rsync "${OPTIONS[@]}" "${EXCLUDES[@]}" "${SOURCES[@]}" "$DEST" > "$ERROR_TEMP" 2>&1
rsync_exit_code=$?

# Extract ONLY errors/warnings to main log (prevents bloat)
# ": open$" matches rsync's "filename: open" error at end of line only
grep -E "mkstempat|File name too long|Operation not permitted|: open$" "$ERROR_TEMP" | grep -v "rsync_downloader\|rsync_receiver\|rsync_sender\|io_read\|unexpected end of file\|child.*exited" >> "$LOG_FILE" 2>/dev/null || true

# ----------------------------------------------------------------------
# INTELLIGENT ERROR HANDLING
# ----------------------------------------------------------------------
if [ $rsync_exit_code -eq 0 ]; then
    # Perfect success
    log_success
    rm "$ERROR_TEMP"
    cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
    echo "Backup completed."
    exit 0

elif [ $rsync_exit_code -eq 23 ] || [ $rsync_exit_code -eq 24 ]; then
    # Partial failure - check if errors are tolerable
    # 23 = Partial transfer due to error
    # 24 = Source files vanished during backup
    if grep -qE "mkstempat|File name too long|Input/output error|Operation not permitted|vanished|: open$" "$ERROR_TEMP"; then
        # Tolerable errors: filesystem can't store certain filenames, or files disappeared
        # Log success first (for "Last Backup" display)
        log_success
        # Then log the warning details
        log_entry "Warning: Some files could not be backed up due to filesystem limitations"
        # Extract and log problematic filenames
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Files that could not be backed up:" >> "$LOG_FILE"
        grep -E "mkstempat|File name too long|: open$" "$ERROR_TEMP" | grep -oE "(Downloads|Documents|Pictures|Desktop)/[^:]*" | head -20 >> "$LOG_FILE"
        rm "$ERROR_TEMP"
        cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
        # Always notify on warnings (both manual and scheduled)
        echo "Backup completed with warnings."
        exit 2
    else
        # Real partial failure (network timeout, disk issues, etc.)
        log_entry "Backup Failed: Partial transfer with critical errors (exit code: $rsync_exit_code)"
        rm "$ERROR_TEMP"
        cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
        echo "Backup failed."
        exit $rsync_exit_code
    fi

elif [ $rsync_exit_code -eq 1 ]; then
    # Exit code 1 - check if it's just filename issues
    if grep -qE "mkstempat|File name too long|Input/output error|Operation not permitted|: open$" "$ERROR_TEMP"; then
        # Just filename problems, treat as success with warnings
        # Log success first (for "Last Backup" display)
        log_success
        # Then log the warning details
        log_entry "Warning: Some files could not be backed up due to filesystem limitations"
        # Extract and log problematic filenames
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Files that could not be backed up:" >> "$LOG_FILE"
        grep -E "mkstempat|File name too long|: open$" "$ERROR_TEMP" | grep -oE "(Downloads|Documents|Pictures|Desktop)/[^:]*" | head -20 >> "$LOG_FILE"
        rm "$ERROR_TEMP"
        cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
        # Always notify on warnings (both manual and scheduled)
        echo "Backup completed with warnings."
        exit 2
    else
        # Real configuration/syntax error
        log_entry "Backup Failed: Configuration or syntax error (exit code: 1)"
        rm "$ERROR_TEMP"
        cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
        echo "Backup failed."
        exit 1
    fi

else
    # Catastrophic failures - provide specific error messages
    case $rsync_exit_code in
        10)
            log_entry "Backup Failed: Network connection error (exit code: 10)"
            ;;
        # Check if it's specifically a disk full error
        11) 
            if grep -q "No space left on device" "$ERROR_TEMP"; then
                log_entry "Backup Failed: Network drive is full (exit code: 11)"
            else
                log_entry "Backup Failed: File I/O error (exit code: 11)"
            fi
            ;;
        12)
            log_entry "Backup Failed: Data stream error (exit code: 12)"
            ;;
        30)
            log_entry "Backup Failed: Network timeout (exit code: 30)"
            ;;
        *)
            log_entry "Backup Failed: Critical error (exit code: $rsync_exit_code)"
            ;;
    esac
    rm "$ERROR_TEMP"
    cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
    echo "Backup failed."
    exit $rsync_exit_code
fi
