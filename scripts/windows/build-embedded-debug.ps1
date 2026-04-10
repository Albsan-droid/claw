param(
    [string]$Task = "assembleEmbeddedDebug"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Resolve repository root from this script location.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..\..")
$androidDir = Join-Path $repoRoot "android"
$gradleWrapper = Join-Path $androidDir "gradlew.bat"

if (!(Test-Path $gradleWrapper)) {
    throw "gradlew.bat not found at $gradleWrapper"
}

Write-Host "Running Android build task: $Task"
& $gradleWrapper -p $androidDir $Task

if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE"
}

Write-Host "Build finished successfully."
Write-Host "APK output: $androidDir\app\build\outputs\apk\embedded\debug"
