Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
strDir = fso.GetParentFolderName(WScript.ScriptFullName)
exePath = strDir & "\K50Bridge.exe"

If fso.FileExists(exePath) Then
    WshShell.Run """" & exePath & """", 0, False
End If
