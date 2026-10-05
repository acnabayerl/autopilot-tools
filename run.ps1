if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue | Where-Object {$_.Version -ge '2.8.5.201'})) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Script -Name Get-AutopilotDiagnostics -Force -Scope CurrentUser
$script = Get-ChildItem -Path C:\Users -Recurse -Filter "Get-AutopilotDiagnostics.ps1" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if ($script) { & $script } else { Write-Host "Script não encontrado." -ForegroundColor Red }

$logPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log"
$htmlPath = "C:\Windows\Temp\ime_monitor.html"
$keywords = "Win32App|Identifying|Installing|Download|Success|Failed|Error|SideCarAgent|exitCode|Detection|enforcement|Completed|Pending|Tracked"

function Get-Badge($msg) {
    if ($msg -match "Failed|Error")                  { return "error" }
    elseif ($msg -match "Success|Completed|Installed"){ return "success" }
    elseif ($msg -match "Downloading|Download")       { return "download" }
    elseif ($msg -match "Installing|InProgress")      { return "installing" }
    elseif ($msg -match "Identifying|Pending")        { return "pending" }
    else                                              { return "info" }
}

function Update-HTML {
    $lines = Get-Content $logPath -Tail 300 | ForEach-Object {
        if ($_ -match '\!\[LOG\[(.+?)\]LOG\].*time="(\d+:\d+:\d+)') {
            $msg = $matches[1].Trim(); $time = $matches[2]
            if ($msg -match $keywords) {
                $badge = Get-Badge $msg
                $appName = if ($msg -match "Win32App_([a-f0-9\-]+)") { $matches[1].Substring(0,8) } else { "" }
                $appTag = if ($appName) { "<span class='app'>APP:$appName</span>" } else { "" }
                "<div class='row $badge'><span class='time'>$time</span><span class='badge $badge'>$badge</span>$appTag<span class='msg'>$msg</span></div>"
            }
        }
    }

    $html = @"
<!DOCTYPE html><html><head><meta http-equiv='refresh' content='5'>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: #0f0f0f; font-family: 'Segoe UI', Consolas, monospace; font-size: 13px; color: #ccc; }
header { background: #1a1a2e; padding: 16px 20px; border-bottom: 2px solid #333; display: flex; align-items: center; gap: 16px; }
header h1 { color: #fff; font-size: 18px; }
header .clock { color: #888; font-size: 13px; margin-left: auto; }
.stats { display: flex; gap: 12px; padding: 12px 20px; background: #111; border-bottom: 1px solid #222; }
.stat { background: #1e1e1e; border-radius: 8px; padding: 8px 16px; text-align: center; min-width: 80px; }
.stat .n { font-size: 22px; font-weight: bold; }
.stat .l { font-size: 11px; color: #888; margin-top: 2px; }
.success .n { color: #4ade80; } .error .n { color: #f87171; } .installing .n { color: #facc15; } .download .n { color: #60a5fa; }
#log { padding: 12px 20px; overflow-y: auto; max-height: calc(100vh - 140px); }
.row { display: flex; align-items: flex-start; gap: 8px; padding: 6px 10px; border-radius: 6px; margin-bottom: 4px; border-left: 3px solid transparent; }
.row.error   { background: #2a1010; border-color: #f87171; }
.row.success { background: #0d2a1a; border-color: #4ade80; }
.row.download{ background: #0d1e2e; border-color: #60a5fa; }
.row.installing{ background: #2a2200; border-color: #facc15; }
.row.pending { background: #1e1e2a; border-color: #a78bfa; }
.row.info    { background: #1a1a1a; border-color: #555; }
.time { color: #888; min-width: 70px; font-size: 12px; padding-top: 1px; }
.badge { font-size: 10px; font-weight: bold; padding: 2px 7px; border-radius: 4px; min-width: 72px; text-align: center; text-transform: uppercase; }
.badge.error    { background: #f87171; color: #000; }
.badge.success  { background: #4ade80; color: #000; }
.badge.download { background: #60a5fa; color: #000; }
.badge.installing{ background: #facc15; color: #000; }
.badge.pending  { background: #a78bfa; color: #000; }
.badge.info     { background: #555; color: #fff; }
.app { background: #333; color: #aaa; font-size: 10px; padding: 2px 6px; border-radius: 4px; }
.msg { color: #ddd; line-height: 1.4; word-break: break-word; }
</style></head><body>
<header>
  <h1>🔍 IME Monitor</h1>
  <span class='clock'>Atualizado: $(Get-Date -Format 'HH:mm:ss') &nbsp;|&nbsp; Auto-refresh: 5s</span>
</header>
<div class='stats'>
  <div class='stat success'><div class='n'>$(($lines | Where-Object {$_ -match 'row success'}).Count)</div><div class='l'>Success</div></div>
  <div class='stat error'><div class='n'>$(($lines | Where-Object {$_ -match 'row error'}).Count)</div><div class='l'>Errors</div></div>
  <div class='stat installing'><div class='n'>$(($lines | Where-Object {$_ -match 'row installing'}).Count)</div><div class='l'>Installing</div></div>
  <div class='stat download'><div class='n'>$(($lines | Where-Object {$_ -match 'row download'}).Count)</div><div class='l'>Downloads</div></div>
</div>
<div id='log'>$($lines -join '')</div>
<script>document.getElementById('log').scrollTop=99999</script>
</body></html>
"@
    $html | Set-Content $htmlPath -Encoding UTF8
}

Update-HTML
Start-Process $htmlPath
Write-Host "Monitor aberto! Atualizando a cada 5s..." -ForegroundColor Cyan
while ($true) { Start-Sleep 5; Update-HTML }
