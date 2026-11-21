# SAFE setup: does NOT restart IIS, does NOT touch or delete other sites, no server-wide ASP.NET re-registration.
$ErrorActionPreference = 'Stop'
$Port = 8080; $Name = 'SendAnywhereLAN'
$AppDir = Join-Path $PSScriptRoot 'iis-app'; $DataDir = Join-Path $AppDir 'App_Data'

Write-Host "[1/5] Enabling ASP.NET 4.x features (adds features only, existing sites unaffected)..." -ForegroundColor Cyan
foreach ($f in 'IIS-ApplicationDevelopment','NetFx4Extended-ASPNET45','IIS-NetFxExtensibility45','IIS-ISAPIExtensions','IIS-ISAPIFilter','IIS-ASPNET45','IIS-ManagementScriptingTools') {
  try { Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart -ErrorAction Stop | Out-Null; Write-Host "  ok  $f" }
  catch { Write-Host "  skip $f" -ForegroundColor DarkYellow }
}
Import-Module WebAdministration

Write-Host "[2/5] App pool '$Name' (.NET v4.0 Integrated, separate from other sites)..." -ForegroundColor Cyan
if (-not (Test-Path "IIS:\AppPools\$Name")) { New-WebAppPool -Name $Name | Out-Null }
Set-ItemProperty "IIS:\AppPools\$Name" managedRuntimeVersion 'v4.0'
Set-ItemProperty "IIS:\AppPools\$Name" managedPipelineMode 'Integrated'

Write-Host "[3/5] Website on port $Port..." -ForegroundColor Cyan
$other = Get-Website | Where-Object { $_.Name -ne $Name -and ($_.bindings.Collection | Where-Object { $_.bindingInformation -like "*:${Port}:*" }) }
if ($other) {
  Write-Host "  Port $Port is used by: $($other.Name -join ', ')" -ForegroundColor Yellow
  if ($other.Name -eq 'Default Web Site' -or (Read-Host "  Is '$($other.Name -join ', ')' the old file-transfer site? Remove it? (y/n)") -eq 'y') {
    $other | ForEach-Object { Remove-Website -Name $_.Name; Write-Host "  removed $($_.Name)" }
  } else { Write-Host "  Not touching it. Edit `$Port in setup-safe.ps1 and run again." -ForegroundColor Red; return }
}
if (Test-Path "IIS:\Sites\$Name") { Set-ItemProperty "IIS:\Sites\$Name" physicalPath $AppDir; Set-ItemProperty "IIS:\Sites\$Name" applicationPool $Name }
else { New-Website -Name $Name -Port $Port -PhysicalPath $AppDir -ApplicationPool $Name | Out-Null }

Write-Host "[4/5] App_Data write permission + firewall..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
icacls $DataDir /grant "IIS_IUSRS:(OI)(CI)M" /grant "IIS AppPool\${Name}:(OI)(CI)M" /T /Q | Out-Null
if (-not (Get-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue)) { New-NetFirewallRule -DisplayName $Name -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port | Out-Null }

Write-Host "[5/5] Restarting ONLY this app pool and site..." -ForegroundColor Cyan
Restart-WebAppPool -Name $Name -ErrorAction SilentlyContinue
Stop-Website -Name $Name; Start-Website -Name $Name

try {
  $r = Invoke-WebRequest "http://localhost:$Port/api/transfer.ashx?action=ping" -UseBasicParsing
  Write-Host "`nAPI test: OK $($r.Content)" -ForegroundColor Green
} catch {
  Write-Host "`nAPI test FAILED: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "ASP.NET may need registering. Run once (restarts IIS briefly):  dism /online /enable-feature /featurename:IIS-ASPNET45 /all" -ForegroundColor Yellow
}
Start-Process "http://localhost:$Port"
