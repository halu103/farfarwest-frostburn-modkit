using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace FFWFrostburn8Installer
{
    internal static class UninstallerProgram
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
                    "FFWFrostburn8 Uninstaller " + BuildInfo.ModVersion + Environment.NewLine +
                    "Far Far West " + BuildInfo.GameVersion,
                    "FFWFrostburn8",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
                return 0;
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new UninstallerForm(GetArgumentValue(args, "--game-root")));
            return 0;
        }

        private static int RunVerification(string[] args)
        {
            var messages = new List<string>();
            string logPath = GetArgumentValue(args, "--log");
            try
            {
                UninstallerEngine.VerifyBuild(messages.Add);
                string gameRoot = GetArgumentValue(args, "--game-root");
                if (!String.IsNullOrWhiteSpace(gameRoot))
                {
                    UninstallerEngine.ValidateGameRootShape(gameRoot, messages.Add);
                }
                messages.Add("Uninstaller verification completed successfully.");
                WriteLog(logPath, messages);
                return 0;
            }
            catch (Exception ex)
            {
                messages.Add("ERROR: " + ex);
                WriteLog(logPath, messages);
                return 2;
            }
        }

        private static void WriteLog(string path, IList<string> messages)
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
            return args.Any(value => String.Equals(value, name, StringComparison.OrdinalIgnoreCase));
        }

        private static string GetArgumentValue(string[] args, string name)
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

    internal sealed class UninstallerForm : Form
    {
        private readonly TextBox gameRootTextBox;
        private readonly TextBox logTextBox;
        private readonly Button browseButton;
        private readonly Button uninstallButton;
        private readonly Button closeButton;
        private readonly Label statusLabel;
        private bool busy;

        internal UninstallerForm(string requestedGameRoot)
        {
            Text = "FFWFrostburn8 v" + BuildInfo.ModVersion + " - Uninstaller";
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(760, 535);
            MinimumSize = new Size(720, 510);
            MaximizeBox = false;
            AutoScaleMode = AutoScaleMode.Dpi;
            Font = new Font("Segoe UI", 9F, FontStyle.Regular, GraphicsUnit.Point);

            var title = new Label();
            title.AutoSize = true;
            title.Font = new Font("Segoe UI Semibold", 18F, FontStyle.Bold, GraphicsUnit.Point);
            title.Location = new Point(24, 18);
            title.Text = "FFWFrostburn8 - Safe Uninstaller";
            Controls.Add(title);

            var version = new Label();
            version.AutoSize = true;
            version.ForeColor = Color.DimGray;
            version.Location = new Point(27, 58);
            version.Text = "Mod v" + BuildInfo.ModVersion + "  |  Restore-based removal";
            Controls.Add(version);

            var warning = new Label();
            warning.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            warning.BackColor = Color.FromArgb(255, 247, 214);
            warning.BorderStyle = BorderStyle.FixedSingle;
            warning.Location = new Point(24, 88);
            warning.Size = new Size(712, 72);
            warning.Padding = new Padding(10, 8, 10, 8);
            warning.Text =
                "Close Far Far West first. This tool restores the newest verified clean backup from before " +
                "FFWFrostburn8 was installed. It never starts, closes, or restarts the game and refuses to " +
                "continue if the backup is missing or damaged.";
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

            statusLabel = new Label();
            statusLabel.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            statusLabel.AutoEllipsis = true;
            statusLabel.Font = new Font("Segoe UI Semibold", 9F, FontStyle.Bold, GraphicsUnit.Point);
            statusLabel.Location = new Point(24, 245);
            statusLabel.Size = new Size(712, 24);
            statusLabel.Text = "Ready / Sẵn sàng";
            Controls.Add(statusLabel);

            logTextBox = new TextBox();
            logTextBox.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            logTextBox.BackColor = Color.White;
            logTextBox.Font = new Font("Consolas", 8.5F, FontStyle.Regular, GraphicsUnit.Point);
            logTextBox.Location = new Point(24, 273);
            logTextBox.Multiline = true;
            logTextBox.ReadOnly = true;
            logTextBox.ScrollBars = ScrollBars.Vertical;
            logTextBox.Size = new Size(712, 192);
            Controls.Add(logTextBox);

            uninstallButton = new Button();
            uninstallButton.Anchor = AnchorStyles.Bottom | AnchorStyles.Right;
            uninstallButton.BackColor = Color.FromArgb(176, 68, 54);
            uninstallButton.FlatStyle = FlatStyle.Flat;
            uninstallButton.ForeColor = Color.White;
            uninstallButton.Location = new Point(494, 482);
            uninstallButton.Size = new Size(124, 36);
            uninstallButton.Text = "Uninstall / Gỡ";
            uninstallButton.UseVisualStyleBackColor = false;
            uninstallButton.Click += UninstallButtonClick;
            Controls.Add(uninstallButton);

            closeButton = new Button();
            closeButton.Anchor = AnchorStyles.Bottom | AnchorStyles.Right;
            closeButton.Location = new Point(624, 482);
            closeButton.Size = new Size(112, 36);
            closeButton.Text = "Close / Đóng";
            closeButton.Click += delegate { Close(); };
            Controls.Add(closeButton);

            FormClosing += UninstallerFormClosing;
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
                if (candidates.Count > 0)
                {
                    gameRootTextBox.Text = candidates[0];
                    AppendLog(candidates.Count == 1 ?
                        "Detected Steam installation: " + candidates[0] :
                        "Multiple Steam installations were found. Verify the selected path.");
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

        private async void UninstallButtonClick(object sender, EventArgs e)
        {
            string gameRoot = gameRootTextBox.Text.Trim();
            if (String.IsNullOrWhiteSpace(gameRoot))
            {
                MessageBox.Show(this, "Select the FarFarWest game folder first.", "Missing game folder",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            string message =
                "Uninstall FFWFrostburn8 from:" + Environment.NewLine + Environment.NewLine + gameRoot +
                Environment.NewLine + Environment.NewLine +
                "The tool will restore the newest verified backup that does not contain FFWFrostburn8. " +
                "This can also restore UE4SS or legacy mod files that existed before installation. Continue?";
            if (MessageBox.Show(this, message, "Confirm uninstallation", MessageBoxButtons.YesNo,
                    MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) != DialogResult.Yes)
            {
                return;
            }

            SetBusy(true);
            logTextBox.Clear();
            statusLabel.ForeColor = SystemColors.ControlText;
            statusLabel.Text = "Uninstalling / Đang gỡ cài đặt...";
            string logPath = null;
            try
            {
                string logDirectory = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "FFWFrostburn8", "Logs");
                Directory.CreateDirectory(logDirectory);
                logPath = Path.Combine(logDirectory,
                    "uninstaller-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmssfff", CultureInfo.InvariantCulture) +
                    "Z.log");

                UninstallResult result = await Task.Run(delegate
                {
                    using (var writer = new StreamWriter(logPath, false, new UTF8Encoding(false)))
                    {
                        writer.AutoFlush = true;
                        Action<string> logger = delegate(string line)
                        {
                            writer.WriteLine(DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture) + " " + line);
                            AppendLog(line);
                        };
                        return UninstallerEngine.Uninstall(gameRoot, logger);
                    }
                });

                statusLabel.ForeColor = Color.DarkGreen;
                statusLabel.Text = "Uninstalled successfully / Gỡ cài đặt thành công";
                MessageBox.Show(this,
                    "FFWFrostburn8 was removed successfully." + Environment.NewLine +
                    "Restored from: " + result.RestoredBackupDirectory + Environment.NewLine +
                    "Safety backup: " + result.SafetyBackupDirectory + Environment.NewLine +
                    "Log: " + logPath + Environment.NewLine + Environment.NewLine +
                    "The uninstaller did not start the game.",
                    "FFWFrostburn8 uninstalled",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                statusLabel.ForeColor = Color.DarkRed;
                statusLabel.Text = "Uninstallation failed / Gỡ cài đặt thất bại";
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
                    "The game was not started. If file restoration had begun, the uninstaller attempted " +
                    "to restore its safety backup." + Environment.NewLine + "Log: " +
                    (String.IsNullOrWhiteSpace(logPath) ? "not created" : logPath),
                    "Uninstallation failed",
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
            uninstallButton.Enabled = !value;
            browseButton.Enabled = !value;
            gameRootTextBox.Enabled = !value;
            closeButton.Enabled = !value;
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

        private void UninstallerFormClosing(object sender, FormClosingEventArgs e)
        {
            if (busy)
            {
                e.Cancel = true;
                MessageBox.Show(this, "Wait for uninstallation or rollback to finish before closing.",
                    "Uninstallation in progress", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
    }

    internal sealed class UninstallResult
    {
        internal string GameRoot { get; set; }
        internal string RestoredBackupDirectory { get; set; }
        internal string SafetyBackupDirectory { get; set; }
    }

    internal sealed class BackupCandidate
    {
        internal string Directory { get; set; }
        internal BackupManifest Manifest { get; set; }
        internal DateTime CreatedAtUtc { get; set; }
    }

    internal static class UninstallerEngine
    {
        private static readonly string[] ManagedPaths = new[]
        {
            @"FarFarWest\Binaries\Win64\dwmapi.dll",
            @"FarFarWest\Binaries\Win64\ue4ss",
            @"FarFarWest\Content\Paks\~mods\ZZZ_FFWMorePlayers_P.pak",
            @"FarFarWest\Content\Paks\~mods\ZZZ_FFWMorePlayers_P.ucas",
            @"FarFarWest\Content\Paks\~mods\ZZZ_FFWMorePlayers_P.utoc"
        };

        internal static void VerifyBuild(Action<string> log)
        {
            if (String.IsNullOrWhiteSpace(BuildInfo.ModVersion) ||
                String.IsNullOrWhiteSpace(BuildInfo.GameExecutableRelativePath) || ManagedPaths.Length != 5)
            {
                throw new InvalidDataException("The uninstaller build metadata is incomplete.");
            }
            log("Uninstaller build metadata is complete.");
        }

        internal static string ValidateGameRootShape(string requestedGameRoot, Action<string> log)
        {
            if (String.IsNullOrWhiteSpace(requestedGameRoot))
            {
                throw new ArgumentException("The game folder is required.", "requestedGameRoot");
            }
            string root = Path.GetFullPath(requestedGameRoot)
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string executable = FileSystem.CombineInside(root, BuildInfo.GameExecutableRelativePath);
            if (!File.Exists(executable))
            {
                throw new FileNotFoundException("Far Far West executable was not found.", executable);
            }
            FileSystem.AssertNoReparsePoints(executable);
            foreach (string relativePath in ManagedPaths)
            {
                FileSystem.AssertNoReparsePoints(FileSystem.CombineInside(root, relativePath));
            }
            string productVersion = FileVersionInfo.GetVersionInfo(executable).ProductVersion;
            log("Far Far West game folder found. Current version: " +
                (String.IsNullOrWhiteSpace(productVersion) ? "unknown" : productVersion) + ".");
            return root;
        }

        internal static UninstallResult Uninstall(string requestedGameRoot, Action<string> log)
        {
            return Uninstall(requestedGameRoot, log, null, null);
        }

        internal static UninstallResult Uninstall(string requestedGameRoot, Action<string> log,
            string backupRootOverride)
        {
            return Uninstall(requestedGameRoot, log, backupRootOverride, null);
        }

        internal static UninstallResult Uninstall(string requestedGameRoot, Action<string> log,
            string backupRootOverride, Action<int> faultInjector)
        {
            if (log == null)
            {
                throw new ArgumentNullException("log");
            }
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
                            "Another FFWFrostburn8 installer or uninstaller is already running.");
                    }
                    return UninstallExclusive(requestedGameRoot, log, backupRootOverride, faultInjector);
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

        private static UninstallResult UninstallExclusive(string requestedGameRoot, Action<string> log,
            string backupRootOverride, Action<int> faultInjector)
        {
            GameValidator.EnsureGameNotRunning();
            string gameRoot = ValidateGameRootShape(requestedGameRoot, log);
            AssertOwnedInstallation(gameRoot);

            string backupRoot = String.IsNullOrWhiteSpace(backupRootOverride) ?
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "FFWFrostburn8", "Backups") :
                Path.GetFullPath(backupRootOverride);
            FileSystem.AssertTreesAreSeparate(gameRoot, backupRoot);
            BackupCandidate source = FindCleanBackup(gameRoot, backupRoot, log);
            ValidateBackupCandidate(source, gameRoot, backupRoot);

            string safetyRoot = String.IsNullOrWhiteSpace(backupRootOverride) ?
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "FFWFrostburn8", "UninstallSafety") :
                Path.Combine(Path.GetDirectoryName(backupRoot), "UninstallSafety");
            FileSystem.AssertTreesAreSeparate(gameRoot, safetyRoot);
            FileSystem.AssertTreesAreSeparate(backupRoot, safetyRoot);
            string safetyDirectory = CreateSafetyBackup(gameRoot, safetyRoot, log);
            string safetyManifestPath = Path.Combine(safetyDirectory, "backup-manifest.json");
            BackupManifest safetyManifest = ReadManifest(safetyManifestPath);

            GameValidator.EnsureGameNotRunning();
            using (FileStream gameStartGuard = GameValidator.AcquireGameStartGuard(gameRoot))
            {
                log("Game is closed and its executable is locked against startup during file changes.");
                try
                {
                    RestoreRecords(gameRoot, source.Directory, source.Manifest.records, log, faultInjector);
                    if (IsOwnedInstallation(gameRoot))
                    {
                        throw new IOException("The selected backup still contains FFWFrostburn8.");
                    }
                    safetyManifest.status = "uninstalled";
                    safetyManifest.completedAtUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture);
                    WriteManifest(safetyManifestPath, safetyManifest);
                    log("FFWFrostburn8 was removed and the verified pre-install state was restored.");
                    return new UninstallResult
                    {
                        GameRoot = gameRoot,
                        RestoredBackupDirectory = source.Directory,
                        SafetyBackupDirectory = safetyDirectory
                    };
                }
                catch (Exception uninstallError)
                {
                    log("Uninstall failed; restoring the pre-uninstall safety backup.");
                    var rollbackErrors = new List<Exception>();
                    try
                    {
                        RestoreRecords(gameRoot, safetyDirectory, safetyManifest.records, log, null);
                    }
                    catch (Exception rollbackError)
                    {
                        rollbackErrors.Add(rollbackError);
                    }
                    safetyManifest.status = rollbackErrors.Count == 0 ?
                        "rolled-back-after-uninstall-error" : "uninstall-rollback-incomplete";
                    safetyManifest.error = uninstallError.Message + (rollbackErrors.Count == 0 ? "" :
                        " | Rollback errors: " + String.Join(" | ", rollbackErrors.Select(value => value.Message)));
                    safetyManifest.completedAtUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture);
                    WriteManifest(safetyManifestPath, safetyManifest);
                    if (rollbackErrors.Count > 0)
                    {
                        var allErrors = new List<Exception> { uninstallError };
                        allErrors.AddRange(rollbackErrors);
                        throw new AggregateException(
                            "Uninstallation failed and safety rollback was incomplete. Safety backup: " +
                            safetyDirectory, allErrors);
                    }
                    throw new InvalidOperationException(
                        "Uninstallation failed and was rolled back from the safety backup. " +
                        uninstallError.Message, uninstallError);
                }
            }
        }

        private static void AssertOwnedInstallation(string gameRoot)
        {
            if (!IsOwnedInstallation(gameRoot))
            {
                throw new InvalidOperationException(
                    "No active FFWFrostburn8 installation was found in this game folder. Nothing was changed.");
            }
        }

        private static bool IsOwnedInstallation(string gameRoot)
        {
            string ue4ssRoot = FileSystem.CombineInside(gameRoot, @"FarFarWest\Binaries\Win64\ue4ss");
            string marker = FileSystem.CombineInside(ue4ssRoot, "FARFARWEST_MODKIT_MANIFEST.json");
            string mainLua = FileSystem.CombineInside(ue4ssRoot, @"Mods\FFWFrostburn8\Scripts\main.lua");
            if (!File.Exists(marker) || !File.Exists(mainLua))
            {
                return false;
            }
            try
            {
                var serializer = new JavaScriptSerializer();
                var root = serializer.DeserializeObject(File.ReadAllText(marker, Encoding.UTF8)) as
                    IDictionary<string, object>;
                if (root == null || !root.ContainsKey("mod"))
                {
                    return false;
                }
                var mod = root["mod"] as IDictionary<string, object>;
                return mod != null && mod.ContainsKey("id") &&
                    String.Equals(Convert.ToString(mod["id"], CultureInfo.InvariantCulture),
                        "FFWFrostburn8", StringComparison.Ordinal);
            }
            catch
            {
                return false;
            }
        }

        private static BackupCandidate FindCleanBackup(string gameRoot, string backupRoot, Action<string> log)
        {
            if (!Directory.Exists(backupRoot))
            {
                throw new DirectoryNotFoundException(
                    "No FFWFrostburn8 backup directory was found. Uninstallation was stopped safely: " + backupRoot);
            }
            FileSystem.AssertNoReparsePoints(backupRoot);
            var candidates = new List<BackupCandidate>();
            foreach (string directory in Directory.GetDirectories(backupRoot))
            {
                string manifestPath = Path.Combine(directory, "backup-manifest.json");
                if (!File.Exists(manifestPath))
                {
                    continue;
                }
                try
                {
                    BackupManifest manifest = ReadManifest(manifestPath);
                    if (manifest.schemaVersion != 1 ||
                        !String.Equals(manifest.status, "installed", StringComparison.OrdinalIgnoreCase) ||
                        !PathsEqual(manifest.gameRoot, gameRoot) || !BackupIsClean(directory, manifest))
                    {
                        continue;
                    }
                    DateTime created;
                    if (!DateTime.TryParse(manifest.createdAtUtc, CultureInfo.InvariantCulture,
                            DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out created))
                    {
                        created = System.IO.Directory.GetCreationTimeUtc(directory);
                    }
                    candidates.Add(new BackupCandidate
                    {
                        Directory = Path.GetFullPath(directory),
                        Manifest = manifest,
                        CreatedAtUtc = created
                    });
                }
                catch
                {
                    // Invalid candidates are ignored here and never reach a write operation.
                }
            }
            BackupCandidate selected = candidates
                .OrderByDescending(value => value.CreatedAtUtc)
                .FirstOrDefault();
            if (selected == null)
            {
                throw new InvalidDataException(
                    "No verified clean pre-install backup was found for this game folder. " +
                    "Nothing was changed; do not delete the UE4SS folder manually.");
            }
            log("Selected clean pre-install backup: " + selected.Directory);
            return selected;
        }

        private static bool BackupIsClean(string backupDirectory, BackupManifest manifest)
        {
            BackupPathRecord ue4ssRecord = manifest.records == null ? null :
                manifest.records.FirstOrDefault(value => NormalizeRelative(value.relativePath).Equals(
                    NormalizeRelative(@"FarFarWest\Binaries\Win64\ue4ss"),
                    StringComparison.OrdinalIgnoreCase));
            if (ue4ssRecord == null || !ue4ssRecord.existedBefore)
            {
                return true;
            }
            string backupFilesRoot = Path.Combine(backupDirectory, "files");
            string ue4ssRoot = FileSystem.CombineInside(backupFilesRoot, ue4ssRecord.relativePath);
            string modDirectory = FileSystem.CombineInside(ue4ssRoot, @"Mods\FFWFrostburn8");
            string marker = FileSystem.CombineInside(ue4ssRoot, "FARFARWEST_MODKIT_MANIFEST.json");
            if (Directory.Exists(modDirectory))
            {
                return false;
            }
            if (!File.Exists(marker))
            {
                return true;
            }
            try
            {
                var serializer = new JavaScriptSerializer();
                var root = serializer.DeserializeObject(File.ReadAllText(marker, Encoding.UTF8)) as
                    IDictionary<string, object>;
                var mod = root != null && root.ContainsKey("mod") ?
                    root["mod"] as IDictionary<string, object> : null;
                return mod == null || !mod.ContainsKey("id") ||
                    !String.Equals(Convert.ToString(mod["id"], CultureInfo.InvariantCulture),
                        "FFWFrostburn8", StringComparison.Ordinal);
            }
            catch
            {
                return false;
            }
        }

        private static void ValidateBackupCandidate(BackupCandidate candidate, string gameRoot, string backupRoot)
        {
            string fullBackupRoot = Path.GetFullPath(backupRoot)
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string fullDirectory = Path.GetFullPath(candidate.Directory)
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (!fullDirectory.StartsWith(fullBackupRoot + Path.DirectorySeparatorChar,
                    StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("Backup path is outside the trusted backup root.");
            }
            FileSystem.AssertNoReparsePoints(fullDirectory);
            if (candidate.Manifest.schemaVersion != 1 ||
                !String.Equals(candidate.Manifest.status, "installed", StringComparison.OrdinalIgnoreCase) ||
                !PathsEqual(candidate.Manifest.gameRoot, gameRoot) || candidate.Manifest.records == null ||
                candidate.Manifest.records.Count != ManagedPaths.Length)
            {
                throw new InvalidDataException("The selected backup manifest is not valid for this installation.");
            }

            var expected = new HashSet<string>(ManagedPaths.Select(NormalizeRelative),
                StringComparer.OrdinalIgnoreCase);
            var observed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            string filesRoot = Path.Combine(fullDirectory, "files");
            foreach (BackupPathRecord record in candidate.Manifest.records)
            {
                string normalized = NormalizeRelative(record.relativePath);
                if (!expected.Contains(normalized) || !observed.Add(normalized) || record.backupFiles == null)
                {
                    throw new InvalidDataException("The backup contains an unexpected or duplicate managed path.");
                }
                string backupTarget = FileSystem.CombineInside(filesRoot, record.relativePath);
                if (record.existedBefore)
                {
                    if (!File.Exists(backupTarget) && !System.IO.Directory.Exists(backupTarget))
                    {
                        throw new FileNotFoundException("A recorded backup path is missing.", backupTarget);
                    }
                    FileSystem.AssertNoReparsePoints(backupTarget);
                    Hashing.AssertInventory(backupTarget, record.backupFiles);
                }
                else if (record.backupFiles.Count != 0)
                {
                    throw new InvalidDataException("A non-existent backup path unexpectedly contains file records.");
                }
            }
            if (observed.Count != expected.Count)
            {
                throw new InvalidDataException("The backup manifest does not cover every managed path.");
            }
        }

        private static string CreateSafetyBackup(string gameRoot, string safetyRoot, Action<string> log)
        {
            Directory.CreateDirectory(safetyRoot);
            FileSystem.AssertNoReparsePoints(safetyRoot);
            string directory = Path.Combine(safetyRoot,
                DateTime.UtcNow.ToString("yyyyMMdd-HHmmssfff", CultureInfo.InvariantCulture) + "Z-" +
                Guid.NewGuid().ToString("N").Substring(0, 8));
            Directory.CreateDirectory(directory);
            string filesRoot = Path.Combine(directory, "files");
            Directory.CreateDirectory(filesRoot);
            var manifest = new BackupManifest
            {
                schemaVersion = 1,
                status = "uninstall-safety-preparing",
                createdAtUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
                gameRoot = gameRoot,
                gameVersion = FileVersionInfo.GetVersionInfo(FileSystem.CombineInside(
                    gameRoot, BuildInfo.GameExecutableRelativePath)).ProductVersion,
                gameExecutableSha256 = Hashing.GetFileSha256(FileSystem.CombineInside(
                    gameRoot, BuildInfo.GameExecutableRelativePath)),
                modVersion = BuildInfo.ModVersion,
                releaseArchiveSha256 = "",
                records = new List<BackupPathRecord>()
            };
            foreach (string relativePath in ManagedPaths)
            {
                string target = FileSystem.CombineInside(gameRoot, relativePath);
                bool existed = File.Exists(target) || System.IO.Directory.Exists(target);
                string backupTarget = FileSystem.CombineInside(filesRoot, relativePath);
                var record = new BackupPathRecord
                {
                    relativePath = relativePath,
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
            manifest.status = "uninstall-safety-prepared";
            WriteManifest(Path.Combine(directory, "backup-manifest.json"), manifest);
            log("Created pre-uninstall safety backup: " + directory);
            return directory;
        }

        private static void RestoreRecords(string gameRoot, string backupDirectory,
            IList<BackupPathRecord> records, Action<string> log, Action<int> faultInjector)
        {
            string filesRoot = Path.Combine(backupDirectory, "files");
            int step = 0;
            for (int index = records.Count - 1; index >= 0; index--)
            {
                BackupPathRecord record = records[index];
                step++;
                if (faultInjector != null)
                {
                    faultInjector(step);
                }
                string target = FileSystem.CombineInside(gameRoot, record.relativePath);
                FileSystem.DeletePath(target);
                if (record.existedBefore)
                {
                    string backupTarget = FileSystem.CombineInside(filesRoot, record.relativePath);
                    Hashing.AssertInventory(backupTarget, record.backupFiles);
                    FileSystem.CopyPath(backupTarget, target);
                    Hashing.AssertInventory(target, record.backupFiles);
                }
                else if (File.Exists(target) || System.IO.Directory.Exists(target))
                {
                    throw new IOException("Could not remove managed path: " + record.relativePath);
                }
                log("Restored managed path: " + record.relativePath);
            }
        }

        private static BackupManifest ReadManifest(string path)
        {
            var serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = Int32.MaxValue;
            BackupManifest manifest = serializer.Deserialize<BackupManifest>(
                File.ReadAllText(path, Encoding.UTF8));
            if (manifest == null)
            {
                throw new InvalidDataException("Backup manifest is empty: " + path);
            }
            return manifest;
        }

        private static void WriteManifest(string path, BackupManifest manifest)
        {
            var serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = Int32.MaxValue;
            string temporary = path + ".tmp";
            File.WriteAllText(temporary, serializer.Serialize(manifest) + Environment.NewLine,
                new UTF8Encoding(false));
            if (File.Exists(path))
            {
                File.Replace(temporary, path, null);
            }
            else
            {
                File.Move(temporary, path);
            }
        }

        private static bool PathsEqual(string first, string second)
        {
            if (String.IsNullOrWhiteSpace(first) || String.IsNullOrWhiteSpace(second))
            {
                return false;
            }
            return String.Equals(
                Path.GetFullPath(first).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
                Path.GetFullPath(second).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
                StringComparison.OrdinalIgnoreCase);
        }

        private static string NormalizeRelative(string value)
        {
            return (value ?? "").Replace('/', '\\').TrimStart('\\');
        }
    }
}
