using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace FFWFrostburn8Installer
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            if (HasArgument(args, "--verify-only"))
            {
                return RunVerification(args);
            }

            if (HasArgument(args, "--version"))
            {
                MessageBox.Show(
                    "FFWFrostburn8 Installer " + BuildInfo.ModVersion + Environment.NewLine +
                    "Far Far West " + BuildInfo.GameVersion,
                    "FFWFrostburn8",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
                return 0;
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new InstallerForm(GetArgumentValue(args, "--game-root")));
            return 0;
        }

        private static int RunVerification(string[] args)
        {
            var messages = new List<string>();
            string logPath = GetArgumentValue(args, "--log");
            try
            {
                using (ReleasePayload payload = ReleaseValidator.ExtractAndValidate(messages.Add))
                {
                    string gameRoot = GetArgumentValue(args, "--game-root");
                    if (!String.IsNullOrWhiteSpace(gameRoot))
                    {
                        GameValidator.Validate(gameRoot, messages.Add);
                    }
                }
                messages.Add("Verification completed successfully.");
                WriteVerificationLog(logPath, messages);
                return 0;
            }
            catch (Exception ex)
            {
                messages.Add("ERROR: " + ex);
                WriteVerificationLog(logPath, messages);
                return 2;
            }
        }

        private static void WriteVerificationLog(string path, IList<string> messages)
        {
            if (String.IsNullOrWhiteSpace(path))
            {
                return;
            }

            string fullPath = Path.GetFullPath(path);
            string parent = Path.GetDirectoryName(fullPath);
            if (!String.IsNullOrWhiteSpace(parent))
            {
                Directory.CreateDirectory(parent);
            }
            File.WriteAllLines(fullPath, messages.ToArray(), new UTF8Encoding(false));
        }

        private static bool HasArgument(string[] args, string name)
        {
            return args.Any(arg => String.Equals(arg, name, StringComparison.OrdinalIgnoreCase));
        }

        internal static string GetArgumentValue(string[] args, string name)
        {
            for (int index = 0; index < args.Length - 1; index++)
            {
                if (String.Equals(args[index], name, StringComparison.OrdinalIgnoreCase))
                {
                    return args[index + 1];
                }
            }
            return null;
        }
    }

    internal sealed class InstallerForm : Form
    {
        private readonly TextBox gameRootTextBox;
        private readonly TextBox logTextBox;
        private readonly Button browseButton;
        private readonly Button installButton;
        private readonly Button closeButton;
        private readonly Button noticesButton;
        private readonly Label statusLabel;
        private bool busy;

        internal InstallerForm(string requestedGameRoot)
        {
            Text = "FFWFrostburn8 v" + BuildInfo.ModVersion + " - Installer";
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(760, 565);
            MinimumSize = new Size(720, 540);
            MaximizeBox = false;
            AutoScaleMode = AutoScaleMode.Dpi;
            Font = new Font("Segoe UI", 9F, FontStyle.Regular, GraphicsUnit.Point);

            var title = new Label();
            title.AutoSize = true;
            title.Font = new Font("Segoe UI Semibold", 18F, FontStyle.Bold, GraphicsUnit.Point);
            title.Location = new Point(24, 18);
            title.Text = "Far Far West Frostburn - 8 Players";
            Controls.Add(title);

            var version = new Label();
            version.AutoSize = true;
            version.ForeColor = Color.DimGray;
            version.Location = new Point(27, 58);
            version.Text = "Mod v" + BuildInfo.ModVersion + "  |  Game " + BuildInfo.GameVersion +
                "  |  Offline package";
            Controls.Add(version);

            var warning = new Label();
            warning.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            warning.BackColor = Color.FromArgb(255, 247, 214);
            warning.BorderStyle = BorderStyle.FixedSingle;
            warning.Location = new Point(24, 88);
            warning.Size = new Size(712, 72);
            warning.Padding = new Padding(10, 8, 10, 8);
            warning.Text =
                "Close Far Far West before installing. The installer backs up and replaces the current " +
                "dwmapi.dll and entire ue4ss folder. Existing UE4SS mods remain recoverable in the backup, " +
                "but are not kept active automatically. The game is never started, closed, or restarted.";
            Controls.Add(warning);

            var pathLabel = new Label();
            pathLabel.AutoSize = true;
            pathLabel.Location = new Point(24, 177);
            pathLabel.Text = "Game folder / Thư mục game:";
            Controls.Add(pathLabel);

            gameRootTextBox = new TextBox();
            gameRootTextBox.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            gameRootTextBox.Location = new Point(24, 199);
            gameRootTextBox.Size = new Size(606, 27);
            Controls.Add(gameRootTextBox);

            browseButton = new Button();
            browseButton.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            browseButton.Location = new Point(638, 197);
            browseButton.Size = new Size(98, 30);
            browseButton.Text = "Browse...";
            browseButton.Click += BrowseButtonClick;
            Controls.Add(browseButton);

            var hint = new Label();
            hint.AutoSize = true;
            hint.ForeColor = Color.DimGray;
            hint.Location = new Point(24, 231);
            hint.Text = "Steam libraries are detected automatically. Browse only if the detected path is wrong.";
            Controls.Add(hint);

            statusLabel = new Label();
            statusLabel.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            statusLabel.AutoEllipsis = true;
            statusLabel.Font = new Font("Segoe UI Semibold", 9F, FontStyle.Bold, GraphicsUnit.Point);
            statusLabel.Location = new Point(24, 262);
            statusLabel.Size = new Size(712, 24);
            statusLabel.Text = "Ready / Sẵn sàng";
            Controls.Add(statusLabel);

            logTextBox = new TextBox();
            logTextBox.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            logTextBox.BackColor = Color.White;
            logTextBox.Font = new Font("Consolas", 8.5F, FontStyle.Regular, GraphicsUnit.Point);
            logTextBox.Location = new Point(24, 289);
            logTextBox.Multiline = true;
            logTextBox.ReadOnly = true;
            logTextBox.ScrollBars = ScrollBars.Vertical;
            logTextBox.Size = new Size(712, 205);
            Controls.Add(logTextBox);

            installButton = new Button();
            installButton.Anchor = AnchorStyles.Bottom | AnchorStyles.Right;
            installButton.BackColor = Color.FromArgb(40, 120, 72);
            installButton.FlatStyle = FlatStyle.Flat;
            installButton.ForeColor = Color.White;
            installButton.Location = new Point(506, 511);
            installButton.Size = new Size(112, 36);
            installButton.Text = "Install / Cài";
            installButton.UseVisualStyleBackColor = false;
            installButton.Click += InstallButtonClick;
            Controls.Add(installButton);

            closeButton = new Button();
            closeButton.Anchor = AnchorStyles.Bottom | AnchorStyles.Right;
            closeButton.Location = new Point(624, 511);
            closeButton.Size = new Size(112, 36);
            closeButton.Text = "Close / Đóng";
            closeButton.Click += delegate { Close(); };
            Controls.Add(closeButton);

            noticesButton = new Button();
            noticesButton.Anchor = AnchorStyles.Bottom | AnchorStyles.Left;
            noticesButton.Location = new Point(24, 511);
            noticesButton.Size = new Size(136, 36);
            noticesButton.Text = "Licenses / Giấy phép";
            noticesButton.Click += delegate { NoticesForm.ShowNotices(this); };
            Controls.Add(noticesButton);

            FormClosing += InstallerFormClosing;
            DetectGameRoot(requestedGameRoot);
        }

        private void DetectGameRoot(string requestedGameRoot)
        {
            try
            {
                if (!String.IsNullOrWhiteSpace(requestedGameRoot))
                {
                    gameRootTextBox.Text = Path.GetFullPath(requestedGameRoot);
                    AppendLog("Using command-line game path: " + gameRootTextBox.Text);
                    return;
                }

                IList<string> candidates = GameLocator.FindCandidates();
                if (candidates.Count == 1)
                {
                    gameRootTextBox.Text = candidates[0];
                    AppendLog("Detected Steam installation: " + candidates[0]);
                }
                else if (candidates.Count > 1)
                {
                    gameRootTextBox.Text = candidates[0];
                    AppendLog("Multiple Steam installations were found. Verify the selected path.");
                    foreach (string candidate in candidates)
                    {
                        AppendLog("  " + candidate);
                    }
                }
                else
                {
                    AppendLog("Far Far West was not found automatically. Select its root folder.");
                }
            }
            catch (Exception ex)
            {
                AppendLog("Automatic Steam detection failed: " + ex.Message);
            }
        }

        private void BrowseButtonClick(object sender, EventArgs e)
        {
            using (var dialog = new FolderBrowserDialog())
            {
                dialog.Description = "Select the FarFarWest game root folder";
                dialog.ShowNewFolderButton = false;
                if (Directory.Exists(gameRootTextBox.Text))
                {
                    dialog.SelectedPath = gameRootTextBox.Text;
                }
                if (dialog.ShowDialog(this) == DialogResult.OK)
                {
                    gameRootTextBox.Text = dialog.SelectedPath;
                }
            }
        }

        private async void InstallButtonClick(object sender, EventArgs e)
        {
            string gameRoot = gameRootTextBox.Text.Trim();
            if (String.IsNullOrWhiteSpace(gameRoot))
            {
                MessageBox.Show(this, "Select the FarFarWest game folder first.", "Missing game folder",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            string message =
                "Install FFWFrostburn8 v" + BuildInfo.ModVersion + " into:" +
                Environment.NewLine + Environment.NewLine + gameRoot + Environment.NewLine + Environment.NewLine +
                "The current UE4SS folder and known legacy More Players files will be backed up and replaced. " +
                "Continue?";
            if (MessageBox.Show(this, message, "Confirm installation", MessageBoxButtons.YesNo,
                    MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) != DialogResult.Yes)
            {
                return;
            }

            SetBusy(true);
            logTextBox.Clear();
            statusLabel.Text = "Installing / Đang cài đặt...";

            string logPath = null;
            try
            {
                string logDirectory = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "FFWFrostburn8", "Logs");
                Directory.CreateDirectory(logDirectory);
                logPath = Path.Combine(logDirectory,
                    "installer-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmssfff", CultureInfo.InvariantCulture) +
                    "Z.log");

                InstallResult result = await Task.Run(delegate
                {
                    using (var writer = new StreamWriter(logPath, false, new UTF8Encoding(false)))
                    {
                        writer.AutoFlush = true;
                        Action<string> logger = delegate(string line)
                        {
                            writer.WriteLine(DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture) + " " + line);
                            AppendLog(line);
                        };
                        return InstallerEngine.Install(gameRoot, logger);
                    }
                });

                statusLabel.ForeColor = Color.DarkGreen;
                statusLabel.Text = "Installed successfully / Cài đặt thành công";
                MessageBox.Show(this,
                    "Installation completed successfully." + Environment.NewLine +
                    "Backup: " + result.BackupDirectory + Environment.NewLine +
                    "Log: " + logPath + Environment.NewLine + Environment.NewLine +
                    "The installer did not start the game.",
                    "FFWFrostburn8 installed",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                statusLabel.ForeColor = Color.DarkRed;
                statusLabel.Text = "Installation failed / Cài đặt thất bại";
                AppendLog("ERROR: " + ex.Message);
                try
                {
                    if (!String.IsNullOrWhiteSpace(logPath))
                    {
                        File.AppendAllText(logPath, DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture) +
                            " ERROR " + ex + Environment.NewLine, new UTF8Encoding(false));
                    }
                }
                catch
                {
                }
                MessageBox.Show(this,
                    ex.Message + Environment.NewLine + Environment.NewLine +
                    "No game launch was attempted. If installation had started, the installer attempted an automatic rollback." +
                    Environment.NewLine + "Log: " +
                    (String.IsNullOrWhiteSpace(logPath) ? "not created" : logPath),
                    "Installation failed",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            finally
            {
                SetBusy(false);
            }
        }

        private void SetBusy(bool value)
        {
            busy = value;
            installButton.Enabled = !value;
            browseButton.Enabled = !value;
            gameRootTextBox.Enabled = !value;
            closeButton.Enabled = !value;
            noticesButton.Enabled = !value;
            UseWaitCursor = value;
        }

        private void AppendLog(string line)
        {
            if (IsDisposed)
            {
                return;
            }
            if (InvokeRequired)
            {
                BeginInvoke(new Action<string>(AppendLog), line);
                return;
            }
            logTextBox.AppendText(line + Environment.NewLine);
        }

        private void InstallerFormClosing(object sender, FormClosingEventArgs e)
        {
            if (busy)
            {
                e.Cancel = true;
                MessageBox.Show(this, "Wait for installation or rollback to finish before closing.",
                    "Installation in progress", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
    }

    internal static class NoticesForm
    {
        internal static void ShowNotices(IWin32Window owner)
        {
            string text = ReadResource("FFWFrostburn8.LICENSE.txt") + Environment.NewLine + Environment.NewLine +
                ReadResource("FFWFrostburn8.THIRD_PARTY_NOTICES.txt");
            using (var form = new Form())
            {
                form.Text = "FFWFrostburn8 licenses and notices";
                form.StartPosition = FormStartPosition.CenterParent;
                form.ClientSize = new Size(720, 520);
                var box = new TextBox();
                box.Dock = DockStyle.Fill;
                box.Multiline = true;
                box.ReadOnly = true;
                box.ScrollBars = ScrollBars.Both;
                box.WordWrap = false;
                box.Font = new Font("Consolas", 9F);
                box.Text = text;
                form.Controls.Add(box);
                form.ShowDialog(owner);
            }
        }

        private static string ReadResource(string name)
        {
            using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
            {
                if (stream == null)
                {
                    return "Missing embedded notice: " + name;
                }
                using (var reader = new StreamReader(stream, Encoding.UTF8))
                {
                    return reader.ReadToEnd();
                }
            }
        }
    }

    internal sealed class ReleasePayload : IDisposable
    {
        internal string StagingRoot { get; private set; }
        internal string PackageGameRoot { get; private set; }
        internal string ArchivePath { get; private set; }

        internal ReleasePayload(string stagingRoot, string packageGameRoot, string archivePath)
        {
            StagingRoot = stagingRoot;
            PackageGameRoot = packageGameRoot;
            ArchivePath = archivePath;
        }

        public void Dispose()
        {
            FileSystem.TryDeleteDirectory(StagingRoot);
        }
    }

    internal static class ReleaseValidator
    {
        private const long MaximumExpandedBytes = 536870912L;

        internal static ReleasePayload ExtractAndValidate(Action<string> log)
        {
            string stagingRoot = Path.Combine(Path.GetTempPath(),
                "FFWFrostburn8-Installer-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(stagingRoot);
            try
            {
                string archivePath = Path.Combine(stagingRoot, BuildInfo.ReleaseFileName);
                using (Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream(BuildInfo.PayloadResourceName))
                {
                    if (resource == null)
                    {
                        throw new InvalidDataException("The embedded release resource is missing.");
                    }
                    using (var output = new FileStream(archivePath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                    {
                        resource.CopyTo(output);
                    }
                }

                string archiveHash = Hashing.GetFileSha256(archivePath);
                if (!String.Equals(archiveHash, BuildInfo.ReleaseSha256, StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidDataException("Embedded release SHA-256 validation failed.");
                }
                log("Embedded release SHA-256: " + archiveHash);

                string expandedRoot = Path.Combine(stagingRoot, "expanded");
                Directory.CreateDirectory(expandedRoot);
                ExtractZipSafely(archivePath, expandedRoot);

                string packageGameRoot = FileSystem.CombineInside(expandedRoot, "FarFarWest");
                ValidatePackage(packageGameRoot);
                log("Embedded package manifest and source tree are valid.");
                return new ReleasePayload(stagingRoot, packageGameRoot, archivePath);
            }
            catch
            {
                FileSystem.TryDeleteDirectory(stagingRoot);
                throw;
            }
        }

        private static void ExtractZipSafely(string archivePath, string destination)
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            long expandedBytes = 0;
            using (ZipArchive archive = ZipFile.OpenRead(archivePath))
            {
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string normalized = entry.FullName.Replace('/', '\\');
                    if (String.IsNullOrWhiteSpace(normalized))
                    {
                        continue;
                    }
                    string[] pathParts = normalized.Split(new[] { '\\' }, StringSplitOptions.RemoveEmptyEntries);
                    if (Path.IsPathRooted(normalized) || normalized.IndexOf(':') >= 0 ||
                        pathParts.Contains("..") ||
                        pathParts.Any(part => part.EndsWith(".", StringComparison.Ordinal) ||
                            part.EndsWith(" ", StringComparison.Ordinal)))
                    {
                        throw new InvalidDataException("Unsafe ZIP entry: " + entry.FullName);
                    }
                    if (!seen.Add(normalized.TrimEnd('\\')))
                    {
                        throw new InvalidDataException("Duplicate ZIP entry: " + entry.FullName);
                    }
                    if (normalized.EndsWith(".pak", StringComparison.OrdinalIgnoreCase) ||
                        normalized.EndsWith(".ucas", StringComparison.OrdinalIgnoreCase) ||
                        normalized.EndsWith(".utoc", StringComparison.OrdinalIgnoreCase))
                    {
                        throw new InvalidDataException("Cooked game asset is forbidden in the release: " + entry.FullName);
                    }

                    if (entry.Length < 0 || entry.Length > MaximumExpandedBytes - expandedBytes)
                    {
                        throw new InvalidDataException("Embedded release exceeds the safe expanded-size limit.");
                    }
                    expandedBytes += entry.Length;

                    string target = FileSystem.CombineInside(destination, normalized);
                    if (String.IsNullOrEmpty(entry.Name))
                    {
                        Directory.CreateDirectory(target);
                    }
                    else
                    {
                        Directory.CreateDirectory(Path.GetDirectoryName(target));
                        entry.ExtractToFile(target, false);
                    }
                }
            }
        }

        private static void ValidatePackage(string packageGameRoot)
        {
            string manifestPath = FileSystem.CombineInside(packageGameRoot,
                @"Binaries\Win64\ue4ss\FARFARWEST_MODKIT_MANIFEST.json");
            string proxyPath = FileSystem.CombineInside(packageGameRoot, @"Binaries\Win64\dwmapi.dll");
            string ue4ssPath = FileSystem.CombineInside(packageGameRoot, @"Binaries\Win64\ue4ss\UE4SS.dll");
            string modRoot = FileSystem.CombineInside(packageGameRoot,
                @"Binaries\Win64\ue4ss\Mods\FFWFrostburn8");
            string enabledPath = FileSystem.CombineInside(modRoot, "enabled.txt");
            string luaPath = FileSystem.CombineInside(modRoot, @"Scripts\main.lua");

            foreach (string required in new[] { manifestPath, proxyPath, ue4ssPath, enabledPath, luaPath })
            {
                if (!File.Exists(required))
                {
                    throw new InvalidDataException("Required package file is missing: " + required);
                }
            }

            var serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = Int32.MaxValue;
            var manifest = serializer.DeserializeObject(File.ReadAllText(manifestPath, Encoding.UTF8))
                as Dictionary<string, object>;
            if (manifest == null)
            {
                throw new InvalidDataException("Package manifest is not a JSON object.");
            }

            RequireInteger(manifest, "schemaVersion", 2);
            RequireString(manifest, "targetProductVersion", BuildInfo.GameVersion);
            RequireString(manifest, "targetExecutableSha256", BuildInfo.GameExecutableSha256);
            Dictionary<string, object> ue4ss = RequireObject(manifest, "ue4ss");
            RequireString(ue4ss, "commit", BuildInfo.Ue4ssCommit);
            RequireString(ue4ss, "assetSha256", BuildInfo.Ue4ssAssetSha256);
            Dictionary<string, object> mod = RequireObject(manifest, "mod");
            RequireString(mod, "id", "FFWFrostburn8");
            RequireString(mod, "version", BuildInfo.ModVersion);
            RequireString(mod, "license", "MIT");
            RequireString(mod, "packageMode", "source-owned-lua");
            RequireString(mod, "sourceTreeSha256", BuildInfo.SourceTreeSha256);
            RequireInteger(mod, "maxPlayers", 8);
            if (!mod.ContainsKey("cookedAssetsIncluded") || Convert.ToBoolean(mod["cookedAssetsIncluded"], CultureInfo.InvariantCulture))
            {
                throw new InvalidDataException("Package manifest permits cooked game assets.");
            }

            string treeHash = Hashing.GetDirectoryTreeSha256(modRoot);
            if (!String.Equals(treeHash, BuildInfo.SourceTreeSha256, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException("Packaged mod source-tree SHA-256 validation failed.");
            }
        }

        private static Dictionary<string, object> RequireObject(Dictionary<string, object> source, string key)
        {
            object value;
            if (!source.TryGetValue(key, out value))
            {
                throw new InvalidDataException("Package manifest is missing: " + key);
            }
            var result = value as Dictionary<string, object>;
            if (result == null)
            {
                throw new InvalidDataException("Package manifest field is not an object: " + key);
            }
            return result;
        }

        private static void RequireString(Dictionary<string, object> source, string key, string expected)
        {
            object value;
            if (!source.TryGetValue(key, out value) ||
                !String.Equals(Convert.ToString(value, CultureInfo.InvariantCulture), expected,
                    StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException("Package manifest mismatch: " + key);
            }
        }

        private static void RequireInteger(Dictionary<string, object> source, string key, int expected)
        {
            object value;
            if (!source.TryGetValue(key, out value) || Convert.ToInt32(value, CultureInfo.InvariantCulture) != expected)
            {
                throw new InvalidDataException("Package manifest mismatch: " + key);
            }
        }
    }

    internal static class GameLocator
    {
        internal static IList<string> FindCandidates()
        {
            var steamRoots = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            AddRegistryPath(steamRoots, RegistryHive.CurrentUser, RegistryView.Default,
                @"Software\Valve\Steam", "SteamPath");
            AddRegistryPath(steamRoots, RegistryHive.LocalMachine, RegistryView.Registry32,
                @"SOFTWARE\Valve\Steam", "InstallPath");
            AddRegistryPath(steamRoots, RegistryHive.LocalMachine, RegistryView.Registry64,
                @"SOFTWARE\Valve\Steam", "InstallPath");
            AddIfDirectory(steamRoots, Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Steam"));
            AddIfDirectory(steamRoots, Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Steam"));

            var libraries = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string steamRoot in steamRoots)
            {
                AddIfDirectory(libraries, steamRoot);
                string vdfPath = Path.Combine(steamRoot, @"steamapps\libraryfolders.vdf");
                if (!File.Exists(vdfPath))
                {
                    continue;
                }
                string vdf = File.ReadAllText(vdfPath);
                foreach (Match match in Regex.Matches(vdf, "\\\"path\\\"\\s+\\\"([^\\\"]+)\\\"",
                    RegexOptions.IgnoreCase))
                {
                    AddIfDirectory(libraries, match.Groups[1].Value.Replace("\\\\", "\\"));
                }
            }

            var candidates = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string library in libraries)
            {
                string manifestPath = Path.Combine(library, @"steamapps\appmanifest_3124540.acf");
                if (!File.Exists(manifestPath))
                {
                    continue;
                }
                Match install = Regex.Match(File.ReadAllText(manifestPath),
                    "\\\"installdir\\\"\\s+\\\"([^\\\"]+)\\\"", RegexOptions.IgnoreCase);
                if (!install.Success)
                {
                    continue;
                }
                string candidate = Path.GetFullPath(Path.Combine(library, "steamapps", "common", install.Groups[1].Value));
                if (File.Exists(Path.Combine(candidate, BuildInfo.GameExecutableRelativePath)))
                {
                    candidates.Add(candidate.TrimEnd(Path.DirectorySeparatorChar));
                }
            }
            return candidates.OrderBy(value => value, StringComparer.OrdinalIgnoreCase).ToList();
        }

        private static void AddRegistryPath(HashSet<string> paths, RegistryHive hive, RegistryView view,
            string subKey, string valueName)
        {
            try
            {
                using (RegistryKey baseKey = RegistryKey.OpenBaseKey(hive, view))
                using (RegistryKey key = baseKey.OpenSubKey(subKey))
                {
                    if (key != null)
                    {
                        object value = key.GetValue(valueName);
                        if (value != null)
                        {
                            AddIfDirectory(paths, Convert.ToString(value, CultureInfo.InvariantCulture));
                        }
                    }
                }
            }
            catch
            {
            }
        }

        private static void AddIfDirectory(HashSet<string> paths, string value)
        {
            if (!String.IsNullOrWhiteSpace(value) && Directory.Exists(value))
            {
                paths.Add(Path.GetFullPath(value).TrimEnd(Path.DirectorySeparatorChar));
            }
        }
    }

    internal static class GameValidator
    {
        internal static string Validate(string gameRoot, Action<string> log)
        {
            string root = Path.GetFullPath(gameRoot).TrimEnd(Path.DirectorySeparatorChar);
            string executable = FileSystem.CombineInside(root, BuildInfo.GameExecutableRelativePath);
            if (!File.Exists(executable))
            {
                throw new FileNotFoundException("Far Far West executable was not found.", executable);
            }

            string productVersion = FileVersionInfo.GetVersionInfo(executable).ProductVersion;
            if (!String.Equals(productVersion, BuildInfo.GameVersion, StringComparison.Ordinal))
            {
                throw new InvalidOperationException("Unsupported game version. Expected " + BuildInfo.GameVersion +
                    ", found " + productVersion + ". Do not force-install after a game update.");
            }

            string executableHash = Hashing.GetFileSha256(executable);
            if (!String.Equals(executableHash, BuildInfo.GameExecutableSha256, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("The game executable SHA-256 does not match the supported build.");
            }
            log("Game build and executable SHA-256 are supported.");

            byte[] data = File.ReadAllBytes(executable);
            for (int index = 0; index < BuildInfo.AobPatterns.Length; index++)
            {
                int matches = CountPatternMatches(data, BuildInfo.AobPatterns[index], 2);
                log("AOB " + BuildInfo.AobNames[index] + ": " + matches + " match(es)");
                if (matches != 1)
                {
                    throw new InvalidOperationException("Compatibility signature " + BuildInfo.AobNames[index] +
                        " must match exactly once; found " + matches + ".");
                }
            }
            return root;
        }

        internal static void EnsureGameNotRunning()
        {
            var ids = new List<int>();
            foreach (string name in new[] { "FarFarWest", "FarFarWest-Win64-Shipping" })
            {
                foreach (Process process in Process.GetProcessesByName(name))
                {
                    try
                    {
                        ids.Add(process.Id);
                    }
                    finally
                    {
                        process.Dispose();
                    }
                }
            }
            if (ids.Count > 0)
            {
                throw new InvalidOperationException("Far Far West is running (PID " +
                    String.Join(", ", ids.Distinct().OrderBy(value => value)) +
                    "). Close the game before installing. The installer will not close it for you.");
            }
        }

        internal static FileStream AcquireGameStartGuard(string gameRoot)
        {
            EnsureGameNotRunning();
            string executable = FileSystem.CombineInside(
                Path.GetFullPath(gameRoot).TrimEnd(Path.DirectorySeparatorChar),
                BuildInfo.GameExecutableRelativePath);
            try
            {
                return new FileStream(executable, FileMode.Open, FileAccess.Read, FileShare.None);
            }
            catch (Exception ex)
            {
                throw new IOException(
                    "Could not lock the game executable against startup. Close Far Far West and try again.", ex);
            }
        }

        private static int CountPatternMatches(byte[] data, string pattern, int limit)
        {
            string[] tokens = pattern.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            byte[] values = new byte[tokens.Length];
            bool[] wildcards = new bool[tokens.Length];
            int anchor = -1;
            for (int index = 0; index < tokens.Length; index++)
            {
                if (tokens[index] == "?" || tokens[index] == "??")
                {
                    wildcards[index] = true;
                }
                else
                {
                    values[index] = Byte.Parse(tokens[index], NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                    if (anchor < 0)
                    {
                        anchor = index;
                    }
                }
            }

            int count = 0;
            int last = data.Length - tokens.Length;
            for (int offset = 0; offset <= last; offset++)
            {
                if (anchor >= 0 && data[offset + anchor] != values[anchor])
                {
                    continue;
                }
                bool matched = true;
                for (int index = 0; index < tokens.Length; index++)
                {
                    if (!wildcards[index] && data[offset + index] != values[index])
                    {
                        matched = false;
                        break;
                    }
                }
                if (matched)
                {
                    count++;
                    if (count >= limit)
                    {
                        break;
                    }
                }
            }
            return count;
        }
    }

    internal sealed class ManagedEntry
    {
        internal string RelativePath { get; private set; }
        internal string SourcePath { get; private set; }
        internal bool Install { get; private set; }

        internal ManagedEntry(string relativePath, string sourcePath, bool install)
        {
            RelativePath = relativePath;
            SourcePath = sourcePath;
            Install = install;
        }
    }

    internal sealed class InstallResult
    {
        internal string GameRoot { get; set; }
        internal string BackupDirectory { get; set; }
    }

    internal sealed class BackupFileRecord
    {
        public string path { get; set; }
        public string sha256 { get; set; }
    }

    internal sealed class BackupPathRecord
    {
        public string relativePath { get; set; }
        public bool existedBefore { get; set; }
        public List<BackupFileRecord> backupFiles { get; set; }
    }

    internal sealed class BackupManifest
    {
        public int schemaVersion { get; set; }
        public string status { get; set; }
        public string createdAtUtc { get; set; }
        public string completedAtUtc { get; set; }
        public string error { get; set; }
        public string gameRoot { get; set; }
        public string gameVersion { get; set; }
        public string gameExecutableSha256 { get; set; }
        public string modVersion { get; set; }
        public string releaseArchiveSha256 { get; set; }
        public List<BackupPathRecord> records { get; set; }
    }

    internal static class InstallerEngine
    {
        internal static InstallResult Install(string requestedGameRoot, Action<string> log)
        {
            return Install(requestedGameRoot, log, null);
        }

        internal static InstallResult Install(string requestedGameRoot, Action<string> log,
            string backupRootOverride)
        {
            using (var installerMutex = new Mutex(false, @"Local\FFWFrostburn8-Installer-v1"))
            {
                bool acquired = false;
                try
                {
                    try
                    {
                        acquired = installerMutex.WaitOne(0, false);
                    }
                    catch (AbandonedMutexException)
                    {
                        acquired = true;
                    }
                    if (!acquired)
                    {
                        throw new InvalidOperationException(
                            "Another FFWFrostburn8 installer is already running. Finish or close it first.");
                    }
                    return InstallExclusive(requestedGameRoot, log, backupRootOverride);
                }
                finally
                {
                    if (acquired)
                    {
                        installerMutex.ReleaseMutex();
                    }
                }
            }
        }

        private static InstallResult InstallExclusive(string requestedGameRoot, Action<string> log,
            string backupRootOverride)
        {
            GameValidator.EnsureGameNotRunning();
            string gameRoot = GameValidator.Validate(requestedGameRoot, log);

            using (ReleasePayload payload = ReleaseValidator.ExtractAndValidate(log))
            {
                string sourceWin64 = FileSystem.CombineInside(payload.PackageGameRoot, @"Binaries\Win64");
                var managed = new List<ManagedEntry>
                {
                    new ManagedEntry(@"FarFarWest\Binaries\Win64\dwmapi.dll",
                        FileSystem.CombineInside(sourceWin64, "dwmapi.dll"), true),
                    new ManagedEntry(@"FarFarWest\Binaries\Win64\ue4ss",
                        FileSystem.CombineInside(sourceWin64, "ue4ss"), true),
                    new ManagedEntry(@"FarFarWest\Content\Paks\~mods\ZZZ_FFWMorePlayers_P.pak", null, false),
                    new ManagedEntry(@"FarFarWest\Content\Paks\~mods\ZZZ_FFWMorePlayers_P.ucas", null, false),
                    new ManagedEntry(@"FarFarWest\Content\Paks\~mods\ZZZ_FFWMorePlayers_P.utoc", null, false)
                };

                foreach (ManagedEntry entry in managed)
                {
                    string target = FileSystem.CombineInside(gameRoot, entry.RelativePath);
                    FileSystem.AssertNoReparsePoints(target);
                    if (entry.Install && !File.Exists(entry.SourcePath) && !Directory.Exists(entry.SourcePath))
                    {
                        throw new InvalidDataException("Required release path is missing: " + entry.RelativePath);
                    }
                    if (entry.Install)
                    {
                        FileSystem.AssertNoReparsePoints(entry.SourcePath);
                    }
                }

                string backupRoot = String.IsNullOrWhiteSpace(backupRootOverride) ?
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                        "FFWFrostburn8", "Backups") :
                    Path.GetFullPath(backupRootOverride);
                FileSystem.AssertTreesAreSeparate(gameRoot, backupRoot);
                FileSystem.AssertTreesAreSeparate(payload.StagingRoot, backupRoot);
                Directory.CreateDirectory(backupRoot);
                string backupDirectory = Path.Combine(backupRoot,
                    DateTime.UtcNow.ToString("yyyyMMdd-HHmmssfff", CultureInfo.InvariantCulture) + "Z-" +
                    Guid.NewGuid().ToString("N").Substring(0, 8));
                Directory.CreateDirectory(backupDirectory);
                string backupFilesRoot = Path.Combine(backupDirectory, "files");
                Directory.CreateDirectory(backupFilesRoot);

                var manifest = new BackupManifest
                {
                    schemaVersion = 1,
                    status = "preparing",
                    createdAtUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
                    gameRoot = gameRoot,
                    gameVersion = BuildInfo.GameVersion,
                    gameExecutableSha256 = BuildInfo.GameExecutableSha256,
                    modVersion = BuildInfo.ModVersion,
                    releaseArchiveSha256 = BuildInfo.ReleaseSha256,
                    records = new List<BackupPathRecord>()
                };
                string manifestPath = Path.Combine(backupDirectory, "backup-manifest.json");

                log("Creating persistent backup: " + backupDirectory);
                foreach (ManagedEntry entry in managed)
                {
                    string target = FileSystem.CombineInside(gameRoot, entry.RelativePath);
                    bool existed = File.Exists(target) || Directory.Exists(target);
                    string backupTarget = FileSystem.CombineInside(backupFilesRoot, entry.RelativePath);
                    var record = new BackupPathRecord
                    {
                        relativePath = entry.RelativePath,
                        existedBefore = existed,
                        backupFiles = new List<BackupFileRecord>()
                    };
                    if (existed)
                    {
                        FileSystem.CopyPath(target, backupTarget);
                        record.backupFiles = Hashing.GetPathInventory(backupTarget);
                        Hashing.AssertSameInventory(target, backupTarget);
                    }
                    manifest.records.Add(record);
                }
                manifest.status = "prepared";
                WriteManifest(manifestPath, manifest);

                GameValidator.EnsureGameNotRunning();
                GameValidator.Validate(gameRoot, log);
                using (FileStream gameStartGuard = GameValidator.AcquireGameStartGuard(gameRoot))
                {
                    log("Game is closed and its executable is locked against startup during file changes.");
                    manifest.status = "installing";
                    WriteManifest(manifestPath, manifest);

                    try
                    {
                        foreach (ManagedEntry entry in managed)
                        {
                            GameValidator.EnsureGameNotRunning();
                            string target = FileSystem.CombineInside(gameRoot, entry.RelativePath);
                            FileSystem.DeletePath(target);
                            if (entry.Install)
                            {
                                FileSystem.CopyPath(entry.SourcePath, target);
                            }
                        }

                        foreach (ManagedEntry entry in managed.Where(value => value.Install))
                        {
                            string target = FileSystem.CombineInside(gameRoot, entry.RelativePath);
                            Hashing.AssertSameInventory(entry.SourcePath, target);
                        }
                        foreach (ManagedEntry entry in managed.Where(value => !value.Install))
                        {
                            string target = FileSystem.CombineInside(gameRoot, entry.RelativePath);
                            if (File.Exists(target) || Directory.Exists(target))
                            {
                                throw new IOException("Legacy cooked asset was not removed: " + entry.RelativePath);
                            }
                        }

                        manifest.status = "installed";
                        manifest.completedAtUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture);
                        WriteManifest(manifestPath, manifest);
                        log("Installed files match the embedded release.");
                        return new InstallResult { GameRoot = gameRoot, BackupDirectory = backupDirectory };
                    }
                    catch (Exception installError)
                    {
                        log("Install failed; restoring every prepared backup entry.");
                        var rollbackErrors = new List<Exception>();
                        for (int index = manifest.records.Count - 1; index >= 0; index--)
                        {
                            BackupPathRecord record = manifest.records[index];
                            try
                            {
                                string target = FileSystem.CombineInside(gameRoot, record.relativePath);
                                FileSystem.DeletePath(target);
                                if (record.existedBefore)
                                {
                                    string backupTarget = FileSystem.CombineInside(backupFilesRoot, record.relativePath);
                                    Hashing.AssertInventory(backupTarget, record.backupFiles);
                                    FileSystem.CopyPath(backupTarget, target);
                                    Hashing.AssertInventory(target, record.backupFiles);
                                }
                                else if (File.Exists(target) || Directory.Exists(target))
                                {
                                    throw new IOException("Rollback could not remove: " + record.relativePath);
                                }
                            }
                            catch (Exception ex)
                            {
                                rollbackErrors.Add(new IOException(
                                    "Rollback failed for " + record.relativePath + ": " + ex.Message, ex));
                            }
                        }
                        manifest.status = rollbackErrors.Count == 0 ?
                            "rolled-back-after-install-error" : "rollback-incomplete";
                        manifest.error = installError.Message + (rollbackErrors.Count == 0 ? "" :
                            " | Rollback errors: " + String.Join(" | ", rollbackErrors.Select(value => value.Message)));
                        manifest.completedAtUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture);
                        WriteManifest(manifestPath, manifest);
                        if (rollbackErrors.Count > 0)
                        {
                            var allErrors = new List<Exception> { installError };
                            allErrors.AddRange(rollbackErrors);
                            throw new AggregateException(
                                "Installation failed and rollback was incomplete. Backup: " + backupDirectory,
                                allErrors);
                        }
                        throw new InvalidOperationException("Installation failed and was rolled back. Backup: " +
                            backupDirectory + ". " + installError.Message, installError);
                    }
                }
            }
        }

        private static void WriteManifest(string path, BackupManifest manifest)
        {
            var serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = Int32.MaxValue;
            string json = serializer.Serialize(manifest);
            string temporary = path + ".tmp";
            File.WriteAllText(temporary, json + Environment.NewLine, new UTF8Encoding(false));
            if (File.Exists(path))
            {
                File.Replace(temporary, path, null);
            }
            else
            {
                File.Move(temporary, path);
            }
        }
    }

    internal static class FileSystem
    {
        internal static string CombineInside(string root, string relative)
        {
            string fullRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string fullPath = Path.GetFullPath(Path.Combine(fullRoot, relative));
            string prefix = fullRoot + Path.DirectorySeparatorChar;
            if (!fullPath.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("Unsafe path outside root: " + fullPath);
            }
            return fullPath;
        }

        internal static void AssertTreesAreSeparate(string first, string second)
        {
            string left = Path.GetFullPath(first).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string right = Path.GetFullPath(second).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string leftPrefix = left + Path.DirectorySeparatorChar;
            string rightPrefix = right + Path.DirectorySeparatorChar;
            if (left.Equals(right, StringComparison.OrdinalIgnoreCase) ||
                left.StartsWith(rightPrefix, StringComparison.OrdinalIgnoreCase) ||
                right.StartsWith(leftPrefix, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("Unsafe overlapping directories: " + left + " and " + right);
            }
        }

        internal static void AssertNoReparsePoints(string path)
        {
            if (!File.Exists(path) && !Directory.Exists(path))
            {
                return;
            }

            var pending = new Stack<string>();
            pending.Push(path);
            while (pending.Count > 0)
            {
                string current = pending.Pop();
                FileAttributes attributes = File.GetAttributes(current);
                if ((attributes & FileAttributes.ReparsePoint) != 0)
                {
                    throw new InvalidOperationException(
                        "Reparse points and junctions are not allowed in managed installer paths: " + current);
                }
                if ((attributes & FileAttributes.Directory) == 0)
                {
                    continue;
                }
                foreach (string child in Directory.GetFileSystemEntries(current))
                {
                    pending.Push(child);
                }
            }
        }

        internal static void CopyPath(string source, string destination)
        {
            AssertNoReparsePoints(source);
            if (File.Exists(source))
            {
                Directory.CreateDirectory(Path.GetDirectoryName(destination));
                File.Copy(source, destination, true);
                return;
            }
            if (!Directory.Exists(source))
            {
                throw new FileNotFoundException("Source path was not found.", source);
            }
            CopyDirectory(source, destination);
        }

        private static void CopyDirectory(string source, string destination)
        {
            Directory.CreateDirectory(destination);
            foreach (string directory in Directory.GetDirectories(source, "*", SearchOption.AllDirectories))
            {
                string relative = directory.Substring(source.TrimEnd('\\').Length).TrimStart('\\');
                Directory.CreateDirectory(CombineInside(destination, relative));
            }
            foreach (string file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
            {
                string relative = file.Substring(source.TrimEnd('\\').Length).TrimStart('\\');
                string target = CombineInside(destination, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(target));
                File.Copy(file, target, true);
            }
        }

        internal static void DeletePath(string path)
        {
            AssertNoReparsePoints(path);
            if (File.Exists(path))
            {
                File.SetAttributes(path, FileAttributes.Normal);
                File.Delete(path);
                return;
            }
            if (Directory.Exists(path))
            {
                foreach (string file in Directory.GetFiles(path, "*", SearchOption.AllDirectories))
                {
                    File.SetAttributes(file, FileAttributes.Normal);
                }
                Directory.Delete(path, true);
            }
        }

        internal static void TryDeleteDirectory(string path)
        {
            try
            {
                if (!String.IsNullOrWhiteSpace(path) && Directory.Exists(path) &&
                    Path.GetFileName(path).StartsWith("FFWFrostburn8-Installer-", StringComparison.Ordinal))
                {
                    DeletePath(path);
                }
            }
            catch
            {
            }
        }
    }

    internal static class Hashing
    {
        internal static string GetFileSha256(string path)
        {
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            using (SHA256 sha = SHA256.Create())
            {
                return ToHex(sha.ComputeHash(stream));
            }
        }

        internal static string GetDirectoryTreeSha256(string root)
        {
            string fullRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar);
            string[] files = Directory.GetFiles(fullRoot, "*", SearchOption.AllDirectories);
            var records = files.Select(file => new
                {
                    Relative = file.Substring(fullRoot.Length + 1).Replace('\\', '/'),
                    Path = file
                })
                .OrderBy(value => value.Relative, StringComparer.OrdinalIgnoreCase)
                .Select(value => value.Relative + "\0" + GetFileSha256(value.Path))
                .ToArray();
            if (records.Length == 0)
            {
                throw new InvalidDataException("Cannot hash an empty directory: " + root);
            }
            byte[] payload = new UTF8Encoding(false).GetBytes(String.Join("\n", records));
            using (SHA256 sha = SHA256.Create())
            {
                return ToHex(sha.ComputeHash(payload));
            }
        }

        internal static List<BackupFileRecord> GetPathInventory(string path)
        {
            var result = new List<BackupFileRecord>();
            if (File.Exists(path))
            {
                result.Add(new BackupFileRecord { path = Path.GetFileName(path), sha256 = GetFileSha256(path) });
                return result;
            }
            string root = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar);
            foreach (string file in Directory.GetFiles(root, "*", SearchOption.AllDirectories)
                .OrderBy(value => value, StringComparer.OrdinalIgnoreCase))
            {
                result.Add(new BackupFileRecord
                {
                    path = file.Substring(root.Length + 1).Replace('\\', '/'),
                    sha256 = GetFileSha256(file)
                });
            }
            return result;
        }

        internal static void AssertSameInventory(string first, string second)
        {
            List<BackupFileRecord> left = GetPathInventory(first);
            List<BackupFileRecord> right = GetPathInventory(second);
            if (left.Count != right.Count)
            {
                throw new IOException("File inventory count mismatch between source and destination.");
            }
            for (int index = 0; index < left.Count; index++)
            {
                if (!String.Equals(left[index].path, right[index].path, StringComparison.OrdinalIgnoreCase) ||
                    !String.Equals(left[index].sha256, right[index].sha256, StringComparison.OrdinalIgnoreCase))
                {
                    throw new IOException("File inventory hash mismatch: " + left[index].path);
                }
            }
        }

        internal static void AssertInventory(string path, IList<BackupFileRecord> expected)
        {
            List<BackupFileRecord> actual = GetPathInventory(path);
            if (expected == null || actual.Count != expected.Count)
            {
                throw new IOException("Recorded backup inventory count mismatch: " + path);
            }
            for (int index = 0; index < actual.Count; index++)
            {
                if (!String.Equals(actual[index].path, expected[index].path, StringComparison.OrdinalIgnoreCase) ||
                    !String.Equals(actual[index].sha256, expected[index].sha256,
                        StringComparison.OrdinalIgnoreCase))
                {
                    throw new IOException("Recorded backup inventory hash mismatch: " + actual[index].path);
                }
            }
        }

        private static string ToHex(byte[] value)
        {
            var builder = new StringBuilder(value.Length * 2);
            foreach (byte item in value)
            {
                builder.Append(item.ToString("X2", CultureInfo.InvariantCulture));
            }
            return builder.ToString();
        }
    }
}
