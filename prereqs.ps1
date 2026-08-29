# Check (default) or install (-Install) Windows prerequisites for my-pi-setup.
# Run from PowerShell. After Git + Node are installed, open Git Bash and run ./install.sh
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Install,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$MinNode = [version]"22.19.0"
$PiPkg = "@earendil-works/pi-coding-agent"

function Write-Ok($msg) { Write-Host "  [ok]  $msg" }
function Write-Bad($msg) { Write-Host "  [!!]  $msg" }
function Write-Note($msg) { Write-Host "        $msg" }

function Test-Cmd($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Get-NodeVersion {
    if (-not (Test-Cmd "node")) { return $null }
    try {
        $raw = (node -v 2>$null)
        if (-not $raw) { return $null }
        return [version]($raw.TrimStart("v").Split("-")[0])
    } catch {
        return $null
    }
}

function Confirm-Step($prompt) {
    if ($Yes) { return $true }
    $reply = Read-Host "$prompt [y/N]"
    return $reply -match '^[yY](es)?$'
}

function Install-Winget($id, $override) {
    if (-not (Test-Cmd "winget")) {
        throw "winget not found. Install 'App Installer' from the Microsoft Store."
    }
    Write-Note "winget install $id"
    $args = @(
        "install", "--id", $id, "-e", "--source", "winget",
        "--accept-package-agreements", "--accept-source-agreements"
    )
    if ($override) { $args += @("--override", $override) }
    & winget @args
    if ($LASTEXITCODE -ne 0) {
        Write-Note "winget returned $LASTEXITCODE for $id (ok if already installed)"
    }
}

$doInstall = [bool]$Install
$missing = New-Object System.Collections.Generic.List[string]

Write-Host "OS: windows"
Write-Host ("Mode: " + $(if ($doInstall) { "install" } else { "check" }))
Write-Host ""
Write-Host "Checking prerequisites (Node >= $MinNode)..."

if (Test-Cmd "git") {
    Write-Ok "git $((git --version) -replace 'git version ','')"
} else {
    Write-Bad "git — not found (Git for Windows)"
    $missing.Add("git") | Out-Null
}

$py = $null
if (Test-Cmd "python") { $py = "python" }
elseif (Test-Cmd "python3") { $py = "python3" }
if ($py) {
    Write-Ok "$py $(& $py --version 2>&1)"
} else {
    Write-Bad "python — not found"
    $missing.Add("python") | Out-Null
}

$vsok = $false
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($vsPath) { $vsok = $true }
}
if (Test-Cmd "cl") { $vsok = $true }
if ($vsok) {
    Write-Ok "Visual Studio C++ tools"
} else {
    Write-Bad "C toolchain — Visual Studio Build Tools (Desktop development with C++)"
    $missing.Add("vs-build-tools") | Out-Null
}

$nodeVer = Get-NodeVersion
if ($null -eq $nodeVer) {
    Write-Bad "Node.js — not found (need >= $MinNode)"
    $missing.Add("node") | Out-Null
} elseif ($nodeVer -lt $MinNode) {
    Write-Bad "Node.js $nodeVer — too old (need >= $MinNode)"
    $missing.Add("node") | Out-Null
} else {
    Write-Ok "Node.js $nodeVer"
}

if (Test-Cmd "npm") {
    Write-Ok "npm $(npm -v)"
} else {
    Write-Bad "npm — not found"
    $missing.Add("npm") | Out-Null
}

if (Test-Cmd "pi") {
    Write-Ok "pi"
} else {
    Write-Bad "pi — not found"
    $missing.Add("pi") | Out-Null
}

if ($missing.Count -eq 0) {
    Write-Host ""
    Write-Host "All prerequisites are present. Next: open Git Bash and run ./install.sh"
    exit 0
}

Write-Host ""
Write-Host ("Missing: " + ($missing -join ", "))

if (-not $doInstall) {
    Write-Host ""
    Write-Host "Install them with:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File .\prereqs.ps1 -Install"
    exit 1
}

Write-Host ""
Write-Host "Installing missing prerequisites..."

foreach ($item in $missing) {
    switch ($item) {
        "git" { Install-Winget "Git.Git" $null }
        "python" { Install-Winget "Python.Python.3.12" $null }
        "node" { Install-Winget "OpenJS.NodeJS.LTS" $null }
        "npm" { if (-not $missing.Contains("node")) { Install-Winget "OpenJS.NodeJS.LTS" $null } }
        "vs-build-tools" {
            if (Confirm-Step "Install Visual Studio Build Tools with C++ workload? (large download)") {
                Install-Winget "Microsoft.VisualStudio.2022.BuildTools" "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
            }
        }
        "pi" { }
    }
}

$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

if (-not (Test-Cmd "pi")) {
    if (-not (Test-Cmd "npm")) {
        Write-Host "npm still not on PATH. Open a new PowerShell after Node install, then re-run with -Install."
        exit 1
    }
    Write-Note "npm install -g --ignore-scripts $PiPkg"
    npm install -g --ignore-scripts $PiPkg
}

Write-Host ""
Write-Host "Re-run this script (no -Install) after opening a new terminal so PATH refreshes."
Write-Host "Then open Git Bash in this repo and run ./install.sh"
exit 0
