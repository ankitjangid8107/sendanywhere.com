<%@ WebHandler Language="C#" Class="TransferHandler" %>
using System;
using System.IO;
using System.Net;
using System.Web;
using System.Linq;
using System.Threading;
using System.Diagnostics;
using System.Collections.Generic;
using System.Web.Script.Serialization;
using System.Web.Configuration;
using System.Security.Cryptography;
using System.Text;

// SendAnywhere LAN API - local network only, no database (JSON metadata in App_Data).
// Every uploaded file is scanned with Microsoft Defender; only files with a detected threat are blocked.
public class TransferHandler : IHttpHandler
{
    const long MaxFileSize = 50L * 1024 * 1024 * 1024; // 50 GB per file
    const int MaxFiles = 500;
    static readonly TimeSpan Ttl = TimeSpan.FromHours(24);          // default expiry
    static readonly int[] AllowedHours = { 1, 6, 24, 72 };
    static readonly Dictionary<string, KeyValuePair<int, DateTime>> Fails = new Dictionary<string, KeyValuePair<int, DateTime>>();
    static readonly TimeSpan ScanTimeout = TimeSpan.FromMinutes(30);
    static readonly object Lock = new object();
    static readonly Random Rng = new Random();
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
    static readonly HashSet<string> RiskyExt = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        { ".exe",".msi",".bat",".cmd",".com",".scr",".ps1",".vbs",".js",".jse",".wsf",".hta",".jar",".dll",".lnk",".reg",".pif",".cpl" };

    public bool IsReusable { get { return true; } }

    public class FileMeta { public string name; public long size; public string type; public string scan; public string scanDetail; public bool risky; }
    public class Meta { public string code; public DateTime created; public DateTime expires; public List<FileMeta> files; public bool complete; public string pinHash; public string owner; public string pin; public int hours; public int downloads; }

    static string Root(HttpContext c)
    {
        var p = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(c.Request.PhysicalPath), "..", "App_Data", "transfers"));
        Directory.CreateDirectory(p);
        return p;
    }

    public void ProcessRequest(HttpContext c)
    {
        var res = c.Response;
        res.Cache.SetCacheability(HttpCacheability.NoCache);
        res.AddHeader("X-Content-Type-Options", "nosniff");
        res.AddHeader("X-Frame-Options", "DENY");
        res.AddHeader("Referrer-Policy", "no-referrer");
        if (!IsLocalClient(c.Request))
        {
            // Internet access (port forwarding) is OFF by default. When enabled in web.config it always needs the AccessKey.
            var allow = string.Equals(WebConfigurationManager.AppSettings["AllowInternet"], "true", StringComparison.OrdinalIgnoreCase);
            var key = WebConfigurationManager.AppSettings["AccessKey"] ?? "";
            var given = c.Request.Headers["X-Access-Key"] ?? c.Request.QueryString["ak"] ?? "";
            if (!allow || key.Length < 8) { Fail(c, 403, "Only devices on the local network can use this server."); return; }
            if (Blocked(c)) { Fail(c, 429, "Too many attempts. Try again in 15 minutes."); return; }
            if (!SafeEquals(given, key)) { Fail(c, 401, "ACCESS_KEY"); AddFail(c); return; }
        }
        try
        {
            switch ((c.Request["action"] ?? "").ToLowerInvariant())
            {
                case "ping": Ping(c); break;
                case "delete": RequirePost(c); Delete(c); break;
                case "init": RequirePost(c); Init(c); break;
                case "chunk": RequirePost(c); Chunk(c); break;
                case "complete": RequirePost(c); Complete(c); break;
                case "info": Info(c); break;
                case "download": Download(c); break;
                default: Fail(c, 400, "Unknown action"); break;
            }
        }
        catch (HttpException ex) { Fail(c, ex.GetHttpCode(), ex.Message); }
        catch (Exception ex) { Fail(c, 500, ex.Message); }
    }

    // ---------- security helpers ----------
    static bool IsLocalClient(HttpRequest r)
    {
        IPAddress ip;
        if (!IPAddress.TryParse(r.UserHostAddress ?? "", out ip)) return false;
        if (IPAddress.IsLoopback(ip)) return true;
        if (ip.IsIPv4MappedToIPv6) ip = ip.MapToIPv4();
        if (ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetworkV6)
        {
            var b6 = ip.GetAddressBytes();
            return ip.IsIPv6LinkLocal || ip.IsIPv6SiteLocal || (b6[0] & 0xFE) == 0xFC;
        }
        var b = ip.GetAddressBytes();
        return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168) || (b[0] == 169 && b[1] == 254);
    }

    static string Ip(HttpContext c) { return c.Request.UserHostAddress ?? "?"; }
    static bool Blocked(HttpContext c)
    {
        lock (Fails)
        {
            KeyValuePair<int, DateTime> v;
            if (!Fails.TryGetValue(Ip(c), out v)) return false;
            if (DateTime.UtcNow - v.Value > TimeSpan.FromMinutes(15)) { Fails.Remove(Ip(c)); return false; }
            return v.Key >= 20;
        }
    }
    static void AddFail(HttpContext c)
    {
        lock (Fails)
        {
            KeyValuePair<int, DateTime> v;
            if (!Fails.TryGetValue(Ip(c), out v) || DateTime.UtcNow - v.Value > TimeSpan.FromMinutes(15)) v = new KeyValuePair<int, DateTime>(0, DateTime.UtcNow);
            Fails[Ip(c)] = new KeyValuePair<int, DateTime>(v.Key + 1, v.Value);
            if (Fails.Count > 10000) Fails.Clear();
        }
    }
    static bool SafeEquals(string a, string b)
    {
        if (a == null || b == null) return false;
        int diff = a.Length ^ b.Length;
        for (int i = 0; i < Math.Min(a.Length, b.Length); i++) diff |= a[i] ^ b[i];
        return diff == 0;
    }
    static string Hash(string code, string pin)
    {
        using (var sha = SHA256.Create()) return Convert.ToBase64String(sha.ComputeHash(Encoding.UTF8.GetBytes("sa-lan|" + code + "|" + pin)));
    }
    static string Token()
    {
        var b = new byte[18];
        using (var r = RandomNumberGenerator.Create()) r.GetBytes(b);
        return Convert.ToBase64String(b).Replace('+', '-').Replace('/', '_');
    }
    static DateTime Expiry(Meta m) { return m.expires == default(DateTime) ? m.created.Add(Ttl) : m.expires; }

    // Lookup with brute-force protection and optional PIN check. Returns null after writing the error.
    static Meta Authorized(HttpContext c, string root, bool requireComplete)
    {
        if (Blocked(c)) { Fail(c, 429, "Too many wrong codes. Try again in 15 minutes."); return null; }
        var m = Load(root, CleanCode(c.Request["code"]));
        if (m == null || (requireComplete && !m.complete)) { AddFail(c); Fail(c, 404, "Invalid or expired code"); return null; }
        if (m.pinHash != null && !SafeEquals(Hash(m.code, c.Request["pin"] ?? ""), m.pinHash))
        {
            if (!string.IsNullOrEmpty(c.Request["pin"])) AddFail(c);
            Fail(c, 401, "PIN_REQUIRED"); return null;
        }
        return m;
    }

    static void RequirePost(HttpContext c)
    {
        if (c.Request.HttpMethod != "POST") throw new HttpException(405, "POST required");
    }

    static void Send(HttpContext c, object o) { c.Response.ContentType = "application/json"; c.Response.Write(Json.Serialize(o)); }

    static void Fail(HttpContext c, int status, string msg)
    {
        c.Response.Clear();
        c.Response.StatusCode = status;
        c.Response.TrySkipIisCustomErrors = true;
        Send(c, new { error = msg });
    }

    static string CleanCode(string code)
    {
        code = (code ?? "").Trim().ToUpperInvariant();
        return code.Length == 6 && code.All(char.IsLetterOrDigit) ? code : null;
    }

    static Meta Load(string root, string code)
    {
        if (code == null) return null;
        var f = Path.Combine(root, code, "meta.json");
        if (!File.Exists(f)) return null;
        Meta m;
        lock (Lock) m = Json.Deserialize<Meta>(File.ReadAllText(f));
        return DateTime.UtcNow > Expiry(m) ? null : m;
    }

    static void Save(string root, Meta m)
    {
        var f = Path.Combine(root, m.code, "meta.json");
        lock (Lock) { File.WriteAllText(f + ".tmp", Json.Serialize(m)); if (File.Exists(f)) File.Delete(f); File.Move(f + ".tmp", f); }
    }

    static void Cleanup(string root)
    {
        foreach (var d in Directory.GetDirectories(root))
            try
            {
                var mf = Path.Combine(d, "meta.json");
                bool expired = File.Exists(mf)
                    ? DateTime.UtcNow > Expiry(Json.Deserialize<Meta>(File.ReadAllText(mf)))
                    : DateTime.UtcNow - Directory.GetCreationTimeUtc(d) > TimeSpan.FromHours(2);
                if (expired) Directory.Delete(d, true);
            }
            catch { }
    }

    // ---------- API ----------
    static void Init(HttpContext c)
    {
        string body;
        using (var r = new StreamReader(c.Request.InputStream)) body = r.ReadToEnd();
        var req = Json.Deserialize<Meta>(body);
        if (req == null || req.files == null || req.files.Count == 0) { Fail(c, 400, "No files"); return; }
        if (req.files.Count > MaxFiles) { Fail(c, 400, "Too many files (max " + MaxFiles + ")"); return; }
        var root = Root(c);
        Cleanup(root);
        long need = req.files.Sum(f => Math.Max(0, f.size));
        try
        {
            var drive = new DriveInfo(Path.GetPathRoot(root));
            if (drive.AvailableFreeSpace < need + (1L << 30)) { Fail(c, 507, "Not enough free disk space on the server (" + (drive.AvailableFreeSpace >> 30) + " GB free)."); return; }
        }
        catch { }
        int hours = AllowedHours.Contains(req.hours) ? req.hours : 24;

        string code;
        const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        lock (Lock)
        {
            do { code = new string(Enumerable.Range(0, 6).Select(_ => chars[Rng.Next(chars.Length)]).ToArray()); }
            while (Directory.Exists(Path.Combine(root, code)));
            Directory.CreateDirectory(Path.Combine(root, code));
        }

        var m = new Meta { code = code, created = DateTime.UtcNow, expires = DateTime.UtcNow.AddHours(hours), files = new List<FileMeta>(), owner = Token() };
        var pin = (req.pin ?? "").Trim();
        if (pin.Length > 0) { if (pin.Length < 4 || pin.Length > 32) { Directory.Delete(Path.Combine(root, code), true); Fail(c, 400, "PIN must be 4-32 characters"); return; } m.pinHash = Hash(code, pin); }
        for (int i = 0; i < req.files.Count; i++)
        {
            var f = req.files[i];
            if (f.size < 0 || f.size > MaxFileSize) { Directory.Delete(Path.Combine(root, code), true); Fail(c, 400, "File too large (max 50 GB): " + f.name); return; }
            var name = Path.GetFileName(f.name ?? "file");
            foreach (var ch in Path.GetInvalidFileNameChars()) name = name.Replace(ch, '_');
            if (name.Length == 0) name = "file";
            m.files.Add(new FileMeta { name = name, size = f.size, type = "application/octet-stream", scan = "pending", risky = RiskyExt.Contains(Path.GetExtension(name)) });
            using (var fs = new FileStream(Path.Combine(root, code, i + ".bin"), FileMode.Create)) fs.SetLength(f.size);
        }
        Save(root, m);
        Send(c, new { code, owner = m.owner });
    }

    static void Chunk(HttpContext c)
    {
        var root = Root(c);
        var code = CleanCode(c.Request["code"]);
        var m = Load(root, code);
        if (m == null || m.complete || !SafeEquals(c.Request["owner"], m.owner)) { Fail(c, 404, "Transfer not found"); return; }
        int idx; long offset;
        if (!int.TryParse(c.Request["file"], out idx) || !long.TryParse(c.Request["offset"], out offset)
            || idx < 0 || idx >= m.files.Count || offset < 0 || offset > m.files[idx].size) { Fail(c, 400, "Bad chunk"); return; }

        var input = c.Request.GetBufferlessInputStream(true);
        using (var fs = new FileStream(Path.Combine(root, code, idx + ".bin"), FileMode.Open, FileAccess.Write, FileShare.ReadWrite, 1 << 20))
        {
            fs.Seek(offset, SeekOrigin.Begin);
            var buf = new byte[1 << 20];
            int n; long written = 0;
            while ((n = input.Read(buf, 0, buf.Length)) > 0)
            {
                if (offset + written + n > m.files[idx].size) { Fail(c, 400, "Chunk overflow"); return; }
                fs.Write(buf, 0, n); written += n;
            }
        }
        Send(c, new { ok = true });
    }

    static void Complete(HttpContext c)
    {
        var root = Root(c);
        var m = Load(root, CleanCode(c.Request["code"]));
        if (m == null || !SafeEquals(c.Request["owner"], m.owner)) { Fail(c, 404, "Transfer not found"); return; }
        if (!m.complete)
        {
            m.complete = true;
            Save(root, m);
            var code = m.code;
            ThreadPool.QueueUserWorkItem(_ => ScanAll(root, code));
        }
        Send(c, Public(m));
    }

    static object Public(Meta m)
    {
        return new
        {
            code = m.code,
            expires = Expiry(m).ToString("o"),
            locked = m.pinHash != null,
            downloads = m.downloads,
            files = m.files.Select(f => new { f.name, f.size, f.scan, f.scanDetail, f.risky })
        };
    }

    static void Info(HttpContext c)
    {
        var root = Root(c);
        var owner = c.Request["owner"];
        if (!string.IsNullOrEmpty(owner))
        {   // sender polling its own transfer (no PIN needed)
            var mo = Load(root, CleanCode(c.Request["code"]));
            if (mo == null || !SafeEquals(owner, mo.owner)) { Fail(c, 404, "Transfer not found"); return; }
            Send(c, Public(mo)); return;
        }
        var m = Authorized(c, root, true);
        if (m != null) Send(c, Public(m));
    }

    static void Ping(HttpContext c)
    {
        long free = -1;
        try { free = new DriveInfo(Path.GetPathRoot(Root(c))).AvailableFreeSpace; } catch { }
        Send(c, new { ok = true, scanner = ScannerPath() != null, freeSpace = free, maxFile = MaxFileSize, local = IsLocalClient(c.Request) });
    }

    static void Delete(HttpContext c)
    {
        var root = Root(c);
        var code = CleanCode(c.Request["code"]);
        var m = Load(root, code);
        if (m == null || !SafeEquals(c.Request["owner"], m.owner)) { Fail(c, 404, "Transfer not found"); return; }
        try { Directory.Delete(Path.Combine(root, code), true); } catch { }
        Send(c, new { ok = true });
    }

    static void Download(HttpContext c)
    {
        var root = Root(c);
        var m = Authorized(c, root, true);
        if (m == null) return;
        var code = m.code;
        int idx;
        if (!int.TryParse(c.Request["file"], out idx) || idx < 0 || idx >= m.files.Count) { Fail(c, 404, "File not found"); return; }
        var f = m.files[idx];
        if (f.scan == "threat") { Fail(c, 403, "Blocked: Microsoft Defender detected a threat in this file."); return; }
        if (f.scan == "pending" || f.scan == "scanning") { Fail(c, 409, "Security scan still running, please wait."); return; }
        var path = Path.Combine(root, code, idx + ".bin");
        if (!File.Exists(path)) { Fail(c, 410, "File was removed."); return; }
        c.Response.BufferOutput = false;
        c.Response.ContentType = "application/octet-stream";
        c.Response.AddHeader("Content-Disposition", "attachment; filename*=UTF-8''" + Uri.EscapeDataString(f.name));
        lock (Lock) { var mm = Load(root, code); if (mm != null) { mm.downloads++; Save(root, mm); } }
        c.Response.TransmitFile(path);
    }

    // ---------- Microsoft Defender scanning ----------
    static string ScannerPath()
    {
        var candidates = new List<string>();
        var platform = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), @"Microsoft\Windows Defender\Platform");
        try { if (Directory.Exists(platform)) candidates.AddRange(Directory.GetDirectories(platform).OrderByDescending(d => d).Select(d => Path.Combine(d, "MpCmdRun.exe"))); } catch { }
        candidates.Add(Path.Combine(Environment.GetEnvironmentVariable("ProgramW6432") ?? @"C:\Program Files", @"Windows Defender\MpCmdRun.exe"));
        candidates.Add(@"C:\Program Files\Windows Defender\MpCmdRun.exe");
        return candidates.FirstOrDefault(File.Exists);
    }

    static void SetScan(string root, string code, int i, string status, string detail)
    {
        lock (Lock)
        {
            var m = Load(root, code); if (m == null) return;
            m.files[i].scan = status; m.files[i].scanDetail = detail;
            Save(root, m);
        }
    }

    static void ScanAll(string root, string code)
    {
        var m = Load(root, code); if (m == null) return;
        var exe = ScannerPath();
        for (int i = 0; i < m.files.Count; i++)
        {
            var path = Path.Combine(root, code, i + ".bin");
            if (exe == null) { SetScan(root, code, i, "skipped", "Microsoft Defender not found on server"); continue; }
            SetScan(root, code, i, "scanning", null);
            try
            {
                if (!File.Exists(path)) { SetScan(root, code, i, "threat", "Removed by antivirus real-time protection"); continue; }
                var psi = new ProcessStartInfo(exe, "-Scan -ScanType 3 -DisableRemediation -File \"" + path + "\"")
                { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
                using (var p = Process.Start(psi))
                {
                    var outTask = p.StandardOutput.ReadToEndAsync();
                    p.StandardError.ReadToEndAsync();
                    if (!p.WaitForExit((int)ScanTimeout.TotalMilliseconds)) { try { p.Kill(); } catch { } SetScan(root, code, i, "skipped", "Scan timed out"); continue; }
                    var output = outTask.Result;
                    if (p.ExitCode == 0) SetScan(root, code, i, "clean", "Microsoft Defender: no threats found");
                    else if (p.ExitCode == 2 || output.IndexOf("Threat", StringComparison.OrdinalIgnoreCase) >= 0 && output.IndexOf("found no threats", StringComparison.OrdinalIgnoreCase) < 0)
                    {
                        try { File.Delete(path); } catch { }
                        var line = output.Split('\n').FirstOrDefault(l => l.IndexOf("Threat", StringComparison.OrdinalIgnoreCase) >= 0);
                        SetScan(root, code, i, "threat", (line ?? "Threat detected").Trim());
                    }
                    else SetScan(root, code, i, "skipped", "Scanner unavailable (code " + p.ExitCode + ")");
                }
            }
            catch (Exception ex)
            {
                if (!File.Exists(path)) SetScan(root, code, i, "threat", "Removed by antivirus real-time protection");
                else SetScan(root, code, i, "skipped", "Scan could not run: " + ex.Message);
            }
        }
    }
}
