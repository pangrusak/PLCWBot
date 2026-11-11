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