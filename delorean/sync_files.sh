#!/bin/bash

# Ensure child processes (rsync) are terminated when this script exits
# When we receive SIGTERM/SIGINT, exit immediately without logging
cleanup() {
    # First, try graceful termination
    kill -TERM -- -$$ 2>/dev/null
    
    # Wait briefly for processes to clean up
    sleep 0.5
    
    # Force kill any remaining processes
    kill -KILL -- -$$ 2>/dev/null
    
    exit 130  # Standard exit code for script terminated by signal
}

trap cleanup SIGINT SIGTERM
 
# Backup scheduling parameters
scheduledBackupTime="8:10"
rangeStart="07:00"
rangeEnd="21:00"
# How often the app should check if an rsync happened that day in seconds (3600 seconds = 1 hour)
frequencyCheck="3600"
maxDayAttemptNotification=6
 
# Define source directories
SOURCES=("$HOME/Pictures" "$HOME/Documents" "$HOME/Downloads" "$HOME/Desktop")
#SOURCES=("$HOME/Documents" "$HOME/Downloads" "$HOME/Pictures")
#SOURCES=("$HOME/Pictures" "$HOME/Downloads")
 
# Define destination directory
DEST="/Volumes/SFA-All/User Data/$(whoami)/"
mkdir -p "$DEST" # Create destination directory if it doesn't exist
 
# Log file
LOG_FILE="$HOME/delorean.log"
mkdir -p "$(dirname "$LOG_FILE")" # Create log file directory if it doesn't exist
 
# Function to log a failure with rsync exit code
log_failure_with_code() {
    local exit_code=$1
    local error_desc=""
    
    case $exit_code in
        1) error_desc="Configuration or syntax error" ;;
        3) error_desc="File access error (permissions or file in use)" ;;
        10) error_desc="Network connection error" ;;
        11) error_desc="File I/O error (disk full or file locked)" ;;
        12) error_desc="Data corruption during transfer" ;;
        23) error_desc="Transfer incomplete due to errors" ;;
        24) error_desc="Source file was deleted during backup" ;;
        30) error_desc="Network timeout" ;;
        *) error_desc="Unknown error (code $exit_code)" ;;
    esac
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup Failed: $error_desc (exit code: $exit_code)" >> "$LOG_FILE"
}
 
# Function to log a successful backup
log_success() {
    # Check if this was triggered by manual or scheduled backup
    # We'll pass this as an environment variable from Swift
    local backup_type="${BACKUP_TYPE:-scheduled}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup completed successfully ($backup_type)" >> "$LOG_FILE"
}
 
# Rsync options and excludes as arrays
OPTIONS=(--archive --verbose --partial --progress --stats --delete)
EXCLUDES=(--exclude='Pictures/Photos Library.photoslibrary' --exclude='.DS_Store')
 
# Run single rsync command for all sources at once
rsync "${OPTIONS[@]}" "${EXCLUDES[@]}" "${SOURCES[@]}" "$DEST"
rsync_exit_code=$?

# Log result based on exit code
if [ $rsync_exit_code -eq 0 ]; then
    log_success
    # Copy log file to destination on success
    cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
    echo "Backup completed."
    exit 0
else
    log_failure_with_code $rsync_exit_code
    # Try to copy log file even on failure (might not work if network is down)
    cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
    echo "Backup failed."
    exit $rsync_exit_code  # Exit with the actual rsync error code
fi
