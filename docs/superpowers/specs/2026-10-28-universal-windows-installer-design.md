# DeepSeek Harness Universal Windows Installer Design

## Goal

Turn the existing one-click scripts into a portable Windows 10/11 installer that installs a reliable, app-like DeepSeek Harness experience for the current user. It must retain the existing Node.js fallback, API-key setup, and current user customizations while replacing the fragile VBS web-start path with the verified native launcher pattern.

## Scope and compatibility

- Support Windows 10 and Windows 11, x64, for a non-administrator user.
- Install only into the current user's profile; never write to Program Files, modify system policy, or require administrator rights.
- Keep DSH data, configuration, credentials, and user work in `%USERPROFILE%\\DeepSeek Harness`.
- Install the native launcher and its icon in `%LOCALAPPDATA%\\Programs\\DeepSeek Harness`.
- Create a Desktop shortcut and a Start Menu shortcut named `DeepSeek Harness`.
- Preserve existing uncommitted improvements in `scripts/install.ps1`, `scripts/start-web.ps1`, `scripts/set-api-key.ps1`, `5-后台启动.vbs`, and `README.md` unless a change is explicitly needed for the new behavior.

## Chosen architecture

The package remains a ZIP-friendly PowerShell installer, but adds a small native Windows launcher. The launcher owns the local DSH web lifecycle: it prevents duplicate launches, reuses a healthy local server on port 3080, starts `dsh web --no-open` when needed, reads the generated token URL from a redacted local log, and opens Microsoft Edge in app mode.

The installer copies versioned launcher assets from the package into the current user's local program folder. It creates the shortcuts and registers a conservative daily update check. The existing batch files remain simple entry points to PowerShell scripts, so a downloaded ZIP can still be extracted and used without a package manager or an administrator account.

## Components and responsibilities

| Component | Responsibility |
| --- | --- |
| `1-一键安装.bat` | Starts the installation script with a clear policy-bypass command scoped to that process only. |
| `scripts/install.ps1` | Validates Windows/Node prerequisites, installs or updates DSH, deploys launcher files, migrates safely, creates shortcuts, and registers the update check. |
| Native launcher | Starts or reuses the local DSH web service and opens the tokenized app window. It does not alter DSH settings or credentials. |
| `3-启动Web界面.bat` | Opens the installed native launcher, not a VBS shell or raw `dsh web` process. |
| `scripts/update.ps1` | Checks release metadata and npm package metadata, prompts before any install, updates atomically, verifies health, and rolls back on failure. |
| `6-检查更新.bat` | Manually invokes `update.ps1` in check-only or user-approved update mode. |
| `scripts/repair.ps1` | Repairs missing launcher files, shortcuts, and scheduled update registration without deleting user data. |
| `scripts/uninstall.ps1` | Removes installed launcher, shortcuts, and scheduled task; it asks separately before deleting DSH data. |
| `scripts/diagnostics.ps1` | Collects redacted version, launcher, port, and log information into a user-shareable report. |

## Installation and launch flow

1. The installer confirms it is running on supported Windows and obtains Node.js through the existing reliable detection/fallback path.
2. It installs the pinned package version or the latest compatible `@deepseek-ai/dsh` release.
3. It copies a signed-by-package native launcher executable and official DeepSeek Harness icon into `%LOCALAPPDATA%\\Programs\\DeepSeek Harness`.
4. It backs up only files it will replace, verifies hashes of copied launcher assets, creates Desktop and Start Menu shortcuts, and records installed versions in a small manifest.
5. A launch request invokes the native launcher. It uses one named mutex, detects an existing healthy port 3080 server, waits for a new server when required, then opens Edge using the one-time token URL.
6. No automatic startup is enabled by default. The old background-start VBS remains available only for compatibility until a later major release explicitly deprecates it.

## Update design

The installer registers one current-user scheduled task that runs once daily at a quiet default time. The task performs a metadata-only check asynchronously and exits silently when there is no update, no network, or a transient registry/release failure.

When an update is available, it shows a notification or clear prompt; it never silently changes DSH, Node, API keys, plugins, or credentials. A manual `6-检查更新.bat` offers the same check and gives the user an explicit Install / Later decision. The updater compares the installed manifest with both the project release version and the npm DSH package version, downloads only declared assets, validates SHA-256 when a release manifest provides it, and writes all activity to rotating local logs.

Before replacement, the updater backs up launcher files and non-secret configuration metadata. It never archives `.credentials.yaml` or prints token URLs. It stops only a process it has verified as the local DSH listener, applies the update, starts the launcher, and checks that port 3080 responds. If the health check fails, it restores the previous launcher version and reports the rollback result.

## Repair, diagnostics, and uninstall

`repair.ps1` is idempotent: it restores launcher files from the package or current installation, recreates missing shortcuts and the scheduled task, and can restart DSH. It must not delete profiles, conversations, workspace files, credentials, or custom plugin settings.

Diagnostics captures Windows version, Node version, DSH version, installed launcher version, port listener state, and the final bounded lines of relevant logs after redacting API keys, bearer tokens, tokenized localhost URLs, and user secrets. The report is saved locally and intended to be attached to a support request.

Uninstall removes only the launcher installation, shortcuts, update task, and installer-managed logs by default. It displays a second, explicit choice before removing `%USERPROFILE%\\DeepSeek Harness`, so normal uninstall preserves users' DSH profile and API-key configuration.

## Error handling

- Missing Node.js: use the existing installer fallback path and give a one-action recovery message if it still cannot be installed.
- DSH or launcher download failure: retain the prior working installation and explain where the log is saved.
- Port 3080 in use by another application: do not terminate it; show the owning process and offer repair instructions.
- Existing healthy DSH server: reuse it without changing token, profile, or user files.
- Broken experimental plugin: preserve profile before any repair, remove only the explicitly selected optional plugin, and verify the revised profile parses.
- Update failure: restore the launcher backup automatically and state whether DSH itself was changed.
- No network: leave the installed application usable and defer the update check without error dialogs.

## Test and acceptance criteria

1. On a clean non-admin Windows 10/11 user profile, a ZIP extraction followed by `1-一键安装.bat` installs Node/DSH as needed, creates both shortcuts, and opens the native app launcher.
2. A user with Node and DSH already installed completes installation without replacing credentials or unrelated profile files.
3. Double-clicking the Desktop or Start Menu shortcut starts one backend or reuses a healthy backend, then opens the local app window.
4. Repeated launches do not create duplicate DSH servers or leave hidden command windows.
5. The daily update check produces no UI when no update is available; an available update always requires user confirmation.
6. A deliberately invalid launcher update triggers health-check failure and restores the prior launcher.
7. Repair restores missing shortcuts and update registration without touching profile data.
8. Uninstall leaves `%USERPROFILE%\\DeepSeek Harness` intact unless the user explicitly chooses data removal.
9. Diagnostics output contains no API key, bearer token, local web token, or credentials-file contents.

## Explicitly out of scope

- A system-wide MSI installer, administrator installation, auto-start on login, automatic Node major-version upgrades, automatic plugin installation, or automatic updates without approval.
- Changing user model/API configuration, DSH conversation data, or optional plugin choices during installation or update.
