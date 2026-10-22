param(
    [string]$Iscc = 'ISCC.exe',
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$versionMatch = [regex]::Match([IO.File]::ReadAllText((Join-Path $repo 'pubspec.yaml')), '(?m)^version:\s*([^+\s]+)')
if (-not $versionMatch.Success) { throw 'Cannot determine NaiLu version' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repo 'dist' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$staging = Join-Path $repo 'build/installer'
New-Item -ItemType Directory -Force $staging | Out-Null
$bootstrapper = Join-Path $staging 'MicrosoftEdgeWebview2Setup.exe'
if (-not (Test-Path -LiteralPath $bootstrapper)) {
    Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' -OutFile $bootstrapper
}
$signature = Get-AuthenticodeSignature -LiteralPath $bootstrapper
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
    throw 'WebView2 bootstrapper signature verification failed'
}
& $Iscc "/DNaiLuVersion=$($versionMatch.Groups[1].Value)" "/DNaiLuWebViewBootstrapper=$bootstrapper" "/O$OutputDirectory" (Join-Path $repo 'windows/packaging/exe/nailu-installer.iss')
if ($LASTEXITCODE -ne 0) { throw "Installer build failed: $LASTEXITCODE" }
