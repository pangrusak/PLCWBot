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
# Helper: strip trailing punctuation that dictation engines append
# ---------------------------------------------------------------------------
function CleanText([string]$raw) {
    # Remove trailing period, comma, question mark that SAPI appends
    $t = $raw.TrimEnd('.', ',', '?', '!').Trim()
    # Collapse internal whitespace
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
# Strategy 1 — SAPI (System.Speech)
# ---------------------------------------------------------------------------
function TrySapi {
    Add-Type -AssemblyName System.Speech

    # --- Pick a recognizer -------------------------------------------------
    $available = @([System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers())

    $selected = $null

    if ($available.Count -gt 0) {
        # Prefer exact en-US, then any English
        $selected = $available | Where-Object { $_.Culture.Name -eq 'en-US' } | Select-Object -First 1
        if (-not $selected) {
            $selected = $available | Where-Object { $_.Culture.TwoLetterISOLanguageName -eq 'en' } | Select-Object -First 1
        }
        if (-not $selected) {
            $selected = $available | Select-Object -First 1
        }
    }

    # --- Build recognizer --------------------------------------------------
    $engine = if ($selected) {
        [System.Speech.Recognition.SpeechRecognitionEngine]::new($selected)
    } else {
        # Default constructor may still work if SAPI has a default token configured
        [System.Speech.Recognition.SpeechRecognitionEngine]::new()
    }

    try {
        $engine.LoadGrammar([System.Speech.Recognition.DictationGrammar]::new())
        $engine.SetInputToDefaultAudioDevice()

        $engine.InitialSilenceTimeout       = [TimeSpan]::FromSeconds($INITIAL_SILENCE_SEC)
        $engine.BabbleTimeout               = [TimeSpan]::FromSeconds($BABBLE_SEC)
        $engine.EndSilenceTimeout           = [TimeSpan]::FromMilliseconds($END_SILENCE_MS)
        $engine.EndSilenceTimeoutAmbiguous  = [TimeSpan]::FromMilliseconds($END_SILENCE_AMB_MS)

        # Signal JS that we are ready
        Write-Output "ORBIT_LISTENING"

        for ($attempt = 0; $attempt -le $MAX_RETRIES; $attempt++) {
            $result = $engine.Recognize([TimeSpan]::FromSeconds($RECOGNIZE_WINDOW_S))

            if ($null -eq $result) {
                if ($attempt -lt $MAX_RETRIES) { continue }
                throw "No speech detected. Please try again."
            }

            if ($result.Confidence -lt $CONFIDENCE_MIN) {
                if ($attempt -lt $MAX_RETRIES) {
                    # Retry silently — keep the microphone open
                    continue
                }
                # Return the low-confidence result with a flag so JS can warn
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
# Strategy 2 — WinRT via compiled C# helper
# ---------------------------------------------------------------------------
function TryWinRT {
    $csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path $csc)) {
        $csc = Join-Path $env:windir 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
    }
    if (-not (Test-Path $csc)) { throw "csc.exe not found — cannot use WinRT fallback." }

    $winMetaDir = Join-Path $env:windir 'System32\WinMetadata'
    $fwDir      = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319'

    # Pick required winmd references
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
        # Write helper source -------------------------------------------------
        @'
using System;
using System.Threading.Tasks;
using Windows.Media.SpeechRecognition;

class Program {
    static void Main() {
        try {
            RunAsync().GetAwaiter().GetResult();
        } catch (Exception ex) {
            Console.Error.WriteLine(ex.Message);
            Environment.Exit(1);
        }
    }

    static async Task RunAsync() {
        var rec = new SpeechRecognizer();

        var constraint = new SpeechRecognitionTopicConstraint(
            SpeechRecognitionScenario.Dictation, "dictation");
        rec.Constraints.Add(constraint);

        var compileResult = await rec.CompileConstraintsAsync();
        if (compileResult.Status != SpeechRecognitionResultStatus.Success) {
            throw new Exception("WinRT compile constraints failed: " + compileResult.Status);
        }

        Console.WriteLine("ORBIT_LISTENING");
        Console.Out.Flush();

        var result = await rec.RecognizeAsync();

        if (result == null || string.IsNullOrWhiteSpace(result.Text)) {
            throw new Exception("No speech detected. Please try again.");
        }

        double conf = result.RawConfidence;
        string text = result.Text.TrimEnd('.', ',', '?', '!').Trim();

        Console.WriteLine(
            "{\"text\":\"" + text.Replace("\\","\\\\").Replace("\"","\\\"") +
            "\",\"confidence\":" + conf.ToString("0.####") + "}");
    }
}
'@ | Set-Content -Path $src -Encoding UTF8

        # Compile -------------------------------------------------------------
        $refArgs = ($refs | ForEach-Object { "/r:`"$_`"" }) -join ' '
        $compileCmd = "& `"$csc`" /nologo /target:exe /out:`"$exe`" $refArgs `"$src`""
        $compileOut = Invoke-Expression $compileCmd 2>&1
        if (-not (Test-Path $exe)) {
            throw "WinRT helper compile failed: $compileOut"
        }

        # Run helper ----------------------------------------------------------
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

# SAPI failed — emit stderr note and try WinRT
[Console]::Error.WriteLine("SAPI unavailable ($sapiError); trying WinRT fallback…")

try {
    TryWinRT
} catch {
    $winrtError = $_.Exception.Message
}

# Both failed
[Console]::Error.WriteLine("Voice recognition failed.")
[Console]::Error.WriteLine("SAPI:  $sapiError")
[Console]::Error.WriteLine("WinRT: $winrtError")
exit 1
