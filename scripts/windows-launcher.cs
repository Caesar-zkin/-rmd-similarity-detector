using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using Microsoft.Win32;

internal static class WindowsLauncher
{
    private static int Main()
    {
        string workspace = Path.Combine(Path.GetTempPath(), "rmd-detector-" + Guid.NewGuid().ToString("N"));
        try
        {
            string rscript = FindRscript();
            if (rscript == null)
                throw new InvalidOperationException("未找到 Rscript.exe。请先安装 R，或将 R 的 bin 目录加入 PATH。");

            Directory.CreateDirectory(workspace);
            Extract("detector.Rmd", workspace);
            Extract("launch-detector.R", workspace);
            Console.WriteLine("正在启动 Rmd 作业相似性检测。使用期间请保留此窗口。");
            var start = new ProcessStartInfo(rscript, "--vanilla launch-detector.R")
            {
                WorkingDirectory = workspace,
                UseShellExecute = false
            };
            using (var process = Process.Start(start))
            {
                Console.CancelKeyPress += delegate(object sender, ConsoleCancelEventArgs e) { e.Cancel = true; };
                process.WaitForExit();
                if (process.ExitCode != 0)
                    PauseAfterError("检测页面已退出，请查看上方的 R 错误信息。");
                return process.ExitCode;
            }
        }
        catch (Exception e)
        {
            PauseAfterError(e.Message);
            return 1;
        }
        finally
        {
            try { Directory.Delete(workspace, true); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    private static void Extract(string name, string directory)
    {
        using (var input = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
        using (var output = File.Create(Path.Combine(directory, name)))
            input.CopyTo(output);
    }

    private static string FindRscript()
    {
        foreach (var hive in new[] { Registry.CurrentUser, Registry.LocalMachine })
        {
            foreach (var key in new[] { @"SOFTWARE\R-core\R", @"SOFTWARE\R-core\R64" })
            {
                using (var registration = hive.OpenSubKey(key))
                {
                    var home = registration == null ? null : registration.GetValue("InstallPath") as string;
                    if (String.IsNullOrEmpty(home)) continue;
                    string exe = Path.Combine(home, "bin", "Rscript.exe");
                    if (File.Exists(exe)) return exe;
                }
            }
        }

        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';'))
        {
            string folder = dir.Trim().Trim('"');
            if (folder.Length == 0) continue;
            string exe = Path.Combine(folder, "Rscript.exe");
            if (Path.IsPathRooted(exe) && File.Exists(exe)) return exe;
        }

        string installs = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "R");
        if (!Directory.Exists(installs)) return null;
        return Directory.GetDirectories(installs, "R-*")
            .OrderByDescending(dir =>
            {
                Version version;
                return Version.TryParse(Path.GetFileName(dir).Substring(2), out version) ? version : new Version(0, 0);
            })
            .Select(dir => Path.Combine(dir, "bin", "Rscript.exe"))
            .FirstOrDefault(File.Exists);
    }

    private static void PauseAfterError(string message)
    {
        Console.Error.WriteLine(message);
        if (!Console.IsInputRedirected)
        {
            Console.WriteLine("按任意键关闭窗口。");
            Console.ReadKey(true);
        }
    }
}
