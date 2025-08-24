param(
    [string]$Src,
    [string]$Out
)

# Absolute paths
$src = (Resolve-Path $Src).Path
# Ensure output directory exists before resolving path
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$out = (Resolve-Path $Out).Path
$bld = Join-Path $out "build"

# Prepare directories
New-Item -ItemType Directory -Force -Path $bld | Out-Null
Push-Location $bld

# Configure with CMake (MSVC)
cmake $src -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release -A x64

# Build
cmake --build . --config Release

Pop-Location

# Collect DLL + LIB outputs
$binDir = Join-Path $out "bin"
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
Get-ChildItem -Recurse $bld -Include *.dll,*.lib -File | Copy-Item -Destination $binDir
