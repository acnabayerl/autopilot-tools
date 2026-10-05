$VERSION = "1.8.2"
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "  IME Monitor v$VERSION" -ForegroundColor Yellow
Write-Host "==============================" -ForegroundColor Cyan

if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue | Where-Object {$_.Version -ge '2.8.5.201'})) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false | Out-Null
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

# Mapa manual opcional: adicione AppId (primeiros 8 chars) = "Nome do App"
$manualAppNames = @{
    # "501FCB7D" = "Microsoft Teams"
    # "XXXXXXXX" = "Nome do App"
}
$keywords = "Win32App|Identifying|Installing|Downloading|Success|Failed|Error|SideCarAgent|exitCode|Detection|enforcement|Completed|Pending|Tracked|started|Add File|Job|action status"

$exitCodes = @{
    "0x87D1041C"  = "App não detectado após instalação — regra de detecção falhou"
    "0x87D00324"  = "App já instalado — sem necessidade de reinstalar"
    "0x80070002"  = "Arquivo não encontrado — conteúdo do app ausente ou corrompido"
    "0x80070005"  = "Acesso negado — permissão insuficiente para instalar"
    "0x80070057"  = "Parâmetro inválido — erro no comando de instalação"
    "0x800704C7"  = "Instalação cancelada pelo usuário ou sistema"
    "0x80070BC2"  = "Reinicialização pendente necessária para concluir"
    "0x80070BC9"  = "Reinicialização necessária antes de continuar"
    "0x80070643"  = "Falha geral na instalação — verificar log do instalador"
    "0x80070652"  = "Outra instalação em andamento — conflito de MSI"
    "0x80004005"  = "Erro não especificado — falha genérica de acesso"
    "0x80240438"  = "WSUS/WU não disponível — sem fonte de atualização"
    "0xC1900101"  = "Falha de driver durante upgrade do Windows"
    "0x80091007"  = "Hash do arquivo inválido — conteúdo corrompido no download"
    "0x80D02002"  = "Timeout no download via Delivery Optimization"
    "0x80D02003"  = "Delivery Optimization sem fonte disponível"
    "-2016281112" = "App não detectado após instalação — regra de detecção falhou"
    "-2147024894" = "Arquivo não encontrado"
    "-2147024891" = "Acesso negado"
    "1603"        = "Falha fatal durante instalação MSI"
    "1605"        = "App não instalado — código MSI desconhecido"
    "1618"        = "Outra instalação MSI em andamento"
    "1633"        = "Plataforma não suportada para este pacote"
    "3010"        = "Instalação concluída — reinicialização necessária"
    "3399548929"  = "Falha ao obter token AAD — dispositivo sem conectividade com Azure AD"
    "0xCAA20009"  = "Falha ao obter token AAD — dispositivo sem conectividade com Azure AD"
}

function Get-ExitCodeInfo($msg) {
    foreach ($code in $exitCodes.Keys) {
        if ($msg -match [regex]::Escape($code)) { return $exitCodes[$code] }
    }
    if ($msg -match "exitCode\s*[=:]\s*(\-?\d+|0x[0-9a-fA-F]+)") {
        return "Exit code: $($matches[1]) — sem descrição mapeada"
    }
    return ""
}

function Get-Badge($msg) {
    if ($msg -match "Failed|Error")                                           { return "error" }
    elseif ($msg -match "Success|Completed|Installed|action status.*Success") { return "success" }
    elseif ($msg -match "Add File|Downloading|Download")                      { return "download" }
    elseif ($msg -match "Installing|InProgress|started|Starting job")         { return "installing" }
    elseif ($msg -match "Identifying|Pending|Waiting")                        { return "pending" }
    else                                                                      { return "info" }
}

function Build-HTML {
    $errorGroups = @{}

    # Mapear AppId -> Nome do app via arquivos de estado do IME
    $script:appNameMap = @{}
    $appNameMap = $script:appNameMap
    $imePath = "C:\ProgramData\Microsoft\IntuneManagementExtension"

    # 1) Todos os JSON do IME recursivamente
    Get-ChildItem $imePath -Recurse -Include "*.json","*.dat" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $j = Get-Content $_.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            # Função para extrair Id->Nome de qualquer objeto
            $extract = {
                param($o)
                $id = $null; $nm = $null
                foreach ($k in @("ApplicationId","AppId","Id","appId")) { if ($o.$k) { $id = $o.$k; break } }
                foreach ($k in @("ApplicationName","DisplayName","AppName","Name","appName")) { if ($o.$k -and $o.$k -ne "null") { $nm = $o.$k; break } }
                if ($id -and $nm) { $appNameMap[$id.ToUpper()] = $nm }
            }
            & $extract $j
            foreach ($prop in @("Apps","Win32Apps","Applications","Policies","value","items","Results")) {
                if ($j.$prop -is [array]) { $j.$prop | ForEach-Object { & $extract $_ } }
            }
        } catch {}
    }

    $guidPattern = "[A-Fa-f0-9]{8}-(?:[A-Fa-f0-9]{4}-){3}[A-Fa-f0-9]{12}"

    # 2) Registro MDM - políticas de app Win32 cached pelo CSP
    try {
        @(
            "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device",
            "HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager\Tracked",
            "HKLM:\SOFTWARE\Microsoft\Enrollments"
        ) | ForEach-Object {
            if (Test-Path $_) {
                Get-ChildItem $_ -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                    $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                    if ($p) {
                        $p.PSObject.Properties | Where-Object { $_.Name -match "^[A-Fa-f0-9]{8}-" } | ForEach-Object {
                            $val = $_.Value
                            if ($val -and $val -match "DisplayName|AppName|Name") {
                                try {
                                    $j = $val | ConvertFrom-Json -ErrorAction Stop
                                    foreach ($k in @("DisplayName","AppName","ApplicationName","Name")) {
                                        if ($j.$k) { $appNameMap[$_.Name.ToUpper()] = $j.$k; break }
                                    }
                                } catch {}
                            }
                        }
                    }
                }
            }
        }
    } catch {}

    # Mapa manual configurado pelo usuário
    $manualAppNames.GetEnumerator() | ForEach-Object { $appNameMap[$_.Key.ToUpper()] = $_.Value }

    # 3) Windows Event Log do IME (contém nomes de apps)
    try {
        Get-WinEvent -LogName "Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin" -MaxEvents 1000 -ErrorAction Stop |
            ForEach-Object {
                $msg = $_.Message
                if ($msg -match "($guidPattern).*?(?:app)?[Nn]ame\s*[=:]\s*'?([^,'\r\n]{3,80}?)'?(?:[,;)]|$)") {
                    if (-not $appNameMap[$matches[1].ToUpper()]) { $appNameMap[$matches[1].ToUpper()] = $matches[2].Trim() }
                }
                if ($msg -match "(?:app)?[Nn]ame\s*[=:]\s*'?([^,'\r\n]{3,80}?)'?[,;(].*?($guidPattern)") {
                    if (-not $appNameMap[$matches[2].ToUpper()]) { $appNameMap[$matches[2].ToUpper()] = $matches[1].Trim() }
                }
            }
    } catch {}

    # 4) Registro do IME (Win32Apps enforcement data)
    try {
        $regBase = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps"
        if (Test-Path $regBase) {
            Get-ChildItem $regBase -ErrorAction SilentlyContinue | ForEach-Object {
                Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
                    $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                    if ($p.AppName -and $p.AppId) { $appNameMap[$p.AppId.ToUpper()] = $p.AppName }
                    if ($p.Name -and $p.Id)       { $appNameMap[$p.Id.ToUpper()] = $p.Name }
                }
            }
        }
    } catch {}

    # 5) Todos os logs do IME (SideCarAgent, AgentExecutor, etc.)
    $logDir = Split-Path $logPath
    Get-ChildItem $logDir -Filter "*.log" -ErrorAction SilentlyContinue | ForEach-Object {
        Get-Content $_.FullName -Tail 5000 -ErrorAction SilentlyContinue | ForEach-Object {
            $raw = if ($_ -match '\!\[LOG\[(.+?)\]LOG\]') { $matches[1] } else { $_ }
            # "id = {guid} ... name = X" e variações
            if ($raw -match "($guidPattern)[^`n]{0,80}?(?:app)?[Nn]ame\s*[=:]\s*[`"']?([^,`"'\r`n]{3,80}?)(?:[`"',;)]|$)") {
                if (-not $appNameMap[$matches[1].ToUpper()]) { $appNameMap[$matches[1].ToUpper()] = $matches[2].Trim() }
            }
            if ($raw -match "(?:app)?[Nn]ame\s*[=:]\s*[`"']?([^,`"'\r`n]{3,80}?)[`"']?\s*[,;(]?[^`n]{0,80}?($guidPattern)") {
                if (-not $appNameMap[$matches[2].ToUpper()]) { $appNameMap[$matches[2].ToUpper()] = $matches[1].Trim() }
            }
        }
    }

    $lines = Get-Content $logPath -Tail 3000 | ForEach-Object {
        if ($_ -match '\!\[LOG\[(.+?)\]LOG\].*time="(\d+:\d+:\d+)') {
            $msg = $matches[1].Trim(); $time = $matches[2]
            if ($msg -match $keywords) {
                $badge = Get-Badge $msg
                $resolvedApp = ""
                if ($msg -match "File Id:\s*([A-Fa-f0-9]{8}-(?:[A-Fa-f0-9]{4}-){3}[A-Fa-f0-9]{12})") {
                    $fid = $matches[1].ToUpper()
                    $resolvedApp = if ($appNameMap[$fid]) { $appNameMap[$fid] } else { "não encontrado" }
                } elseif ($msg -match "Win32App_([a-f0-9\-]+)") {
                    $aid = $matches[1].ToUpper().Substring(0, [Math]::Min(36, $matches[1].Length))
                    $resolvedApp = if ($appNameMap[$aid]) { $appNameMap[$aid] } else { "não encontrado" }
                }
                $appName = $resolvedApp
                $appTag = if ($appName) { "<span class='app' title='$appName'>$appName</span>" } else { "" }
                $tooltipAttr = ""; $tooltip = ""
                if ($badge -eq "error") {
                    $info = Get-ExitCodeInfo $msg
                    if ($info) {
                        $tooltipAttr = "data-tooltip=`"$info`""
                        $tooltip = "<span class='tooltip-icon'>💡</span>"
                    }
                    if ($appName) {
                        if (-not $errorGroups[$appName]) { $errorGroups[$appName] = 0 }
                        $errorGroups[$appName]++
                    }
                }
                "<div class='row $badge' data-type='$badge' $tooltipAttr><span class='time'>$time</span><span class='badge $badge'>$badge</span>$appTag$tooltip<span class='msg'>$msg</span></div>"
            }
        }
    }

    $cSuccess  = ($lines | Where-Object {$_ -match "data-type='success'"}).Count
    $cError    = ($lines | Where-Object {$_ -match "data-type='error'"}).Count
    $cInstall  = ($lines | Where-Object {$_ -match "data-type='installing'"}).Count
    $cDownload = ($lines | Where-Object {$_ -match "data-type='download'"}).Count

    $errorGroupHTML = ""
    if ($errorGroups.Count -gt 0) {
        $errorGroupHTML = "<div class='error-groups'><div class='eg-title'>❌ Erros por App</div>"
        foreach ($key in ($errorGroups.Keys | Sort-Object)) {
            $count = $errorGroups[$key]
            $bar = [Math]::Min($count * 20, 200)
            $errorGroupHTML += "<div class='eg-row'><span class='eg-app'>APP:$key</span><div class='eg-bar-wrap'><div class='eg-bar' style='width:${bar}px'></div></div><span class='eg-count'>$count x</span></div>"
        }
        $errorGroupHTML += "</div>"
    }

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
.stats { display: flex; gap: 12px; padding: 10px 20px; background: #111; border-bottom: 1px solid #222; flex-wrap: wrap; }
.stat { background: #1e1e1e; border-radius: 8px; padding: 8px 16px; text-align: center; min-width: 80px; }
.stat .n { font-size: 22px; font-weight: bold; }
.stat .l { font-size: 11px; color: #888; margin-top: 2px; }
.success .n { color: #4ade80; } .error .n { color: #f87171; } .installing .n { color: #facc15; } .download .n { color: #60a5fa; }
.error-groups { background: #1a0a0a; border: 1px solid #f87171; border-radius: 8px; padding: 12px 16px; margin: 10px 20px; }
.eg-title { color: #f87171; font-weight: bold; margin-bottom: 8px; font-size: 12px; }
.eg-row { display: flex; align-items: center; gap: 10px; margin-bottom: 6px; }
.eg-app { color: #aaa; font-size: 11px; min-width: 100px; background: #333; padding: 2px 6px; border-radius: 4px; }
.eg-bar-wrap { background: #2a1010; border-radius: 4px; height: 12px; width: 200px; }
.eg-bar { background: #f87171; height: 12px; border-radius: 4px; }
.eg-count { color: #f87171; font-weight: bold; font-size: 12px; min-width: 30px; }
.filters { display: flex; gap: 8px; padding: 10px 20px; background: #111; border-bottom: 1px solid #222; flex-wrap: wrap; align-items: center; }
.filters span { color: #888; font-size: 12px; }
.filter-btn { cursor: pointer; border: 2px solid transparent; border-radius: 6px; padding: 4px 12px; font-size: 11px; font-weight: bold; opacity: 0.5; transition: opacity .2s; }
.filter-btn.active { opacity: 1; }
.filter-btn.all        { background: #444;    color: #fff;    border-color: #666; }
.filter-btn.success    { background: #0d2a1a; color: #4ade80; border-color: #4ade80; }
.filter-btn.error      { background: #2a1010; color: #f87171; border-color: #f87171; }
.filter-btn.installing { background: #2a2200; color: #facc15; border-color: #facc15; }
.filter-btn.download   { background: #0d1e2e; color: #60a5fa; border-color: #60a5fa; }
.filter-btn.pending    { background: #1e1e2a; color: #a78bfa; border-color: #a78bfa; }
.filter-btn.info       { background: #1a1a1a; color: #888;    border-color: #555; }
#log { padding: 12px 20px; overflow-y: auto; max-height: calc(100vh - 260px); }
.row { display: flex; align-items: flex-start; gap: 8px; padding: 6px 10px; border-radius: 6px; margin-bottom: 4px; border-left: 3px solid transparent; position: relative; }
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
.badge.info       { background: #555;    color: #fff; }
.app { background: #333; color: #aaa; font-size: 10px; padding: 2px 6px; border-radius: 4px; max-width: 180px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; flex-shrink: 0; cursor: default; }
.msg { color: #ddd; line-height: 1.4; word-break: break-word; flex: 1; }
.tooltip-icon { cursor: help; font-size: 14px; }
.row[data-tooltip]:hover::after {
    content: attr(data-tooltip);
    position: absolute; left: 80px; top: 100%; z-index: 99;
    background: #1e1e2e; color: #fff; border: 1px solid #f87171;
    padding: 8px 12px; border-radius: 6px; font-size: 12px;
    white-space: normal; max-width: 400px; line-height: 1.5;
    box-shadow: 0 4px 12px rgba(0,0,0,0.5);
}
</style></head><body>
<header>
  <h1>🔍 IME Monitor</h1>
  <span class='version'>v$VERSION</span>
  <span class='clock'>Atualizado: $(Get-Date -Format 'HH:mm:ss') | Auto-refresh: 5s</span>
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
$errorGroupHTML
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
  var paused = false; var refreshTimer;

  function ping() { fetch('/ping').catch(function(){}); setTimeout(ping, 3000); }
  ping();

  function toggleRefresh() {
    paused = !paused;
    var btn = document.getElementById('btnRefresh');
    if (paused) { btn.textContent = '▶ Retomar'; btn.classList.add('paused'); clearTimeout(refreshTimer); }
    else { btn.textContent = '⏸ Pausar'; btn.classList.remove('paused'); scheduleRefresh(); }
  }

  function filter(type) {
    document.querySelectorAll('.filter-btn').forEach(function(b) { b.classList.remove('active'); });
    document.querySelector('.filter-btn.' + type).classList.add('active');
    document.querySelectorAll('.row').forEach(function(r) {
      r.style.display = (type === 'all' || r.dataset.type === type) ? '' : 'none';
    });
  }

  // Debug IME
  console.log('[IME] nomes=$($script:appNameMap.Count)');
  $(
    $target = "501FCB7D-A970-4E34-A753-4B48FE5D8BEF"
    $hits = @()
    Get-ChildItem (Split-Path $logPath) -Filter "*.log" -ErrorAction SilentlyContinue | ForEach-Object {
        Get-Content $_.FullName -ErrorAction SilentlyContinue | Where-Object { $_ -match $target } | Select-Object -First 5 | ForEach-Object {
            $m = if ($_ -match '\!\[LOG\[(.+?)\]LOG\]') { $matches[1] } else { $_ }
            $safe = ($m.Substring(0,[Math]::Min(300,$m.Length))) -replace '[\\`"''<>]',''
            $hits += "console.log('[LOG] $safe');"
        }
    }
    if ($hits.Count -gt 0) { $hits -join "`n" } else { "console.warn('[IME] GUID 501FCB7D nao encontrado nos logs');" }
  )

  document.getElementById('log').scrollTop = 99999;
  if (!paused) scheduleRefresh();

  var _closing = false;
  function scheduleRefresh() { refreshTimer = setTimeout(function() { _closing = true; location.reload(); }, 5000); }

  document.addEventListener('visibilitychange', function() {
    if (document.visibilityState === 'hidden' && !_closing) {
      setTimeout(function() {
        if (document.visibilityState === 'hidden' && !_closing) {
          navigator.sendBeacon('/close');
        }
      }, 15000);
    }
  });
</script>
</body></html>
"@
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:8080/")
$listener.Start()
Write-Host "Monitor em http://localhost:8080 — abrindo browser..." -ForegroundColor Cyan
Start-Process "http://localhost:8080/"

$script:lastPing = [datetime]::UtcNow
$watchdog = [System.Threading.Timer]::new({
    if (([datetime]::UtcNow - $script:lastPing).TotalSeconds -gt 90) {
        Write-Host "Browser fechado — encerrando." -ForegroundColor Yellow
        $listener.Stop()
    }
}, $null, 60000, 3000)

while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
        $path = $ctx.Request.Url.AbsolutePath
        if ($path -eq "/ping") {
            $script:lastPing = [datetime]::UtcNow
            $ctx.Response.StatusCode = 204
            $ctx.Response.OutputStream.Close()
        } elseif ($path -eq "/close") {
            $ctx.Response.StatusCode = 204
            $ctx.Response.OutputStream.Close()
            Write-Host "Browser fechado — encerrando." -ForegroundColor Yellow
            $listener.Stop()
        } elseif ($path -eq "/debug-app") {
            $dbgLines = @("=== AppNameMap ($($script:appNameMap.Count) entradas) ===")
            $script:appNameMap.GetEnumerator() | Select-Object -First 20 | ForEach-Object { $dbgLines += "$($_.Key) = $($_.Value)" }
            $dbgLines += ""
            $dbgLines += "=== Linhas do log com GUID + name (primeiras 20) ==="
            $found = Get-Content $logPath -Tail 3000 | Where-Object {
                $_ -match '\!\[LOG\[' -and $_ -match "[A-Fa-f0-9]{8}-(?:[A-Fa-f0-9]{4}-){3}[A-Fa-f0-9]{12}" -and $_ -match "[Nn]ame"
            } | Select-Object -First 20 | ForEach-Object {
                if ($_ -match '\!\[LOG\[(.+?)\]LOG\]') { $matches[1] } else { $_ }
            }
            if ($found) { $dbgLines += $found } else { $dbgLines += "(nenhuma linha encontrada)" }
            $body = $dbgLines -join "`n"
            $buf = [System.Text.Encoding]::UTF8.GetBytes($body)
            $ctx.Response.ContentType = "text/plain; charset=utf-8"
            $ctx.Response.ContentLength64 = $buf.Length
            $ctx.Response.OutputStream.Write($buf, 0, $buf.Length)
            $ctx.Response.OutputStream.Close()
        } elseif ($path -eq "/favicon.ico") {
            $ctx.Response.StatusCode = 404
            $ctx.Response.OutputStream.Close()
        } else {
            try {
                $html = Build-HTML
                $buf = [System.Text.Encoding]::UTF8.GetBytes($html)
                $ctx.Response.ContentType = "text/html; charset=utf-8"
                $ctx.Response.ContentLength64 = $buf.Length
                $ctx.Response.OutputStream.Write($buf, 0, $buf.Length)
                $ctx.Response.OutputStream.Close()
            } catch {
                try { $ctx.Response.StatusCode = 500; $ctx.Response.OutputStream.Close() } catch {}
            }
        }
    } catch [System.Net.HttpListenerException] {
        if ($listener.IsListening) { continue } else { break }
    } catch {
        continue
    }
}

$watchdog.Dispose()
Write-Host "Monitor encerrado." -ForegroundColor Red
