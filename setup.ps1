# SendAnywhere LAN - one-click IIS setup (run via setup.bat as Administrator)
$ErrorActionPreference = 'Stop'
$Port = 8080
$Name = 'SendAnywhereLAN'
$AppDir = Join-Path $PSScriptRoot 'iis-app'
$DataDir = Join-Path $AppDir 'App_Data'

Write-Host "`n[1/5] Enabling IIS + ASP.NET 4.x (can take a few minutes)..." -ForegroundColor Cyan
$features = 'IIS-WebServerRole','IIS-WebServer','IIS-CommonHttpFeatures','IIS-StaticContent','IIS-DefaultDocument',
  'IIS-HttpErrors','IIS-RequestFiltering','IIS-HttpCompressionStatic','IIS-ManagementConsole',
  'IIS-ApplicationDevelopment','NetFx4Extended-ASPNET45','IIS-NetFxExtensibility45','IIS-ISAPIExtensions','IIS-ISAPIFilter','IIS-ASPNET45'
foreach ($f in $features) {
  try { Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart -ErrorAction Stop | Out-Null; Write-Host "  ok  $f" }
  catch { Write-Host "  skip $f ($($_.Exception.Message))" -ForegroundColor DarkYellow }
}
# Register ASP.NET with IIS on older systems where the feature alone is not enough
$regiis = "$env:windir\Microsoft.NET\Framework64\v4.0.30319\aspnet_regiis.exe"
if (Test-Path $regiis) { & $regiis -iru 2>$null | Out-Null }

Import-Module WebAdministration

Write-Host "[2/5] Creating app pool '$Name' (.NET v4.0, Integrated)..." -ForegroundColor Cyan
if (-not (Test-Path "IIS:\AppPools\$Name")) { New-WebAppPool -Name $Name | Out-Null }
Set-ItemProperty "IIS:\AppPools\$Name" -Name managedRuntimeVersion -Value 'v4.0'
Set-ItemProperty "IIS:\AppPools\$Name" -Name managedPipelineMode -Value 'Integrated'
Set-ItemProperty "IIS:\AppPools\$Name" -Name enable32BitAppOnWin64 -Value $false

Write-Host "[3/5] Creating website on port $Port..." -ForegroundColor Cyan
Get-Website | Where-Object { $_.Name -eq $Name -or ($_.bindings.Collection | Where-Object { $_.bindingInformation -like "*:${Port}:*" }) } |
  ForEach-Object { Write-Host "  removing old site '$($_.Name)'"; Remove-Website -Name $_.Name }
New-Website -Name $Name -Port $Port -PhysicalPath $AppDir -ApplicationPool $Name | Out-Null

Write-Host "[4/5] Granting write access to App_Data..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
icacls $DataDir /grant "IIS_IUSRS:(OI)(CI)M" /grant "IIS AppPool\${Name}:(OI)(CI)M" /T /Q | Out-Null

Write-Host "[5/5] Opening firewall port $Port..." -ForegroundColor Cyan
Get-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName $Name -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port | Out-Null

iisreset /restart | Out-Null
Start-Website -Name $Name
$ips = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254*' }).IPAddress
Write-Host "`nDone! Open:" -ForegroundColor Green
Write-Host "  http://localhost:$Port"
$ips | ForEach-Object { Write-Host "  http://${_}:$Port   (other devices on your network)" }
Start-Process "http://localhost:$Port"
