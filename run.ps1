if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue | Where-Object {$_.Version -ge '2.8.5.201'})) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Script -Name Get-AutopilotDiagnostics -Force -Scope CurrentUser
$script = Get-ChildItem -Path C:\Users -Recurse -Filter "Get-AutopilotDiagnostics.ps1" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if ($script) { & $script } else { Write-Host "Script não encontrado." -ForegroundColor Red }

Write-Host "`n--- MONITORANDO IME (Ctrl+C para parar) ---`n" -ForegroundColor Cyan
$logPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log"
Get-Content $logPath -Wait -Tail 5 | ForEach-Object {
    if ($_ -match '^\<!\[LOG\[(.+?)\]LOG\].*time="(\d+:\d+:\d+)') {
        $msg  = $matches[1].Trim()
        $time = $matches[2]
        if ($msg -match "Win32App|Identifying|Installing|Download|Success|Failed|Error|SideCarAgent|exitCode|Detection") {
            if     ($msg -match "Failed|Error")    { Write-Host "[$time] $msg" -ForegroundColor Red }
            elseif ($msg -match "Success")         { Write-Host "[$time] $msg" -ForegroundColor Green }
            elseif ($msg -match "Installing|Down") { Write-Host "[$time] $msg" -ForegroundColor Yellow }
            else                                   { Write-Host "[$time] $msg" -ForegroundColor White }
        }
    }
}
