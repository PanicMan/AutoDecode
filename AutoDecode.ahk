#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
#Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.

if A_WorkingDir =
	SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.

;-- Icon setzen
EnvGet, SysRoot, SYSTEMROOT
Menu, tray, icon, %SysRoot%\system32\SHELL32.dll, 44

;-- Menü erweitern
Menu, tray, add  ; Creates a separator line.
Menu, tray, add, Script abbrechen, AbortScript
Menu, tray, add, Rechner runterfahren, ShutdownPC
g_bAbort := false
g_bShutdown := false
g_sRotate = #NoRotate
g_bRotateOnly := false
g_bPortraitMode := false
g_bUseLSMASH := false
g_bSeriesConvert := false
g_bSeriesConvertAnim := false

;--- Priorität ändern
Process, priority, , Low  ; Have the script set itself to Low priority.

;--- Ini Laden
UseIniFile := A_ScriptDir . "\AutoDecode.ini"
IniRead, MeGuiPath, %UseIniFile%, General, MeGuiPath
IniRead, nHiReso, %UseIniFile%, General, HiReso
IniRead, nHiBpS, %UseIniFile%, General, HiBpS
IniRead, nMiReso, %UseIniFile%, General, MiReso
IniRead, nMiBpS, %UseIniFile%, General, MiBpS
IniRead, nLoReso, %UseIniFile%, General, LoReso
IniRead, nLoBpS, %UseIniFile%, General, LoBpS
IniRead, NetWorkMode, %UseIniFile%, General, Network
IniRead, nRotOnlyRes, %UseIniFile%, General, RotOnlyRes
IniRead, nRotOnlyBps, %UseIniFile%, General, RotOnlyBps
IniRead, nSeriesRes, %UseIniFile%, General, SeriesRes
IniRead, nSeriesBps, %UseIniFile%, General, SeriesBps
IniRead, nSeriesABps, %UseIniFile%, General, SeriesABps

;-- MediaInfo Initialisieren
hModule := DllCall("LoadLibrary", "str", MeGuiPath . "MediaInfo.dll")  ; Avoids the need for subsequent DllCalls to load the library

;Wenn Parameter übergeben, diese auswerten
if 0 > 0
{
	if 1 = -SeriesConvert
	{
		g_bSeriesConvert := true
		if 2 = -IsAnim
			g_bSeriesConvertAnim := true
	}
	else
	{
		if 2 = 
			MsgBox Kein Dateiname als 2. Parameter!
		else if 1 = -ao ;Nur Audio dekodieren
		{
			FileDelete, %2%.avs
			FileAppend, #File auto created by %A_ScriptName%, %2%.avs
			FileAppend, `nLoadPlugin("%MeGuiPath%tools\ffms\ffms2.dll"), %2%.avs
			FileAppend, `nFFAudioSource("%2%"), %2%.avs
		
			Tool = %MeGuiPath%tools\avs2pipemod\avs2pipemod.exe
			Script = -wav "%2%.avs"
			RunWait, %comspec% /c %Tool% %Script% | %MeGuiPath%tools\oggenc2\oggenc2.exe -Q --ignorelength --quality 2.0 -o "%2%_track1.ogg" -,, Min UseErrorLevel
			
			if ErrorLevel = 0
			{
				sFileOut = %2%
				StringTrimRight, sFileOut, sFileOut, 4
				
				Tool = %MeGuiPath%tools\mkvmerge\mkvmerge.exe
				RunWait, %comspec% /c %Tool% -o "%2%.mkv" --engage keep_bitstream_ar_info "--compression" "0:none" -d "0" --no-chapters -A -S "%sFileOut%.mkv" "--compression" "0:none" -a 0 --no-chapters -D -S "%2%_track1.ogg" --engage no_cue_duration --engage no_cue_relative_position --ui-language en,, Min UseErrorLevel
				
				if ErrorLevel = 0
				{
					FileDelete, %2%.avs
					FileDelete, %2%.ffindex
					FileDelete, %2%_track1.ogg
				}
			}
		}
		else if 1 contains -r
		{
			g_bRotateOnly := true
			
			Loop %0%  ; For each parameter (or file dropped onto a script):
			{
				;Ersten Parameter überspringen
				if A_Index = 1
					continue
					
				FileLongPath := %A_Index% ; Fetch the contents of the variable whose name is contained in A_Index.
				
				IfNotExist %FileLongPath% ; Sicher gehen dass es die datei gibt
					continue
				
				g_sRotate = #NoRotate
				if 1 = -rr ;Explizites drehen rechts
					g_sRotate = TurnRight()
				if 1 = -rl ;Explizites drehen links
					g_sRotate = TurnLeft()
				
				SplitPath, FileLongPath, OutFileName, OutDir, OutExtension, OutNameNoExt, OutDrive
				StringLower, OutExtension, OutExtension

				;wenn eine _org.* datei existiert, überspringen
				IfExist %OutDir%\%OutNameNoExt%_org.*
					continue

				;sind wir selbst eine _org.* datei?
				StringRight, OrgStr, OutNameNoExt, 4
				If OrgStr = _org
					continue
				
				sTempWorkDir = %A_ScriptDir%\tmp_%OutNameNoExt%
				FileCreateDir, %sTempWorkDir%
				FileCopy, %FileLongPath%, %sTempWorkDir%, 1
				FileLongPath = %sTempWorkDir%\%OutFileName%
				
				; Convertierung an eine Funktion übergeben
				ConvertFile(FileLongPath, OutExtension)

				; Temporäre Dateien wieder entfernen, nur wenn kein Fehler
				IfExist %sTempWorkDir%\%OutNameNoExt%_.mp4
				{
					FileMove, %OutDir%\%OutNameNoExt%.%OutExtension%, %OutDir%\%OutNameNoExt%_org.%OutExtension%
					FileMove, %sTempWorkDir%\%OutNameNoExt%_.mp4, %OutDir%\%OutNameNoExt%.mp4
					FileRemoveDir, %sTempWorkDir%, 1
				}
				
				if g_bAbort ;Wenn Abbruchbefehl, abrrechen
					break
			}
			SoundPlay *-1
		}
		else
			MsgBox Falsche Parameter!`nNur -ao/-rr akzeptiert!
			
		ExitApp
	}
}

;-- Alle Dateien durchgehen
Loop, *.*,, 1
{
	; Alle Dateien außer Video-Dateien überspringen
    StringLower, FileExtLo, A_LoopFileExt
	FileLongPath = %A_LoopFileLongPath%
	
	if FileExtLo not in avi,mkv,mp4,mpg,mpeg,mov,wmv,flv
		continue
	
	; Wenn eine .inwork-datei existiert, überspringen
	IfExist %FileLongPath%.inwork
		continue

	StringTrimRight, sFileNameOrg, FileLongPath, 4
	StringTrimRight, sFileNamePure, A_LoopFileName, 4

	; mpeq in mpg umwandeln und damit weitermachen
	if FileExtLo = mpeg
	{
		StringTrimRight, sFileNameOrg, FileLongPath, 5
		StringTrimRight, sFileNamePure, A_LoopFileName, 5
		
		FileMove, %FileLongPath%, %sFileNameOrg%.mpg
		FileLongPath := sFileNameOrg . ".mpg"
		FileExtLo = mpg
	}
	
	; Wenn eine *.mkv-datei existiert, überspringen
	if (FileExtLo <> "mkv")
		IfExist %sFileNameOrg%.mkv
			continue

	; Wenn eine *-muxed.mkv-datei existiert, überspringen
	IfExist %sFileNameOrg%-muxed.mkv
		continue

	; Wenn eine *_as_mkv.mkv-datei existiert, überspringen
	IfExist %sFileNameOrg%_as_mkv.mkv
		continue

	; Wenn eine *_.mkv-datei existiert, überspringen
	IfExist %sFileNameOrg%_.mkv
		continue

	; Die -muxed.mkv selber auch überspringen
	StringRight, MuxedStr, FileLongPath, 10
	If MuxedStr = -muxed.mkv
		continue

	;Bei MKV: Wenn eine der anderen Dateien als Source bereits existiert, überspringen
	if FileExtLo = mkv
	{
		IfExist %sFileNameOrg%.avi
			continue
		IfExist %sFileNameOrg%.mp4
			continue
		IfExist %sFileNameOrg%.mpg
			continue
		IfExist %sFileNameOrg%.mov
			continue
		IfExist %sFileNameOrg%.wmv
			continue
		IfExist %sFileNameOrg%.flv
			continue
		StringTrimRight, sFileNameOrg, sFileNameOrg, 1 ;Wegen dem _
		IfExist %sFileNameOrg%.mkv
			continue
	}

	;Vorhandene Datei überspringen wenn der vorhandene Platz nicht mind. 2x so viel ist
	StringLeft, DriveLetter, FileLongPath, 3
	DriveSpaceFree, DriveFree, %DriveLetter%
	if (DriveFree < A_LoopFileSizeMB * 2)
	{
		sCommand := "Skipped: DriveSpace < " . (A_LoopFileSizeMB * 2) . "MB, Free: " . DriveFree . "MB"
		CreateErrorFile(FileLongPath, sCommand, 0, 0)
		continue
	}

	; Markieren dass hier gearbeitet wird
	FileAppend, #Work on File by %A_ScriptName%`n, %FileLongPath%.inwork
	; Convertierung an eine Funktion übergeben
	ConvertFile(FileLongPath, FileExtLo)
	; Arbeitsmarkierung wieder entfernen
	FileDelete, %FileLongPath%.inwork
	
	if g_bAbort ;Wenn Abbruchbefehl, abrrechen
		break

	;Wenn wir unter einem Gigabyte sind, abbrechen
	DriveSpaceFree, DriveFree, %DriveLetter%
	if DriveFree < 1024
	{
		sCommand := "Abort: DriveSpace < 1024MB, Free: " . DriveFree . "MB"
		CreateErrorFile(FileLongPath, sCommand, 0, 0)
		break
	}
}

;-- MediaInfo entladen
DllCall("FreeLibrary", "UInt", hModule)  ; To conserve memory, the DLL may be unloaded after using it.
SoundPlay *-1

if g_bShutdown ;Wenn Shutdown, herunterfahren
	RunWait, %comspec% /c shutdown /s /t 60,, Min UseErrorLevel
ExitApp

;-------------------------------------------------------------------------------------------------------------------
ConvertFile(sFileName, sFileExt) 
{
	global MeGuiPath, nHiReso, nHiBpS, nMiReso, nMiBpS, nLoReso, nLoBpS, sCommand, NetWorkMode, nRotOnlyRes, nRotOnlyBps, sFileNamePure, g_sRotate, g_bRotateOnly, g_bPortraitMode, sTempWorkDir, g_bUseLSMASH, g_bSeriesConvert, g_bSeriesConvertAnim, nSeriesBps, nSeriesABps
	Menu, tray, tip, %A_ScriptName%`nCurrent: %sFileName%
	
	StringTrimRight, sFileNameOut, sFileName, 4
	
	;wenn eine Log-Datei existiert, schauen bis wo gearbeitet wurde
	bStep0 := bStep1 := bStep2 := bStep3 := bStep4 := bStep5 := bStep6 := bStep7 := bStep8 := false
	Loop, read, %sFileName%.log
	{
		sNum := SubStr(A_LoopReadLine, 11, 1)
		bStep%sNum% := true
	}

	;wenn der Schritt für die Umwandlung existiert, abbrechen
	if (bStep8 = true)
	{
		; Arbeitsmarkierung wieder entfernen
		FileDelete, %sFileName%.inwork
		return
	}
	
	; Bei avi, mp4, mpg erstmal in mkv muxen und dann ganz normal mit mkv weitermachen, nicht im rotations- oder serienmodus
	if (g_bRotateOnly = false AND g_bSeriesConvert = false)
		if sFileExt in avi,mp4,mpg,mov,flv
		{
			; Im Netzwerkmodus lokal arbeiten
			if (NetWorkMode = "1")
			{
				Random, rand , 0, 9 ; nur für den fall der Fälle
				sTempWorkDir = %A_ScriptDir%\tmp%rand%_%sFileNamePure%
				FileCreateDir, %sTempWorkDir%
				sFileNameOutTemp = %sFileNameOut%
				sFileNameOut = %sTempWorkDir%\%sFileNamePure%
			}
			
			ErrorLevel = 0
			IfNotExist %sFileNameOut%_as_mkv.mkv
			{
				ToolPathAndName = %MeGuiPath%tools\mkvmerge\mkvmerge.exe
				RunWait, %comspec% /c %ToolPathAndName% -o "%sFileNameOut%_as_mkv.mkv" "%sFileName%" "--compression" "0:none" --ui-language en,, Min UseErrorLevel
			}
			if ErrorLevel not in 0,1
			{
				; Im Netzwerkmodus lokal aufräumen
				if (NetWorkMode = "1")
				{
					sFileNameOut = %sFileNameOutTemp%
					FileRemoveDir, %sTempWorkDir%, 1 
				}

				sCommand = %ToolPathAndName% -o "%sFileNameOut%_as_mkv.mkv" "%sFileName%" "--compression" "0:none" --ui-language en
				CreateErrorFile(sFileName, sCommand, ErrorLevel, A_LastError)
				;Hat nicht geklappt, also normal weitermachen
			}
			else
			{
				AppendLogFile(sFileName, 8, "Converted to MKV continue with it")
				
				;Hat geklappt, als temporäre MKV weitermachen
				sFileName = %sFileNameOut%_as_mkv.mkv
				
				; Markieren dass hier gearbeitet wird
				FileAppend, #Work on File by %A_ScriptName%`n, %sFileName%.inwork
				
				;Rekursiver aufruf mit der neuen Datei
				ConvertFile(sFileName, "mkv")
				
				;temporäre Dateien wieder entfernen, nur wenn kein Fehler
				IfExist %sFileNameOut%.mkv
				{
					; Im Netzwerkmodus lokal aufräumen
					if (NetWorkMode = "1")
					{
						FileMove, %sFileNameOut%.mkv, %sFileNameOutTemp%.mkv
						FileRemoveDir, %sTempWorkDir%, 1
					}

					; _as_mkv.mkv Datei löschen
					FileDelete, %sFileName%
				}

				; Arbeitsmarkierung wieder entfernen
				FileDelete, %sFileName%.inwork
				return
			}
		}

	;-- Nötige FileInfos auslesen
	handle := DllCall("mediainfo\MediaInfo_New") ;initialize mediainfo
	resultopenfile := DllCall("mediainfo\MediaInfoA_Open", "UInt", handle, "str", sFileName) ;open the file

	if resultopenfile
	{
		RetPtr:=DllCall("mediainfo\MediaInfoA_Get", "UInt", handle, "int", 1, "int", 0, "str", "Width", "int", 1, "int", 0)
		nWidth := ExtractData(RetPtr)
		RetPtr:=DllCall("mediainfo\MediaInfoA_Get", "UInt", handle, "int", 1, "int", 0, "str", "Height", "int", 1, "int", 0)
		nHeight := ExtractData(RetPtr)
		RetPtr:=DllCall("mediainfo\MediaInfoA_Get", "UInt", handle, "int", 1, "int", 0, "str", "Width_Original", "int", 1, "int", 0)
		nWidth_Original := ExtractData(RetPtr)
		RetPtr:=DllCall("mediainfo\MediaInfoA_Get", "UInt", handle, "int", 1, "int", 0, "str", "Height_Original", "int", 1, "int", 0)
		nHeight_Original := ExtractData(RetPtr)
		RetPtr:=DllCall("mediainfo\MediaInfoA_Get", "UInt", handle, "int", 1, "int", 0, "str", "FrameRate", "int", 1, "int", 0)
		nFPS := ExtractData(RetPtr)	
		RetPtr:=DllCall("mediainfo\MediaInfoA_Get", "UInt", handle, "int", 0, "int", 0, "str", "AudioCount", "int", 1, "int", 0)
		nAudioCount := ExtractData(RetPtr)
		RetPtr:=DllCall("mediainfo\MediaInfoA_Get", "UInt", handle, "int", 1, "int", 0, "str", "Rotation", "int", 1, "int", 0)
		nRotation := ExtractData(RetPtr)	
		
		; Automatisch drehen, nur bei RotationsModus
		if (g_bRotateOnly)
		{
			if nRotation = 90.000
				g_sRotate = TurnRight()
			else if nRotation = 180.000
				g_sRotate = TurnRight()`nTurnRight()
			else if nRotation = 270.000
				g_sRotate = TurnLeft()
		}
		
		DllCall("mediainfo\MediaInfoA_Close", "UInt", handle) ;close the file
		handle := DllCall("mediainfo\MediaInfo_Delete", "UInt", handle) ;Delete MediaInfo handle

		; Portrait Modus?
		if (nWidth < nHeight)
			g_bPortraitMode := true
		
		;Init new Run
		if (bStep0 = false)
			AppendLogFile(sFileName, 0, "--- Init new Run ---")

		;Avs-Datei erstellen
		if (bStep1 = false)
		{
			CreateAvsFile(sFileName, sFileExt, nWidth_Original ? nWidth_Original : nWidth, nHeight_Original ? nHeight_Original : nHeight, nFPS, g_bRotateOnly)
			AppendLogFile(sFileName, 1, "avs file")
		}
		
		;Wenn nicht AVI ffmsindex aufrufen
		if (bStep2 = false)
		{
			if sFileExt != avi
			{
				ToolPathAndName = %MeGuiPath%tools\ffms\ffmsindex.exe
				RunWait, %comspec% /c %ToolPathAndName% -t -1 -f "%sFileName%" "%sFileName%.ffindex",, Min UseErrorLevel
				if ErrorLevel != 0
				{
					sCommand = %ToolPathAndName% -t -1 -f "%sFileName%" "%sFileName%.ffindex"
					CreateErrorFile(sFileName, sCommand, ErrorLevel, A_LastError)
					
					;Bei wmv einfach weitermachen, da dann wohl über DS geht, sonst LSMASH benutzen
					if sFileExt != wmv
					{
						g_bUseLSMASH := true
						CreateAvsFile(sFileName, sFileExt, nWidth_Original ? nWidth_Original : nWidth, nHeight_Original ? nHeight_Original : nHeight, nFPS, g_bRotateOnly)
					}
				}
				else
					AppendLogFile(sFileName, 2, "ffmsindex")
			}
			else
				AppendLogFile(sFileName, 2, "not necessary")
		}
		
		;bei avi,mkv,mp4,mpg,mov,wmv audio über BePipe oder avs2pipemod decodieren
		if (bStep3 = false AND nAudioCount > 0)
		{
			if sFileExt in avi,mkv,mp4,mpg,mov,wmv,flv
			{
				bTryDS := false
				bTryAvs2Pipe := false
				bTryAvs2Pipe2 := false
				bTryAvs2Pipe3 := false
				bWMVasDS := (sFileExt = "wmv")
				if (g_bUseLSMASH)
				{
					bTryAvs2Pipe := true
					bTryAvs2Pipe2 := true
					bTryAvs2Pipe3 := true
				}
				
				Loop
				{
					ToolPathAndName = %MeGuiPath%tools\BePipe\BePipe.exe
					TargetCommand = %MeGuiPath%tools\oggenc2\oggenc2.exe -Q --ignorelength --quality 2.0 -o "%sFileName%_track1.ogg" -
					LoadPlugin =
					
					;Bei rotate immer über pipemod gehen und als mpa encdieren
					if (g_bRotateOnly)
					{
						bTryAvs2Pipe := true
						TargetCommand = %MeGuiPath%tools\neroaacenc\win32\neroAacEnc.exe -ignorelength -q 0.5 -if - -of "%sFileName%.m4a"
					}
					else if (g_bSeriesConvert)
					{
						bTryAvs2Pipe := true
						bTryAvs2Pipe2 := true
						TargetCommand = %MeGuiPath%tools\lame\lame.exe -b %nSeriesABps% -h - "%sFileName%.mp3"
					}
					
					if ((bTryAvs2Pipe = false AND (sFileExt = "avi" OR bTryDS)) OR (sFileExt = "wmv" AND bWMVasDS))
					{
						LoadPlugin = --lp "%MeGuiPath%tools\avs\directshowsource.dll"
						RunScript = --script "DirectShowSource(^%sFileName%^, fps=%nFPS%, audio=true)"
					}
					else if (bTryAvs2Pipe3)
					{
						ToolPathAndName = %MeGuiPath%tools\avs2pipemod\avs2pipemod.exe
						LoadPlugin =
						RunScript = -wav "%sFileName%_audio3.avs"
					}
					else if (bTryAvs2Pipe2)
					{
						ToolPathAndName = %MeGuiPath%tools\avs2pipemod\avs2pipemod.exe
						LoadPlugin =
						RunScript = -wav "%sFileName%_audio2.avs"
					}
					else if (bTryAvs2Pipe)
					{
						ToolPathAndName = %MeGuiPath%tools\avs2pipemod\avs2pipemod.exe
						LoadPlugin =
						RunScript = -wav "%sFileName%_audio.avs"
					}
					else
					{
						LoadPlugin = --lp "%MeGuiPath%tools\ffms\ffms2.dll"
						RunScript = --script "FFAudioSource(^%sFileName%^, cachefile=^%sFileName%.ffindex^)"
					}
					
					;Hier anders, da es öffter hängen bleibt, starten und weiter
					Run, %comspec% /c %ToolPathAndName% %LoadPlugin% %RunScript% | %TargetCommand%,, Min UseErrorLevel, runID
					WinWait, ahk_pid %runID%,,5 ;5 Sec warten bis startet
					if ErrorLevel = 0 
					{
						WinWaitClose, ahk_pid %runID%,,600 ;10 Min warten bis fertig
						if ErrorLevel != 0 
						{
							while (WinExist("ahk_pid " runID))
								WinKill, ahk_pid %runID%
						
							;Evtl vorhandene Reste von Audio löschen
							FileDelete, %sFileName%_track1.ogg
							FileDelete, %sFileName%.m4a
						}	
					}
					
					If (!FileExist(sFileName "_track1.ogg") AND !FileExist(sFileName ".m4a") AND !FileExist(sFileName ".mp3"))
					{
						sCommand = Flags: bTryDS=%bTryDS%, bWMVasDS=%bWMVasDS%, bTryAvs2Pipe=%bTryAvs2Pipe%, bTryAvs2Pipe2=%bTryAvs2Pipe2%, bTryAvs2Pipe3=%bTryAvs2Pipe3%`n%ToolPathAndName% %LoadPlugin% %RunScript% | %TargetCommand%
						CreateErrorFile(sFileName, sCommand, ErrorLevel, A_LastError)
						
						if (sFileExt = "wmv" and bWMVasDS)
							bWMVasDS := false
						else if (sFileExt = "avi" AND bTryAvs2Pipe = false)
							bTryAvs2Pipe := true
						else if (sFileExt != "avi" AND sFileExt != "wmv" AND bTryDS = false)
							bTryDS := true
						else if (sFileExt != "avi" AND bTryAvs2Pipe = false)
							bTryAvs2Pipe := true
						else if (sFileExt != "avi" AND bTryAvs2Pipe = true AND bTryAvs2Pipe2 = false)
							bTryAvs2Pipe2 := true
						else if (sFileExt != "avi" AND bTryAvs2Pipe = true AND bTryAvs2Pipe2 = true AND bTryAvs2Pipe3 = false)
							bTryAvs2Pipe3 := true
						else
							return
					}
					else
					{
						sLogText = Decode/Encode Audio (WMVasDS=%bWMVasDS%, TryDS=%bTryDS%, TryAvs2Pipe=%bTryAvs2Pipe%|%bTryAvs2Pipe2%|%bTryAvs2Pipe3%)
						AppendLogFile(sFileName, 3, sLogText)
						if bWMVasDS
							CreateAvsFile(sFileName, sFileExt, nWidth_Original ? nWidth_Original : nWidth, nHeight_Original ? nHeight_Original : nHeight, nFPS, true)
						break
					}
				}
			}
		}
		
		;bitrate bestimmen
		nTemp := g_bPortraitMode ? nHeight : nWidth
		nBitrate := nLoBpS
		sTune =
		
		if (g_bRotateOnly)
			nBitrate := nRotOnlyBps
		else if (g_bSeriesConvert)
			nBitrate := nSeriesBps
		else if nTemp >= %nHiReso%
			nBitrate := nHiBpS
		else if nTemp >= %nMiReso%
			nBitrate := nMiBpS
		
		if (g_bSeriesConvertAnim)
			sTune = --tune animation
		
		;erster und zweiter pass
		if (bStep4 = false)
		{
			ToolPathAndName = %MeGuiPath%tools\x264\avs4x264mod.exe
			RunWait, %comspec% /c %ToolPathAndName% --pass 1 %sTune% --bitrate %nBitrate% --stats "%sFileName%.stats" --sar 1:1 --output NUL "%sFileName%.avs",, Min UseErrorLevel
			if ErrorLevel != 0
			{
				sCommand = %ToolPathAndName% --pass 1 %sTune% --bitrate %nBitrate% --stats "%sFileName%.stats" --sar 1:1 --output NUL "%sFileName%.avs"
				CreateErrorFile(sFileName, sCommand, ErrorLevel, A_LastError)
				return
			}
			else
				AppendLogFile(sFileName, 4, "first pass")
		}
		
		if (bStep5 = false)
		{
			ToolPathAndName = %MeGuiPath%tools\x264\avs4x264mod.exe
			RunWait, %comspec% /c %ToolPathAndName% --pass 2 %sTune% --bitrate %nBitrate% --stats "%sFileName%.stats" --sar 1:1 --output "%sFileName%.264" "%sFileName%.avs",, Min UseErrorLevel
			if ErrorLevel != 0
			{
				sCommand = %ToolPathAndName% --pass 2 %sTune% --bitrate %nBitrate% --stats "%sFileName%.stats" --sar 1:1 --output "%sFileName%.264" "%sFileName%.avs"
				CreateErrorFile(sFileName, sCommand, ErrorLevel, A_LastError)
				return
			}
			else
				AppendLogFile(sFileName, 5, "second pass")
		}
				
		;Video und Audio Muxen
		if (bStep6 = false)
		{
			;temporäre erweiterung _as_mkv wieder entfernen
			if (SubStr(sFileNameOut, -6) = "_as_mkv")
				sFileNameOut := SubStr(sFileNameOut, 1, StrLen(sFileNameOut)-7)
			else if (sFileExt = "mkv" OR g_bRotateOnly) 
				sFileNameOut = %sFileNameOut%_ ;Bei MKV oder Rotation noch Unterstrich hinzufügen
			
			; Bei rotation als mp4 muxen
			if (g_bRotateOnly)
			{
				ToolPathAndName = %MeGuiPath%tools\mp4box\mp4box.exe

				;Audio überhaupt vorhanden?
				AudioCommand =
				if (nAudioCount > 0)
					AudioCommand = -add "%sFileName%.m4a#trackID=1"

				TargetCommand = -add "%sFileName%.264#trackID=1:fps=%nFPS%" %AudioCommand% -tmp "%sTempWorkDir%" -new "%sFileNameOut%.mp4"
			}
			else
			{
				ToolPathAndName = %MeGuiPath%tools\mkvmerge\mkvmerge.exe

				;Audio überhaupt vorhanden?
				AudioCommand =
				if (nAudioCount > 0)
				{
					if (g_bSeriesConvert)
						AudioCommand = -D -S "%sFileName%.mp3"
					else
						AudioCommand = -D -S "%sFileName%_track1.ogg"
				}
				
				TargetCommand = -o "%sFileNameOut%.mkv" --engage keep_bitstream_ar_info "--compression" "0:none" -d "0" --no-chapters -A -S "%sFileName%.264" "--compression" "0:none" -a 0 --no-chapters %AudioCommand% --engage no_cue_duration --engage no_cue_relative_position --ui-language en
			}
			
			RunWait, %comspec% /c %ToolPathAndName% %TargetCommand%,, Min UseErrorLevel
			if ErrorLevel != 0
			{
				sCommand = %ToolPathAndName% %TargetCommand%
				CreateErrorFile(sFileName, sCommand, ErrorLevel, A_LastError)
				return
			}
			else
				AppendLogFile(sFileName, 6, "mux")
		}
		
		;Aufräumen
		if (bStep7 = false)
		{
			FileDelete, %sFileName%.avs
			FileDelete, %sFileName%_audio.avs
			FileDelete, %sFileName%_audio2.avs
			FileDelete, %sFileName%_audio3.avs
			FileDelete, %sFileName%.ffindex
			FileDelete, %sFileName%.lwi
			FileDelete, %sFileName%.m4a
			FileDelete, %sFileName%.mp3
			FileDelete, %sFileName%_track1.ogg
			FileDelete, %sFileName%.stats
			FileDelete, %sFileName%.stats.mbtree
			FileDelete, %sFileName%.264
			FileDelete, %sFileName%.err
			AppendLogFile(sFileName, 7, "### all done! ###")
		}
	}
	else
		handle := DllCall("mediainfo\MediaInfo_Delete", "UInt", handle) ;Delete MediaInfo handle
}
;-------------------------------------------------------------------------------------------------------------------
CreateAvsFile(sFileName, sFileExt, nWidth, nHeight, nFPS, bForceDS=0)
{
	global MeGuiPath, nHiReso, nMiReso, nLoReso, nRotOnlyRes, g_sRotate, g_bRotateOnly, g_bPortraitMode, g_bUseLSMASH, g_bSeriesConvert, nSeriesRes
	sParams = %sFileName%, %sFileExt%, %nWidth%, %nHeight%, %nFPS%, ForceDS:%bForceDS%, UseLSMASH:%g_bUseLSMASH%
	bExtraAudioAvs := true ;einfach immer anlegen, schadet nix
	
	;Bei AVI anders
	if (sFileExt = "avi" OR bForceDS)
	{
		LibInclude = LoadPlugin("%MeGuiPath%tools\avs\directshowsource.dll")
		if (g_bRotateOnly = false)
			FileSource = DirectShowSource("%sFileName%", fps=%nFPS%, audio=false)
		else
			FileSource = DirectShowSource("%sFileName%", fps=%nFPS%, audio=false, convertfps=true).AssumeFPS(%nFPS%)
	}
	else if (g_bUseLSMASH)
	{
		LibInclude = LoadPlugin("%MeGuiPath%tools\lsmash\LSMASHSource.dll")
		FileSource = LWLibavVideoSource("%sFileName%")
	}
	else
	{
		LibInclude = LoadPlugin("%MeGuiPath%tools\ffms\ffms2.dll")
		FileSource = FFVideoSource("%sFileName%", threads=1)
	}
	
	if (bExtraAudioAvs)
	{
		LibIncludeAudio = LoadPlugin("%MeGuiPath%tools\ffms\ffms2.dll")
		FileSourceAudio = FFAudioSource("%sFileName%")
		
		;Noch eine fürs Audio erstellen, vorhandene löschen
		FileDelete, %sFileName%_audio.avs
		FileAppend, #File auto created by %A_ScriptName% (Params: %sParams%)`n%LibIncludeAudio%`n%FileSourceAudio%, %sFileName%_audio.avs
		
		FileSourceAudio = DirectShowSource("%sFileName%", fps=%nFPS%, audio=true, convertfps=true).AssumeFPS(%nFPS%)
		
		;Noch eine fürs Audio erstellen, vorhandene löschen
		FileDelete, %sFileName%_audio2.avs
		FileAppend, #File auto created by %A_ScriptName% (Params: %sParams%)`n%FileSourceAudio%, %sFileName%_audio2.avs

		;Noch eine fürs LSMASH Audio erstellen, vorhandene löschen
		FileDelete, %sFileName%_audio3.avs
		LibIncludeAudio = LoadPlugin("%MeGuiPath%tools\lsmash\LSMASHSource.dll")
		FileSourceAudio = LWLibavAudioSource("%sFileName%")
		FileAppend, #File auto created by %A_ScriptName% (Params: %sParams%)`n%LibIncludeAudio%`n%FileSourceAudio%, %sFileName%_audio3.avs
	}

	; Temporär Höhe mit Breite tauschen
	if (g_bPortraitMode)
	{
		nTemp := nWidth
		nWidth := nHeight
		nHeight := nTemp
	}
	
	;Auflösung für resize bestimmen
	nWidthNew := nWidth
	
	if (g_bSeriesConvert)
	{
		if (nWidth > nSeriesRes)
			nWidthNew := nSeriesRes
	}
	else if (g_bRotateOnly)
	{
		if (nWidth > nRotOnlyRes)
			nWidthNew := nRotOnlyRes
	}
	else
	{
		if nWidth >= %nHiReso%
			nWidthNew := nHiReso
		else if nWidth >= %nMiReso%
			nWidthNew := nMiReso
		else if nWidth >= %nLoReso%
			nWidthNew := nLoReso
	}
			
	FileResize = 
	if nWidthNew <> %nWidth%
	{
		dAR := nWidth / nHeight
		nHeightNew := Round(nWidthNew / dAR)
		rem := Mod(nHeightNew, 4)
		nHeightNew := nHeightNew - rem
		
		; wieder zurück tauschen
		if (g_bPortraitMode)
		{
			nTemp := nWidthNew
			nWidthNew := nHeightNew
			nHeightNew := nTemp
		}
		
		FileResize = Lanczos4Resize(%nWidthNew%,%nHeightNew%) # Lanczos4 (Sharp) (PortraitMode=%g_bPortraitMode%)
		
		;Wenn sehr kleine größe, Sharpen hinzufügen
		if ((nWidthNew < nLoReso AND g_bPortraitMode = false) OR (nHeightNew < nLoReso AND g_bPortraitMode))
			FileResize = %FileResize%`nSharpen(0.33)
	}
	
	;Datei Speichern, vorher löschen
	FileDelete, %sFileName%.avs
	sTry = try `{
	sCatch = `} catch (err) `{`n`tWriteFileStart(BlankClip(), "%sFileName%.avs.err", "script", """ ": " """, err, append=true)`n`}
	
	; Bei Rotate kein Try/Catch, kein plan warum das nicht tut...
	if (g_bRotateOnly)
	{
		sTry =
		sCatch = 
	}
	
	sCommands = %sTry%`n`t%LibInclude%`n`t%FileSource%`n`t%FileResize%`n`t%g_sRotate%`n`tConvertToYV12()`n%sCatch%
	FileAppend, #File auto created by %A_ScriptName% (Params: %sParams%)`n%sCommands%, %sFileName%.avs
}
;-------------------------------------------------------------------------------------------------------------------
CreateErrorFile(sFileName, sCommand, sErrorcode, nLastError)
{
	;Fehlerdatei erstellen
	FileAppend, #Error occured in %A_ScriptName% while:`n%sCommand%`nErrorcode:%sErrorcode%`nLastError:%nLastError%`n, %sFileName%.err
}
;-------------------------------------------------------------------------------------------------------------------
AppendLogFile(sFileName, nStep, sCommand)
{
	;Fehlerdatei erstellen
	FileAppend, Done Step %nStep%: %sCommand%`n, %sFileName%.log
}
;-------------------------------------------------------------------------------------------------------------------
ExtractData(pointer) 
{
	String :=
	Loop 
	{
       errorLevel := ( pointer+(A_Index-1) )
       Asc := *( errorLevel )
       IfEqual, Asc, 0, Break ; Break if NULL Character
       String := String . Chr(Asc)
    }
	Return String
}
;-------------------------------------------------------------------------------------------------------------------
AbortScript:
	global g_bAbort
	if (g_bAbort = true)
	{
		g_bAbort := false
		Menu, tray, uncheck, %A_ThisMenuItem%
	} 
	else 
	{
		g_bAbort := true
		Menu, tray, check, %A_ThisMenuItem%
	}
	return
;-------------------------------------------------------------------------------------------------------------------
ShutdownPC:
	global g_bShutdown
	if (g_bShutdown = true)
	{
		g_bShutdown := false
		Menu, tray, uncheck, %A_ThisMenuItem%
	} 
	else 
	{
		g_bShutdown := true
		Menu, tray, check, %A_ThisMenuItem%
	}
	return
;-------------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------------
