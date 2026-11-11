$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$baseUrl = "http://127.0.0.1:11434"
$model = "qwen2.5:1.5b"
$tempDir = $null

function Test-Ollama {
    try {
        $null = Invoke-RestMethod `
            -Uri "$baseUrl/api/version" `
            -TimeoutSec 2
        return $true
    } catch {
        return $false
    }
}

function Find-Ollama {
    $command = Get-Command ollama.exe -ErrorAction SilentlyContinue

    if ($command) {
        return $command.Source
    }

    $defaultPath = Join-Path `
        $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"

    if (Test-Path -LiteralPath $defaultPath) {
        return $defaultPath
    }

    return $null
}

try {
    Write-Output "Checking Ollama..."

    if (-not (Test-Ollama)) {
        $ollamaExe = Find-Ollama

        if (-not $ollamaExe) {
            $tempDir = Join-Path `
                ([IO.Path]::GetTempPath()) `
                ("Orbit-" + [guid]::NewGuid().ToString())

            $null = New-Item -ItemType Directory -Path $tempDir
            $installer = Join-Path $tempDir "OllamaSetup.exe"

            Write-Output "Downloading Ollama. This may take a while..."

            Invoke-WebRequest `
                -Uri "https://ollama.com/download/OllamaSetup.exe" `
                -OutFile $installer `
                -UseBasicParsing `
                -TimeoutSec 1800

            Write-Output "Verifying Ollama's digital signature..."

            $signature = Get-AuthenticodeSignature -FilePath $installer

            if ($signature.Status -ne "Valid") {
                throw "Installer signature is not valid. Installation blocked."
            }

            $subject = $signature.SignerCertificate.Subject

            if ($subject -notmatch '(^|, )O=Ollama Inc\.(,|$)') {
                throw "Unexpected installer publisher. Installation blocked."
            }

            Write-Output "Installing Ollama..."

            $process = Start-Process `
                -FilePath $installer `
                -ArgumentList "/VERYSILENT /NORESTART /SUPPRESSMSGBOXES" `
                -PassThru

            $process.WaitForExit()

            if ($process.ExitCode -ne 0) {
                throw "Ollama installer failed: exit code $($process.ExitCode)."
            }

            $ollamaExe = Find-Ollama

            if (-not $ollamaExe) {
                throw "Ollama was installed, but its executable wasn't found."
            }
        }

        # The installer may already have started Ollama.
        if (-not (Test-Ollama)) {
            Write-Output "Starting Ollama..."

            $null = Start-Process `
                -FilePath $ollamaExe `
                -ArgumentList "serve" `
                -WindowStyle Hidden `
                -PassThru
        }

        $ready = $false

        for ($i = 0; $i -lt 60; $i++) {
            if (Test-Ollama) {
                $ready = $true
                break
            }

            Start-Sleep -Seconds 1
        }

        if (-not $ready) {
            throw "Ollama didn't start. Try opening Ollama, then retry setup."
        }
    }

    Write-Output "Downloading/checking Qwen 2.5 1.5B. Please wait..."

    $pullBody = @{
        model = $model
        stream = $false
    } | ConvertTo-Json

    $pull = Invoke-RestMethod `
        -Uri "$baseUrl/api/pull" `
        -Method Post `
        -ContentType "application/json" `
        -Body $pullBody `
        -TimeoutSec 7200

    if ($pull.status -ne "success") {
        throw "The model download did not report success."
    }

    Write-Output "Testing the model. First startup can take a minute..."

    $testBody = @{
        model = $model
        prompt = "Reply with OK."
        stream = $false
        options = @{
            num_predict = 8
            num_ctx = 2048
        }
    } | ConvertTo-Json -Depth 5

    $test = Invoke-RestMethod `
        -Uri "$baseUrl/api/generate" `
        -Method Post `
        -ContentType "application/json" `
        -Body $testBody `
        -TimeoutSec 600

    if (-not $test.done -or
        [string]::IsNullOrWhiteSpace($test.response)) {
        throw "The model didn't return a completed response."
    }

    Write-Output "Local AI is installed and responding."
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    if ($tempDir -and (Test-Path -LiteralPath $tempDir)) {
        Remove-Item -LiteralPath $tempDir `
            -Recurse -Force -ErrorAction SilentlyContinue
    }
}