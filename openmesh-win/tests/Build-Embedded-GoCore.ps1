param(
    [string]$OutputDir = ".\openmesh-win\bin\Debug\net10.0-windows",
    [string]$GoExe = "go",
    [string]$CC = "gcc",
    [string]$BuildTags = "with_clash_api"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path "."
$embedDir = Join-Path $repoRoot "go-cli-lib\cmd\openmesh-win-core-embedded"
$outputPath = Resolve-Path $OutputDir -ErrorAction SilentlyContinue
if (-not $outputPath) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $outputPath = Resolve-Path $OutputDir
}

Push-Location $embedDir
try {
    & $GoExe version | Out-Null
    $env:CGO_ENABLED = "1"
    if (-not [string]::IsNullOrWhiteSpace($CC)) {
        $candidateCC = $CC
        if ($CC -eq "gcc" -and -not (Get-Command gcc -ErrorAction SilentlyContinue)) {
            $fallbackGcc = "C:\msys64\ucrt64\bin\gcc.exe"
            if (Test-Path $fallbackGcc) {
                $candidateCC = $fallbackGcc
                $env:Path = "C:\msys64\ucrt64\bin;$env:Path"
            }
        }
        $env:CC = $candidateCC
    }
    Write-Host "Building embedded core DLL in $embedDir"
    Write-Host "CGO_ENABLED=$env:CGO_ENABLED, CC=$env:CC"
    if ([string]::IsNullOrWhiteSpace($BuildTags)) {
        & $GoExe build -buildmode=c-shared -o openmesh_core.dll .
    }
    else {
        Write-Host "Build tags: $BuildTags"
        & $GoExe build -tags $BuildTags -buildmode=c-shared -o openmesh_core.dll .
    }
    if ($LASTEXITCODE -ne 0) {
        throw "go build failed with exit code $LASTEXITCODE. Ensure CGO toolchain is installed (e.g., MinGW-w64 gcc)."
    }

    Copy-Item ".\openmesh_core.dll" (Join-Path $outputPath "openmesh_core.dll") -Force
    Copy-Item ".\openmesh_core.h" (Join-Path $outputPath "openmesh_core.h") -Force
    Write-Host "Embedded core built and copied to: $outputPath"
}
finally {
    Pop-Location
}
