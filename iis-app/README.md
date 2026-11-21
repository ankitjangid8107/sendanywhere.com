# SendAnywhere LAN — IIS edition

Designed & developed by [AJ System Soft](https://www.ajsystemsoft.in) · AI tools: [tvc0.lovable.app](https://tvc0.lovable.app) · [tvc0.pro](https://tvc0.pro) · [WhatsApp channel](https://whatsapp.com/channel/0029VbC2DdxJUM2bvG9gBy29)

Local-network file transfer. **No SQL Server, no Node.js, no build step.** Pure IIS + ASP.NET (.NET Framework 4.5+, built into Windows).

## One-click setup (recommended)
Right-click **setup.bat** (in the repo root) → *Run as administrator*. It enables IIS + ASP.NET 4.x, creates the app pool and site on port 8080, sets App_Data permissions, opens the firewall and launches the browser.

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

## How it works
- Files upload in 8 MB chunks, 4 in parallel, written directly at their offset (no merge step) — saturates LAN speed; per-file limit 50 GB.
- Download uses IIS `TransmitFile` (kernel-mode, zero-copy).
- Metadata is JSON in `App_Data/transfers` (hidden from web). Transfers auto-delete after 24 h.
- Receiver enters 6-char code or opens the share link `?code=XXXXXX`.

## Troubleshooting
- **HTTP 405 on upload**: ASP.NET 4.x is not enabled or the app pool is "No Managed Code". Run `setup.bat` as administrator.
- **403.14 Forbidden**: the site's physical path must be the `iis-app` folder (or the repo root, which now redirects to `iis-app/`).
- **"Server API not running" / 404.3 on transfer.ashx**: Windows Features → IIS → Application Development Features → tick **ASP.NET 4.x**, **.NET Extensibility 4.x**, **ISAPI Extensions**, **ISAPI Filters**. Then run `iisreset`.
- **Access denied when uploading**: run the `icacls` command from step 4 on `iis-app\App_Data`.
