Option Explicit

Dim fso, shell, root, cmd, rc
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

root = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = """" & shell.ExpandEnvironmentStrings("%ComSpec%") & """ /d /c call """ & root & "\Launch-YUMRAM.cmd"""

On Error Resume Next
rc = shell.Run(cmd, 1, True)
If Err.Number <> 0 Then
    MsgBox "YUMRAM launcher error: " & Err.Description, 16, "YUMRAM"
    WScript.Quit 1
End If
On Error GoTo 0
WScript.Quit rc
