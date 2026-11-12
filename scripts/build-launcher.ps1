param(
    [ValidatePattern('^[A-Za-z0-9_-]+\.exe$')]
    [string]$OutputName = 'RmdDetector.exe'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'
}
if (-not (Test-Path -LiteralPath $compiler)) {
    throw 'The .NET Framework C# compiler was not found.'
}

$outputDir = Join-Path $root 'dist'
$null = New-Item -Path $outputDir -ItemType Directory -Force
$output = Join-Path $outputDir $OutputName
$document = Join-Path $root 'detector.Rmd'
$launcher = Join-Path $PSScriptRoot 'launch-detector.R'
$source = Join-Path $PSScriptRoot 'windows-launcher.cs'
& $compiler /nologo /target:exe /optimize+ /codepage:65001 "/out:$output" "/resource:$document,detector.Rmd" "/resource:$launcher,launch-detector.R" $source
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output $output
