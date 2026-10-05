if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue | Where-Object {$_.Version -ge '2.8.5.201'})) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Script -Name Get-AutopilotDiagnostics -Force -Scope CurrentUser
$script = Get-ChildItem -Path C:\Users -Recurse -Filter "Get-AutopilotDiagnostics.ps1" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if ($script) {
    & $script
} else {
    Write-Host "Script não encontrado após instalação." -ForegroundColor Red
}
