const path = require("path");
let appName = "PLCWBot";
try {
  const config = require("./orbit-desktop/app-config.json");
  if (config.appName) appName = config.appName;
} catch (e) {
  console.warn("Could not load app-config.json:", e);
}

module.exports = {
  appId: `com.srihaas.${appName.toLowerCase().replace(/[^a-z0-9]/g, "")}`,
  productName: appName,
  directories: {
    output: "release",
    app: "orbit-desktop",
  },
  files: [
    "main.js",
    "preload.js",
    "renderer.js",
    "app-launcher.js",
    "desktop-controls.js",
    "index.html",
    "style.css",
    "package.json",
    "app-config.json",
    "logo.png"
  ],
  extraResources: [
    {
      from: "setup-ai.ps1",
      to: "setup-ai.ps1"
    },
    {
      from: "voice-command.ps1",
      to: "voice-command.ps1"
    }
  ],
  win: {
    target: [
      {
        target: "nsis",
        arch: ["x64"]
      }
    ],
    icon: "logo.png"
  },
  nsis: {
    oneClick: false,
    perMachine: false,
    allowToChangeInstallationDirectory: true,
    createDesktopShortcut: true,
    createStartMenuShortcut: true,
    shortcutName: appName,
    runAfterFinish: true
  }
};

