<%@ WebHandler Language="C#" Class="TransferHandler" %>
using System;
using System.IO;
using System.Net;
using System.Web;
using System.Linq;
using System.Text;
using System.Threading;
using System.Diagnostics;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Web.Configuration;
using System.Web.Script.Serialization;

// SendAnywhere LAN API - no database. All state is JSON under iis-app\App_Data:
//   App_Data\boxes\<6-digit code>\meta.json + <fileId>.bin   (quick sends and user folders)
//   App_Data\accounts\users.json, settings.json, secret.key
// Quick sends and user files live at most 60 minutes (admin can change the user limit; admin's own files can live longer).
// Every file is scanned with Microsoft Defender for information only; downloads are never blocked.
public class TransferHandler : IHttpHandler
{
    const long MaxFileSize = 50L * 1024 * 1024 * 1024;   // 50 GB per file
    const int MaxFilesPerUpload = 500;
    const int AdminMaxMinutes = 10 * 365 * 24 * 60;      // 10 years
    static readonly TimeSpan ScanTimeout = TimeSpan.FromMinutes(30);
    static readonly TimeSpan SessionLife = TimeSpan.FromDays(7);
    static readonly object Lock = new object();
    static readonly object UserLock = new object();
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
    static readonly Dictionary<string, KeyValuePair<int, DateTime>> Fails = new Dictionary<string, KeyValuePair<int, DateTime>>();
    static readonly HashSet<string> RiskyExt = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        { ".exe",".msi",".bat",".cmd",".com",".scr",".ps1",".vbs",".js",".jse",".wsf",".hta",".jar",".dll",".lnk",".reg",".pif",".cpl" };
    static Timer sweeper;
    static string dataRoot;

    public bool IsReusable { get { return true; } }

    // ---------- models ----------
    public class FileMeta
    {
        public int id; public string name; public long size; public bool complete; public string scan; public string scanDetail; public bool risky;
        public DateTime uploaded; public DateTime expires; public bool deleteAfterDownload; public DateTime? downloadedAt; public int downloads;
    }
    public class Box
    {
        public string code; public string kind; public string name; public string ownerUser; public string ownerToken; public string pinHash;
        public DateTime created; public DateTime? expires; public int nextId; public List<FileMeta> files = new List<FileMeta>();
    }
    public class User
    {
        public string name; public string hash; public string salt; public string recHash; public string recSalt;
        public bool admin; public DateTime created; public string stamp; public DateTime? lastLogin;
        public string mobile; public string secQuestion; public string secHash; public string secSalt; public int failCount; public bool locked;
    }
    public class Settings { public int userMaxMinutes = 60; public bool allowSignup = true; }
    public class Req
    {
        public string code; public string name; public string password; public string newPassword; public string username; public string recoveryKey;
        public string pin; public int minutes; public bool deleteAfterDownload; public List<FileMeta> files; public List<int> ids;
        public int userMaxMinutes; public bool allowSignup;
        public string mobile; public string secQuestion; public string secAnswer; public string method; public bool admin;
        public string path; public string target; public long size; public string token; public bool recursive;
    }

    // ---------- paths ----------
    static string Data(HttpContext c)
    {
        if (dataRoot == null)
        {
            var p = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(c.Request.PhysicalPath), "..", "App_Data"));
            Directory.CreateDirectory(Path.Combine(p, "boxes"));
            Directory.CreateDirectory(Path.Combine(p, "accounts"));
            dataRoot = p;
            lock (Lock) { if (sweeper == null) sweeper = new Timer(_ => { try { Cleanup(); } catch { } }, null, 5000, 60000); }
        }
        return dataRoot;
    }
    static string Boxes { get { return Path.Combine(dataRoot, "boxes"); } }
    static string Accounts { get { return Path.Combine(dataRoot, "accounts"); } }

    // ---------- entry ----------
    public void ProcessRequest(HttpContext c)
    {
        var res = c.Response;
        res.Cache.SetCacheability(HttpCacheability.NoCache);
        res.AddHeader("X-Content-Type-Options", "nosniff");
        res.AddHeader("X-Frame-Options", "DENY");
        res.AddHeader("Referrer-Policy", "no-referrer");
        Data(c);
        if (!IsLocalClient(c.Request))
        {
            // Internet access (port forwarding) is OFF by default. When enabled in web.config it always needs the AccessKey.
            var allow = string.Equals(WebConfigurationManager.AppSettings["AllowInternet"], "true", StringComparison.OrdinalIgnoreCase);
            var key = WebConfigurationManager.AppSettings["AccessKey"] ?? "";
            var given = c.Request.Headers["X-Access-Key"] ?? c.Request.QueryString["ak"] ?? "";
            if (!allow || key.Length < 8) { Fail(c, 403, "Only devices on the local network can use this server."); return; }
            if (Blocked(c)) { Fail(c, 429, "Too many attempts. Try again in 15 minutes."); return; }
            if (!SafeEquals(given, key)) { AddFail(c); Fail(c, 403, "ACCESS_KEY"); return; }
        }
        try
        {
            var action = (c.Request["action"] ?? "").ToLowerInvariant();
            if (c.Request.HttpMethod == "POST" && action != "chunk" && c.Request.Headers["X-SA"] != "1")
                throw new HttpException(400, "Bad request");   // CSRF guard: browsers cannot send custom headers cross-site
            switch (action)
            {
                case "ping": Ping(c); break;
                // quick send + folder uploads
                case "init": Post(c); Init(c); break;
                case "chunk": Post(c); Chunk(c); break;
                case "complete": Post(c); Complete(c); break;
                case "info": Info(c); break;
                case "download": Download(c); break;
                case "delete": Post(c); DeleteBox(c); break;
                // accounts
                case "me": Me(c); break;
                case "setup-admin": Post(c); SetupAdmin(c); break;
                case "signup": Post(c); Signup(c); break;
                case "login": Post(c); Login(c); break;
                case "logout": Post(c); SetSession(c, null); Send(c, new { ok = true }); break;
                case "change-password": Post(c); ChangePassword(c); break;
                case "recover": Post(c); Recover(c); break;
                // folders
                case "folders": Folders(c); break;
                case "folder-create": Post(c); FolderCreate(c); break;
                case "folder-update": Post(c); FolderUpdate(c); break;
                case "folder-delete": Post(c); FolderDelete(c); break;
                case "file-delete": Post(c); FileDelete(c); break;
                // admin
                case "admin-overview": AdminOverview(c); break;
                case "admin-settings": Post(c); AdminSettings(c); break;
                case "admin-reset-user": Post(c); AdminResetUser(c); break;
                case "admin-delete-user": Post(c); AdminDeleteUser(c); break;
                case "admin-toggle-admin": Post(c); AdminToggle(c); break;
                case "admin-create-user": Post(c); AdminCreateUser(c); break;
                case "admin-set-mobile": Post(c); AdminSetMobile(c); break;
                case "admin-shares": AdminShares(c); break;
                case "admin-delete-share": Post(c); AdminDeleteShare(c); break;
                case "profile": Post(c); Profile(c); break;
                case "recover-options": Post(c); RecoverOptions(c); break;
                // server file manager (admin only)
                case "fs-list": FsList(c); break;
                case "fs-download": FsDownload(c); break;
                case "fs-mkdir": Post(c); FsMkdir(c); break;
                case "fs-rename": Post(c); FsRename(c); break;
                case "fs-delete": Post(c); FsDelete(c); break;
                case "fs-upload-init": Post(c); FsUploadInit(c); break;
                case "fs-chunk": Post(c); FsChunk(c); break;
                case "fs-upload-done": Post(c); FsUploadDone(c); break;
                default: Fail(c, 400, "Unknown action"); break;
            }
        }
        catch (HttpException ex) { Fail(c, ex.GetHttpCode(), ex.Message); }
        catch (Exception ex) { Fail(c, 500, ex.Message); }
    }

    // ---------- helpers ----------
    static void Post(HttpContext c) { if (c.Request.HttpMethod != "POST") throw new HttpException(405, "POST required"); }
    static void Send(HttpContext c, object o) { c.Response.ContentType = "application/json"; c.Response.Write(Json.Serialize(o)); }
    static void Fail(HttpContext c, int status, string msg)
    {
        c.Response.Clear(); c.Response.StatusCode = status; c.Response.TrySkipIisCustomErrors = true;
        Send(c, new { error = msg });
    }
    static HttpException Err(int code, string msg) { return new HttpException(code, msg); }
    static Req Body(HttpContext c)
    {
        using (var r = new StreamReader(c.Request.InputStream, Encoding.UTF8))
        {
            var t = r.ReadToEnd();
            return string.IsNullOrWhiteSpace(t) ? new Req() : (Json.Deserialize<Req>(t) ?? new Req());
        }
    }
    static string CleanCode(string code)
    {
        code = (code ?? "").Trim();
        return code.Length == 6 && code.All(ch => ch >= '0' && ch <= '9') ? code : null;
    }
    static string CleanName(string n, string fallback)
    {
        n = Path.GetFileName((n ?? "").Replace('/', '\\'));
        foreach (var ch in Path.GetInvalidFileNameChars()) n = n.Replace(ch, '_');
        n = n.Trim();
        if (n.Length > 200) n = n.Substring(0, 200);
        return n.Length == 0 ? fallback : n;
    }
    static void WriteJson(string file, object o)
    {
        File.WriteAllText(file + ".tmp", Json.Serialize(o));
        if (File.Exists(file)) File.Replace(file + ".tmp", file, null); else File.Move(file + ".tmp", file);
    }

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

    // ---------- brute-force protection ----------
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
    static void Guard(HttpContext c) { if (Blocked(c)) throw Err(429, "Too many wrong attempts. Try again in 15 minutes."); }

    // ---------- crypto ----------
    static byte[] secret;
    static byte[] Secret()
    {
        if (secret != null) return secret;
        lock (UserLock)
        {
            var f = Path.Combine(Accounts, "secret.key");
            if (!File.Exists(f)) { var b = new byte[32]; using (var r = RandomNumberGenerator.Create()) r.GetBytes(b); File.WriteAllBytes(f, b); }
            secret = File.ReadAllBytes(f);
        }
        return secret;
    }
    static string Hmac(string s) { using (var h = new HMACSHA256(Secret())) return B64(h.ComputeHash(Encoding.UTF8.GetBytes(s))); }
    static string B64(byte[] b) { return Convert.ToBase64String(b).TrimEnd('=').Replace('+', '-').Replace('/', '_'); }
    static string RandomToken(int bytes) { var b = new byte[bytes]; using (var r = RandomNumberGenerator.Create()) r.GetBytes(b); return B64(b); }
    static string RandomDigits(int n)
    {
        var b = new byte[n * 4]; using (var r = RandomNumberGenerator.Create()) r.GetBytes(b);
        var sb = new StringBuilder();
        for (int i = 0; i < n; i++) sb.Append((char)('0' + (BitConverter.ToUInt32(b, i * 4) % 10)));
        return sb.ToString();
    }
    static string Pbkdf2(string pass, string salt)
    {
        using (var k = new Rfc2898DeriveBytes(pass ?? "", Convert.FromBase64String(salt), 100000)) return Convert.ToBase64String(k.GetBytes(32));
    }
    static string NewSalt() { var b = new byte[16]; using (var r = RandomNumberGenerator.Create()) r.GetBytes(b); return Convert.ToBase64String(b); }
    static bool SafeEquals(string a, string b)
    {
        if (a == null || b == null) return false;
        int diff = a.Length ^ b.Length;
        for (int i = 0; i < Math.Min(a.Length, b.Length); i++) diff |= a[i] ^ b[i];
        return diff == 0;
    }
    static string PinHash(string code, string pin) { return Hmac("pin|" + code + "|" + pin); }

    // ---------- users & settings ----------
    static Dictionary<string, User> LoadUsers()
    {
        var f = Path.Combine(Accounts, "users.json");
        return File.Exists(f) ? Json.Deserialize<Dictionary<string, User>>(File.ReadAllText(f)) ?? new Dictionary<string, User>() : new Dictionary<string, User>();
    }
    static void SaveUsers(Dictionary<string, User> u) { WriteJson(Path.Combine(Accounts, "users.json"), u); }
    static Settings LoadSettings()
    {
        var f = Path.Combine(Accounts, "settings.json");
        try { if (File.Exists(f)) return Json.Deserialize<Settings>(File.ReadAllText(f)) ?? new Settings(); } catch { }
        return new Settings();
    }
    static string CleanUser(string u)
    {
        u = (u ?? "").Trim().ToLowerInvariant();
        if (u.Length < 3 || u.Length > 32 || !u.All(ch => char.IsLetterOrDigit(ch) && ch < 128 || ch == '_' || ch == '.' || ch == '-'))
            throw Err(400, "Username: 3-32 characters, letters, numbers, _ . -");
        return u;
    }
    static void CheckPassword(string p) { if (p == null || p.Length < 6 || p.Length > 128) throw Err(400, "Password must be at least 6 characters."); }
    static string NewRecoveryKey() { var d = RandomDigits(16); return d.Substring(0, 4) + "-" + d.Substring(4, 4) + "-" + d.Substring(8, 4) + "-" + d.Substring(12, 4); }

    // ---------- sessions (signed cookie, no server storage) ----------
    const string Cookie = "sa_session";
    static void SetSession(HttpContext c, User u)
    {
        string val = "", extra = "; Max-Age=0";
        if (u != null)
        {
            var exp = DateTime.UtcNow.Add(SessionLife).Ticks.ToString();
            var payload = u.name + "|" + u.stamp + "|" + exp;
            val = B64(Encoding.UTF8.GetBytes(payload)) + "." + Hmac("session|" + payload);
            extra = "; Max-Age=" + (int)SessionLife.TotalSeconds;
        }
        c.Response.AddHeader("Set-Cookie", Cookie + "=" + val + "; Path=/; HttpOnly; SameSite=Strict" + extra);
    }
    static User Current(HttpContext c)
    {
        var ck = c.Request.Cookies[Cookie];
        if (ck == null || string.IsNullOrEmpty(ck.Value)) return null;
        var parts = ck.Value.Split('.');
        if (parts.Length != 2) return null;
        string payload;
        try { var s = parts[0].Replace('-', '+').Replace('_', '/'); s = s.PadRight(s.Length + (4 - s.Length % 4) % 4, '='); payload = Encoding.UTF8.GetString(Convert.FromBase64String(s)); }
        catch { return null; }
        if (!SafeEquals(Hmac("session|" + payload), parts[1])) return null;
        var p = payload.Split('|');
        long t;
        if (p.Length != 3 || !long.TryParse(p[2], out t) || new DateTime(t) < DateTime.UtcNow) return null;
        User u;
        lock (UserLock) { var all = LoadUsers(); if (!all.TryGetValue(p[0], out u)) return null; }
        return SafeEquals(u.stamp, p[1]) ? u : null;
    }
    static User RequireUser(HttpContext c) { var u = Current(c); if (u == null) throw Err(403, "LOGIN_REQUIRED"); return u; }
    static User RequireAdmin(HttpContext c) { var u = RequireUser(c); if (!u.admin) throw Err(403, "Admin only"); return u; }
    static int MaxMinutes(User u) { return u != null && u.admin ? AdminMaxMinutes : Math.Max(1, LoadSettings().userMaxMinutes); }

    // ---------- boxes ----------
    static Box LoadBox(string code)
    {
        if (code == null) return null;
        var f = Path.Combine(Boxes, code, "meta.json");
        if (!File.Exists(f)) return null;
        Box b;
        lock (Lock) b = Json.Deserialize<Box>(File.ReadAllText(f));
        if (b.expires.HasValue && DateTime.UtcNow > b.expires.Value) return null;
        return b;
    }
    static void SaveBox(Box b) { lock (Lock) WriteJson(Path.Combine(Boxes, b.code, "meta.json"), b); }
    static void Update(string code, Action<Box> change)
    {
        lock (Lock) { var b = LoadBox(code); if (b == null) return; change(b); SaveBox(b); }
    }
    static string NewBoxCode()
    {
        lock (Lock)
        {
            string code;
            do { code = RandomDigits(6); } while (code[0] == '0' || Directory.Exists(Path.Combine(Boxes, code)));
            Directory.CreateDirectory(Path.Combine(Boxes, code));
            return code;
        }
    }
    static string FilePath(string code, int id) { return Path.Combine(Boxes, code, id + ".bin"); }
    static bool Owns(HttpContext c, Box b, User u)
    {
        if (u != null && (u.admin || u.name == b.ownerUser)) return true;
        return b.ownerToken != null && SafeEquals(c.Request["owner"], b.ownerToken);
    }
    static bool Live(FileMeta f) { return f.complete && DateTime.UtcNow < f.expires && !(f.deleteAfterDownload && f.downloadedAt.HasValue); }

    // Deletes expired files, downloaded one-time files and empty/expired quick sends. Runs every minute.
    static void Cleanup()
    {
        if (dataRoot == null) return;
        foreach (var d in Directory.GetDirectories(Boxes))
        {
            try
            {
                var mf = Path.Combine(d, "meta.json");
                if (!File.Exists(mf)) { if (DateTime.UtcNow - Directory.GetCreationTimeUtc(d) > TimeSpan.FromHours(1)) Directory.Delete(d, true); continue; }
                lock (Lock)
                {
                    var b = Json.Deserialize<Box>(File.ReadAllText(mf));
                    bool boxExpired = b.expires.HasValue && DateTime.UtcNow > b.expires.Value;
                    bool changed = false;
                    foreach (var f in b.files.ToList())
                    {
                        bool remove = boxExpired || DateTime.UtcNow > f.expires
                            || (!f.complete && DateTime.UtcNow - f.uploaded > TimeSpan.FromHours(6))
                            || (f.deleteAfterDownload && f.downloadedAt.HasValue && DateTime.UtcNow - f.downloadedAt.Value > TimeSpan.FromSeconds(30));
                        if (!remove) continue;
                        var p = Path.Combine(d, f.id + ".bin");
                        try { if (File.Exists(p)) File.Delete(p); } catch { continue; }   // still being downloaded: retry next minute
                        if (remove) { b.files.Remove(f); changed = true; }
                    }
                    if (b.kind == "send" && (boxExpired || b.files.Count == 0)) { Directory.Delete(d, true); continue; }
                    if (changed) WriteJson(mf, b);
                }
            }
            catch { }
        }
    }

    // ---------- upload (quick send or into a folder) ----------
    static void Init(HttpContext c)
    {
        var u = Current(c);
        var req = Body(c);
        if (req.files == null || req.files.Count == 0) throw Err(400, "No files");
        if (req.files.Count > MaxFilesPerUpload) throw Err(400, "Too many files (max " + MaxFilesPerUpload + ")");
        if (req.files.Any(f => f.size < 0 || f.size > MaxFileSize)) throw Err(400, "Each file must be 50 GB or smaller.");
        long need = req.files.Sum(f => f.size);
        try
        {
            var drive = new DriveInfo(Path.GetPathRoot(dataRoot));
            if (drive.AvailableFreeSpace < need + (1L << 30)) throw Err(507, "Not enough free disk space on the server (" + (drive.AvailableFreeSpace >> 30) + " GB free).");
        }
        catch (HttpException) { throw; } catch { }

        int max = MaxMinutes(u);
        int minutes = req.minutes <= 0 ? Math.Min(60, max) : req.minutes;
        if (minutes > max) throw Err(400, "Maximum time allowed is " + FormatMinutes(max) + ".");
        var now = DateTime.UtcNow;
        Box b;
        var folderCode = CleanCode(req.code);
        if (folderCode != null)
        {
            b = LoadBox(folderCode);
            if (b == null || b.kind != "folder" || u == null || !(u.admin || u.name == b.ownerUser)) throw Err(404, "Folder not found");
        }
        else
        {
            var pin = (req.pin ?? "").Trim();
            if (pin.Length > 0 && (pin.Length < 4 || pin.Length > 32)) throw Err(400, "PIN must be 4-32 characters");
            var code = NewBoxCode();
            b = new Box { code = code, kind = "send", created = now, expires = now.AddMinutes(minutes), ownerToken = RandomToken(18), ownerUser = u == null ? null : u.name };
            if (pin.Length > 0) b.pinHash = PinHash(code, pin);
        }
        var ids = new List<int>();
        lock (Lock)
        {
            if (folderCode != null) b = LoadBox(folderCode);
            foreach (var f in req.files)
            {
                var name = CleanName(f.name, "file");
                var fm = new FileMeta
                {
                    id = b.nextId++, name = name, size = f.size, scan = "pending", risky = RiskyExt.Contains(Path.GetExtension(name)),
                    uploaded = now, expires = now.AddMinutes(minutes), deleteAfterDownload = b.kind == "send" ? req.deleteAfterDownload : false
                };
                using (var fs = new FileStream(FilePath(b.code, fm.id), FileMode.Create)) fs.SetLength(f.size);
                b.files.Add(fm); ids.Add(fm.id);
            }
            SaveBox(b);
        }
        Send(c, new { code = b.code, owner = b.kind == "send" ? b.ownerToken : null, ids, expires = now.AddMinutes(minutes).ToString("o") });
    }

    static void Chunk(HttpContext c)
    {
        var b = LoadBox(CleanCode(c.Request["code"]));
        if (b == null || !Owns(c, b, Current(c))) throw Err(404, "Transfer not found");
        int id; long offset;
        if (!int.TryParse(c.Request["file"], out id) || !long.TryParse(c.Request["offset"], out offset)) throw Err(400, "Bad chunk");
        var f = b.files.FirstOrDefault(x => x.id == id);
        if (f == null || f.complete || offset < 0 || offset > f.size) throw Err(400, "Bad chunk");

        var input = c.Request.GetBufferlessInputStream(true);
        using (var fs = new FileStream(FilePath(b.code, id), FileMode.Open, FileAccess.Write, FileShare.ReadWrite, 1 << 20))
        {
            fs.Seek(offset, SeekOrigin.Begin);
            var buf = new byte[1 << 20];
            int n; long written = 0;
            while ((n = input.Read(buf, 0, buf.Length)) > 0)
            {
                if (offset + written + n > f.size) throw Err(400, "Chunk overflow");
                fs.Write(buf, 0, n); written += n;
            }
        }
        Send(c, new { ok = true });
    }

    static void Complete(HttpContext c)
    {
        var req = Body(c);
        var code = CleanCode(c.Request["code"] ?? req.code);
        var b = LoadBox(code);
        if (b == null || !Owns(c, b, Current(c))) throw Err(404, "Transfer not found");
        var ids = (req.ids ?? new List<int>()).ToList();
        Update(code, bx => { foreach (var f in bx.files) if (ids.Contains(f.id) && !f.complete) f.complete = true; });
        ThreadPool.QueueUserWorkItem(_ => ScanFiles(code, ids));
        Send(c, OwnerView(LoadBox(code)));
    }

    // ---------- receive ----------
    static object PublicFile(FileMeta f) { return new { f.id, f.name, f.size, f.scan, f.scanDetail, f.risky, expires = f.expires.ToString("o"), f.deleteAfterDownload }; }
    static object OwnerView(Box b)
    {
        if (b == null) return new { gone = true };
        return new
        {
            b.code, b.kind, b.name, locked = b.pinHash != null, expires = b.expires.HasValue ? b.expires.Value.ToString("o") : null,
            created = b.created.ToString("o"),
            files = b.files.Where(f => f.complete).Select(f => new { f.id, f.name, f.size, f.scan, f.scanDetail, f.risky, expires = f.expires.ToString("o"), f.downloads, f.deleteAfterDownload, downloaded = f.downloadedAt.HasValue })
        };
    }

    // Lookup by code with brute-force protection and PIN / folder password check.
    static Box Authorized(HttpContext c)
    {
        Guard(c);
        var b = LoadBox(CleanCode(c.Request["code"]));
        var u = Current(c);
        if (b != null && Owns(c, b, u)) return b;
        if (b == null) { AddFail(c); throw Err(404, "Invalid or expired code"); }
        if (b.pinHash != null)
        {
            var pin = c.Request["pin"] ?? "";
            if (!SafeEquals(PinHash(b.code, pin), b.pinHash))
            {
                if (pin.Length > 0) AddFail(c);
                throw Err(403, "PIN_REQUIRED");
            }
        }
        return b;
    }

    static void Info(HttpContext c)
    {
        var b = Authorized(c);
        var live = b.files.Where(Live).ToList();
        if (b.kind == "send" && live.Count == 0 && b.files.All(f => f.complete)) throw Err(410, "These files were already downloaded or have expired.");
        Send(c, new
        {
            b.code, b.kind, name = b.name, owner = IsAdminName(b.ownerUser) ? "Administrator" : b.ownerUser, locked = b.pinHash != null,
            expires = b.expires.HasValue ? b.expires.Value.ToString("o") : null,
            files = b.files.Where(Live).Select(PublicFile)
        });
    }

    static void Download(HttpContext c)
    {
        var b = Authorized(c);
        int id;
        if (!int.TryParse(c.Request["file"], out id)) throw Err(404, "File not found");
        var f = b.files.FirstOrDefault(x => x.id == id);
        if (f == null || !Live(f)) throw Err(410, "This file was already downloaded or has expired.");
        var path = FilePath(b.code, id);
        if (!File.Exists(path)) throw Err(410, "File was removed.");
        Update(b.code, bx => { var x = bx.files.FirstOrDefault(y => y.id == id); if (x != null) { x.downloads++; if (x.deleteAfterDownload) x.downloadedAt = DateTime.UtcNow; } });
        c.Response.BufferOutput = false;
        c.Response.ContentType = "application/octet-stream";
        c.Response.AddHeader("Content-Disposition", "attachment; filename*=UTF-8''" + Uri.EscapeDataString(f.name));
        c.Response.TransmitFile(path);
    }

    static void DeleteBox(HttpContext c)
    {
        var code = CleanCode(c.Request["code"]);
        var b = LoadBox(code);
        if (b == null || b.kind != "send" || !Owns(c, b, Current(c))) throw Err(404, "Transfer not found");
        lock (Lock) try { Directory.Delete(Path.Combine(Boxes, code), true); } catch { }
        Send(c, new { ok = true });
    }

    static void Ping(HttpContext c)
    {
        long free = -1;
        try { free = new DriveInfo(Path.GetPathRoot(dataRoot)).AvailableFreeSpace; } catch { }
        Send(c, new { ok = true, scanner = ScannerPath() != null, freeSpace = free, maxFile = MaxFileSize, local = IsLocalClient(c.Request) });
    }

    static string FormatMinutes(int m)
    {
        if (m % (365 * 1440) == 0) return m / (365 * 1440) + " year(s)";
        if (m % 1440 == 0) return m / 1440 + " day(s)";
        if (m % 60 == 0) return m / 60 + " hour(s)";
        return m + " minute(s)";
    }

    // ---------- accounts ----------
    static object MeView(User u)
    {
        var s = LoadSettings();
        bool noAdmin; lock (UserLock) noAdmin = !LoadUsers().Values.Any(x => x.admin);
        return new
        {
            user = u == null ? null : u.name, admin = u != null && u.admin, needsAdminSetup = noAdmin,
            maxMinutes = MaxMinutes(u), userMaxMinutes = s.userMaxMinutes, allowSignup = s.allowSignup,
            mobile = u == null ? null : MaskMobile(u.mobile), secQuestion = u == null ? null : u.secQuestion
        };
    }
    static void Me(HttpContext c) { Send(c, MeView(Current(c))); }

    static User CreateUser(string name, string password, bool admin, out string recovery)
    {
        recovery = NewRecoveryKey();
        var u = new User { name = name, salt = NewSalt(), recSalt = NewSalt(), admin = admin, created = DateTime.UtcNow, stamp = RandomToken(12) };
        u.hash = Pbkdf2(password, u.salt); u.recHash = Pbkdf2(recovery, u.recSalt);
        return u;
    }

    static void SetupAdmin(HttpContext c)
    {
        var ip = IPAddress.Parse(c.Request.UserHostAddress);
        if (!IPAddress.IsLoopback(ip)) throw Err(403, "Create the admin account from the server PC itself (open http://localhost).");
        var req = Body(c);
        var name = CleanUser(req.username); CheckPassword(req.password);
        string rec; User u;
        lock (UserLock)
        {
            var all = LoadUsers();
            if (all.Values.Any(x => x.admin)) throw Err(409, "Admin account already exists.");
            if (all.ContainsKey(name)) throw Err(409, "Username already taken.");
            u = CreateUser(name, req.password, true, out rec);
            ApplySecurity(u, req.mobile, req.secQuestion, req.secAnswer, false);
            all[name] = u; SaveUsers(all);
        }
        SetSession(c, u);
        Send(c, new { ok = true, recoveryKey = rec, me = MeView(u) });
    }

    static void Signup(HttpContext c)
    {
        Guard(c);
        if (!LoadSettings().allowSignup) throw Err(403, "New sign-ups are disabled by the admin.");
        var req = Body(c);
        var name = CleanUser(req.username); CheckPassword(req.password);
        string rec; User u;
        lock (UserLock)
        {
            var all = LoadUsers();
            if (all.ContainsKey(name)) throw Err(409, "Username already taken.");
            if (all.Count >= 5000) throw Err(507, "User limit reached.");
            u = CreateUser(name, req.password, false, out rec);
            ApplySecurity(u, req.mobile, req.secQuestion, req.secAnswer, false);
            all[name] = u; SaveUsers(all);
        }
        AddFail(c); // sign-ups count toward the per-IP limit to stop mass account creation
        SetSession(c, u);
        Send(c, new { ok = true, recoveryKey = rec, me = MeView(u) });
    }

    static void Login(HttpContext c)
    {
        Guard(c);
        var req = Body(c);
        var name = (req.username ?? "").Trim().ToLowerInvariant();
        User u;
        lock (UserLock)
        {
            var all = LoadUsers();
            if (!all.TryGetValue(name, out u)) { AddFail(c); throw Err(403, "Wrong username or password."); }
            if (u.locked) throw Err(403, "ACCOUNT_LOCKED");
            if (!SafeEquals(Pbkdf2(req.password, u.salt), u.hash))
            {
                AddFail(c);
                u.failCount++;
                if (u.failCount >= MaxWrongPasswords) { u.locked = true; SaveUsers(all); throw Err(403, "ACCOUNT_LOCKED"); }
                SaveUsers(all);
                throw Err(403, "Wrong username or password. " + (MaxWrongPasswords - u.failCount) + " attempt(s) left before the account is locked.");
            }
            u.failCount = 0; u.lastLogin = DateTime.UtcNow; SaveUsers(all);
        }
        SetSession(c, u);
        Send(c, new { ok = true, me = MeView(u) });
    }

    static void ChangePassword(HttpContext c)
    {
        var me = RequireUser(c);
        var req = Body(c);
        CheckPassword(req.newPassword);
        User u;
        lock (UserLock)
        {
            var all = LoadUsers(); u = all[me.name];
            if (!SafeEquals(Pbkdf2(req.password, u.salt), u.hash)) { AddFail(c); throw Err(403, "Current password is wrong."); }
            u.salt = NewSalt(); u.hash = Pbkdf2(req.newPassword, u.salt); u.stamp = RandomToken(12);   // logs out other devices
            SaveUsers(all);
        }
        SetSession(c, u);
        Send(c, new { ok = true });
    }

    const int MaxWrongPasswords = 10;
    static string NormMobile(string m) { return new string((m ?? "").Where(char.IsDigit).ToArray()); }
    static bool SameMobile(string a, string b)
    {
        a = NormMobile(a); b = NormMobile(b);
        if (a.Length < 10 || b.Length < 10) return false;
        return a.Substring(a.Length - 10) == b.Substring(b.Length - 10);   // ignore country code
    }
    static string MaskMobile(string m) { m = NormMobile(m); return m.Length < 4 ? (m.Length == 0 ? null : "****") : new string('*', m.Length - 4) + m.Substring(m.Length - 4); }
    static string NormAnswer(string a) { return string.Join(" ", (a ?? "").Trim().ToLowerInvariant().Split((char[])null, StringSplitOptions.RemoveEmptyEntries)); }

    // Sets mobile number + security question/answer. Used together as the second way to reset a password.
    static void ApplySecurity(User u, string mobile, string q, string a, bool required)
    {
        var m = NormMobile(mobile);
        if (m.Length > 0 && (m.Length < 10 || m.Length > 15)) throw Err(400, "Mobile number must have 10-15 digits.");
        if (m.Length > 0) u.mobile = m;
        if (!string.IsNullOrWhiteSpace(q) || !string.IsNullOrWhiteSpace(a))
        {
            if (string.IsNullOrWhiteSpace(q) || q.Trim().Length > 120) throw Err(400, "Choose a security question.");
            if (NormAnswer(a).Length < 2) throw Err(400, "Security answer is too short.");
            u.secQuestion = q.Trim(); u.secSalt = NewSalt(); u.secHash = Pbkdf2(NormAnswer(a), u.secSalt);
        }
        else if (required && u.secHash == null) throw Err(400, "Set a security question and answer.");
    }

    static void Profile(HttpContext c)
    {
        var me = RequireUser(c);
        var req = Body(c);
        lock (UserLock)
        {
            var all = LoadUsers(); var u = all[me.name];
            if (!SafeEquals(Pbkdf2(req.password, u.salt), u.hash)) { AddFail(c); throw Err(403, "Current password is wrong."); }
            ApplySecurity(u, req.mobile, req.secQuestion, req.secAnswer, false);
            SaveUsers(all);
            Send(c, new { ok = true, me = MeView(u) });
        }
    }

    // Tells the reset page which methods exist for a user (never reveals whether a user is an admin).
    static void RecoverOptions(HttpContext c)
    {
        Guard(c);
        var name = (Body(c).username ?? "").Trim().ToLowerInvariant();
        User u; lock (UserLock) LoadUsers().TryGetValue(name, out u);
        bool local = IPAddress.IsLoopback(IPAddress.Parse(c.Request.UserHostAddress)) && EmergencyAllowed();
        Send(c, new
        {
            recoveryKey = true,
            mobile = u != null && u.mobile != null && u.secHash != null,
            question = u != null && u.secHash != null ? u.secQuestion : "What is your favourite colour?",
            emergency = local
        });
    }

    // Emergency reset: someone ran reset-password.bat as Windows administrator on the server PC in the last 15 minutes.
    static bool EmergencyAllowed()
    {
        var f = Path.Combine(Accounts, "reset.allow");
        return File.Exists(f) && DateTime.UtcNow - File.GetLastWriteTimeUtc(f) < TimeSpan.FromMinutes(15);
    }

    static void Recover(HttpContext c)
    {
        Guard(c);
        var req = Body(c);
        var name = (req.username ?? "").Trim().ToLowerInvariant();
        CheckPassword(req.newPassword);
        string rec; User u;
        lock (UserLock)
        {
            var all = LoadUsers();
            bool ok = all.TryGetValue(name, out u);
            if (ok)
            {
                switch (req.method)
                {
                    case "mobile":
                        ok = u.mobile != null && u.secHash != null && SameMobile(req.mobile, u.mobile) && SafeEquals(Pbkdf2(NormAnswer(req.secAnswer), u.secSalt), u.secHash);
                        break;
                    case "emergency":
                        ok = IPAddress.IsLoopback(IPAddress.Parse(c.Request.UserHostAddress)) && EmergencyAllowed();
                        break;
                    default:
                        ok = SafeEquals(Pbkdf2((req.recoveryKey ?? "").Trim(), u.recSalt), u.recHash);
                        break;
                }
            }
            if (!ok) { AddFail(c); throw Err(403, "The details do not match. Check them and try again."); }
            rec = NewRecoveryKey();
            u.salt = NewSalt(); u.hash = Pbkdf2(req.newPassword, u.salt); u.recSalt = NewSalt(); u.recHash = Pbkdf2(rec, u.recSalt); u.stamp = RandomToken(12);
            u.failCount = 0; u.locked = false;
            SaveUsers(all);
            if (req.method == "emergency") try { File.Delete(Path.Combine(Accounts, "reset.allow")); } catch { }
        }
        SetSession(c, u);
        Send(c, new { ok = true, recoveryKey = rec, me = MeView(u) });
    }

    // ---------- folders ----------
    static IEnumerable<Box> AllBoxes()
    {
        foreach (var d in Directory.GetDirectories(Boxes))
        {
            Box b = null;
            try { b = LoadBox(Path.GetFileName(d)); } catch { }
            if (b != null) yield return b;
        }
    }

    static void Folders(HttpContext c)
    {
        var u = RequireUser(c);
        var list = AllBoxes().Where(b => b.kind == "folder" && b.ownerUser == u.name).OrderBy(b => b.created).Select(OwnerView).ToList();
        var sends = AllBoxes().Where(b => b.kind == "send" && b.ownerUser == u.name).OrderByDescending(b => b.created).Select(OwnerView).ToList();
        Send(c, new { folders = list, sends });
    }

    static Box OwnFolder(HttpContext c, User u, string code)
    {
        var b = LoadBox(CleanCode(code));
        if (b == null || b.kind != "folder" || !(u.admin || b.ownerUser == u.name)) throw Err(404, "Folder not found");
        return b;
    }

    static void FolderCreate(HttpContext c)
    {
        var u = RequireUser(c);
        var req = Body(c);
        var name = (req.name ?? "").Trim();
        if (name.Length < 1 || name.Length > 60) throw Err(400, "Folder name: 1-60 characters.");
        var pass = req.password ?? "";
        if (pass.Length < 4 || pass.Length > 64) throw Err(400, "Folder password must be at least 4 characters.");
        if (AllBoxes().Count(b => b.kind == "folder" && b.ownerUser == u.name) >= 50) throw Err(400, "Maximum 50 folders per user.");
        var code = NewBoxCode();
        var box = new Box { code = code, kind = "folder", name = name, ownerUser = u.name, created = DateTime.UtcNow, pinHash = PinHash(code, pass) };
        SaveBox(box);
        Send(c, OwnerView(box));
    }

    static void FolderUpdate(HttpContext c)
    {
        var u = RequireUser(c);
        var req = Body(c);
        var b = OwnFolder(c, u, req.code);
        if (req.name != null) { var n = req.name.Trim(); if (n.Length < 1 || n.Length > 60) throw Err(400, "Folder name: 1-60 characters."); }
        if (req.password != null && (req.password.Length < 4 || req.password.Length > 64)) throw Err(400, "Folder password must be at least 4 characters.");
        Update(b.code, bx => { if (req.name != null) bx.name = req.name.Trim(); if (req.password != null) bx.pinHash = PinHash(bx.code, req.password); });
        Send(c, OwnerView(LoadBox(b.code)));
    }

    static void FolderDelete(HttpContext c)
    {
        var u = RequireUser(c);
        var b = OwnFolder(c, u, Body(c).code);
        lock (Lock) try { Directory.Delete(Path.Combine(Boxes, b.code), true); } catch { }
        Send(c, new { ok = true });
    }

    static void FileDelete(HttpContext c)
    {
        var req = Body(c);
        var b = LoadBox(CleanCode(req.code));
        if (b == null || !Owns(c, b, Current(c))) throw Err(404, "Not found");
        var ids = req.ids ?? new List<int>();
        Update(b.code, bx => { foreach (var f in bx.files.Where(f => ids.Contains(f.id)).ToList()) { try { File.Delete(FilePath(bx.code, f.id)); } catch { } bx.files.Remove(f); } });
        Send(c, new { ok = true });
    }

    // ---------- admin ----------
    static void AdminOverview(HttpContext c)
    {
        RequireAdmin(c);
        var boxes = AllBoxes().ToList();
        Dictionary<string, User> users; lock (UserLock) users = LoadUsers();
        long free = -1, total = -1;
        try { var d = new DriveInfo(Path.GetPathRoot(dataRoot)); free = d.AvailableFreeSpace; total = d.TotalSize; } catch { }
        Send(c, new
        {
            settings = LoadSettings(),
            disk = new { free, total, used = boxes.Sum(b => b.files.Sum(f => f.size)) },
            activeSends = boxes.Count(b => b.kind == "send"),
            files = boxes.Sum(b => b.files.Count),
            threats = boxes.Sum(b => b.files.Count(f => f.scan == "threat")),
            users = users.Values.OrderBy(x => x.name).Select(x => new
            {
                x.name, x.admin, mobile = x.mobile, x.locked, created = x.created.ToString("o"), lastLogin = x.lastLogin.HasValue ? x.lastLogin.Value.ToString("o") : null,
                folders = boxes.Count(b => b.kind == "folder" && b.ownerUser == x.name),
                storage = boxes.Where(b => b.ownerUser == x.name).Sum(b => b.files.Sum(f => f.size))
            })
        });
    }

    static void AdminSettings(HttpContext c)
    {
        RequireAdmin(c);
        var req = Body(c);
        if (req.userMaxMinutes < 1 || req.userMaxMinutes > AdminMaxMinutes) throw Err(400, "Invalid time limit.");
        var s = new Settings { userMaxMinutes = req.userMaxMinutes, allowSignup = req.allowSignup };
        lock (UserLock) WriteJson(Path.Combine(Accounts, "settings.json"), s);
        Send(c, new { ok = true, settings = s });
    }

    static void AdminResetUser(HttpContext c)
    {
        var me = RequireAdmin(c);
        var name = (Body(c).username ?? "").ToLowerInvariant();
        string temp = RandomDigits(4) + "-" + RandomToken(4);
        lock (UserLock)
        {
            var all = LoadUsers(); User u;
            if (!all.TryGetValue(name, out u)) throw Err(404, "User not found");
            u.salt = NewSalt(); u.hash = Pbkdf2(temp, u.salt); u.stamp = RandomToken(12); u.failCount = 0; u.locked = false;
            SaveUsers(all);
            if (name == me.name) SetSession(c, u);
        }
        Send(c, new { ok = true, tempPassword = temp });
    }

    static void AdminDeleteUser(HttpContext c)
    {
        var me = RequireAdmin(c);
        var name = (Body(c).username ?? "").ToLowerInvariant();
        if (name == me.name) throw Err(400, "You cannot delete your own account.");
        lock (UserLock) { var all = LoadUsers(); if (!all.Remove(name)) throw Err(404, "User not found"); SaveUsers(all); }
        foreach (var b in AllBoxes().Where(b => b.ownerUser == name).ToList())
            lock (Lock) try { Directory.Delete(Path.Combine(Boxes, b.code), true); } catch { }
        Send(c, new { ok = true });
    }

    static void AdminToggle(HttpContext c)
    {
        var me = RequireAdmin(c);
        var name = (Body(c).username ?? "").ToLowerInvariant();
        if (name == me.name) throw Err(400, "You cannot change your own admin rights.");
        lock (UserLock) { var all = LoadUsers(); User u; if (!all.TryGetValue(name, out u)) throw Err(404, "User not found"); u.admin = !u.admin; u.stamp = RandomToken(12); SaveUsers(all); }
        Send(c, new { ok = true });
    }

    // ---------- admin: users & shares ----------
    static bool IsAdminName(string n)
    {
        if (n == null) return false;
        User u; lock (UserLock) return LoadUsers().TryGetValue(n, out u) && u.admin;
    }

    static void AdminCreateUser(HttpContext c)
    {
        RequireAdmin(c);
        var req = Body(c);
        var name = CleanUser(req.username); CheckPassword(req.password);
        string rec;
        lock (UserLock)
        {
            var all = LoadUsers();
            if (all.ContainsKey(name)) throw Err(409, "Username already taken.");
            var u = CreateUser(name, req.password, req.admin, out rec);
            ApplySecurity(u, req.mobile, null, null, false);
            all[name] = u; SaveUsers(all);
        }
        Send(c, new { ok = true, recoveryKey = rec });
    }

    static void AdminSetMobile(HttpContext c)
    {
        RequireAdmin(c);
        var req = Body(c);
        var name = (req.username ?? "").ToLowerInvariant();
        lock (UserLock)
        {
            var all = LoadUsers(); User u;
            if (!all.TryGetValue(name, out u)) throw Err(404, "User not found");
            var m = NormMobile(req.mobile);
            if (m.Length == 0) u.mobile = null; else ApplySecurity(u, m, null, null, false);
            SaveUsers(all);
        }
        Send(c, new { ok = true });
    }

    static void AdminShares(HttpContext c)
    {
        RequireAdmin(c);
        Send(c, AllBoxes().OrderByDescending(b => b.created).Select(b => new
        {
            b.code, b.kind, b.name, owner = b.ownerUser ?? "guest", locked = b.pinHash != null,
            files = b.files.Count(f => f.complete), size = b.files.Sum(f => f.size),
            expires = b.files.Count == 0 ? null : b.files.Max(f => f.expires).ToString("o"), created = b.created.ToString("o")
        }));
    }

    static void AdminDeleteShare(HttpContext c)
    {
        RequireAdmin(c);
        var code = CleanCode(Body(c).code);
        if (code == null || !Directory.Exists(Path.Combine(Boxes, code))) throw Err(404, "Not found");
        lock (Lock) try { Directory.Delete(Path.Combine(Boxes, code), true); } catch { }
        Send(c, new { ok = true });
    }

    // ---------- server file manager (admin only) ----------
    // Lets an admin browse the server PC's drives from any LAN PC, download, upload, create, rename and delete.
    // What is reachable depends on the IIS app pool identity (setup-safe.bat can grant full access).
    class FsUpload { public string temp; public string final; public long size; public string user; public DateTime started; }
    static readonly Dictionary<string, FsUpload> FsUploads = new Dictionary<string, FsUpload>();

    static string FullPath(string p)
    {
        if (string.IsNullOrWhiteSpace(p)) throw Err(400, "Path required");
        p = p.Replace('/', '\\');
        if (p.StartsWith(@"\\")) throw Err(400, "Network paths are not allowed.");
        var full = Path.GetFullPath(p);
        if (!Path.IsPathRooted(full)) throw Err(400, "Invalid path");
        return full;
    }
    static string CheckChildName(string n)
    {
        n = (n ?? "").Trim();
        if (n.Length == 0 || n.Length > 200 || n == "." || n == ".." || n.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) throw Err(400, "Invalid name");
        return n;
    }

    static void FsList(HttpContext c)
    {
        RequireAdmin(c);
        var path = c.Request["path"];
        if (string.IsNullOrEmpty(path))
        {
            var drives = DriveInfo.GetDrives().Where(d => { try { return d.IsReady; } catch { return false; } }).Select(d => new
            {
                name = d.Name, label = SafeGet(() => d.VolumeLabel, ""), type = d.DriveType.ToString(),
                free = SafeGet(() => d.AvailableFreeSpace, -1L), total = SafeGet(() => d.TotalSize, -1L)
            });
            Send(c, new { path = "", drives }); return;
        }
        var full = FullPath(path);
        if (!Directory.Exists(full)) throw Err(404, "Folder not found");
        var di = new DirectoryInfo(full);
        var items = new List<object>();
        try
        {
            foreach (var e in di.EnumerateFileSystemInfos())
            {
                try
                {
                    if ((e.Attributes & (FileAttributes.System | FileAttributes.Hidden)) == (FileAttributes.System | FileAttributes.Hidden)) continue;
                    var isDir = (e.Attributes & FileAttributes.Directory) != 0;
                    items.Add(new { name = e.Name, dir = isDir, size = isDir ? -1 : ((FileInfo)e).Length, modified = e.LastWriteTimeUtc.ToString("o"), hidden = (e.Attributes & FileAttributes.Hidden) != 0 });
                    if (items.Count >= 5000) break;
                }
                catch { }
            }
        }
        catch (UnauthorizedAccessException) { throw Err(403, "Access denied to this folder. Run setup-safe.bat and allow full drive access for the admin."); }
        Send(c, new { path = full, parent = di.Parent == null ? "" : di.Parent.FullName, items });
    }
    static T SafeGet<T>(Func<T> f, T d) { try { return f(); } catch { return d; } }

    static void FsDownload(HttpContext c)
    {
        RequireAdmin(c);
        var full = FullPath(c.Request["path"]);
        if (!File.Exists(full)) throw Err(404, "File not found");
        c.Response.BufferOutput = false;
        c.Response.ContentType = "application/octet-stream";
        c.Response.AddHeader("Content-Disposition", "attachment; filename*=UTF-8''" + Uri.EscapeDataString(Path.GetFileName(full)));
        c.Response.TransmitFile(full);
    }

    static void FsMkdir(HttpContext c)
    {
        RequireAdmin(c);
        var req = Body(c);
        var dir = FullPath(req.path);
        var target = Path.Combine(dir, CheckChildName(req.name));
        if (Directory.Exists(target) || File.Exists(target)) throw Err(409, "Already exists");
        Directory.CreateDirectory(target);
        Send(c, new { ok = true });
    }

    static void FsRename(HttpContext c)
    {
        RequireAdmin(c);
        var req = Body(c);
        var full = FullPath(req.path);
        var target = Path.Combine(Path.GetDirectoryName(full), CheckChildName(req.name));
        if (Directory.Exists(target) || File.Exists(target)) throw Err(409, "A file or folder with that name already exists");
        if (Directory.Exists(full)) Directory.Move(full, target);
        else if (File.Exists(full)) File.Move(full, target);
        else throw Err(404, "Not found");
        Send(c, new { ok = true });
    }

    static void FsDelete(HttpContext c)
    {
        RequireAdmin(c);
        var req = Body(c);
        var full = FullPath(req.path);
        if (Path.GetPathRoot(full) == full) throw Err(400, "Drives cannot be deleted.");
        var win = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        if (full.StartsWith(win, StringComparison.OrdinalIgnoreCase) || full.StartsWith(dataRoot, StringComparison.OrdinalIgnoreCase)) throw Err(403, "This location is protected.");
        if (Directory.Exists(full))
        {
            if (!req.recursive && Directory.EnumerateFileSystemEntries(full).Any()) throw Err(409, "FOLDER_NOT_EMPTY");
            Directory.Delete(full, req.recursive);
        }
        else if (File.Exists(full)) File.Delete(full);
        else throw Err(404, "Not found");
        Send(c, new { ok = true });
    }

    static void FsUploadInit(HttpContext c)
    {
        var u = RequireAdmin(c);
        var req = Body(c);
        var dir = FullPath(req.path);
        if (!Directory.Exists(dir)) throw Err(404, "Folder not found");
        if (req.size < 0 || req.size > MaxFileSize) throw Err(400, "Each file must be 50 GB or smaller.");
        var name = CheckChildName(CleanName(req.name, "file"));
        var final = Path.Combine(dir, name);
        for (int i = 1; File.Exists(final) || Directory.Exists(final); i++)
            final = Path.Combine(dir, Path.GetFileNameWithoutExtension(name) + " (" + i + ")" + Path.GetExtension(name));
        var token = RandomToken(18);
        var temp = final + ".sa-uploading";
        try { using (var fs = new FileStream(temp, FileMode.Create)) fs.SetLength(req.size); }
        catch (UnauthorizedAccessException) { throw Err(403, "No permission to write in this folder. Run setup-safe.bat and allow full drive access."); }
        lock (FsUploads)
        {
            foreach (var k in FsUploads.Where(x => DateTime.UtcNow - x.Value.started > TimeSpan.FromHours(12)).Select(x => x.Key).ToList()) FsUploads.Remove(k);
            FsUploads[token] = new FsUpload { temp = temp, final = final, size = req.size, user = u.name, started = DateTime.UtcNow };
        }
        Send(c, new { token, name = Path.GetFileName(final) });
    }

    static FsUpload GetUpload(HttpContext c, User u, string token)
    {
        FsUpload up;
        lock (FsUploads) if (token == null || !FsUploads.TryGetValue(token, out up) || up.user != u.name) throw Err(404, "Upload not found");
        return up;
    }

    static void FsChunk(HttpContext c)
    {
        var u = RequireAdmin(c);
        var up = GetUpload(c, u, c.Request["token"]);
        long offset;
        if (!long.TryParse(c.Request["offset"], out offset) || offset < 0 || offset > up.size) throw Err(400, "Bad chunk");
        var input = c.Request.GetBufferlessInputStream(true);
        using (var fs = new FileStream(up.temp, FileMode.Open, FileAccess.Write, FileShare.ReadWrite, 1 << 20))
        {
            fs.Seek(offset, SeekOrigin.Begin);
            var buf = new byte[1 << 20]; int n; long written = 0;
            while ((n = input.Read(buf, 0, buf.Length)) > 0)
            {
                if (offset + written + n > up.size) throw Err(400, "Chunk overflow");
                fs.Write(buf, 0, n); written += n;
            }
        }
        Send(c, new { ok = true });
    }

    static void FsUploadDone(HttpContext c)
    {
        var u = RequireAdmin(c);
        var req = Body(c);
        var up = GetUpload(c, u, req.token);
        lock (FsUploads) FsUploads.Remove(req.token);
        if (req.recursive) { try { File.Delete(up.temp); } catch { } Send(c, new { ok = true }); return; }   // cancelled
        var final = up.final;
        for (int i = 1; File.Exists(final); i++)
            final = Path.Combine(Path.GetDirectoryName(up.final), Path.GetFileNameWithoutExtension(up.final) + " (" + i + ")" + Path.GetExtension(up.final));
        File.Move(up.temp, final);
        Send(c, new { ok = true, name = Path.GetFileName(final) });
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

    static void SetScan(string code, int id, string status, string detail)
    {
        Update(code, b => { var f = b.files.FirstOrDefault(x => x.id == id); if (f != null) { f.scan = status; f.scanDetail = detail; } });
    }

    static void ScanFiles(string code, List<int> ids)
    {
        var exe = ScannerPath();
        foreach (var id in ids)
        {
            var path = FilePath(code, id);
            if (exe == null) { SetScan(code, id, "skipped", "Microsoft Defender not found on server"); continue; }
            SetScan(code, id, "scanning", null);
            try
            {
                if (!File.Exists(path)) { SetScan(code, id, "skipped", "File not found for scanning"); continue; }
                var psi = new ProcessStartInfo(exe, "-Scan -ScanType 3 -DisableRemediation -File \"" + path + "\"")
                { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
                using (var p = Process.Start(psi))
                {
                    var outTask = p.StandardOutput.ReadToEndAsync();
                    p.StandardError.ReadToEndAsync();
                    if (!p.WaitForExit((int)ScanTimeout.TotalMilliseconds)) { try { p.Kill(); } catch { } SetScan(code, id, "skipped", "Scan timed out"); continue; }
                    var output = outTask.Result;
                    if (p.ExitCode == 0) SetScan(code, id, "clean", "Microsoft Defender: no threats found");
                    else if (p.ExitCode == 2 && output.IndexOf("no threats", StringComparison.OrdinalIgnoreCase) < 0 && output.IndexOf("Threat", StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        var line = output.Split('\n').FirstOrDefault(l => l.IndexOf("Threat", StringComparison.OrdinalIgnoreCase) >= 0);
                        SetScan(code, id, "threat", (line ?? "Threat detected").Trim());
                    }
                    else SetScan(code, id, "skipped", "Scanner unavailable (code " + p.ExitCode + ")");
                }
            }
            catch (Exception ex)
            {
                SetScan(code, id, "skipped", "Scan could not run: " + ex.Message);
            }
        }
    }
}
