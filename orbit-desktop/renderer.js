const form = document.querySelector("#command-form");
const input = document.querySelector("#command");
const status = document.querySelector("#status");
const runButton = document.querySelector("#run");
const notepadButton = document.querySelector("#notepad");
const setupButton = document.querySelector("#setup-ai");

let busy = false;

function setBusy(value) {
    busy = value;

    runButton.disabled = value;
    notepadButton.disabled = value;
    setupButton.disabled = value;
    input.disabled = value;
}

async function runTask(task) {
    if (busy) return;

    setBusy(true);

    try {
        await task();
    } catch {
        status.textContent =
            "Something went wrong with the desktop connection.";
    } finally {
        await refreshRecentApps();
        setBusy(false);
        input.focus();
    }
}

form.addEventListener("submit", (event) => {
    event.preventDefault();

    const text = input.value.trim();

    if (!text) {
        status.textContent = "Type something first.";
        return;
    }

    runTask(async () => {
        status.textContent = "Understanding your request and checking Windows…";

        const result = await window.orbit.interpretCommand(text);
        status.textContent = result.message;
    });
});

notepadButton.addEventListener("click", () => {
    runTask(async () => {
        status.textContent = "Launching Notepad…";

        const result = await window.orbit.openApp("notepad");
        status.textContent = result.message;
    });
});

window.orbit.onSetupProgress((message) => {
    status.textContent = message;
});

setupButton.addEventListener("click", () => {
    runTask(async () => {
        status.textContent = "Preparing setup…";

        const result = await window.orbit.setupAI();
        status.textContent = result.message;

        if (result.ok) {
            setupButton.textContent = "Check / repair local AI";
        }
    });
});

input.focus();

const recentList = document.querySelector("#recent-list");
const recentEmpty = document.querySelector("#recent-empty");

async function refreshRecentApps() {
    try {
        const apps = await window.orbit.getRecentApps();

        recentList.replaceChildren();
        recentEmpty.hidden = apps.length > 0;

        apps.forEach((app, index) => {
            const item = document.createElement("li");
            const number = document.createElement("span");
            const name = document.createElement("span");
            const button = document.createElement("button");

            number.className = "recent-number";
            number.textContent = String(index + 1).padStart(2, "0");

            name.className = "recent-name";
            name.textContent = app.Name;

            button.type = "button";
            button.textContent = "Open again";
            button.setAttribute("aria-label", `Open ${app.Name} again`);

            button.addEventListener("click", () => {
                runTask(async () => {
                    status.textContent = `Looking for ${app.Name}…`;

                    // Uses the existing catalog checks and launch protections.
                    const result = await window.orbit.interpretCommand(
                        `Open ${app.Name}`
                    );

                    status.textContent = result.message;
                });
            });

            item.append(number, name, button);
            recentList.append(item);
        });
    } catch (error) {
        console.warn("Couldn't load recent apps:", error);
    }
}

refreshRecentApps();

let quickLauncherVisible = false;

window.orbit.onQuickMode((enabled) => {
    quickLauncherVisible = enabled;
    document.body.classList.toggle("quick-mode", enabled);

    if (enabled) {
        requestAnimationFrame(() => {
            if (!input.disabled) {
                input.focus();
                input.select();
            }
        });
    }
});

document.querySelector("#quick-expand").addEventListener("click", () => {
    window.orbit.quickLauncherAction("expand");
});

document.querySelector("#quick-hide").addEventListener("click", () => {
    window.orbit.quickLauncherAction("hide");
});

document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && quickLauncherVisible) {
        event.preventDefault();
        window.orbit.quickLauncherAction("hide");
    }
});