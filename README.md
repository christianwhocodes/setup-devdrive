# Setup Nodejs & NPM with DevDrive on Windows

A PowerShell script to configure npm's global package installation and cache directories on a Windows Dev Drive for better performance.

## 📋 Overview

This script automates the configuration of npm to use a Dev Drive (or any custom location) for:
- Global package installations (`prefix`)
- Package cache storage (`cache`)
- Global binary executables

Benefits of using a Dev Drive include faster I/O operations, better performance for development workflows, and centralized package management.

## ⚡ Prerequisites

- **Windows 11** (Dev Drive is a Windows 11 feature)
- **PowerShell 7**
- **Node.js & npm** installed (see installation steps below)
- **Dev Drive** created and mounted (e.g., `G:\`)

### Installing Node.js

1. **Download the Node.js installer**:
   - Click this link: [https://nodejs.org/dist/v25.0.0/node-v25.0.0-x64.msi](https://nodejs.org/dist/v25.0.0/node-v25.0.0-x64.msi)

2. **Run the installer**:
   - Open the downloaded MSI file
   - Follow the installation prompts
   - Accept the default settings (recommended)
   - Complete the installation

3. **Verify installation**:
   - Open a new PowerShell window
   - Run `node --version` and `npm --version` to confirm successful installation

## 🚀 Quick Start

1. **Run directly from GitHub**:

   ```powershell
   irm https://raw.githubusercontent.com/christianwhocodes/setup-nodejs-devdrive/main/npm.ps1 | iex
   ```

2. **Clone or download** this repository 

   **Open PowerShell** (no admin rights required)
   
   **Navigate** to the script directory:
   
   ```powershell
   cd G:\christianwhocodes\public\setup-nodejs-devdrive
   ```
   **Run the script**:
   
   ```powershell
   .\npm.ps1
   ```

## 🔧 What It Does

The script performs the following actions:

1. ✅ Creates necessary directories:
   - `G:\.packages\npm` (prefix)
   - `G:\.packages\npm\cache` (cache)
   - `G:\.packages\npm\bin` (binaries)

2. ✅ Configures npm via `npm config set`:
   - Sets global prefix
   - Sets cache location

3. ✅ Updates user environment variables:
   - `NPM_CONFIG_PREFIX`
   - `NPM_CONFIG_CACHE`

4. ✅ Updates user PATH:
   - Adds npm bin directory to user PATH
   - Removes default npm path if present
   - Ensures required default paths exist (like WindowsApps)
   - Fixes malformed PATH entries with missing semicolons
   - Updates current session PATH for immediate use

5. ✅ Creates/updates `~/.npmrc`:
   - Backs up existing file with timestamp (as `.npmrc.bak.YYYYMMDDHHMMSS`)
   - Adds or updates `prefix` and `cache` settings

6. ✅ Verifies configuration:
   - Checks npm settings
   - Validates PATH format
   - Confirms directory creation with visual indicators

## ⚙️ Customization

To change the target location, edit these variables at the top of the script:

```powershell
$npmGlobal = "G:\.packages\npm"  # Change G:\ to your Dev Drive letter
$npmCache = Join-Path $npmGlobal "cache"
$npmBin = Join-Path $npmGlobal "bin"
```

## 📝 Post-Installation

After running the script:

1. **Test the configuration**:
   ```powershell
   npm config get prefix
   npm config get cache
   npm bin -g
   ```

2. **Install a global package**:
   ```powershell
   npm install -g npm@latest
   npm list -g --depth=0
   ```

3. **Verify npm location**:
   ```powershell
   where.exe npm
   ```

4. **For new terminals**: Environment variables are persisted, but you may need to:
   - Open a new PowerShell/CMD window, or
   - Sign out and back in, or
   - Run `refreshenv` (if using Chocolatey)

## 🐛 Troubleshooting

**npm not found after setup:**
- Close and reopen your terminal
- Check that `G:\.packages\npm\bin` is in your PATH: `$env:Path`

**Permission errors:**
- Ensure your Dev Drive is accessible
- Run PowerShell as your regular user (admin not required for user-scope changes)

**Old npm location still being used:**
- Delete the old `.npmrc` backup if needed (located at `~/.npmrc.bak.YYYYMMDDHHMMSS`)
- Verify environment variables: `[Environment]::GetEnvironmentVariable("NPM_CONFIG_PREFIX", "User")`

**Malformed PATH entries:**
- The script automatically fixes PATH entries with missing semicolons
- You can verify with: `$env:Path -split ';'`

**Script execution policy error:**
- Run: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Issues and pull requests are welcome! Feel free to suggest improvements or report bugs.

## 👤 Author

**Kevin Wasike Wakhisi** ([@christianwhocodes](https://github.com/christianwhocodes))

---

**Note**: Dev Drives are optimized for development workloads on Windows 11. For more information, see [Microsoft's Dev Drive documentation](https://learn.microsoft.com/windows/dev-drive/).

