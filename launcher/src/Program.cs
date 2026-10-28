using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Windows.Forms;

internal static class Program
{
    private static readonly Uri HealthUri = new Uri("http://127.0.0.1:3080/");

    [STAThread]
    private static int Main()
    {
        bool ownsMutex;
        using (Mutex mutex = new Mutex(true, @"Local\DeepSeekHarnessStableLauncher", out ownsMutex))
        {
            if (!ownsMutex)
            {
                return 0;
            }

            string home = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "DeepSeek Harness");
            string launcherDirectory = Path.Combine(home, "launcher");
            string logDirectory = Path.Combine(launcherDirectory, "logs");
            string logPath = Path.Combine(logDirectory, "server-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".log");

            try
            {
                if (LauncherCore.IsHealthy(HealthUri, 1000))
                {
                    LauncherCore.OpenAppWindow(HealthUri.AbsoluteUri);
                    return 0;
                }

                string dshPath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                    @"npm\dsh.cmd");
                if (!File.Exists(dshPath))
                {
                    throw new FileNotFoundException("找不到 dsh.cmd，请确认 DeepSeek Harness 已安装。", dshPath);
                }

                Directory.CreateDirectory(logDirectory);
                Process dshProcess = LauncherCore.StartDsh(dshPath, home, logPath);
                string startupUrl = LauncherCore.WaitForStartup(dshProcess, logPath, HealthUri, TimeSpan.FromSeconds(90));
                LauncherCore.OpenAppWindow(startupUrl);
                return 0;
            }
            catch (Exception exception)
            {
                Directory.CreateDirectory(logDirectory);
                string errorPath = Path.Combine(logDirectory, "launcher-error-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".txt");
                File.WriteAllText(errorPath, exception.ToString());
                MessageBox.Show(
                    "DeepSeek Harness 启动失败。\r\n\r\n" + exception.Message + "\r\n\r\n诊断日志：\r\n" + errorPath,
                    "DeepSeek Harness",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 1;
            }
            finally
            {
                mutex.ReleaseMutex();
            }
        }
    }
}
