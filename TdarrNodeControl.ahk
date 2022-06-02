#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.
#Persistent
#SingleInstance Force


FileRead, NodeConfigJson, %A_ScriptDir%/../configs/Tdarr_Node_Config.json
;msgbox % NodeConfigJson
NodeConfig := JsonToAHK(NodeConfigJson)
NodeID := NodeConfig.nodeID
NodeIP := NodeConfig.serverIP
NodePort:= NodeConfig.serverPort
NodeURL = http://%NodeIP%:%NodePort%
;msgbox % NodeURL
gosub MenuInit
SetTimer, IsNodeRunning, 1000
;SetTimer, WorkerLimits, 15000






return

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;Functions;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
MenuInit:
{
	;Menu, Tray, Add, test, TestFunction
	Menu, Tray, Add, Run Node, RunToggle
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
	Menu, Tray, Add, Worker Limits, :Workers
	

	;need to loop through cpu count and make core control
	EnvGet, ProcessorCount, NUMBER_OF_PROCESSORS
	loop, %ProcessorCount%
	{
		CCC%A_Index% := Func("CCC").Bind(A_Index)
		Menu, Cores, Add, %A_Index%, % CCC%A_Index%
	}
	Menu, Cores, Check, %ProcessorCount%
	Menu, Tray, Add, Core Limit, :Cores
	
	;need to make priority control menu
	;Set := Func("GivePar").Bind("First", "Test one")
	;L (or Low), B (or BelowNormal), N (or Normal), A (or AboveNormal), H (or High), R (or Realtime)
	p6 := Func("PriorityChange").Bind(6)
	Menu, Priority, Add, Realtime, % p6
	p5 := Func("PriorityChange").Bind(5)
	Menu, Priority, Add, High, % p5
	p4 := Func("PriorityChange").Bind(4)
	Menu, Priority, Add, AboveNormal, % p4
	p3 := Func("PriorityChange").Bind(3)
	Menu, Priority, Add, Normal, % p3
	p2 := Func("PriorityChange").Bind(2)
	Menu, Priority, Add, BelowNormal, % p2
	p1 := Func("PriorityChange").Bind(1)
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

TestFunction()
{
	msgbox test
	return
}

PriorityChange(Level)
{
	;L (or Low), B (or BelowNormal), N (or Normal), A (or AboveNormal), H (or High), R (or Realtime)
	If (Level = 1)
		Level = L
	
	If (Level = 2)
		Level = B
	
	If (Level = 3)
		Level = N
	
	If (Level = 4)
		Level = A
	
	If (Level = 5)
		Level = H
	
	If (Level = 6)
		Level = R
	
	Process, Exist, Tdarr_Node.exe
	NodePID := ErrorLevel
	If (NodePID > 0)
		Process, Priority, % NodePID, % Level
	return
}


CCC(CoreLimit)
{
	;InputBox, proc, proc, proc:
	loop %CoreLimit%
	{
		if Binary
			Binary=1%Binary%
		else
			Binary=1
	}
	;msgbox %Binary%
	Decimal := Dec(Binary)
	;msgbox % Decimal
	Process, Exist, Tdarr_Node.exe
	NodePID := ErrorLevel
	If (NodePID > 0)
	{
		Affinity_Set(Decimal,NodePID)
		EnvGet, ProcessorCount, NUMBER_OF_PROCESSORS
		loop, %ProcessorCount%
			Menu, Cores, Uncheck, %A_Index%
		Menu, Cores, Check, %CoreLimit%
	}
	return
}

Affinity_Set( CPU=1, PID=0x0 ) { ; CPU0=1 CPU1=2 | to use both, CPU should be 3
  Process, Exist, %PID%
  IfEqual,ErrorLevel,0,  SetEnv,PID,% DllCall( "GetCurrentProcessId" )
  hPr := DllCall( "OpenProcess",Int,1536,Int,0,Int,PID )  
  DllCall( "GetProcessAffinityMask", Int,hPr, IntP,PAM, IntP,SAM )
  If ( CPU>0 && CPU<=SAM )
     Res := DllCall( "SetProcessAffinityMask", Int,hPr, Int,CPU )
  DllCall( "CloseHandle", Int,hPr )
Return ( Res="" ) ? 0 : Res
}

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

IsNodeRunning()
{
	Process, Exist, Tdarr_Node.exe
	If ErrorLevel
	{
		Menu, Tray, Check, Run Node
	}
	else
	{
		Menu, Tray, Uncheck, Run Node
	}
	return NodePID
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
	{
		endpoint := NodeURL "/api/v2/alter-worker-limit"
		Try
		{
			whr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
			whr.Open("POST", endpoint)
			whr.SetRequestHeader("Content-Type", "application/json")
			body = {"data": {"workerType": "%WType%","process": "%process%","nodeID": "%NodeID%"}}
			whr.Send(body)
		}
		;MsgBox % whr.ResponseText
	}

	gosub MenuWorkerRefresh

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
	NodeList := JsonToAHK(Nodes)
	Node := NodeList[NodeID]
	result := Node.nodePaused
	return result
}


GetNodes(NodeURL)
{
	;msgbox % NodeURL
	endpoint := NodeURL "/api/v2/get-nodes"
	;msgbox % endpoint
	Try
	{
		HTTP := ComObjCreate("WinHttp.WinHttpRequest.5.1")
		HTTP.Open("GET", endpoint) ; "GET" "POST" ; be sure to uppercase
		HTTP.SetRequestHeader("Content-Type","application/x-www-form-urlencoded")
		HTTP.Send()
		Response:=HTTP.ResponseText
	}
	;SciTE_Output(Response) ;Text,Clear=1,LineBreak=1,Exit=0}
	return Response
}


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