# SendAnywhere LAN — IIS edition

Designed & developed by [AJ System Soft](https://www.ajsystemsoft.in) · AI tools: [tvc0.lovable.app](https://tvc0.lovable.app) · [tvc0.pro](https://tvc0.pro) · [WhatsApp channel](https://whatsapp.com/channel/0029VbC2DdxJUM2bvG9gBy29)

Local-network file transfer. **No SQL Server, no Node.js, no build step.** Pure IIS + ASP.NET (.NET Framework 4.5+, built into Windows).

## One-click setup (recommended)
Right-click **setup-safe.bat** → Run as administrator (pure batch, no PowerShell needed; window stays open and writes setup-log.txt). It only adds ASP.NET features, creates its own app pool + site on 8080, sets App_Data permission and firewall, restarts only its own site, and tests the API. Other IIS sites are not restarted or changed.

## Manual setup (any Windows PC)
1. Enable IIS: *Control Panel → Programs → Turn Windows features on/off* → tick **Internet Information Services** and under
   *World Wide Web Services → Application Development Features* tick **ASP.NET 4.x** (and .NET Extensibility 4.x, ISAPI Extensions/Filters).
2. Copy this `iis-app` folder to e.g. `C:\inetpub\sendanywhere`.
3. IIS Manager → *Sites → Add Website* → Physical path = that folder, Port = `8080` (any). App pool: **.NET CLR v4.0, Integrated**.
4. Give write permission on `iis-app\App_Data` to the app pool identity (or simply to the `IIS_IUSRS` group):
   `icacls "<folder>\App_Data" /grant "IIS_IUSRS":(OI)(CI)M`
5. Allow the port in Windows Firewall:
   `netsh advfirewall firewall add rule name="SendAnywhere" dir=in action=allow protocol=TCP localport=8080`
6. Other devices on the same Wi-Fi/LAN open `http://<server-ip>:8080` (find IP with `ipconfig`).

## Security
- Only private-network clients (10.x, 172.16-31.x, 192.168.x, localhost) can use the API; internet IPs get 403.
- Every uploaded file is scanned by Microsoft Defender (MpCmdRun) in the background. Only files with a detected threat are deleted and blocked; clean files download normally. If Defender is missing, files show "Not scanned" and still work.
- Executables and scripts get an "Executable" warning badge, but they are not blocked.
- Downloads are always sent as attachments, and security headers are set. Nothing loads from the internet, so the app works fully offline.

## How it works
- Files upload in 8 MB chunks, 4 in parallel, written directly at their offset (no merge step) — saturates LAN speed; per-file limit 50 GB.
- Download uses IIS `TransmitFile` (kernel-mode, zero-copy).
- Metadata is JSON in `App_Data/transfers` (hidden from web). Transfers auto-delete after 24 h.
- Receiver enters 6-char code or opens the share link `?code=XXXXXX`.

## Troubleshooting
- **Port 8080 busy (another program answers, e.g. "Invalid url")**: setup-safe.bat now picks the next free port automatically (8090, 8181, ...) and prints the URL to use.
- **HTTP 405 on upload**: ASP.NET 4.x is not enabled or the app pool is "No Managed Code". Run `setup-safe.bat` as administrator.
- **403.14 Forbidden**: the site's physical path must be the `iis-app` folder (or the repo root, which now redirects to `iis-app/`).
- **"Server API not running" / 404.3 on transfer.ashx**: Windows Features → IIS → Application Development Features → tick **ASP.NET 4.x**, **.NET Extensibility 4.x**, **ISAPI Extensions**, **ISAPI Filters**. Then run `iisreset`.
- **Access denied when uploading**: run the `icacls` command from step 4 on `iis-app\App_Data`.
