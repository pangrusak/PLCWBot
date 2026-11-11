const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("orbit", {
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