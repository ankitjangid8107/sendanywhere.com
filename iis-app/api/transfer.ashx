<%@ WebHandler Language="C#" Class="TransferHandler" %>
using System;
using System.IO;
using System.Web;
using System.Linq;
using System.Collections.Generic;
using System.Web.Script.Serialization;

// Local-network file transfer API. No database: metadata is stored as JSON in App_Data.
public class TransferHandler : IHttpHandler
{
    const long MaxFileSize = 50L * 1024 * 1024 * 1024; // 50 GB per file
    static readonly TimeSpan Ttl = TimeSpan.FromHours(24);
    static readonly object Lock = new object();
    static readonly Random Rng = new Random();
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };

    public bool IsReusable { get { return true; } }

    static string Root(HttpContext c)
    {
        var p = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(c.Request.PhysicalPath), "..", "App_Data", "transfers"));
        Directory.CreateDirectory(p);
        return p;
    }

    public class FileMeta { public string name; public long size; public string type; }
    public class Meta { public string code; public DateTime created; public List<FileMeta> files; public bool complete; }

    public void ProcessRequest(HttpContext c)
    {
        c.Response.Cache.SetCacheability(HttpCacheability.NoCache);
        try
        {
            switch ((c.Request["action"] ?? "").ToLowerInvariant())
            {
                case "init": Init(c); break;
                case "chunk": Chunk(c); break;
                case "complete": Complete(c); break;
                case "info": Info(c); break;
                case "download": Download(c); break;
                default: Fail(c, 400, "Unknown action"); break;
            }
        }
        catch (Exception ex) { Fail(c, 500, ex.Message); }
    }

    static void Send(HttpContext c, object o)
    {
        c.Response.ContentType = "application/json";
        c.Response.Write(Json.Serialize(o));
    }

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

    static Meta Load(HttpContext c, string code)
    {
        if (code == null) return null;
        var f = Path.Combine(Root(c), code, "meta.json");
        if (!File.Exists(f)) return null;
        var m = Json.Deserialize<Meta>(File.ReadAllText(f));
        if (DateTime.UtcNow - m.created > Ttl) return null;
        return m;
    }

    static void Save(HttpContext c, Meta m)
    {
        File.WriteAllText(Path.Combine(Root(c), m.code, "meta.json"), Json.Serialize(m));
    }

    static void Cleanup(string root)
    {
        foreach (var d in Directory.GetDirectories(root))
        {
            try { if (DateTime.UtcNow - Directory.GetCreationTimeUtc(d) > Ttl) Directory.Delete(d, true); } catch { }
        }
    }

    // POST JSON {files:[{name,size,type}]} -> {code}
    static void Init(HttpContext c)
    {
        string body;
        using (var r = new StreamReader(c.Request.InputStream)) body = r.ReadToEnd();
        var req = Json.Deserialize<Meta>(body);
        if (req == null || req.files == null || req.files.Count == 0) { Fail(c, 400, "No files"); return; }
        var root = Root(c);
        Cleanup(root);

        string code;
        const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        lock (Lock)
        {
            do { code = new string(Enumerable.Range(0, 6).Select(_ => chars[Rng.Next(chars.Length)]).ToArray()); }
            while (Directory.Exists(Path.Combine(root, code)));
            Directory.CreateDirectory(Path.Combine(root, code));
        }

        var m = new Meta { code = code, created = DateTime.UtcNow, files = new List<FileMeta>() };
        for (int i = 0; i < req.files.Count; i++)
        {
            var f = req.files[i];
            if (f.size < 0 || f.size > MaxFileSize) { Fail(c, 400, "File too large: " + f.name); return; }
            var name = Path.GetFileName(f.name ?? "file");
            foreach (var ch in Path.GetInvalidFileNameChars()) name = name.Replace(ch, '_');
            m.files.Add(new FileMeta { name = name, size = f.size, type = f.type ?? "application/octet-stream" });
            using (var fs = new FileStream(Path.Combine(root, code, i + ".bin"), FileMode.Create)) fs.SetLength(f.size);
        }
        Save(c, m);
        Send(c, new { code });
    }

    // PUT raw bytes ?action=chunk&code=X&file=i&offset=n
    static void Chunk(HttpContext c)
    {
        var code = CleanCode(c.Request["code"]);
        var m = Load(c, code);
        if (m == null || m.complete) { Fail(c, 404, "Transfer not found"); return; }
        int idx = int.Parse(c.Request["file"]);
        long offset = long.Parse(c.Request["offset"]);
        if (idx < 0 || idx >= m.files.Count || offset < 0 || offset > m.files[idx].size) { Fail(c, 400, "Bad chunk"); return; }

        var path = Path.Combine(Root(c), code, idx + ".bin");
        var input = c.Request.GetBufferlessInputStream();
        using (var fs = new FileStream(path, FileMode.Open, FileAccess.Write, FileShare.ReadWrite, 1 << 20))
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
        var m = Load(c, CleanCode(c.Request["code"]));
        if (m == null) { Fail(c, 404, "Transfer not found"); return; }
        m.complete = true;
        Save(c, m);
        Send(c, new { ok = true });
    }

    static void Info(HttpContext c)
    {
        var m = Load(c, CleanCode(c.Request["code"]));
        if (m == null || !m.complete) { Fail(c, 404, "Invalid or expired code"); return; }
        Send(c, new { code = m.code, files = m.files, expires = m.created.Add(Ttl).ToString("o") });
    }

    // GET ?action=download&code=X&file=i  (streams via kernel-mode TransmitFile)
    static void Download(HttpContext c)
    {
        var code = CleanCode(c.Request["code"]);
        var m = Load(c, code);
        int idx;
        if (m == null || !m.complete || !int.TryParse(c.Request["file"], out idx) || idx < 0 || idx >= m.files.Count)
        { Fail(c, 404, "File not found"); return; }
        var f = m.files[idx];
        c.Response.BufferOutput = false;
        c.Response.ContentType = f.type;
        c.Response.AddHeader("Content-Disposition", "attachment; filename*=UTF-8''" + Uri.EscapeDataString(f.name));
        c.Response.TransmitFile(Path.Combine(Root(c), code, idx + ".bin"));
    }
}
