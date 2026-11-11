const { app, BrowserWindow, ipcMain, dialog } = require("electron");
const { spawn } = require("node:child_process");
const path = require("node:path");

let setupRunning = false;
let window;

require("./app-launcher")(() => window);

function createWindow() {
  window = new BrowserWindow({
    width: 900,
    height: 620,
    minWidth: 560,
    minHeight: 420,
    backgroundColor: "#101018",
    autoHideMenuBar: true,
    title: "Orbit",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  window.webContents.setWindowOpenHandler(() => ({
    action: "deny",
  }));

  window.webContents.on("will-navigate", (event) => {
    event.preventDefault();
  });

  window.loadFile("index.html");
}

ipcMain.handle("setup-ai", async (event) => {
  if (
    !window ||
    window.isDestroyed() ||
    event.sender !== window.webContents ||
    event.senderFrame !== window.webContents.mainFrame
  ) {
    return { ok: false, message: "Request rejected." };
  }

  if (setupRunning) {
    return { ok: false, message: "Setup is already running." };
  }

  setupRunning = true;

  const sendProgress = (message) => {
    if (window && !window.isDestroyed()) {
      window.webContents.send("setup-progress", message);
    }
  };

  try {
    const { response } = await dialog.showMessageBox(window, {
      type: "question",
      title: "Set up local AI",
      message: "Install Ollama and download Qwen 2.5 1.5B?",
      detail:
        "This downloads software from Ollama and a model of about 1 GB. " +
        "Additional disk space is required for Ollama. " +
        "Ollama can remain running in the background. " +
        "Keep Orbit open until setup finishes.",
      buttons: ["Cancel", "Install local AI"],
      defaultId: 0,
      cancelId: 0,
      noLink: true,
    });

    if (response !== 1) {
      return { ok: false, message: "Setup cancelled." };
    }

    const scriptPath = app.isPackaged
      ? path.join(process.resourcesPath, "setup-ai.ps1")
      : path.join(__dirname, "setup-ai.ps1");

    const powershell = path.join(
      process.env.SystemRoot || "C:\\Windows",
      "System32",
      "WindowsPowerShell",
      "v1.0",
      "powershell.exe"
    );

    return await new Promise((resolve) => {
      const child = spawn(
        powershell,
        [
          "-NoProfile",
          "-NonInteractive",
          "-ExecutionPolicy",
          "Bypass",
          "-File",
          scriptPath,
        ],
        {
          shell: false,
          windowsHide: true,
          stdio: ["ignore", "pipe", "pipe"],
        }
      );

      let pending = "";
      let errorText = "";

      child.stdout.setEncoding("utf8");
      child.stderr.setEncoding("utf8");

      child.stdout.on("data", (chunk) => {
        pending += chunk;

        const lines = pending.split(/\r?\n/);
        pending = lines.pop() || "";

        for (const line of lines) {
          if (line.trim()) {
            sendProgress(line.trim());
          }
        }
      });

      child.stderr.on("data", (chunk) => {
        errorText = (errorText + chunk).slice(-4000);
      });

      child.once("error", (error) => {
        resolve({
          ok: false,
          message: `Couldn't start setup: ${error.message}`,
        });
      });

      child.once("close", (code) => {
        if (pending.trim()) {
          sendProgress(pending.trim());
        }

        resolve({
          ok: code === 0,
          message:
            code === 0
              ? "Local AI is ready."
              : errorText.trim() || `Setup failed with code ${code}.`,
        });
      });
    });
  } catch (error) {
    return { ok: false, message: error.message };
  } finally {
    setupRunning = false;
  }
});

app.whenReady().then(() => {
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});