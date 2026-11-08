$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
dotnet test .\BossRemote.sln -c Release --nologo
dotnet publish .\src\BossRemote.Windows\BossRemote.Windows.csproj `
  -c Release `
  -r win-x64 `
  --self-contained true `
  -p:PublishSingleFile=true `
  -p:IncludeNativeLibrariesForSelfExtract=true `
  -o .\artifacts\win-x64
Write-Host "Published .\artifacts\win-x64\BossRemote.exe"
