// YUMRAM-Setup.exe - per-user installer (5.12). The release zip is embedded as a resource.
// Installs to %LOCALAPPDATA%\Programs\YUMRAM (no administrator), adds Start menu (+ optional desktop)
// shortcuts and an entry in Settings > Apps (HKCU ...\Uninstall\YUMRAM) whose Uninstall runs
// "YUMRAM.exe --uninstall". Reinstalling/upgrading keeps the user's settings and data (root *.json / *.log).
//   /S            silent      /D=<folder>   install folder      /NoShortcuts  /NoRegister  /NoLaunch
// Build: Tools\Build-Release.ps1 (csc /resource:YUMRAM-<ver>.zip,YUMRAM.zip).
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("YUMRAM Setup")]
[assembly: AssemblyProduct("YUMRAM")]
[assembly: AssemblyCompany("YUMRAM contributors")]

static class YumramSetup
{
    static string Version = "";

    [STAThread]
    static int Main(string[] args)
    {
        bool silent = false, shortcuts = true, register = true, launch = true;
        string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Programs\YUMRAM");
        foreach (var a in args)
        {
            if (a.Equals("/S", StringComparison.OrdinalIgnoreCase)) silent = true;
            else if (a.StartsWith("/D=", StringComparison.OrdinalIgnoreCase)) dir = a.Substring(3).Trim('"');
            else if (a.Equals("/NoShortcuts", StringComparison.OrdinalIgnoreCase)) shortcuts = false;
            else if (a.Equals("/NoRegister", StringComparison.OrdinalIgnoreCase)) register = false;
            else if (a.Equals("/NoLaunch", StringComparison.OrdinalIgnoreCase)) launch = false;
        }
        try { Version = ReadEmbeddedVersion(); } catch { Version = "?"; }
        if (silent)
        {
            try { Install(dir, shortcuts, false, register); if (launch) Start(dir); return 0; }
            catch (Exception ex) { Console.Error.WriteLine(ex.Message); return 1; }
        }
        Application.EnableVisualStyles();
        using (var f = new SetupForm(dir)) { Application.Run(f); return f.Result; }
    }

    static Stream Payload() { return Assembly.GetExecutingAssembly().GetManifestResourceStream("YUMRAM.zip"); }

    static string ReadEmbeddedVersion()
    {
        using (var z = new ZipArchive(Payload(), ZipArchiveMode.Read))
        {
            var e = z.GetEntry("VERSION");
            using (var r = new StreamReader(e.Open())) return r.ReadToEnd().Trim();
        }
    }

    public static void Install(string dir, bool startMenu, bool desktop, bool register)
    {
        Directory.CreateDirectory(dir);
        using (var z = new ZipArchive(Payload(), ZipArchiveMode.Read))
        {
            foreach (var e in z.Entries)
            {
                if (string.IsNullOrEmpty(e.Name)) continue;
                string rel = e.FullName.Replace('/', '\\');
                string dest = Path.GetFullPath(Path.Combine(dir, rel));
                if (!dest.StartsWith(Path.GetFullPath(dir), StringComparison.OrdinalIgnoreCase)) continue; // zip-slip guard
                bool rootUserData = rel.IndexOf('\\') < 0 && (rel.EndsWith(".json", StringComparison.OrdinalIgnoreCase) || rel.EndsWith(".log", StringComparison.OrdinalIgnoreCase));
                if (rootUserData && File.Exists(dest)) continue; // keep the user's settings and data
                Directory.CreateDirectory(Path.GetDirectoryName(dest));
                if (File.Exists(dest) && dest.EndsWith("YUMRAM.exe", StringComparison.OrdinalIgnoreCase))
                {
                    try { if (File.Exists(dest + ".old")) File.Delete(dest + ".old"); } catch { }
                    File.Move(dest, dest + ".old"); // works even while YUMRAM.exe runs
                }
                e.ExtractToFile(dest, true);
            }
        }
        string exe = Path.Combine(dir, "YUMRAM.exe");
        if (startMenu) Shortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "YUMRAM.lnk"), exe, dir);
        if (desktop) Shortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "YUMRAM.lnk"), exe, dir);
        if (register)
        {
            using (var k = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\YUMRAM"))
            {
                k.SetValue("DisplayName", "YUMRAM");
                k.SetValue("DisplayVersion", Version);
                k.SetValue("Publisher", "YUMRAM contributors");
                k.SetValue("DisplayIcon", exe + ",0");
                k.SetValue("InstallLocation", dir);
                k.SetValue("UninstallString", "\"" + exe + "\" --uninstall");
                k.SetValue("QuietUninstallString", "\"" + exe + "\" --uninstall /S");
                k.SetValue("URLInfoAbout", "https://github.com/bigmanjer/YumRam");
                k.SetValue("NoModify", 1, RegistryValueKind.DWord);
                k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                k.SetValue("EstimatedSize", (int)(DirSize(dir) / 1024), RegistryValueKind.DWord);
                k.SetValue("InstallDate", DateTime.Now.ToString("yyyyMMdd"));
            }
        }
    }

    static long DirSize(string d) { long s = 0; foreach (var f in Directory.GetFiles(d, "*", SearchOption.AllDirectories)) { try { s += new FileInfo(f).Length; } catch { } } return s; }

    static void Shortcut(string lnk, string target, string workDir)
    {
        Type t = Type.GetTypeFromProgID("WScript.Shell");
        dynamic sh = Activator.CreateInstance(t);
        dynamic sc = sh.CreateShortcut(lnk);
        sc.TargetPath = target; sc.WorkingDirectory = workDir; sc.IconLocation = target + ",0";
        sc.Description = "YUMRAM - keeps RAM and CPU free for what you are using";
        sc.Save();
    }

    public static void Start(string dir) { Process.Start(new ProcessStartInfo(Path.Combine(dir, "YUMRAM.exe")) { WorkingDirectory = dir, UseShellExecute = true }); }

    class SetupForm : Form
    {
        public int Result = 1;
        TextBox path; CheckBox desktop, launch; Button go, cancel; Label status;
        public SetupForm(string dir)
        {
            Text = "YUMRAM Setup"; FormBorderStyle = FormBorderStyle.FixedDialog; MaximizeBox = false; MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen; ClientSize = new Size(520, 300); Font = new Font("Segoe UI", 9.5f);
            BackColor = Color.FromArgb(24, 16, 33); ForeColor = Color.FromArgb(240, 232, 248);
            try { Icon = Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location); } catch { }
            var title = new Label { Text = "YUMRAM " + Version, Font = new Font("Segoe UI Semibold", 18f), AutoSize = true, Location = new Point(24, 20), ForeColor = Color.FromArgb(207, 168, 255) };
            var sub = new Label { Text = "Keeps RAM and CPU free for what you are using. Installs for you only - no administrator needed.\nYour settings and statistics are kept when you reinstall or update.", AutoSize = false, Size = new Size(470, 40), Location = new Point(26, 64), ForeColor = Color.FromArgb(190, 180, 205) };
            var lbl = new Label { Text = "Install to", AutoSize = true, Location = new Point(26, 118) };
            path = new TextBox { Text = dir, Location = new Point(26, 140), Size = new Size(380, 26), BackColor = Color.FromArgb(36, 26, 48), ForeColor = ForeColor, BorderStyle = BorderStyle.FixedSingle };
            var browse = new Button { Text = "Browse...", Location = new Point(414, 138), Size = new Size(80, 28), FlatStyle = FlatStyle.Flat };
            browse.Click += (s, e) => { using (var fb = new FolderBrowserDialog { SelectedPath = path.Text }) if (fb.ShowDialog(this) == DialogResult.OK) path.Text = Path.Combine(fb.SelectedPath, "YUMRAM"); };
            desktop = new CheckBox { Text = "Desktop shortcut", Checked = true, AutoSize = true, Location = new Point(26, 180) };
            launch = new CheckBox { Text = "Start YUMRAM when setup finishes", Checked = true, AutoSize = true, Location = new Point(26, 206) };
            status = new Label { Text = "", AutoSize = false, Size = new Size(300, 40), Location = new Point(26, 248), ForeColor = Color.FromArgb(134, 239, 172) };
            go = new Button { Text = "Install", Location = new Point(330, 250), Size = new Size(80, 32), FlatStyle = FlatStyle.Flat, BackColor = Color.FromArgb(168, 85, 247), ForeColor = Color.White };
            cancel = new Button { Text = "Cancel", Location = new Point(416, 250), Size = new Size(80, 32), FlatStyle = FlatStyle.Flat };
            cancel.Click += (s, e) => Close();
            go.Click += (s, e) =>
            {
                if (go.Text == "Finish") { Result = 0; if (launch.Checked) Start(path.Text); Close(); return; }
                go.Enabled = false; cancel.Enabled = false; status.ForeColor = Color.FromArgb(240, 232, 248); status.Text = "Installing..."; Refresh();
                try { Install(path.Text, true, desktop.Checked, true); status.ForeColor = Color.FromArgb(134, 239, 172); status.Text = "Installed. YUMRAM is in the Start menu and in Settings > Apps."; go.Text = "Finish"; go.Enabled = true; }
                catch (Exception ex) { status.ForeColor = Color.FromArgb(248, 113, 113); status.Text = "Could not install: " + ex.Message; go.Enabled = true; cancel.Enabled = true; }
            };
            Controls.AddRange(new Control[] { title, sub, lbl, path, browse, desktop, launch, status, go, cancel });
            AcceptButton = go; CancelButton = cancel;
        }
    }
}
