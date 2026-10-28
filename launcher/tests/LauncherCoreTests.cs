using System;
using System.Net;
using System.Net.Sockets;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;

internal static class LauncherCoreTests
{
    private static int failures;

    private static void Main()
    {
        TestExtractStartupUrl();
        TestBuildDshArguments();
        TestBuildEdgeArguments();
        TestHealthProbe();
        TestUnauthorizedMeansServerPresent();
        TestStartDshWithSpaces();

        if (failures != 0)
        {
            Console.Error.WriteLine("FAIL: " + failures + " assertion(s)");
            Environment.Exit(1);
        }

        Console.WriteLine("PASS: LauncherCoreTests");
    }

    private static void TestExtractStartupUrl()
    {
        AssertEqual(
            "http://127.0.0.1:3080/?token=abc-123",
            LauncherCore.ExtractStartupUrl("dsh web: http://127.0.0.1:3080/?token=abc-123"),
            "extracts tokenized startup URL");
        AssertEqual(null, LauncherCore.ExtractStartupUrl("dsh: startup failed"), "rejects unrelated lines");
        AssertEqual(null, LauncherCore.ExtractStartupUrl("dsh web: http://example.com/"), "rejects non-loopback URLs");
    }

    private static void TestBuildDshArguments()
    {
        string value = LauncherCore.BuildDshArguments(@"C:\A B\dsh.cmd", @"C:\Logs\run one.log");
        AssertContains(value, "--no-open", "suppresses default browser");
        AssertContains(value, "call \"C:\\A B\\dsh.cmd\"", "quotes dsh path");
        AssertContains(value, ">> \"C:\\Logs\\run one.log\" 2>&1", "redirects diagnostics");
    }

    private static void TestBuildEdgeArguments()
    {
        string value = LauncherCore.BuildEdgeArguments("http://127.0.0.1:3080/?token=a-b");
        AssertContains(value, "--app=\"http://127.0.0.1:3080/?token=a-b\"", "uses Edge app mode");
        AssertContains(value, "--start-windowed", "requests a window");
    }

    private static void TestHealthProbe()
    {
        TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        Thread server = new Thread(delegate()
        {
            using (TcpClient client = listener.AcceptTcpClient())
            using (NetworkStream stream = client.GetStream())
            {
                int matched = 0;
                byte[] terminator = new byte[] { 13, 10, 13, 10 };
                while (matched < terminator.Length)
                {
                    int value = stream.ReadByte();
                    if (value < 0)
                    {
                        break;
                    }

                    matched = value == terminator[matched] ? matched + 1 : (value == terminator[0] ? 1 : 0);
                }

                byte[] response = Encoding.ASCII.GetBytes(
                    "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok");
                stream.Write(response, 0, response.Length);
            }
        });
        server.IsBackground = true;
        server.Start();
        AssertTrue(LauncherCore.IsHealthy(new Uri("http://127.0.0.1:" + port + "/"), 2000), "accepts HTTP 200");
        server.Join(2000);
        listener.Stop();

        AssertTrue(!LauncherCore.IsHealthy(new Uri("http://127.0.0.1:" + port + "/"), 200), "rejects closed port");
    }

    private static void TestStartDshWithSpaces()
    {
        string root = Path.Combine(Path.GetTempPath(), "dsh launcher test " + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        string fakeDsh = Path.Combine(root, "fake dsh.cmd");
        string log = Path.Combine(root, "server output.log");
        File.WriteAllText(fakeDsh, "@echo off\r\necho fake dsh started\r\nexit /b 0\r\n", Encoding.ASCII);
        try
        {
            using (Process process = LauncherCore.StartDsh(fakeDsh, root, log))
            {
                AssertTrue(process.WaitForExit(5000), "fake dsh exits");
            }

            string output = File.Exists(log) ? File.ReadAllText(log) : null;
            AssertContains(output, "fake dsh started", "cmd quoting supports paths with spaces");
        }
        finally
        {
            try { Directory.Delete(root, true); } catch { }
        }
    }

    private static void TestUnauthorizedMeansServerPresent()
    {
        TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        Thread server = new Thread(delegate()
        {
            using (TcpClient client = listener.AcceptTcpClient())
            using (NetworkStream stream = client.GetStream())
            {
                ReadRequestHeaders(stream);
                byte[] response = Encoding.ASCII.GetBytes(
                    "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                stream.Write(response, 0, response.Length);
            }
        });
        server.IsBackground = true;
        server.Start();
        AssertTrue(
            LauncherCore.IsHealthy(new Uri("http://127.0.0.1:" + port + "/"), 2000),
            "treats DSH-style HTTP 401 as a live server");
        server.Join(2000);
        listener.Stop();
    }

    private static void ReadRequestHeaders(NetworkStream stream)
    {
        int matched = 0;
        byte[] terminator = new byte[] { 13, 10, 13, 10 };
        while (matched < terminator.Length)
        {
            int value = stream.ReadByte();
            if (value < 0)
            {
                break;
            }

            matched = value == terminator[matched] ? matched + 1 : (value == terminator[0] ? 1 : 0);
        }
    }

    private static void AssertEqual(string expected, string actual, string name)
    {
        if (!String.Equals(expected, actual, StringComparison.Ordinal))
        {
            failures++;
            Console.Error.WriteLine(name + ": expected <" + expected + "> actual <" + actual + ">");
        }
    }

    private static void AssertContains(string actual, string expectedPart, string name)
    {
        if (actual == null || actual.IndexOf(expectedPart, StringComparison.Ordinal) < 0)
        {
            failures++;
            Console.Error.WriteLine(name + ": missing <" + expectedPart + "> in <" + actual + ">");
        }
    }

    private static void AssertTrue(bool condition, string name)
    {
        if (!condition)
        {
            failures++;
            Console.Error.WriteLine(name + ": expected true");
        }
    }
}
