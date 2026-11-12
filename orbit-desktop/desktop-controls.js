const {
    app,
    Tray,
    Menu,
    nativeImage,
    globalShortcut,
    dialog,
} = require("electron");

const { spawn } = require("node:child_process");
const path = require("node:path");
const fs = require("node:fs");

module.exports = function registerDesktopControls({
    getWindow,
    showQuickLauncher,
    restoreFullWindow,
    getAppConfig: customGetAppConfig,
}) {
    let tray = null;
    let quitting = false;
    let voiceProcess = null;
    let voiceStarting = false;
    let microphoneApproved = false;

    function getAppName() {
        try {
            if (typeof customGetAppConfig === "function") {
                return customGetAppConfig().appName || "PLCWBot";
            }
            delete require.cache[require.resolve("./app-config.json")];
            return require("./app-config.json").appName || "PLCWBot";
        } catch {
            return "PLCWBot";
        }
    }

    function sendVoice(data) {
        const win = getWindow();

        if (win && !win.isDestroyed()) {
            win.webContents.send("voice-update", data);
        }
    }

    function createTrayIcon() {
        const logoPath = path.join(__dirname, "logo.png");
        if (fs.existsSync(logoPath)) {
            return nativeImage.createFromPath(logoPath).resize({ width: 16, height: 16 });
        }

        const size = 32;
        const pixels = Buffer.alloc(size * size * 4);

        // Flat gold ring on a navy background. Bitmap format is BGRA.
        for (let y = 0; y < size; y++) {
            for (let x = 0; x < size; x++) {
                const offset = (y * size + x) * 4;
                const distance = Math.hypot(x - 15.5, y - 15.5);
                const ring = distance >= 8 && distance <= 11;

                pixels[offset] = ring ? 110 : 34;
                pixels[offset + 1] = ring ? 182 : 23;
                pixels[offset + 2] = ring ? 213 : 16;
                pixels[offset + 3] = 255;
            }
        }

        return nativeImage.createFromBitmap(pixels, {
            width: size,
            height: size,
            scaleFactor: 1,
        });
    }

    function showWindow() {
        restoreFullWindow();
    }

    function updateTrayMenu() {
        const startupEnabled =
            app.isPackaged &&
            app.getLoginItemSettings().openAtLogin;
        const appName = getAppName();

        tray.setContextMenu(
            Menu.buildFromTemplate([
                {
                    label: `Open ${appName}`,
                    click: showWindow,
                },
                {
                    label: "Quick launcher — Ctrl+Alt+O",
                    click: showQuickLauncher,
                },
                {
                    label: "Voice command — Ctrl+Shift+U",
                    click: startVoice,
                },
                { type: "separator" },
                {
                    label: "Start with Windows",
                    type: "checkbox",
                    checked: Boolean(startupEnabled),
                    enabled: app.isPackaged,
                    click: (item) => {
                        app.setLoginItemSettings({
                            openAtLogin: item.checked,
                            path: process.execPath,
                            args: ["--background"],
                        });

                        updateTrayMenu();
                    },
                },
                { type: "separator" },
                {
                    label: `Quit ${appName}`,
                    click: () => app.quit(),
                },
            ])
        );
    }

    // Auto-submit confidence threshold: results at or above this are run
    // immediately without requiring the user to press Enter.
    const AUTO_RUN_CONFIDENCE = 0.82;

    async function startVoice() {
        if (voiceStarting || voiceProcess) return;

        voiceStarting = true;

        try {
            showQuickLauncher();

            const appName = getAppName();

            if (!microphoneApproved) {
                const { response } = await dialog.showMessageBox(
                    getWindow(),
                    {
                        type: "question",
                        title: "Use your microphone?",
                        message: `Allow ${appName} to listen for a voice command?`,
                        detail:
                            `${appName} listens only when you activate voice input. ` +
                            "Speech is processed by the installed Windows recognizer. " +
                            "The recognized text will appear for review before you run it.",
                        buttons: ["Cancel", "Allow"],
                        defaultId: 0,
                        cancelId: 0,
                        noLink: true,
                    }
                );

                if (response !== 1) return;

                microphoneApproved = true;
            }

            const script = app.isPackaged
                ? path.join(process.resourcesPath, "voice-command.ps1")
                : path.join(__dirname, "voice-command.ps1");

            const powershell = path.join(
                process.env.SystemRoot || "C:\\Windows",
                "System32",
                "WindowsPowerShell",
                "v1.0",
                "powershell.exe"
            );

            sendVoice({
                state: "starting",
                message: "Starting microphone…",
            });

            const child = spawn(
                powershell,
                [
                    "-NoProfile",
                    "-NonInteractive",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    script,
                ],
                {
                    windowsHide: true,
                    shell: false,
                    stdio: ["ignore", "pipe", "pipe"],
                }
            );

            voiceProcess = child;

            let output = "";
            let errorOutput = "";
            let notifiedListening = false;
            let timedOut = false;

            // 35 s hard outer timeout — the PS script has its own inner limit
            const timeout = setTimeout(() => {
                timedOut = true;
                child.kill();
            }, 35000);

            child.stdout.setEncoding("utf8");
            child.stderr.setEncoding("utf8");

            child.stdout.on("data", (chunk) => {
                output = (output + chunk).slice(-16000);

                if (!notifiedListening && output.includes("ORBIT_LISTENING")) {
                    notifiedListening = true;

                    sendVoice({
                        state: "listening",
                        message: "Listening… speak your command.",
                    });
                }
            });

            child.stderr.on("data", (chunk) => {
                // Filter out the "trying WinRT fallback" notice — it's normal
                const line = chunk.toString();
                if (!line.includes("trying WinRT fallback")) {
                    errorOutput = (errorOutput + line).slice(-4000);
                }
            });

            child.once("error", (err) => {
                clearTimeout(timeout);

                sendVoice({
                    state: "error",
                    message: `Couldn't start voice input: ${err.message}`,
                });
            });

            child.once("close", (code) => {
                clearTimeout(timeout);
                voiceProcess = null;

                if (quitting) return;

                // ---- Process failed ----------------------------------------
                if (code !== 0) {
                    // Surface only the most useful error line to the user
                    const errLines = errorOutput
                        .split(/\r?\n/)
                        .map((l) => l.trim())
                        .filter(
                            (l) =>
                                l &&
                                !l.startsWith("SAPI:") &&
                                !l.startsWith("WinRT:") &&
                                !l.includes("trying WinRT")
                        );

                    const errMsg = timedOut
                        ? "Voice input timed out. Try speaking sooner after the prompt."
                        : errLines[0] || "Voice input failed.";

                    sendVoice({
                        state: "retry_available",
                        message: errMsg,
                    });

                    return;
                }

                // ---- Process succeeded — parse JSON result ------------------
                try {
                    const lines = output
                        .split(/\r?\n/)
                        .map((l) => l.trim())
                        .filter(Boolean);

                    // The last non-empty line is the JSON payload
                    const result = JSON.parse(lines[lines.length - 1]);

                    if (
                        typeof result.text !== "string" ||
                        !result.text.trim() ||
                        result.text.length > 200
                    ) {
                        throw new Error("Invalid transcript.");
                    }

                    const text = result.text.trim();
                    const conf = typeof result.confidence === "number"
                        ? result.confidence
                        : 0;
                    const pct  = Math.round(conf * 100);

                    // Low-confidence flag set by the PowerShell script
                    if (result.low_confidence) {
                        sendVoice({
                            state: "retry_available",
                            text,
                            message:
                                `Heard: "${text}" — confidence too low (${pct}%). ` +
                                "Speak clearly and try again, or type your command.",
                        });
                        return;
                    }

                    // High confidence — auto-run without requiring Enter
                    if (conf >= AUTO_RUN_CONFIDENCE) {
                        sendVoice({
                            state: "auto_run",
                            text,
                            message: `Heard: "${text}" — running…`,
                        });
                        return;
                    }

                    // Mid confidence — put text in box, let user confirm
                    const confNote = pct > 0 ? ` (${pct}% confidence)` : "";
                    sendVoice({
                        state: "result",
                        text,
                        message:
                            `Heard: "${text}"${confNote}. ` +
                            "Press Enter to run, or edit first.",
                    });
                } catch {
                    sendVoice({
                        state: "retry_available",
                        message: "Couldn't read the voice result. Try again.",
                    });
                }
            });
        } catch (error) {
            sendVoice({
                state: "error",
                message: error.message,
            });
        } finally {
            voiceStarting = false;
        }
    }

    app.on("before-quit", () => {
        quitting = true;

        if (voiceProcess) {
            voiceProcess.kill();
        }
    });

    app.on("will-quit", () => {
        globalShortcut.unregisterAll();
    });

    app.whenReady().then(() => {
        const win = getWindow();

        if (!win) {
            throw new Error(
                "Register desktop controls after the window-creation ready handler."
            );
        }

        win.on("close", (event) => {
            if (!quitting) {
                event.preventDefault();
                win.hide();
            }
        });

        const appName = getAppName();
        tray = new Tray(createTrayIcon());
        tray.setToolTip(appName);
        tray.on("double-click", showWindow);

        updateTrayMenu();

        const unavailable = [];

        if (
            !globalShortcut.register(
                "Control+Alt+O",
                showQuickLauncher
            )
        ) {
            unavailable.push("Ctrl+Alt+O");
        }

        if (
            !globalShortcut.register(
                "Control+Shift+U",
                startVoice
            )
        ) {
            unavailable.push("Ctrl+Shift+U");
        }

        if (unavailable.length) {
            dialog.showMessageBox(win, {
                type: "warning",
                title: "Shortcut unavailable",
                message: `Couldn't register: ${unavailable.join(", ")}`,
                detail:
                    "Another app or Windows may already use these shortcuts. " +
                    `You can still use ${appName}'s tray menu.`,
            });
        }

        if (process.argv.includes("--background")) {
            win.hide();
        }
    });
};