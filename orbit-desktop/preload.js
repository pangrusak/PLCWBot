const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("orbit", {

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