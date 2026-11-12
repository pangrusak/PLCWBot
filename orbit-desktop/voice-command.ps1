$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$recognizer = $null

try {
    Add-Type -AssemblyName System.Speech

    $available = @(
        [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers()
    )

    if ($available.Count -eq 0) {
        throw "No compatible Windows speech recognizer is installed."
    }

    $selected = $available |
        Where-Object { $_.Culture.Name -eq "en-US" } |
        Select-Object -First 1

    if (-not $selected) {
        $selected = $available |
            Where-Object { $_.Culture.TwoLetterISOLanguageName -eq "en" } |
            Select-Object -First 1
    }

    if (-not $selected) {
        throw "An English Windows speech recognizer is required."
    }

    $recognizer = [System.Speech.Recognition.SpeechRecognitionEngine]::new(
        $selected
    )

    $recognizer.LoadGrammar(
        [System.Speech.Recognition.DictationGrammar]::new()
    )

    $recognizer.SetInputToDefaultAudioDevice()

    $recognizer.InitialSilenceTimeout = [TimeSpan]::FromSeconds(7)
    $recognizer.BabbleTimeout = [TimeSpan]::FromSeconds(5)
    $recognizer.EndSilenceTimeout = [TimeSpan]::FromMilliseconds(700)
    $recognizer.EndSilenceTimeoutAmbiguous = [TimeSpan]::FromSeconds(1)

    Write-Output "ORBIT_LISTENING"

    $result = $recognizer.Recognize(
        [TimeSpan]::FromSeconds(7)
    )

    if ($null -eq $result) {
        throw "No speech recognized. Try again."
    }

    @{
        text = $result.Text
        confidence = $result.Confidence
    } | ConvertTo-Json -Compress

    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    if ($null -ne $recognizer) {
        $recognizer.Dispose()
    }
}