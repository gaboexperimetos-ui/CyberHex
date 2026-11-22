#Requires -Version 5.1
<#
.SYNOPSIS
    Compila el núcleo de CyberHex con Zig y empaqueta el bundle de Flutter para
    Windows.

.DESCRIPTION
    Deja `cyberhex_core.dll` junto a `cyberhex.exe` dentro de
    `build\windows\x64\runner\Release`, que es donde el cargador de Windows
    busca las dependencias del ejecutable (Dart abre el archivo por nombre:
    ver `lib/core/native_player.dart`).

    `core/build.zig` compila la biblioteca **dinámica** igual que en Linux:
    aquí solo cambia el nombre (`.dll` en vez de `.so`) y el sitio donde hay
    que copiarla.

    Si el repo no tiene `windows\` (runner de Flutter), el script se detiene y
    dice qué ejecutar: ese andamiaje lo genera el SDK, no se escribe a mano.

.PARAMETER Decoder
    Decodificador que enlaza el núcleo: auto (por defecto), ffmpeg o miniaudio.

.PARAMETER SkipFlutter
    Solo compila el núcleo; no llama a `flutter build windows`.

.EXAMPLE
    .\packaging\windows\build_windows.ps1

.EXAMPLE
    .\packaging\windows\build_windows.ps1 -Decoder miniaudio -SkipFlutter
#>
[CmdletBinding()]
param(
    [ValidateSet('auto', 'ffmpeg', 'miniaudio')]
    [string]$Decoder = 'auto',

    [switch]$SkipFlutter
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Fail([string]$Message) {
    Write-Host "error: $Message" -ForegroundColor Red
    exit 1
}

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $repo
try {
    foreach ($tool in @('zig', 'flutter')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            Fail "falta '$tool' en el PATH (Zig 0.17.x y Flutter 3.x)"
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $repo 'windows'))) {
        Fail "no existe windows\: generalo antes con 'flutter create --platforms=windows .' y vuelve a lanzar esto"
    }

    Write-Host "==> nucleo: zig build -Doptimize=ReleaseFast -Ddecoder=$Decoder"
    Push-Location (Join-Path $repo 'core')
    try {
        & zig build -Doptimize=ReleaseFast "-Ddecoder=$Decoder"
        if ($LASTEXITCODE -ne 0) { throw "zig build terminó con $LASTEXITCODE" }
    }
    finally {
        Pop-Location
    }

    $candidates = @(
        (Join-Path $repo 'core\zig-out\bin\cyberhex_core.dll'),
        (Join-Path $repo 'core\zig-out\lib\cyberhex_core.dll')
    )
    $dll = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $dll) {
        Fail 'no encuentro cyberhex_core.dll tras el build (¿core\zig-out?)'
    }

    if (-not $SkipFlutter) {
        Write-Host '==> app: flutter build windows --release'
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { Fail "flutter build windows terminó con $LASTEXITCODE" }
    }

    $bundle = Join-Path $repo 'build\windows\x64\runner\Release'
    if (-not (Test-Path -LiteralPath $bundle)) {
        Fail "no encuentro $bundle (¿lanzaste flutter build windows?)"
    }

    $target = Join-Path $bundle 'cyberhex_core.dll'
    Copy-Item -LiteralPath $dll -Destination $target -Force

    $exe = Join-Path $bundle 'cyberhex.exe'
    Write-Host ''
    Write-Host "listo: $bundle"
    if (Test-Path -LiteralPath $exe) {
        $size = [math]::Round((Get-Item -LiteralPath $exe).Length / 1MB, 1)
        Write-Host "  ejecutable: $exe ($size MB)"
    }
    else {
        Write-Host "  aviso: no encuentro cyberhex.exe en $bundle"
    }
    Write-Host "  nucleo:     $target"
}
finally {
    Pop-Location
}
