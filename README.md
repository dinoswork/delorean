# DeLorean – Simple Backup Utility

Simple macOS menu bar application to synchronize user data using rsync. This might not be the most elegant way to back up files, but it's simple and it works. Using a small bash script, this Swift application provides an interface to control `sync_files.sh`.

_Forked from: https://github.com/jnsdrtlf/sync/tree/master_

## Configuration

DeLorean reads its entire configuration from the `sync_files.sh` script located inside the app bundle. To customize the backup behavior, modify this script.

### Accessing the Configuration File

For deployed app:
1. Right‑click on `DeLorean.app` in Applications
2. Select “Show Package Contents”
3. Navigate to `Contents/Resources/sync_files.sh`
4. Open with a text editor (you may need admin privileges)

For development:
- Edit `delorean/sync_files.sh` in the repo, then rebuild the app.

### Configurable Variables (at the top of sync_files.sh)

Backup scheduling:
    scheduledBackupTime="09:15"    # Daily backup time (24-hour format)
    rangeStart="07:00"             # Earliest time backups can run
    rangeEnd="21:00"               # Latest time backups can run
    frequencyCheck="60"            # How often to check for backups (seconds)
    maxDayAttemptNotification=6    # Max failure notifications per day

Source directories:
    `SOURCES=("$HOME/Pictures" "$HOME/Documents" "$HOME/Downloads" "$HOME/Desktop")`
Uncomment or modify example lines to customize which folders to back up:
    `#SOURCES=("$HOME/Documents" "$HOME/Downloads" "$HOME/Pictures")`
    `#SOURCES=("$HOME/Pictures" "$HOME/Downloads")`
    `#SOURCES=("$HOME/Pictures")`

Destination:
    `DEST="/Volumes/SFA-All/User Data/$(whoami)/"`

    or

    `DEST="/Volumes/$(whoami)/SYSTEM/delorean/"`
Change this to your network drive or backup location. `$(whoami)` automatically uses the current username.

Log file:
    LOG_FILE="$HOME/delorean.log"
Location where backup logs are stored.

### Example Customization

Back up only Documents and Pictures to a different network drive at 6 PM:
    SOURCES=("$HOME/Documents" "$HOME/Pictures")
    DEST="/Volumes/BackupDrive/Users/$(whoami)/"
    scheduledBackupTime="18:00"

## Notes for Users

### ⚠️ First-Time Setup

After installing DeLorean, you'll **really** want to consider granting it Full Disk Access:

#### macOS Ventura (13.0+) or Sonoma (14.0+):

1. Open **System Settings**
2. Click **Privacy & Security** in the sidebar
3. Scroll down and click **Full Disk Access**
4. Click the **(+)** button
5. Navigate to `/Applications/DeLorean.app` and click **Open**
6. Toggle the switch next to DeLorean to **ON**
7. Quit and restart DeLorean

#### macOS Monterey (12.0) or earlier:

1. Open **System Preferences**
2. Click **Security & Privacy**
3. Click the **Privacy** tab
4. Select **Full Disk Access** from the list
5. Click the lock icon 🔒 and enter your password
6. Click the **(+)** button
7. Navigate to `/Applications/DeLorean.app` and click **Open**
8. Quit and restart DeLorean

**Without this permission, DeLorean might not be able to access all your files in your user profile for backup.**

- As it's configured right now, macOS will prompt for access to Desktop, Documents, and Downloads on first launch. Click “OK/Allow” so DeLorean can back up those folders.
- Ensure the network destination is mounted and accessible before running a backup.

### Important System Requirements

- **macOS 13.5 (Ventura) or later** recommended
- DeLorean automatically launches at login to perform scheduled backups
- Network drive must be mounted before backup attempts

## Development Setup

1. Clone this repository
2. Open the Xcode project
3. Modify `delorean/sync_files.sh` as needed
4. Build and run

## Creating a PKG Installer
from the DeLorean.app file

### Using Packages (GUI Method - Recommended)
1. Download [Packages](http://s.sudre.free.fr/Software/Packages/about.html)
2. Create a new project
3. Add DeLorean.app with install location `/Applications`
4. Build the installer package

### Using pkgbuild (Command Line Method)
Navigate to where your DeLorean.app is located:
```bash
cd /path/to/your/DeLorean.app/..

pkgbuild --root . \
  --identifier ufemit.delorean \
  --version 1.0 \
  --install-location /Applications \
  UF-EM-DeLorean-Backup.pkg
```

<!-- Navigate to where your DeLorean.app is located in Terminal

`cd /path/to/your/DeLorean.app/..`

Create the package

`pkgbuild --root . --identifier ufemit.delorean --version 1.0 --install-location /Applications UF-EM-DeLorean-Backup.pkg` -->

## License

This project is open source under the Apache License, Version 2.0.

Original work © 2019 Jonas Drotleff (Apache 2.0)  
Modifications © 2025 University of Florida (Apache 2.0)

License text: http://www.apache.org/licenses/LICENSE-2.0

AS IS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND. See the License for the specific language governing permissions and limitations under the License.

The white refresh icon is made by Cole Bemis and is part of the awesome feathericons icon set, released under the MIT License.
