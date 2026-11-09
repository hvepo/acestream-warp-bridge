Set WshShell = CreateObject("WScript.Shell")
appData = WshShell.ExpandEnvironmentStrings("%APPDATA%")
batPath = appData & "\ACEStream\engine\launch_acestream.bat"
WshShell.Run """" & batPath & """", 0, False
