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
- Every uploaded file is scanned by Microsoft Defender (MpCmdRun) in the background. Results are shown as badges only; no file is ever blocked or deleted because of the scan. If Defender is missing, files show "Not scanned" and still work.
- Executables and scripts get an "Executable" warning badge, but they are not blocked.
- Downloads are always sent as attachments, and security headers are set. Nothing loads from the internet, so the app works fully offline.

## Features
- **Quick send**: files or whole folders, up to 50 GB per file, 6 parallel chunks with live speed/ETA. You get a **6-digit numeric code**, a link and a QR code.
- **Auto-delete**: you choose 5 min to 1 hour (the user limit). Files can also delete themselves right after download (on by default). Nothing stays on the server PC longer than the timer.
- **Accounts (no SQL)**: sign up / log in / change password / reset password with a recovery key. The admin can also reset any user's password.
- **Password folders**: logged-in users create folders with a password. Anyone with the 6-digit folder ID and the password can download the files. Each file is deleted when its timer ends (max 1 hour for users).
- **Admin panel**: the first admin is created on the server PC (http://localhost). The admin can set the user time limit, turn sign-ups on or off, manage users and see disk usage. Admins can keep their own files for minutes, hours, days or years.
- Microsoft Defender scan with live status (information only — downloads are never blocked), PIN for quick sends, brute-force lockout, dark/light theme, mobile layout, fully offline.

All data is stored in `iis-app\App_Data` (users and settings are JSON files; uploads are in `boxes`). A background job runs every minute and deletes expired files.

## Port forwarding / internet (optional, off by default)
In `iis-app/web.config` set `AllowInternet` to `true` and `AccessKey` to a long secret (8+ chars). Internet users are asked for the key once; LAN users are not. Wrong codes, PINs and keys are rate-limited per IP. Use a PIN on every transfer you share over the internet.

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
