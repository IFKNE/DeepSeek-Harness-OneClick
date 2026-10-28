using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

public static class LauncherCore
{
    private static readonly Regex StartupUrlPattern = new Regex(
        @"dsh web:\s*(https?://127\.0\.0\.1:3080/\S*token=\S+)",
        RegexOptions.Compiled | RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);

    public static string ExtractStartupUrl(string line)
    {
        if (String.IsNullOrWhiteSpace(line))
        {
            return null;
        }

        Match match = StartupUrlPattern.Match(line);
        if (!match.Success)
        {
            return null;
        }

        Uri parsed;
        if (!Uri.TryCreate(match.Groups[1].Value, UriKind.Absolute, out parsed) ||
            parsed.Scheme != Uri.UriSchemeHttp ||
            parsed.Host != "127.0.0.1" ||
            parsed.Port != 3080)
        {
            return null;
        }

        return parsed.AbsoluteUri;
    }

    public static string BuildDshArguments(string dshPath, string logPath)
    {
        RequirePath(dshPath, "dshPath");
        RequirePath(logPath, "logPath");
        return "/d /s /c call \"" + dshPath + "\" web --no-open >> \"" + logPath + "\" 2>&1";
    }

    public static string BuildEdgeArguments(string url)
    {
        ValidateLoopbackUrl(url);
        return "--app=\"" + url + "\" --start-windowed";
    }

    public static bool IsHealthy(Uri uri, int timeoutMilliseconds)
    {
        if (uri == null)
        {
            throw new ArgumentNullException("uri");
        }

        try
        {
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(uri);
            request.Method = "GET";
            request.AllowAutoRedirect = false;
            request.Proxy = null;
            request.Timeout = timeoutMilliseconds;
            request.ReadWriteTimeout = timeoutMilliseconds;
            using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
            {
                int code = (int)response.StatusCode;
                return code >= 200 && code < 400;
            }
        }
        catch (WebException exception)
        {
            HttpWebResponse response = exception.Response as HttpWebResponse;
            if (response != null)
            {
                using (response)
                {
                    int code = (int)response.StatusCode;
                    return (code >= 200 && code < 400) || code == 401;
                }
            }

            return false;
        }
    }

    public static Process StartDsh(string dshPath, string homePath, string logPath)
    {
        RequirePath(dshPath, "dshPath");
        RequirePath(homePath, "homePath");
        RequirePath(logPath, "logPath");

        string logDirectory = Path.GetDirectoryName(logPath);
        if (!String.IsNullOrEmpty(logDirectory))
        {
            Directory.CreateDirectory(logDirectory);
        }

        ProcessStartInfo startInfo = new ProcessStartInfo();
        startInfo.FileName = Environment.GetEnvironmentVariable("ComSpec") ?? @"C:\Windows\System32\cmd.exe";
        startInfo.Arguments = BuildDshArguments(dshPath, logPath);
        startInfo.WorkingDirectory = homePath;
        startInfo.CreateNoWindow = true;
        startInfo.UseShellExecute = false;
        startInfo.WindowStyle = ProcessWindowStyle.Hidden;
        startInfo.EnvironmentVariables["DSH_HOME"] = homePath;

        Process process = Process.Start(startInfo);
        if (process == null)
        {
            throw new InvalidOperationException("无法创建 DeepSeek Harness 后台进程。");
        }

        return process;
    }

    public static string WaitForStartup(Process process, string logPath, Uri healthUri, TimeSpan timeout)
    {
        if (process == null)
        {
            throw new ArgumentNullException("process");
        }

        DateTime deadline = DateTime.UtcNow.Add(timeout);
        string startupUrl = null;
        while (DateTime.UtcNow < deadline)
        {
            string log = ReadSharedText(logPath);
            if (startupUrl == null)
            {
                startupUrl = ExtractStartupUrl(log);
            }

            if (startupUrl != null && IsHealthy(healthUri, 1000))
            {
                return startupUrl;
            }

            if (process.HasExited)
            {
                throw new InvalidOperationException(
                    "DeepSeek Harness 在完成启动前退出，退出代码 " + process.ExitCode + "。\r\n" + Tail(log, 1800));
            }

            Thread.Sleep(250);
        }

        throw new TimeoutException("等待 DeepSeek Harness 启动超时。\r\n" + Tail(ReadSharedText(logPath), 1800));
    }

    public static void OpenAppWindow(string url)
    {
        ValidateLoopbackUrl(url);
        string edge = FindEdge();
        if (edge != null)
        {
            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = edge;
            startInfo.Arguments = BuildEdgeArguments(url);
            startInfo.UseShellExecute = false;
            Process.Start(startInfo);
            return;
        }

        ProcessStartInfo fallback = new ProcessStartInfo();
        fallback.FileName = url;
        fallback.UseShellExecute = true;
        Process.Start(fallback);
    }

    public static string FindEdge()
    {
        string[] candidates = new string[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"Microsoft\Edge\Application\msedge.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"Microsoft\Edge\Application\msedge.exe")
        };

        foreach (string candidate in candidates)
        {
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return null;
    }

    private static void ValidateLoopbackUrl(string value)
    {
        Uri uri;
        if (!Uri.TryCreate(value, UriKind.Absolute, out uri) ||
            uri.Scheme != Uri.UriSchemeHttp ||
            uri.Host != "127.0.0.1" ||
            uri.Port != 3080)
        {
            throw new ArgumentException("只允许打开本机 DeepSeek Harness 地址。", "value");
        }
    }

    private static string ReadSharedText(string path)
    {
        if (!File.Exists(path))
        {
            return String.Empty;
        }

        try
        {
            using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (StreamReader reader = new StreamReader(stream, Encoding.Default, true))
            {
                return reader.ReadToEnd();
            }
        }
        catch (IOException)
        {
            return String.Empty;
        }
    }

    private static string Tail(string value, int length)
    {
        if (String.IsNullOrEmpty(value) || value.Length <= length)
        {
            return value ?? String.Empty;
        }

        return value.Substring(value.Length - length);
    }

    private static void RequirePath(string value, string name)
    {
        if (String.IsNullOrWhiteSpace(value) || value.IndexOf('"') >= 0 || value.IndexOf('\r') >= 0 || value.IndexOf('\n') >= 0)
        {
            throw new ArgumentException("路径无效。", name);
        }
    }
}
