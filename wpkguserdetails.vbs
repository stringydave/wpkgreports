' wpkguserdetails.vbs
' query System event log for last logged OFF username
' print that out, we'll then use that to help identify the computer 
' **needs to run as administrator equivalent** in order to read the event log
'
' loosely derived from VBScript to write event log data to text file
' by Guy Thomas http://computerperformance.co.uk/
'
' 29/05/15  dce  first revision
' 21/08/15  dce  ignore ANONYMOUS LOGON and protect from runaway
' 09/09/15  dce  tidy up
' 10/09/15  dce  temporary code to gather computer domain name
' 28/12/16  dce  also ignore DWM users - new anonymous users on Win 10?
' 18/05/17  dce  and UMFD users - new on Windows 10.2
' 19/05/16  dce  ignore IUSR
' 21/05/18  dce  simplify, change comments
' -----------------------------------------------------------'

Option Explicit

' get the username
Dim objWMI, objItem
Dim strComputer, strUserName, strLogType
Dim intEventID, colLoggedEvents, intUserNameStart, intUserNameEnd, intCounter
Const ForReading = 1, ForWriting = 2, ForAppending = 8

' --------------------------------------------------------
' we get something like this in the event log
'	Security ID:	S-1-5-21-3229376722-999999999-634601471-1115
'	Account Name:	myuser
'	Account Domain:	UK
'	Logon ID:		0x26f292a
' or
'	Security ID:	SYSTEM
'	Account Name:	SYSTEM5$
'	Account Domain:	MYDOMAIN
'	Logon ID:		0x3e7
'	Logon GUID:		{00000000-0000-0000-0000-000000000000}
' --------------------------------------------------------

' --------------------------------------------------------
' Init 
strComputer = "."
strLogType = "Security"
' define the EventID we are looking for, use Logoff, as this seems to be more reliable as an "owner" indicator than Logon.
' intEventID = 4624 ' Logon          An account was successfully logged on.
' intEventID = 4647 ' Logoff         User initiated logoff:
' intEventID = 4648 ' Logon          A logon was attempted using explicit credentials.
' intEventID = 4672 ' Special Logon  Special privileges assigned to new logon.
intEventID = 4634 ' Logoff	An account was logged off, this is more reliable than logged on.

' ----------------------------------------------------------
' WMI Core Section
Set objWMI = GetObject("winmgmts:" & "{impersonationLevel=impersonate,(Security)}!\\" & strComputer & "\root\cimv2")
Set colLoggedEvents = objWMI.ExecQuery ("Select * from Win32_NTLogEvent Where Logfile = '" & strLogType & "' AND EventCode = '" & intEventID & "'")

intCounter = 0

' ----------------------------------------------------------
' loop through ID properties, from the most recent to the oldest, which happens to be the way we want it
For Each objItem in colLoggedEvents
	strUserName = objItem.Message
	
	' crop off the front of the string, everything before "Account Name:"
	intUserNameStart = InStr(1,strUserName,"Account Name:",1)
	strUserName = Mid(strUserName,intUserNameStart) 
	' crop off everything after the CR
	intUserNameEnd   = InStr(1,strUserName,Chr(13),1)
	strUserName = Mid(strUserName,1,intUserNameEnd) 

	' the computer account ends with $, so we're looking for an Account Name without a $, and that isn't "ANONYMOUS LOGON", DWM or UMFD
	if InStr(1,strUserName,"$",1) = 0 then 

		' strip this down to just the string we want
		' Replace(string,find,replacewith[,start[,count[,compare]]]) 
		strUserName = Replace(strUserName,"Account Name:","",1,1,1) 
		strUserName = Replace(strUserName,Chr(10),"",1,1,1)  ' remove LF
		strUserName = Replace(strUserName,Chr(13),"",1,1,1)  ' remove CR
		strUserName = Replace(strUserName,Chr(9), "",1,10,1) ' remove tabs
		
        if ((strUserName <> "ANONYMOUS LOGON") and (InStr(1,strUserName,"DWM",1) <> 1) and (InStr(1,strUserName,"UMFD",1) <> 1) and (InStr(1,strUserName,"IUSR",1) <> 1)) then 
            ' we've found the data we're looking for, exit the loop
            Wscript.Echo "username=" & strUserName
            WScript.Quit
        End If
        
		' make sure we don't go on for ever...
        intCounter = intCounter + 1
		if intCounter > 50 then WScript.Quit
        
	End If
Next

' never get here unless no users ever logged off
WScript.Quit
