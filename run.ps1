$VERSION = "1.2.0"
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "  IME Monitor v$VERSION" -ForegroundColor Yellow
Write-Host "==============================" -ForegroundColor Cyan

if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue | Where-Object {$_.Version -ge '2.8.5.201'})) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Script -Name Get-AutopilotDiagnostics -Force -Scope CurrentUser
$script = Get-ChildItem -Path C:\Users -Recurse -Filter "Get-AutopilotDiagnostics.ps1" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if ($script) {
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$script`"" -NoNewWindow
} else {
    Write-Host "Script não encontrado." -ForegroundColor Red
}

$logPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log"
$keywords = "Win32App|Identifying|Installing|Downloading|Success|Failed|Error|SideCarAgent|exitCode|Detection|enforcement|Completed|Pending|Tracked|started|Add File|Job|action status"

function Get-Badge($msg) {
    if ($msg -match "Failed|Error")                                      { return "error" }
    elseif ($msg -match "Success|Completed|Installed|action status.*Success") { return "success" }
    elseif ($msg -match "Add File|Downloading|Download")                 { return "download" }
    elseif ($msg -match "Installing|InProgress|started|Starting job")    { return "installing" }
    elseif ($msg -match "Identifying|Pending|Waiting")                   { return "pending" }
    else                                                                 { return "info" }
}

function Build-HTML {
    $lines = Get-Content $logPath -Tail 500 | ForEach-Object {
        if ($_ -match '\!\[LOG\[(.+?)\]LOG\].*time="(\d+:\d+:\d+)') {
            $msg = $matches[1].Trim(); $time = $matches[2]
            if ($msg -match $keywords) {
                $badge = Get-Badge $msg
                $appName = if ($msg -match "Win32App_([a-f0-9\-]+)") { $matches[1].Substring(0,8) } else { "" }
                $appTag = if ($appName) { "<span class='app'>APP:$appName</span>" } else { "" }
                "<div class='row $badge' data-type='$badge'><span class='time'>$time</span><span class='badge $badge'>$badge</span>$appTag<span class='msg'>$msg</span></div>"
            }
        }
    }

    $cSuccess  = ($lines | Where-Object {$_ -match "data-type='success'"}).Count
    $cError    = ($lines | Where-Object {$_ -match "data-type='error'"}).Count
    $cInstall  = ($lines | Where-Object {$_ -match "data-type='installing'"}).Count
    $cDownload = ($lines | Where-Object {$_ -match "data-type='download'"}).Count

    return @"
<!DOCTYPE html><html><head>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: #0f0f0f; font-family: 'Segoe UI', Consolas, monospace; font-size: 13px; color: #ccc; }
header { background: #1a1a2e; padding: 14px 20px; border-bottom: 2px solid #333; display: flex; align-items: center; gap: 12px; }
header h1 { color: #fff; font-size: 18px; }
.version { background: #333; color: #aaa; font-size: 11px; padding: 3px 8px; border-radius: 4px; }
header .clock { color: #888; font-size: 13px; margin-left: auto; }
.controls { display: flex; gap: 8px; align-items: center; }
button { cursor: pointer; border: none; border-radius: 6px; padding: 6px 14px; font-size: 12px; font-weight: bold; }
#btnRefresh { background: #4ade80; color: #000; }
#btnRefresh.paused { background: #f87171; color: #000; }
.filters { display: flex; gap: 8px; padding: 10px 20px; background: #111; border-bottom: 1px solid #222; flex-wrap: wrap; align-items: center; }
.filters span { color: #888; font-size: 12px; }
.filter-btn { cursor: pointer; border: 2px solid transparent; border-radius: 6px; padding: 4px 12px; font-size: 11px; font-weight: bold; opacity: 0.5; transition: opacity .2s; }
.filter-btn.active { opacity: 1; }
.filter-btn.all    { background: #444; color: #fff; border-color: #666; }
.filter-btn.success  { background: #0d2a1a; color: #4ade80; border-color: #4ade80; }
.filter-btn.error    { background: #2a1010; color: #f87171; border-color: #f87171; }
.filter-btn.installing{ background: #2a2200; color: #facc15; border-color: #facc15; }
.filter-btn.download { background: #0d1e2e; color: #60a5fa; border-color: #60a5fa; }
.filter-btn.pending  { background: #1e1e2a; color: #a78bfa; border-color: #a78bfa; }
.filter-btn.info     { background: #1a1a1a; color: #888;    border-color: #555; }
.stats { display: flex; gap: 12px; padding: 10px 20px; background: #111; border-bottom: 1px solid #222; }
.stat { background: #1e1e1e; border-radius: 8px; padding: 8px 16px; text-align: center; min-width: 80px; }
.stat .n { font-size: 22px; font-weight: bold; }
.stat .l { font-size: 11px; color: #888; margin-top: 2px; }
.success .n { color: #4ade80; } .error .n { color: #f87171; } .installing .n { color: #facc15; } .download .n { color: #60a5fa; }
#log { padding: 12px 20px; overflow-y: auto; max-height: calc(100vh - 200px); }
.row { display: flex; align-items: flex-start; gap: 8px; padding: 6px 10px; border-radius: 6px; margin-bottom: 4px; border-left: 3px solid transparent; }
.row.error      { background: #2a1010; border-color: #f87171; }
.row.success    { background: #0d2a1a; border-color: #4ade80; }
.row.download   { background: #0d1e2e; border-color: #60a5fa; }
.row.installing { background: #2a2200; border-color: #facc15; }
.row.pending    { background: #1e1e2a; border-color: #a78bfa; }
.row.info       { background: #1a1a1a; border-color: #555; }
.time { color: #888; min-width: 70px; font-size: 12px; padding-top: 1px; }
.badge { font-size: 10px; font-weight: bold; padding: 2px 7px; border-radius: 4px; min-width: 72px; text-align: center; text-transform: uppercase; }
.badge.error      { background: #f87171; color: #000; }
.badge.success    { background: #4ade80; color: #000; }
.badge.download   { background: #60a5fa; color: #000; }
.badge.installing { background: #facc15; color: #000; }
.badge.pending    { background: #a78bfa; color: #000; }
.badge.info       { background: #555; color: #fff; }
.app { background: #333; color: #aaa; font-size: 10px; padding: 2px 6px; border-radius: 4px; }
.msg { color: #ddd; line-height: 1.4; word-break: break-word; }
</style></head><body>
<header>
  <h1>🔍 IME Monitor</h1>
  <span class='version'>v$VERSION</span>
  <span class='clock' id='clock'>Atualizado: $(Get-Date -Format 'HH:mm:ss')</span>
  <div class='controls'>
    <button id='btnRefresh' onclick='toggleRefresh()'>⏸ Pausar</button>
  </div>
</header>
<div class='stats'>
  <div class='stat success'><div class='n'>$cSuccess</div><div class='l'>Success</div></div>
  <div class='stat error'><div class='n'>$cError</div><div class='l'>Errors</div></div>
  <div class='stat installing'><div class='n'>$cInstall</div><div class='l'>Installing</div></div>
  <div class='stat download'><div class='n'>$cDownload</div><div class='l'>Downloads</div></div>
</div>
<div class='filters'>
  <span>Filtrar:</span>
  <button class='filter-btn all active' onclick='filter("all")'>Todos</button>
  <button class='filter-btn success' onclick='filter("success")'>✅ Success</button>
  <button class='filter-btn error' onclick='filter("error")'>❌ Error</button>
  <button class='filter-btn installing' onclick='filter("installing")'>⚙️ Installing</button>
  <button class='filter-btn download' onclick='filter("download")'>📥 Download</button>
  <button class='filter-btn pending' onclick='filter("pending")'>⏳ Pending</button>
  <button class='filter-btn info' onclick='filter("info")'>ℹ️ Info</button>
</div>
<div id='log'>$($lines -join '')</div>
<script>
  var refreshTimer;
  var paused = false;

  function toggleRefresh() {
    paused = !paused;
    var btn = document.getElementById('btnRefresh');
    if (paused) {
      btn.textContent = '▶ Retomar';
      btn.classList.add('paused');
      clearTimeout(refreshTimer);
    } else {
      btn.textContent = '⏸ Pausar';
      btn.classList.remove('paused');
      scheduleRefresh();
    }
  }

  function scheduleRefresh() {
    refreshTimer = setTimeout(function() { location.reload(); }, 5000);
  }

  function filter(type) {
    document.querySelectorAll('.filter-btn').forEach(function(b) { b.classList.remove('active'); });
    document.querySelector('.filter-btn.' + type).classList.add('active');
    document.querySelectorAll('.row').forEach(function(r) {
      if (type === 'all' || r.dataset.type === type) {
        r.style.display = '';
      } else {
        r.style.display = 'none';
      }
    });
  }

  document.getElementById('log').scrollTop = 99999;
  if (!paused) scheduleRefresh();
</script>
</body></html>
"@
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:8080/")
$listener.Start()
Write-Host "Monitor em http://localhost:8080 — abrindo browser..." -ForegroundColor Cyan
Start-Process "http://localhost:8080/"

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $html = Build-HTML
    $buf = [System.Text.Encoding]::UTF8.GetBytes($html)
    $ctx.Response.ContentType = "text/html; charset=utf-8"
    $ctx.Response.ContentLength64 = $buf.Length
    $ctx.Response.OutputStream.Write($buf, 0, $buf.Length)
    $ctx.Response.OutputStream.Close()
}
