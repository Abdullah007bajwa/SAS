import 'dart:io';

/// Cross-platform desktop file picker utilizing native OS utilities
/// without requiring third-party native plugin compilation.
class DesktopFilePicker {
  DesktopFilePicker._();

  /// Prompts the user to pick an image file (.png, .jpg, .jpeg, .webp, .bmp).
  /// Returns the absolute path of the chosen file, or null if cancelled or unavailable.
  static Future<String?> pickImageFile() async {
    try {
      if (Platform.isLinux) {
        // Try zenity first
        final zenityResult = await Process.run('zenity', [
          '--file-selection',
          '--title=Select Student / Staff Photo',
          '--file-filter=Images | *.png *.jpg *.jpeg *.webp *.bmp *.gif',
        ]);
        if (zenityResult.exitCode == 0) {
          final path = zenityResult.stdout.toString().trim();
          if (path.isNotEmpty && File(path).existsSync()) return path;
        }

        // Try kdialog fallback for KDE Plasma
        final kdialogResult = await Process.run('kdialog', [
          '--getopenfilename',
          '.',
          '*.png *.jpg *.jpeg *.webp *.bmp *.gif | Image files',
        ]);
        if (kdialogResult.exitCode == 0) {
          final path = kdialogResult.stdout.toString().trim();
          if (path.isNotEmpty && File(path).existsSync()) return path;
        }
      } else if (Platform.isWindows) {
        // Run lightweight PowerShell OpenFileDialog
        const psScript = r'''
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = "Select Student / Staff Photo"
$dialog.Filter = "Image Files (*.png;*.jpg;*.jpeg;*.webp)|*.png;*.jpg;*.jpeg;*.webp|All Files (*.*)|*.*"
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    Write-Output $dialog.FileName
}
''';
        final psResult = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          psScript,
        ]);
        if (psResult.exitCode == 0) {
          final path = psResult.stdout.toString().trim();
          if (path.isNotEmpty && File(path).existsSync()) return path;
        }
      }
    } catch (_) {
      // In non-graphical or sandbox test environments, gracefully return null
    }

    return null;
  }
}

