if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue | Where-Object {$_.Version -ge '2.8.5.201'})) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Script -Name Get-AutopilotDiagnostics -Force -Scope CurrentUser
$script = Get-ChildItem -Path C:\Users -Recurse -Filter "Get-AutopilotDiagnostics.ps1" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if ($script) { & $script } else { Write-Host "Script não encontrado." -ForegroundColor Red }

Write-Host "`n--- MONITORANDO IME (Ctrl+C para parar) ---`n" -ForegroundColor Cyan
$logPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log"
$keywords = "Win32App|Identifying|Installing|Download|Success|Failed|Error|SideCarAgent|exitCode|Detection|enforcement"

Get-Content $logPath -Wait -Tail 5 | ForEach-Object {
    $line = $_
    # extrai mensagem entre ![LOG[ e ]LOG]
    if ($line -match '\!\[LOG\[(.+?)\]LOG\]') { $msg = $matches[1].Trim() } else { return }
    # extrai horário
    $time = if ($line -match 'time="(\d+:\d+:\d+)') { $matches[1] } else { "??:??:??" }
    # filtra por keywords
    if ($msg -notmatch $keywords) { return }

    if     ($msg -match "Failed|Error")              { Write-Host "[$time] $msg" -ForegroundColor Red }
    elseif ($msg -match "Success|completed")         { Write-Host "[$time] $msg" -ForegroundColor Green }
    elseif ($msg -match "Installing|Download|InProg"){ Write-Host "[$time] $msg" -ForegroundColor Yellow }
    else                                             { Write-Host "[$time] $msg" -ForegroundColor Cyan }
}
