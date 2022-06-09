#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.
#Persistent
#SingleInstance Force
SplitPath, A_ScriptFullPath, ScriptFileName, ScriptDir, ScriptExtension, ScriptNameNoExt, ScriptDrive

global ScriptNameNoExt


IfNotExist, %A_ScriptDir%/%ScriptNameNoExt%.ini
{
	;IniWrite, Value, Filename, Section, Key
	msgbox ini not found, creating.
	EnvGet, ProcessorCount, NUMBER_OF_PROCESSORS 
	IniWrite, %ProcessorCount%, %A_ScriptDir%/%ScriptNameNoExt%.ini, Config, Core Limit
	IniWrite, 3, %A_ScriptDir%/%ScriptNameNoExt%.ini, Config, Priority
	IniWrite, 1, %A_ScriptDir%/%ScriptNameNoExt%.ini, Config, Reverse Core Limit
	IniWrite, 1, %A_ScriptDir%/%ScriptNameNoExt%.ini, Config, Apply On Start
}

;IniRead, OutputVar, Filename, Section, Key
IniRead, ConfigCoreLimit, %A_ScriptDir%/%ScriptNameNoExt%.ini, Config, Core Limit
IniRead, ConfigPriority, %A_ScriptDir%/%ScriptNameNoExt%.ini, Config, Priority
IniRead, CLorder, %A_ScriptDir%/%ScriptNameNoExt%.ini, Config, Reverse Core Limit
IniRead, AutoApplyOnStart, %A_ScriptDir%/%ScriptNameNoExt%.ini, Config, Apply On Start

Global ConfigCoreLimit
Global ConfigPriority
Global CLorder

FileRead, NodeConfigJson, %A_ScriptDir%/../configs/Tdarr_Node_Config.json
;msgbox % NodeConfigJson
NodeConfig := JsonToAHK(NodeConfigJson)
NodeID := NodeConfig.nodeID
NodeIP := NodeConfig.serverIP
NodePort:= NodeConfig.serverPort
NodeURL = http://%NodeIP%:%NodePort%
global CLOrder
;msgbox % NodeURL
gosub MenuInit
gosub Init

ChkInt := 750

SetTimer, PIDMonitor, %ChkInt%

;SetTimer, NodeRunningMonitor, 3000
;SetTimer, NodePausedMonitor, 3000
;SetTimer, WorkerLimits, 15000

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;Functions;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
return


MenuInit:
{
	If !A_IsCompiled
		Menu, Tray, Add
	
	Menu, Tray, Add, Run Node, RunToggle
	;Menu, Tray, Add, Pause Node, PauseNodeToggle
	Menu, Tray, Add, Show Console, ShowToggle
	ShowTdarr := 0
	Menu, Tray, Add
	gosub WorkerLimits
	
	C_HC_C := Func("ChangeWorkers").Bind(NodeID, NodeURL, 1, 1)
	Menu, Health Checks, Add, CPU: (%HC_CPU%), % C_HC_C
	
	C_HC_G := Func("ChangeWorkers").Bind(NodeID, NodeURL, 1, 2)
	Menu, Health Checks, Add, GPU: (%HC_GPU%), % C_HC_G
	
	C_TC_C := Func("ChangeWorkers").Bind(NodeID, NodeURL, 2, 1)
	Menu, Transcodes, Add, CPU: (%TC_CPU%), % C_TC_C
	
	C_TC_G := Func("ChangeWorkers").Bind(NodeID, NodeURL, 2, 2)
	Menu, Transcodes, Add, GPU: (%TC_GPU%), % C_TC_G
	
	Menu, Workers, Add, Health Checks, :Health Checks
	Menu, Workers, Add, Transcodes, :Transcodes	
	Menu, Workers, Add, Refresh, MenuWorkerRefresh
	Menu, Tray, Add, Worker Limits, :Workers
	

;need to loop through cpu count and make core control
	EnvGet, ProcessorCount, NUMBER_OF_PROCESSORS
	loop, %ProcessorCount%
	{
		;CCC%A_Index% := Func("CCCv2").Bind(A_Index)
		AfSet%A_Index% := Func("AfSet").Bind(A_Index)
		Menu, Cores, Add, %A_Index%, % AfSet%A_Index%
	}
	Menu, Cores, Add
	Menu, Cores, Add, Reverse, ToggleClOrder
	if (CLOrder = 0)
		Menu, Cores, Uncheck, Reverse
	else
		Menu, Cores, Check, Reverse
		
	Menu, Cores, Check, %ProcessorCount%
	Menu, Tray, Add, Core Limit, :Cores
	
;need to make priority control menu
	;L (or Low), B (or BelowNormal), N (or Normal), A (or AboveNormal), H (or High), R (or Realtime)
	p6 := Func("PrioSet").Bind("R")
	Menu, Priority, Add, Realtime, % p6
	p5 := Func("PrioSet").Bind("H")
	Menu, Priority, Add, High, % p5
	p4 := Func("PrioSet").Bind("A")
	Menu, Priority, Add, AboveNormal, % p4
	p3 := Func("PrioSet").Bind("N")
	Menu, Priority, Add, Normal, % p3
	p2 := Func("PrioSet").Bind("B")
	Menu, Priority, Add, BelowNormal, % p2
	p1 := Func("PrioSet").Bind("L")
	Menu, Priority, Add, Low, % p1
	Menu, Tray, Add, Priority, :Priority

    If A_IsCompiled
	{
	Menu, Tray, NoDefault
	Menu, Tray, NoStandard
	
	Menu, Tray, Add
	Menu, Tray, Add, Exit TNC, ExitNow
	;Menu, Tray, Add, Exit TNC and kill node, KillNodeAndExit
	}
	return
}

init:
{
	AfSet(ConfigCoreLimit)
	PrioSet(ConfigPriority)

return
}
PIDMonitor:
{
	
	ObjRelease(ffmpegPids)

	global ffmpegPids := []
	
	;;;;;;;;;;Find node workers and parent
	for proc in ComObjGet("winmgmts:").ExecQuery("Select * from Win32_Process WHERE Name = 'Tdarr_Node.exe'")
	{
		name := proc.Name
		cmd := proc.CommandLine
		pid := proc.ProcessId
		;msgbox name: %name%`n cmd: %pid%
		Haystack := cmd
		Needle := "worker"
		If InStr(Haystack, Needle)
				continue
		else
				global tParentPid := pid
	}
	ObjRelease(proc)
	ObjRelease(cmd)
	if (tParentPid > 0)
		Menu, Tray, Check, Run Node
	else
		Menu, Tray, Uncheck, Run Node

	;;;;;;;;;;;Find ffmpegs
	for proc in ComObjGet("winmgmts:").ExecQuery("Select * from Win32_Process WHERE Name = 'ffmpeg.exe'")
	{
		pid := proc.ProcessId
		ffmpegPids.Push(pid)
	}
	ObjRelease(proc)
	
	;;;;;;;;;;;change ffmpegs affinity
	for index, This_ffmpeg in ffmpegPids 
	{
		;MsgBox % "ffmpeg " . index . " is " . This_ffmpeg
		Process, Exist, % This_ffmpeg
		ThisFfmpegPID := ErrorLevel
		;msgbox pid is %ThisFfmpegPID%
		If (ThisFfmpegPID > 0)
		{
			CurrentAf := Affinity_Get(ThisFfmpegPID)
			;msgbox %ThisFfmpegPID%'s affinity is %CurrentAF%, config is %ConfigCoreLimitDec%
			if (CurrentAf = ConfigCoreLimitDec)
				continue
			else
				Affinity_Set(ConfigCoreLimitDec,ThisFfmpegPID)

		}
	}

	;;;;;;;;;;;change ffmpegs priority
	for index, This_ffmpeg in ffmpegPids 
	{
		;MsgBox % "ffmpeg " . index . " is " . This_ffmpeg
		Process, Exist, % This_ffmpeg
		ThisFfmpegPID := ErrorLevel
		If (ThisFfmpegPID > 0)
		{
			CurrentPrio := GetPriority(ThisFfmpegPID)
			if (CurrentPrio = ConfigPriority)
				continue
			Process, Priority, % ThisFfmpegPID, % ConfigPriority

		}
	}
	return
}

AfSet(Affinity)
{
	IniWrite, %Affinity%, %A_ScriptDir%/%ScriptNameNoExt%.ini, Config, Core Limit
	global ConfigCoreLimit := Affinity
	loop %Affinity%
	{
		if CoreLimitBinary
			CoreLimitBinary=1%CoreLimitBinary%
		else
			CoreLimitBinary=1
	}
	global ConfigCoreLimitBinary := CoreLimitBinary
	if (CLOrder = 1)
	{
		EnvGet, ProcessorCount, NUMBER_OF_PROCESSORS
		if (Affinity <> ProcessorCount)
		{
			padding := ProcessorCount - Affinity
			loop %padding%
			{
				CoreLimitBinary=%CoreLimitBinary%0
			}
		}
	}
	global ConfigCoreLimitDec := Dec(CoreLimitBinary)
	EnvGet, ProcessorCount, NUMBER_OF_PROCESSORS
	loop, %ProcessorCount%
		Menu, Cores, Uncheck, %A_Index%
	Menu, Cores, Check, %ConfigCoreLimit%
	

return
}

PrioSet(Priority)
{
	;L (or Low), B (or BelowNormal), N (or Normal), A (or AboveNormal), H (or High), R (or Realtime)
	If (Priority = 1 or Priority = "L")
	{
		Global ConfigPriority := "L"
		Menu, Priority, Uncheck, Realtime
		Menu, Priority, Uncheck, High
		Menu, Priority, Uncheck, AboveNormal	
		Menu, Priority, Uncheck, Normal	
		Menu, Priority, Uncheck, BelowNormal	
		Menu, Priority, Check, Low
	}
	If (Priority = 2 or Priority = "B")
	{
		Global ConfigPriority := "B"
		Menu, Priority, Uncheck, Realtime
		Menu, Priority, Uncheck, High
		Menu, Priority, Uncheck, AboveNormal	
		Menu, Priority, Uncheck, Normal	
		Menu, Priority, Check, BelowNormal	
		Menu, Priority, Uncheck, Low
	}
	If (Priority = 3 or Priority = "N")
	{
		Global ConfigPriority := "N"
		Menu, Priority, Uncheck, Realtime
		Menu, Priority, Uncheck, High
		Menu, Priority, Uncheck, AboveNormal	
		Menu, Priority, Check, Normal	
		Menu, Priority, Uncheck, BelowNormal	
		Menu, Priority, Uncheck, Low
	}
	If (Priority = 4 or Priority = "A")
	{
		Global ConfigPriority := "A"
		Menu, Priority, Uncheck, Realtime
		Menu, Priority, Uncheck, High
		Menu, Priority, Check, AboveNormal	
		Menu, Priority, Uncheck, Normal	
		Menu, Priority, Uncheck, BelowNormal	
		Menu, Priority, Uncheck, Low
	}
	If (Priority = 5 or Priority = "H")
	{
		Global ConfigPriority := "H"
		Menu, Priority, Uncheck, Realtime
		Menu, Priority, Check, High
		Menu, Priority, Uncheck, AboveNormal	
		Menu, Priority, Uncheck, Normal	
		Menu, Priority, Uncheck, BelowNormal	
		Menu, Priority, Uncheck, Low
	}
	If (Priority = 6 or Priority = "R")
	{
		Global ConfigPriority := "R"
		Menu, Priority, Check, Realtime
		Menu, Priority, Uncheck, High
		Menu, Priority, Uncheck, AboveNormal	
		Menu, Priority, Uncheck, Normal	
		Menu, Priority, Uncheck, BelowNormal	
		Menu, Priority, Uncheck, Low
	}
	IniWrite, %ConfigPriority%, %A_ScriptDir%/%ScriptNameNoExt%.ini, Config, Priority
return
}

GetPriority(P="current") {
	static r32:="N", r64:="L", r128:="H" , r256:="R", r16384:="B", r32768:="A"
	Process, Exist, % (P="current") ? "" : (P="") ? 0 : P
	R := DllCall("GetPriorityClass","UInt",hP:=DllCall("OpenProcess","UInt",0x400,"Int",0,"UInt",(P+1) ? P : ErrorLevel))
	DllCall("CloseHandle","UInt",hP)
	return r%R%
}


Affinity_Set( CPU=1, PID=0x0 ) {
  Process, Exist, %PID%
  IfEqual,ErrorLevel,0,  SetEnv,PID,% DllCall( "GetCurrentProcessId" )
  hPr := DllCall( "OpenProcess",Int,1536,Int,0,Int,PID )  
  DllCall( "GetProcessAffinityMask", Int,hPr, IntP,PAM, IntP,SAM )
  If ( CPU>0 && CPU<=SAM )
     Res := DllCall( "SetProcessAffinityMask", Int,hPr, Int,CPU )
  DllCall( "CloseHandle", Int,hPr )
Return ( Res="" ) ? 0 : Res
}

Affinity_Get( PID=0x0 ) { ; 
  Process, Exist, %PID%
  IfEqual,ErrorLevel,0,  SetEnv,PID,% DllCall( "GetCurrentProcessId" )
  hPr := DllCall( "OpenProcess",Int,1536,Int,0,Int,PID )  
  af := DllCall( "GetProcessAffinityMask", Int,hPr, IntP,PAM, IntP,SAM )
  ;If ( CPU>0 && CPU<=SAM )
  ;   Res := DllCall( "SetProcessAffinityMask", Int,hPr, Int,CPU )
  DllCall( "CloseHandle", Int,hPr )
Return pam
}

ToggleClOrder:
{
	if (CLOrder = 0)
	{
		global CLOrder := 1
		Menu, Cores, Check, Reverse
	}
	else
	{
		global CLOrder := 0
		Menu, Cores, Uncheck, Reverse
	}
	return
}

RunToggle:
{
	Process, Exist, Tdarr_Node.exe
	NodePID := ErrorLevel
	If (NodePID > 0)
	{
		MsgBox, 4, , Are you sure you want to close the Tdarr Node?
		IfMsgBox, Yes
		{
			Process, Close, % NodePID
			Process, WaitClose, % NodePID, 30
			If ErrorLevel
				msgbox Could not close Tdarr Node
		}
	}
	else
	{
		If ShowTdarr
			Run, Tdarr_Node.exe, %A_ScriptDir%, , NodePID
		else 
			Run, Tdarr_Node.exe, %A_ScriptDir%, Hide, NodePID
	}
	return
}

ShowToggle:
{
	If (ShowTdarr = 1)
	{
		ShowTdarr := 0
		Process, Exist, Tdarr_Node.exe
		If ErrorLevel
			WinHide, ahk_exe Tdarr_Node.exe
			
		Menu, Tray, Uncheck, Show Console
	}
	else
	{
		ShowTdarr := 1
		Process, Exist, Tdarr_Node.exe
		If ErrorLevel
			WinShow, ahk_exe Tdarr_Node.exe
			
		Menu, Tray, Check, Show Console
	}
	return
}



ChangeWorkers(NodeID, NodeURL,WorkerType,ProcType)
{
	if (WorkerType = 1)
		WType = healthcheck

	if (WorkerType = 2)
		WType = transcode
	
	if (ProcType = 1)
	{
		if (WorkerType = 1)
			CurrentValue := HealthChecksCPU(NodeID, NodeURL)
		if (WorkerType = 2)
			CurrentValue := TranscodesCPU(NodeID, NodeURL)
		WType = %WType%cpu
	}
	if (ProcType = 2)
	{
		if (WorkerType = 1)
			CurrentValue := HealthChecksGPU(NodeID, NodeURL)
		if (WorkerType = 2)
			CurrentValue := TranscodesGPU(NodeID, NodeURL)
		WType = %WType%gpu
	}
	
	InputBox, NewValue, Change Worker Value, Current Workers: %CurrentValue%`nwType: %WType%`nEnter new value:
	
	if (NewValue > CurrentValue)
	{
		process := "increase"
		amount := (NewValue - CurrentValue)
	}
	
	if (NewValue < CurrentValue)
	{
		process := "decrease"
		amount := (CurrentValue - NewValue)
	}
	msgbox will try to %process% by %amount%
	loop, %amount%
		AlterWorkerLimit(NodeURL, NodeID, WType, process)


	gosub MenuWorkerRefresh
	return
}

MenuWorkerRefresh:
{
	
	Menu, Health Checks, Delete, CPU: (%HC_CPU%)

	Menu, Health Checks, Delete, GPU: (%HC_GPU%)

	Menu, Transcodes, Delete, CPU: (%TC_CPU%)

	Menu, Transcodes, Delete, GPU: (%TC_GPU%)
	
	gosub WorkerLimits
	
	C_HC_C := Func("ChangeWorkers").Bind(NodeID, NodeURL, 1, 1)
	Menu, Health Checks, Add, CPU: (%HC_CPU%), % C_HC_C
	
	C_HC_G := Func("ChangeWorkers").Bind(NodeID, NodeURL, 1, 2)
	Menu, Health Checks, Add, GPU: (%HC_GPU%), % C_HC_G
	
	C_TC_C := Func("ChangeWorkers").Bind(NodeID, NodeURL, 2, 1)
	Menu, Transcodes, Add, CPU: (%TC_CPU%), % C_TC_C
	
	C_TC_G := Func("ChangeWorkers").Bind(NodeID, NodeURL, 2, 2)
	Menu, Transcodes, Add, GPU: (%TC_GPU%), % C_TC_G
	return
}



WorkerLimits:	
{
	HC_CPU := HealthChecksCPU(NodeID, NodeURL)
	HC_GPU := HealthChecksGPU(NodeID, NodeURL)
	TC_CPU := TranscodesCPU(NodeID, NodeURL)
	TC_GPU := TranscodesGPU(NodeID, NodeURL)
	return
}

HealthChecksCPU(NodeID, NodeURL)
{
	Nodes := GetNodes(NodeURL)
	NodeList := JsonToAHK(Nodes)
	Node := NodeList[NodeID]
	result := Node.workerLimits.healthcheckcpu
	return result
}



HealthChecksGPU(NodeID, NodeURL)
{
	Nodes := GetNodes(NodeURL)
	NodeList := JsonToAHK(Nodes)
	Node := NodeList[NodeID]
	result := Node.workerLimits.healthcheckgpu
	return result
}

TranscodesCPU(NodeID, NodeURL)
{
	Nodes := GetNodes(NodeURL)
	NodeList := JsonToAHK(Nodes)
	Node := NodeList[NodeID]
	result := Node.workerLimits.transcodecpu
	return result
}

TranscodesGPU(NodeID, NodeURL)
{
	Nodes := GetNodes(NodeURL)
	NodeList := JsonToAHK(Nodes)
	Node := NodeList[NodeID]
	result := Node.workerLimits.transcodegpu
	return result
}

IsNodePaused(NodeID, NodeURL)
{
	Nodes := GetNodes(NodeURL)
	;ClipBoard := Nodes
	NodeList := JsonToAHK(Nodes)
	Node := NodeList[NodeID]
	result := Node.nodePaused
	if (result = -1)
		result := true
	else
		result := false
	;msgbox % result
	return result
}

PauseNodeToggle:
{
	Status := IsNodePaused(NodeID, NodeURL)
	if Status
	{
		Data := "{nodePaused: false}"
		UpdateNode(NodeURL, NodeID, Data) 
	}
	else
	{
		Data := "{nodePaused: true}"
		UpdateNode(NodeURL, NodeID, Data)
	}
	return
}


;;;http stuff

GetNodes(NodeURL)
{
	endpoint := NodeURL "/api/v2/get-nodes"
	Try
	{
		HTTP := ComObjCreate("WinHttp.WinHttpRequest.5.1")
		HTTP.Open("GET", endpoint) ; "GET" "POST" ; be sure to uppercase
		HTTP.SetRequestHeader("Content-Type","application/x-www-form-urlencoded")
		HTTP.Send()
		Response:=HTTP.ResponseText
	}
	;HTTP := "" ;unload com object
	ObjRelease(HTTP)
	return Response
}


UpdateNode(NodeURL, NodeID, Data)
{
	endpoint := NodeURL "/api/v2/update-node"
	


	;Try
	;{
		unp := ComObjCreate("WinHttp.WinHttpRequest.5.1")
		unp.Open("POST", endpoint)
		unp.SetRequestHeader("Content-Type", "application/json")
		ubody = {"data": {nodeID: "%NodeID%", nodeUpdates: %Data%}}
		msgbox % ubody
		unp.Send(ubody)
		Response := unp.ResponseText
		msgbox % Response
	;}
	;unp := "" ;unload com object
	ObjRelease(unp)
	return Response
}

AlterWorkerLimit(NodeURL, NodeID, WType, process)
{
	endpoint := NodeURL "/api/v2/alter-worker-limit"
	Try
	{
		wkr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
		wkr.Open("POST", endpoint)
		wkr.SetRequestHeader("Content-Type", "application/json")
		body = {"data": {"workerType": "%WType%","process": "%process%","nodeID": "%NodeID%"}}
		wkr.Send(body)
	}
	;MsgBox % HTTP.ResponseText
	ObjRelease(wkr)
}

;;;math


Bin(x){
	while x
		r:=1&x r,x>>=1
	return r
}
Dec(x){
	b:=StrLen(x),r:=0
	loop,parse,x
		r|=A_LoopField<<--b
	return r
}



;;;json stuff

JsonToAHK(json, rec := false) { 
   static doc := ComObjCreate("htmlfile") 
         , __ := doc.write("<meta http-equiv=""X-UA-Compatible"" content=""IE=9"">") 
         , JS := doc.parentWindow 
   if !rec 
      obj := %A_ThisFunc%(JS.eval("(" . json . ")"), true) 
   else if !IsObject(json) 
      obj := json 
   else if JS.Object.prototype.toString.call(json) == "[object Array]" { 
      obj := [] 
      Loop % json.length 
         obj.Push( %A_ThisFunc%(json[A_Index - 1], true) ) 
   } 
   else { 
      obj := {} 
      keys := JS.Object.keys(json) 
      Loop % keys.length { 
         k := keys[A_Index - 1] 
         obj[k] := %A_ThisFunc%(json[k], true) 
      } 
   } 
   Return obj 
} 



ExitNow:
{

	exitapp
	return
}