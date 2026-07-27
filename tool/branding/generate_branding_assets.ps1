param(
    [string]$ChromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe",
    [string]$DartExecutable = "dart"
)

$ErrorActionPreference = "Stop"
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$brandingDirectory = Join-Path $projectRoot "assets\branding"

if (-not (Test-Path -LiteralPath $ChromePath)) {
    throw "Chrome was not found at $ChromePath. Pass -ChromePath explicitly."
}

$renders = @(
    @{ Source = "pilgrim_tracker_icon.svg"; Output = "pilgrim_tracker_icon_1024.png" },
    @{ Source = "pilgrim_tracker_icon_foreground.svg"; Output = "pilgrim_tracker_icon_foreground_1024.png" },
    @{ Source = "pilgrim_tracker_icon_monochrome.svg"; Output = "pilgrim_tracker_icon_monochrome_1024.png" }
)

foreach ($render in $renders) {
    $source = Join-Path $brandingDirectory $render.Source
    $output = Join-Path $brandingDirectory $render.Output
    $sourceUri = ([System.Uri]$source).AbsoluteUri

    if (Test-Path -LiteralPath $output) {
        Remove-Item -LiteralPath $output -Force
    }

    & $ChromePath `
        --headless=new `
        --disable-gpu `
        --hide-scrollbars `
        --force-device-scale-factor=1 `
        --window-size=1024,1024 `
        --default-background-color=00000000 `
        "--screenshot=$output" `
        $sourceUri

    for ($attempt = 0; $attempt -lt 50 -and -not (Test-Path -LiteralPath $output); $attempt++) {
        Start-Sleep -Milliseconds 100
    }

    if (-not (Test-Path -LiteralPath $output)) {
        throw "Failed to render $($render.Source)."
    }
}

Push-Location $projectRoot
try {
    & $DartExecutable run flutter_launcher_icons
    if ($LASTEXITCODE -ne 0) {
        throw "flutter_launcher_icons failed."
    }
} finally {
    Pop-Location
}
