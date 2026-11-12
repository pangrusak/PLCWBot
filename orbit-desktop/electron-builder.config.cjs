const fs = require("node:fs");
const path = require("node:path");

const { version } = require("electron-builder/package.json");

const configPath = path.join(__dirname, "app-config.json");

const branding = fs.existsSync(configPath)
    ? JSON.parse(fs.readFileSync(configPath, "utf8"))
    : { appName: "PLCWBot" };

const contents = {
    files: [
        "main.js",
        "preload.js",
        "renderer.js",
        "app-launcher.js",
        "desktop-controls.js",
        "app-config.json",
        "index.html",
        "style.css",
        "package.json",
    ],

    extraResources: [
        {
            from: "setup-ai.ps1",
            to: "setup-ai.ps1",
        },
        {
            from: "voice-command.ps1",
            to: "voice-command.ps1",
        },
    ],
};

module.exports = {
    appId: "com.srihaas.plcwbot",
    productName: branding.appName,

    directories: {
        output: "release",
    },

    ...(Number(version.split(".")[0]) >= 27
        ? { fileOptions: contents }
        : contents),

    win: {
        target: [
            {
                target: "nsis",
                arch: ["x64"],
            },
        ],
    },

    nsis: {
        oneClick: false,
        perMachine: false,
        allowToChangeInstallationDirectory: true,
        createDesktopShortcut: true,
        createStartMenuShortcut: true,
        shortcutName: branding.appName,
        runAfterFinish: true,
    },
};