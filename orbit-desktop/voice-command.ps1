#Requires -Version 5.1
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
$CONFIDENCE_MIN      = 0.35   # results below this are treated as "no match"
$INITIAL_SILENCE_SEC = 10     # wait this long for the user to start speaking
$BABBLE_SEC          = 6      # give up if only noise is heard
$END_SILENCE_MS      = 1200   # stop after this much end-of-speech silence
$END_SILENCE_AMB_MS  = 1600   # allow a bit longer when ambiguous
$RECOGNIZE_WINDOW_S  = 18     # hard outer timeout passed to Recognize()
$MAX_RETRIES         = 1      # number of automatic retries on null/low result

# ---------------------------------------------------------------------------
# Known app names – pre-loading these gives the recognizer much higher
# accuracy for common apps (like "Minecraft") instead of treating speech
# as a free-form sentence.
# ---------------------------------------------------------------------------
$KNOWN_APPS = @(
    # Games
    "minecraft", "minecraft launcher",
    "steam", "epic games", "epic games launcher",
    "roblox", "fortnite", "valorant", "league of legends",
    "genshin impact", "apex legends", "overwatch",
    # Browsers
    "chrome", "google chrome", "firefox", "edge", "microsoft edge",
    "brave", "opera",
    # Microsoft Office & productivity
    "word", "microsoft word",
    "excel", "microsoft excel",
    "powerpoint", "microsoft powerpoint",
    "outlook", "microsoft outlook",
    "onenote", "microsoft onenote",
    "teams", "microsoft teams",
    "access", "publisher",
    # Windows built-ins
    "notepad", "wordpad", "paint",
    "calculator", "calendar", "clock",
    "settings", "windows settings",
    "task manager",
    "file explorer", "explorer",
    "control panel",
    "command prompt", "powershell", "terminal", "windows terminal",
    "snipping tool", "screen clipping",
    "photos", "camera", "voice recorder",
    "maps", "weather", "news",
    "xbox", "xbox console companion",
    "store", "microsoft store",
    # Communication & social
    "discord", "slack", "skype", "zoom", "whatsapp", "telegram",
    # Media
    "spotify", "vlc", "media player", "windows media player",
    "netflix", "youtube",
    # Dev tools
    "visual studio", "visual studio code", "vs code",
    "android studio", "intellij", "pycharm", "webstorm",
    "github desktop", "git", "postman",
    "notepad plus plus",
    # Utilities
    "7zip", "winrar", "winzip",
    "obs", "obs studio",
    "anydesk", "teamviewer",
    "task scheduler",
    "device manager",
    "disk management",
    "event viewer"
)

# Command verbs the user is expected to say
$COMMAND_VERBS = @(
    "open", "launch", "start", "run", "load",
    "close", "quit", "exit", "kill",
    "switch to", "go to",
    "search for", "find", "search"
)

# ---------------------------------------------------------------------------
# Helper: strip trailing punctuation that dictation engines append
# ---------------------------------------------------------------------------
function CleanText([string]$raw) {
    $t = $raw.TrimEnd('.', ',', '?', '!').Trim()
    $t = ($t -replace '\s+', ' ')
    return $t
}

# ---------------------------------------------------------------------------
# Helper: emit a JSON result and exit 0
# ---------------------------------------------------------------------------
function EmitResult([string]$text, [double]$confidence) {
    $cleaned = CleanText $text
    @{
        text       = $cleaned
        confidence = [Math]::Round($confidence, 4)
    } | ConvertTo-Json -Compress
    exit 0
}

# ---------------------------------------------------------------------------
# Strategy 1 — SAPI with structured command grammar
#
# Using DictationGrammar for short imperative commands is a known bad idea:
# the language model picks phonetically similar *sentence* words instead of
# proper nouns like "Minecraft". A GrammarBuilder with Choices constrains
# the recognizer to the actual command shape, dramatically improving accuracy.
# ---------------------------------------------------------------------------
function TrySapi {
    Add-Type -AssemblyName System.Speech

    # --- Pick a recognizer -------------------------------------------------
    $available = @([System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers())

    $selected = $null
    if ($available.Count -gt 0) {
        $selected = $available | Where-Object { $_.Culture.Name -eq 'en-US' } | Select-Object -First 1
        if (-not $selected) {
            $selected = $available | Where-Object { $_.Culture.TwoLetterISOLanguageName -eq 'en' } | Select-Object -First 1
        }
        if (-not $selected) {
            $selected = $available | Select-Object -First 1
        }
    }

    $engine = if ($selected) {
        [System.Speech.Recognition.SpeechRecognitionEngine]::new($selected)
    } else {
        [System.Speech.Recognition.SpeechRecognitionEngine]::new()
    }

    try {
        # --- Grammar 1: verb + KNOWN app name (highest accuracy) -----------
        # When the user says "open minecraft" this grammar matches perfectly
        # because the recognizer knows exactly what words are valid after the verb.
        $verbChoices    = [System.Speech.Recognition.Choices]::new($COMMAND_VERBS)
        $appChoices     = [System.Speech.Recognition.Choices]::new($KNOWN_APPS)
        $builder1       = [System.Speech.Recognition.GrammarBuilder]::new()
        $builder1.Append($verbChoices)
        $builder1.Append($appChoices)
        $grammar1       = [System.Speech.Recognition.Grammar]::new($builder1)
        $grammar1.Name  = "KnownApps"
        $grammar1.Priority = 127   # highest possible

        # --- Grammar 2: verb + unconstrained dictation (unknown app names) -
        # AppendDictation() tells the engine "expect a verb then anything"
        # which is far better than pure DictationGrammar for commands.
        $builder2       = [System.Speech.Recognition.GrammarBuilder]::new()
        $builder2.Append($verbChoices)
        $builder2.AppendDictation()
        $grammar2       = [System.Speech.Recognition.Grammar]::new($builder2)
        $grammar2.Name  = "VerbPlusDictation"
        $grammar2.Priority = 64

        $engine.LoadGrammar($grammar1)
        $engine.LoadGrammar($grammar2)

        $engine.SetInputToDefaultAudioDevice()

        $engine.InitialSilenceTimeout       = [TimeSpan]::FromSeconds($INITIAL_SILENCE_SEC)
        $engine.BabbleTimeout               = [TimeSpan]::FromSeconds($BABBLE_SEC)
        $engine.EndSilenceTimeout           = [TimeSpan]::FromMilliseconds($END_SILENCE_MS)
        $engine.EndSilenceTimeoutAmbiguous  = [TimeSpan]::FromMilliseconds($END_SILENCE_AMB_MS)

        Write-Output "ORBIT_LISTENING"

        for ($attempt = 0; $attempt -le $MAX_RETRIES; $attempt++) {
            $result = $engine.Recognize([TimeSpan]::FromSeconds($RECOGNIZE_WINDOW_S))

            if ($null -eq $result) {
                if ($attempt -lt $MAX_RETRIES) { continue }
                throw "No speech detected. Please try again."
            }

            if ($result.Confidence -lt $CONFIDENCE_MIN) {
                if ($attempt -lt $MAX_RETRIES) { continue }

                @{
                    text           = (CleanText $result.Text)
                    confidence     = [Math]::Round($result.Confidence, 4)
                    low_confidence = $true
                } | ConvertTo-Json -Compress
                exit 0
            }

            EmitResult $result.Text $result.Confidence
        }

        throw "Speech was not recognised clearly. Try speaking closer to the microphone."
    } finally {
        $engine.Dispose()
    }
}

# ---------------------------------------------------------------------------
# Strategy 2 — WinRT via compiled C# helper (WebSearch scenario)
#
# SpeechRecognitionScenario.WebSearch is tuned for short query-like phrases
# (exactly the shape of "open minecraft"), far better than Dictation here.
# ---------------------------------------------------------------------------
function TryWinRT {
    $csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path $csc)) {
        $csc = Join-Path $env:windir 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
    }
    if (-not (Test-Path $csc)) { throw "csc.exe not found — cannot use WinRT fallback." }

    $winMetaDir = Join-Path $env:windir 'System32\WinMetadata'
    $fwDir      = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319'

    $refs = @(
        (Join-Path $winMetaDir 'Windows.Foundation.winmd'),
        (Join-Path $winMetaDir 'Windows.Media.winmd'),
        (Join-Path $fwDir      'System.Runtime.WindowsRuntime.dll'),
        (Join-Path $fwDir      'System.Runtime.dll')
    ) | Where-Object { Test-Path $_ }

    if ($refs.Count -lt 2) { throw "Required WinRT metadata not found." }

    $src = Join-Path $env:TEMP "plcw_voice_$PID.cs"
    $exe = Join-Path $env:TEMP "plcw_voice_$PID.exe"

    try {
        @'
using System;
using System.Threading.Tasks;
using Windows.Media.SpeechRecognition;

class Program {
    static void Main() {
        try { RunAsync().GetAwaiter().GetResult(); }
        catch (Exception ex) { Console.Error.WriteLine(ex.Message); Environment.Exit(1); }
    }

    static async Task RunAsync() {
        var rec = new SpeechRecognizer();

        // WebSearch scenario is tuned for short query-like utterances
        // (e.g. "open minecraft") — much more accurate than Dictation for commands.
        var constraint = new SpeechRecognitionTopicConstraint(
            SpeechRecognitionScenario.WebSearch, "websearch");
        rec.Constraints.Add(constraint);

        var compileResult = await rec.CompileConstraintsAsync();
        if (compileResult.Status != SpeechRecognitionResultStatus.Success)
            throw new Exception("WinRT compile constraints failed: " + compileResult.Status);

        Console.WriteLine("ORBIT_LISTENING");
        Console.Out.Flush();

        var result = await rec.RecognizeAsync();

        if (result == null || string.IsNullOrWhiteSpace(result.Text))
            throw new Exception("No speech detected. Please try again.");

        double conf = result.RawConfidence;
        string text = result.Text.TrimEnd('.', ',', '?', '!').Trim();

        Console.WriteLine(
            "{\"text\":\"" + text.Replace("\\","\\\\").Replace("\"","\\\"") +
            "\",\"confidence\":" + conf.ToString("0.####") + "}");
    }
}
'@ | Set-Content -Path $src -Encoding UTF8

        $refArgs    = ($refs | ForEach-Object { "/r:`"$_`"" }) -join ' '
        $compileCmd = "& `"$csc`" /nologo /target:exe /out:`"$exe`" $refArgs `"$src`""
        $compileOut = Invoke-Expression $compileCmd 2>&1
        if (-not (Test-Path $exe)) {
            throw "WinRT helper compile failed: $compileOut"
        }

        & $exe
        $exitCode = $LASTEXITCODE
        exit $exitCode
    } finally {
        Remove-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Main — try SAPI first, fall through to WinRT
# ---------------------------------------------------------------------------
$sapiError  = $null
$winrtError = $null

try {
    TrySapi
} catch {
    $sapiError = $_.Exception.Message
}

[Console]::Error.WriteLine("SAPI unavailable ($sapiError); trying WinRT fallback…")

try {
    TryWinRT
} catch {
    $winrtError = $_.Exception.Message
}

[Console]::Error.WriteLine("Voice recognition failed.")
[Console]::Error.WriteLine("SAPI:  $sapiError")
[Console]::Error.WriteLine("WinRT: $winrtError")
exit 1
