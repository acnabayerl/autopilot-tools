Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false | Out-Null
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Script -Name Get-AutopilotDiagnostics -Force -Scope CurrentUser
PowerShell -ExecutionPolicy Bypass -File (Get-ChildItem -Path C:\Users -Recurse -Filter "Get-AutopilotDiagnostics.ps1" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName)
