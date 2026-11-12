const { contextBridge, ipcRenderer } = require("electron");

let appConfig = { appName: "PLCWBot" };
try {
    appConfig = ipcRenderer.sendSync("get-app-config-sync") || appConfig;
} catch (e) {
    console.warn("Could not sync app config:", e);
}

contextBridge.exposeInMainWorld("orbit", {
    appName: appConfig.appName || "PLCWBot",
    appConfig,
    getAppConfig: () => ipcRenderer.invoke("get-app-config"),

    onVoiceUpdate: (callback) => {
        const listener = (_event, data) => callback(data);

        ipcRenderer.on("voice-update", listener);

        return () => {
            ipcRenderer.removeListener("voice-update", listener);
        };
    },

    quickLauncherAction: (action) => {
        if (action === "hide" || action === "expand") {
            ipcRenderer.send("quick-launcher-action", action);
        }
    },

    onQuickMode: (callback) => {
        const listener = (_event, enabled) => callback(enabled);

        ipcRenderer.on("quick-mode", listener);

        return () => {
            ipcRenderer.removeListener("quick-mode", listener);
        };
    },

    openApp: (appId) => ipcRenderer.invoke("open-app", appId),

    interpretCommand: (text) =>
        ipcRenderer.invoke("interpret-command", text),

    getRecentApps: () => ipcRenderer.invoke("get-recent-apps"),

    setupAI: () => ipcRenderer.invoke("setup-ai"),

    onSetupProgress: (callback) => {
        const listener = (_event, message) => callback(message);

        ipcRenderer.on("setup-progress", listener);

        return () => {
            ipcRenderer.removeListener("setup-progress", listener);
        };
    },
});