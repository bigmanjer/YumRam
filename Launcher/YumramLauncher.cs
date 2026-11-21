// YUMRAM.exe - small native launcher and updater (5.10).
//
// Why a real launcher instead of PS2EXE: PS2EXE wraps the script in its own PowerShell host, and
// antivirus machine-learning engines repeatedly flag those builds (per file hash, so every release
// again). This launcher only starts Windows PowerShell with the readable scripts next to it.
//
//   YUMRAM.exe                     start YUMRAM (no console window). The manifest asks for
//                                  administrator, so the UAC prompt says "YUMRAM".
//   YUMRAM.exe --apply-update <staging> --target <folder> --wait-pid <pid> [--no-restart]
//                                  wait for YUMRAM to close, back up the current program files to
//                                  <folder>\.previous, copy the verified update in (user data is
//                                  never overwritten), then start YUMRAM again.
//   YUMRAM.exe --rollback          put the files from .previous back.
//
// Build: Tools\Build-Launcher.ps1 (uses the C# compiler that ships with .NET Framework 4).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("YUMRAM")]
[assembly: AssemblyProduct("YUMRAM")]
[assembly: AssemblyDescription("YUMRAM launcher and updater")]
[assembly: AssemblyCompany("YUMRAM contributors")]

static class YumramLauncher
{
    // Root-level files that belong to the user and are never replaced or removed by an update.
    static readonly string[] UserDataExtensions = { ".json", ".log", ".tmp" };
    static readonly string[] SkipDirs = { ".previous", ".git", "Runtime", "cpu-bench" };

    [STAThread]
    static int Main(string[] args)
    {
        string exeDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
        try
        {
            CleanupOldExe(exeDir);
            string mode = args.Length > 0 ? args[0].ToLowerInvariant() : "";
            if (mode == "--apply-update") return ApplyUpdate(args, exeDir);
            if (mode == "--rollback") return Rollback(exeDir, Array.IndexOf(args, "--no-restart") < 0);
            if (mode == "--uninstall") return Uninstall(exeDir, Array.IndexOf(args, "/S") >= 0);
            return StartYumram(exeDir);
        }
        catch (Exception ex)
        {
            Log(exeDir, "Launcher error: " + ex);
            MessageBox.Show("YUMRAM could not start.\n\n" + ex.Message + "\n\nDetails: YUMRAM.log", "YUMRAM", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    static string Arg(string[] args, string name)
    {
        for (int i = 0; i < args.Length - 1; i++) if (string.Equals(args[i], name, StringComparison.OrdinalIgnoreCase)) return args[i + 1];
        return null;
    }

    static int StartYumram(string root)
    {
        string script = Path.Combine(root, @"App\YUMRAM.ps1");
        string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
        if (!File.Exists(script)) throw new FileNotFoundException("App\\YUMRAM.ps1 is missing next to YUMRAM.exe.", script);
        if (!File.Exists(ps)) throw new FileNotFoundException("Windows PowerShell 5.1 was not found.", ps);
        var psi = new ProcessStartInfo(ps, "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\"");
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WorkingDirectory = root;
        Process.Start(psi);
        return 0;
    }

    static int ApplyUpdate(string[] args, string exeDir)
    {
        string staging = Arg(args, "--apply-update");
        string target = Arg(args, "--target");
        string waitPid = Arg(args, "--wait-pid");
        bool restart = Array.IndexOf(args, "--no-restart") < 0;
        if (string.IsNullOrEmpty(staging) || string.IsNullOrEmpty(target)) throw new ArgumentException("--apply-update needs <staging> and --target <folder>.");
        staging = Path.GetFullPath(staging).TrimEnd('\\');
        target = Path.GetFullPath(target).TrimEnd('\\');
        if (!File.Exists(Path.Combine(staging, @"App\YUMRAM.ps1"))) throw new InvalidOperationException("The update package is incomplete (App\\YUMRAM.ps1 missing).");
        if (!File.Exists(Path.Combine(target, @"App\YUMRAM.ps1"))) throw new InvalidOperationException("The target folder is not a YUMRAM folder: " + target);

        int pid;
        if (int.TryParse(waitPid, out pid))
        {
            try { var p = Process.GetProcessById(pid); if (!p.WaitForExit(60000)) throw new TimeoutException("YUMRAM did not close within 60 seconds."); } catch (ArgumentException) { /* already gone */ }
        }
        Log(target, "Updater: applying update from " + staging);

        // 1) Back up the current program files (not user data) to .previous.
        string previous = Path.Combine(target, ".previous");
        if (Directory.Exists(previous)) Directory.Delete(previous, true);
        Directory.CreateDirectory(previous);
        CopyProgramFiles(target, previous, true);

        // 2) Copy the update in. The running YUMRAM.exe cannot be overwritten, but it can be renamed.
        try
        {
            CopyProgramFiles(staging, target, false);
        }
        catch (Exception ex)
        {
            Log(target, "Updater: copy failed, restoring the previous version: " + ex.Message);
            CopyProgramFiles(previous, target, false);
            throw;
        }
        Log(target, "Updater: update applied. Previous version kept in .previous (YUMRAM.exe --rollback).");
        // 5.12: keep Settings > Apps showing the right version after an in-app update.
        try { using (var k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\YUMRAM", true)) { if (k != null && string.Equals(((string)k.GetValue("InstallLocation", "")).TrimEnd('\\'), target, StringComparison.OrdinalIgnoreCase)) k.SetValue("DisplayVersion", File.ReadAllText(Path.Combine(target, "VERSION")).Trim()); } } catch { }
        if (restart) StartYumram(target);
        return 0;
    }

    static int Rollback(string root, bool restart)
    {
        string previous = Path.Combine(root, ".previous");
        if (!File.Exists(Path.Combine(previous, @"App\YUMRAM.ps1")))
        {
            MessageBox.Show("There is no previous version to go back to.", "YUMRAM", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 2;
        }
        foreach (var p in Process.GetProcessesByName("powershell"))
        {
            try { if (p.MainWindowTitle.StartsWith("YUMRAM")) { p.CloseMainWindow(); p.WaitForExit(15000); } } catch { }
        }
        CopyProgramFiles(previous, root, false);
        Log(root, "Updater: rolled back to the previous version.");
        if (restart) StartYumram(root);
        return 0;
    }

    static bool IsUserData(string relative)
    {
        if (relative.IndexOf('\\') >= 0) return false;   // only root-level files are user data
        string ext = Path.GetExtension(relative).ToLowerInvariant();
        return Array.IndexOf(UserDataExtensions, ext) >= 0;
    }

    static void CopyProgramFiles(string from, string to, bool backup)
    {
        foreach (string file in Directory.GetFiles(from, "*", SearchOption.AllDirectories))
        {
            string rel = file.Substring(from.Length).TrimStart('\\');
            string top = rel.Split('\\')[0];
            if (Array.IndexOf(SkipDirs, top) >= 0) continue;
            if (IsUserData(rel)) continue;
            if (rel.EndsWith(".old", StringComparison.OrdinalIgnoreCase)) continue;
            string dest = Path.Combine(to, rel);
            Directory.CreateDirectory(Path.GetDirectoryName(dest));
            if (!backup && File.Exists(dest) && string.Equals(Path.GetFileName(dest), "YUMRAM.exe", StringComparison.OrdinalIgnoreCase))
            {
                string old = dest + ".old";
                try { if (File.Exists(old)) File.Delete(old); } catch { }
                File.Move(dest, old);   // works even while this exe is running
            }
            File.Copy(file, dest, true);
        }
    }

    static void CleanupOldExe(string dir)
    {
        try { string old = Path.Combine(dir, "YUMRAM.exe.old"); if (File.Exists(old)) File.Delete(old); } catch { }
    }

    // 5.12: uninstall (Settings > Apps). Closes YUMRAM, removes shortcuts, the sign-in entry, the no-prompt
    // scheduled task (asks for administrator only if that task exists), the Apps entry and the folder.
    static int Uninstall(string root, bool silent)
    {
        string script = Path.Combine(root, @"App\YUMRAM.ps1");
        if (!File.Exists(script) || Directory.Exists(Path.Combine(root, ".git")))
        {
            if (!silent) MessageBox.Show(Directory.Exists(Path.Combine(root, ".git")) ? "This is a development copy of YUMRAM (a git folder). Nothing was removed." : "This folder does not look like a YUMRAM install. Nothing was removed.", "Uninstall YUMRAM", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 3;
        }
        if (!silent && MessageBox.Show("Remove YUMRAM and its settings from this PC?", "Uninstall YUMRAM", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return 2;
        try
        {
            using (var s = new System.Management.ManagementObjectSearcher("SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name='powershell.exe'"))
                foreach (System.Management.ManagementObject o in s.Get())
                {
                    string cl = (o["CommandLine"] as string) ?? "";
                    if (cl.IndexOf(script, StringComparison.OrdinalIgnoreCase) >= 0) { try { var p = Process.GetProcessById(Convert.ToInt32(o["ProcessId"])); p.CloseMainWindow(); if (!p.WaitForExit(8000)) p.Kill(); } catch { } }
                }
        }
        catch { }
        // 5.12.1: touch only THIS copy. Another install (or a portable copy) keeps its shortcuts, sign-in
        // entry, task and Apps entry, and only YUMRAM's own files are deleted - never the whole folder, which
        // could be Downloads or the Desktop when the portable zip was extracted "here".
        string rootFull = Path.GetFullPath(root).TrimEnd('\\');
        string exePath = Path.Combine(rootFull, "YUMRAM.exe");
        foreach (var f in new[] { Environment.SpecialFolder.Programs, Environment.SpecialFolder.DesktopDirectory })
        { try { string lnk = Path.Combine(Environment.GetFolderPath(f), "YUMRAM.lnk"); if (File.Exists(lnk) && PointsInto(ShortcutTarget(lnk), rootFull)) File.Delete(lnk); } catch { } }
        try { using (var k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true)) { if (k != null && ((k.GetValue("YUMRAM") as string) ?? "").IndexOf(rootFull, StringComparison.OrdinalIgnoreCase) >= 0) k.DeleteValue("YUMRAM", false); } } catch { }
        try
        {
            var q = Process.Start(new ProcessStartInfo("schtasks.exe", "/Query /TN YUMRAM /XML") { CreateNoWindow = true, UseShellExecute = false, RedirectStandardOutput = true });
            string xml = q.StandardOutput.ReadToEnd();
            q.WaitForExit(10000);
            if (q.ExitCode == 0 && xml.IndexOf(script, StringComparison.OrdinalIgnoreCase) >= 0) { var d = Process.Start(new ProcessStartInfo("schtasks.exe", "/Delete /TN YUMRAM /F") { Verb = "runas", UseShellExecute = true, WindowStyle = ProcessWindowStyle.Hidden }); d.WaitForExit(30000); }
        }
        catch { }
        try
        {
            bool ours = false;
            using (var k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\YUMRAM"))
            { if (k != null) ours = string.Equals(((k.GetValue("InstallLocation") as string) ?? "").TrimEnd('\\'), rootFull, StringComparison.OrdinalIgnoreCase); }
            if (ours) Microsoft.Win32.Registry.CurrentUser.DeleteSubKeyTree(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\YUMRAM", false);
        }
        catch { }
        foreach (var d in OwnDirs) { try { string p = Path.Combine(rootFull, d); if (Directory.Exists(p)) Directory.Delete(p, true); } catch { } }
        foreach (var f in OwnFiles) { try { string p = Path.Combine(rootFull, f); if (File.Exists(p)) File.Delete(p); } catch { } }
        // This exe cannot delete itself while running: a short-lived cmd removes it, then the folder only if empty.
        try { Process.Start(new ProcessStartInfo("cmd.exe", "/c ping -n 3 127.0.0.1 >nul & del /f /q \"" + exePath + "\" & rmdir \"" + rootFull + "\"") { CreateNoWindow = true, UseShellExecute = false, WorkingDirectory = Path.GetTempPath() }); } catch { }
        if (!silent) MessageBox.Show("YUMRAM has been removed.", "Uninstall YUMRAM", MessageBoxButtons.OK, MessageBoxIcon.Information);
        return 0;
    }

    // Everything a YUMRAM install contains or creates (release package + runtime data). Nothing else is deleted.
    static readonly string[] OwnDirs = { "App", "Config", "Core", "UI", "Launcher", "Tools", "Runtime", ".previous", "cpu-bench" };
    static readonly string[] OwnFiles = { "VERSION", "README.md", "CHANGELOG.md", "YUMRAM.exe.old",
        "config.json", "state.json", "stats.json", "history.json", "cpu-balance.json", "reclaim-learning.json", "intelligence-db.json",
        "manual-organizations.json", "research-cache.json", "research-history.json", "research-status.json",
        "research-live-results.json", "research-live-results.tmp", "YUMRAM.log", "Research-Diagnostics.log",
        "YUMRAM-app-startup.log", "YUMRAM-app-startup-error.log", "YUMRAM-startup.log", "YUMRAM-launcher.log",
        "cpu-knowledge.json", "cpu-community.json", "windows-bloat-undo.json", "windows-bloat-history.json" };

    static string ShortcutTarget(string lnk)
    {
        object sh = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
        object sc = sh.GetType().InvokeMember("CreateShortcut", System.Reflection.BindingFlags.InvokeMethod, null, sh, new object[] { lnk });
        return (string)sc.GetType().InvokeMember("TargetPath", System.Reflection.BindingFlags.GetProperty, null, sc, null);
    }

    static bool PointsInto(string path, string dir)
    {
        if (string.IsNullOrEmpty(path)) return false;
        try { return Path.GetFullPath(path).StartsWith(dir + "\\", StringComparison.OrdinalIgnoreCase); } catch { return false; }
    }

    static void Log(string root, string line)
    {
        try { File.AppendAllText(Path.Combine(root, "YUMRAM.log"), "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + "] " + line + Environment.NewLine); } catch { }
    }
}
