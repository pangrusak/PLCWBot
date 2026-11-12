# PLCWBot

A Windows desktop assistant that opens installed applications through typed or spoken commands.

Built with Electron, JavaScript, and a local AI model through Ollama.

## Features

- Open applications using commands such as `Open Minecraft` or `Launch Spotify`.
- Match requested apps against a Windows application catalog.
- Cache the catalog locally for faster lookups.
- Refresh the catalog when an application cannot be found.
- Use aliases such as `mc`, `vscode`, and `chrome`.
- Choose between applications when several entries match.
- Keep the five most recently requested application launches.
- Open a compact command popup with a global keyboard shortcut.
- Dictate a command, review the transcript, and press Enter to run it.
- Keep running in the system tray after closing the window.
- Optionally start with Windows.
- Install Ollama and download the local model through guided setup.
- Switch between two dark interface layouts with gold-and-blue colors and Times New Roman typography.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Ctrl+Alt+O` | Show the compact launcher |
| `Ctrl+Shift+U` | Start voice input |
| `Enter` | Run the command in the input field |
| `Escape` | Hide the compact launcher |

PLCWBot must be running for its shortcuts to work.

Closing the window hides the application in the system tray. Selecting **Quit Orbit** in the current tray implementation fully exits it. That label should be changed to use the configurable app name.

Shortcut registration may fail if Windows or another application already uses the combination.

## Requirements

### Running a release

- Windows 11.
- Internet access for initial Ollama installation and model download.
- Enough available memory and disk space for Electron, Ollama, and the selected model.
- A microphone and compatible English Windows speech recognizer for voice input.

The configured model is:

```text
qwen2.5:1.5b
```

Performance depends on the computer and whether the model is already loaded.

### Developing locally

- Node.js LTS and npm.
- Windows PowerShell.
- Git, if cloning the repository.

## Development setup

Clone the repository, then open a terminal in the folder containing `package.json`.

Install dependencies:

```powershell
npm install
```

Start the application:

```powershell
npm start
```

### Set up local AI

1. Select **Set up local AI**.
2. Review and approve the installation prompt.
3. Wait for Ollama installation, model download, and the response test.
4. Begin entering application-opening commands.

If Ollama is already available, setup reuses it rather than installing another copy.

## Usage

### Typed commands

Examples:

```text
Open Minecraft
Launch mc
Open VS Code
Launch Spotify
Open ChatGPT
Could you open Notepad for me?
```

Simple recognized commands can bypass the AI and use catalog matching directly. More conversational requests are interpreted by the local model first.

PLCWBot does not automatically install a requested application or open its website when no matching application is found.

### Voice commands

1. Press `Ctrl+Shift+U`.
2. Approve microphone use when prompted.
3. Wait for the listening message.
4. Speak a command.
5. Review the recognized text.
6. Press Enter to run it.

Voice recognition uses the installed Windows speech recognizer. The transcript is not automatically executed.

### Recently opened

The recent list stores up to five unique application entries.

- A new launch request moves the app to the top.
- Repeated launches do not create duplicates.
- The list persists between restarts.
- **Open again** sends the app name through the existing command flow.

An entry records that Windows accepted a launch request, not that the application window was verified as open.

## How it works

```text
Typed or spoken command
          |
          v
Direct command matching or local AI interpretation
          |
          v
Windows application catalog lookup
          |
          v
Selection prompt if multiple applications match
          |
          v
Launch request through Windows
          |
          v
Update recent applications
```

### Application discovery

PLCWBot builds its catalog using Windows' `Get-StartApps`.

The first run scans and saves application names and IDs. Later runs load the saved catalog rather than scanning on every command.

If a requested app is missing from the cached list, PLCWBot refreshes the catalog before reporting that it could not find a match.

This is not a complete inventory of every executable on the computer. Portable applications and apps without suitable Windows entries may not appear.

### Local AI

Ollama interprets conversational commands using `qwen2.5:1.5b`.

The model returns a structured decision containing an action and application name. The application validates that decision and checks the Windows catalog before launching anything.

The model is not given unrestricted terminal access.

### Background operation

Closing the window hides PLCWBot while its process remains running.

The tray menu provides access to:

- The full interface.
- The compact launcher.
- Voice commands.
- The optional Windows startup setting.
- The quit action.

The startup option is enabled for packaged builds.

## Configuration

Branding configuration is stored in `app-config.json`:

```json
{
  "appName": "PLCWBot",
  "tagline": "Your desktop, one command away.",
  "colors": {
    "background": "#101722",
    "blue": "#A9C9F5",
    "gold": "#D5B66E"
  }
}
```

Use this file as the single source for the display name.

Example in the Electron main process:

```javascript
const { appName } = require("./app-config.json");
```

Then use the variable instead of a hardcoded title:

```javascript
title: appName
```

### Branding integration status

Creating the configuration file does not automatically update existing labels.

Some parts of the current implementation may still use the original name, **Orbit**, including:

- Interface text.
- Tray labels.
- Dialog titles.
- Installer metadata.
- Packaging configuration.

Connect those display strings to the configuration before releasing under the PLCWBot name.

Keep stable internal identifiers and saved-data locations separate from the display name so a branding change does not reset user data.

## Logo direction

The proposed logo is a flat gold ring with a small break at the upper-right, on a deep navy background.

Design constraints:

- Recognizable at tray-icon sizes.
- No gradients or shadows.
- No tiny lettering inside the icon.
- No rounded-square background.
- Times New Roman for the accompanying wordmark.

Keeping the icon text-free allows the application name to change without redesigning the symbol.

## Local data

The current implementation stores these files inside the application's Electron `userData` directory:

```text
orbit-data/
├── installed-apps.json
└── recent-apps.json
```

The original `orbit-data` folder name is an internal storage identifier, not the display name.

Ollama manages its own model storage separately.

## Project structure

```text
.
├── main.js
├── preload.js
├── renderer.js
├── app-launcher.js
├── desktop-controls.js
├── app-config.json
├── index.html
├── style.css
├── setup-ai.ps1
├── voice-command.ps1
├── electron-builder.yml
├── package.json
├── package-lock.json
└── .gitignore
```

| File | Purpose |
|---|---|
| `main.js` | Window lifecycle, compact mode, and AI setup |
| `preload.js` | Restricted bridge between the interface and main process |
| `renderer.js` | Interface interactions, status messages, and recent apps |
| `app-launcher.js` | Catalog discovery, caching, interpretation, and launching |
| `desktop-controls.js` | Tray menu, global shortcuts, startup, and voice process |
| `app-config.json` | Intended shared branding configuration |
| `setup-ai.ps1` | Ollama installation and model setup |
| `voice-command.ps1` | Windows speech recognition |
| `electron-builder.yml` | Windows installer configuration |

## Build the Windows installer

Install the build dependency if it is not already present:

```powershell
npm install --save-dev electron-builder
```

Build the installer:

```powershell
npm run dist
```

The current build script targets a Windows x64 NSIS installer.

Build output is written to:

```text
release/
```

### Packaging checklist

Before building:

- Set installer branding to PLCWBot.
- Include `app-config.json` in the packaged application files.
- Include `setup-ai.ps1` and `voice-command.ps1` as extra resources.
- Confirm the packaged scripts resolve through `process.resourcesPath`.
- Keep `node_modules`, build output, installers, models, and secrets out of Git.

Ollama and its model are downloaded during setup, not bundled into the application installer.

### Release testing

Test the installed application, not only the development version:

- Open an installed application.
- Request an application that is not present.
- Test an ambiguous application name.
- Test a negative request such as `Don't open Minecraft`.
- Confirm the app catalog persists after restart.
- Confirm the recent list is limited to five unique entries.
- Test both keyboard shortcuts.
- Test microphone permission and voice recognition.
- Close the window and verify shortcuts still work.
- Test optional startup after signing back into Windows.
- Quit through the tray and confirm the process exits.

The local model can misinterpret intent even when it produces valid JSON.

## Security and privacy

- Electron context isolation and renderer sandboxing are enabled.
- The interface does not receive unrestricted Node.js access.
- Privileged IPC handlers validate their sender.
- App launching uses catalog entries rather than AI-generated executable paths.
- Maintenance entries identified by names such as “installer” or “uninstaller” require confirmation.
- Ollama installation requires user approval.
- The downloaded Ollama installer is checked for a valid signature and expected publisher.
- Voice input is activated explicitly rather than continuously listening.
- Voice transcripts are reviewed before execution.
- This implementation sends AI requests to the local Ollama endpoint.

Initial software and model downloads require network access. This project does not control the network behavior of launched applications.

Name-based maintenance detection and AI intent classification are safeguards, not guarantees that every potentially sensitive application will be identified.

## Troubleshooting

### `npm start` cannot find `package.json`

Open the terminal in the project folder containing `package.json`.

Then run:

```powershell
npm install
npm start
```

### Ollama cannot be reached

Open Ollama or use the application's setup/check action.

Confirm the configured model is available:

```powershell
ollama list
```

### Commands are slow

- Simple commands such as `Open Minecraft` can use direct matching.
- The catalog cache avoids repeated Windows scans.
- The configured `keep_alive` keeps the model loaded for 30 minutes after a request.
- The first AI request may take longer while the model loads.
- Application launch time also depends on Windows and the target app.

### An installed app cannot be found

The application may lack an entry exposed by `Get-StartApps`.

Try its Windows Start-menu name. A missing match triggers a catalog refresh, but does not guarantee discovery of portable or unregistered applications.

### Voice input fails

Check:

- The default microphone works.
- Windows allows desktop applications to access the microphone.
- A compatible English Windows speech recognizer is installed.
- Another recording session is not already active.

### A keyboard shortcut does not work

Confirm PLCWBot is still running in the tray.

If registration failed, another app or Windows may own the shortcut. Use the tray menu until the conflict is resolved.

### Windows warns about the installer

The current local build may be unsigned.

For public distribution, sign the application and installer. Do not instruct users to disable Windows security protections.

## Author

Srihaas Mynampati

## License

No license has been selected yet. Add a `LICENSE` file before distributing the project under a specific license.
