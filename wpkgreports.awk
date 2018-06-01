# process a wpkg report into a helpful output

# show:
#    summary
#    failed installs today
#    successfull installs today
#    failed OLD installs
#    successful OLD installs

# 04/11/13  dce  tidy up code
# 08/11/13  dce  and more
# 13/01/14  dce  add os to the output
# 29/01/14  dce  log not found does not need format_head()
#                tidy up code
# 30/01/14  dce  handle upgrades
# 22/03/14  dce  add script version
# 05/05/14  dce  2.0 summary at top
# 07/05/14  dce  2.1 summary, and failed installations at top, ignore "servers"
# 09/05/14  dce  2.2 match on package_status[i] because the string may contain trailing "."
# 03/07/14  dce  just the === lines
# 23/07/14  dce  quit with a count of how many computers are not complete
# 18/08/14  dce  add wpkg package version to report
# 20/08/14  dce  report removal
# 21/08/14  dce  escape \) required on some distributions of awk
# 03/10/14  dce  add error 1619
# 08/11/14  dce  show results gathered today before history
#                show Time Synch install successful as "ok"
# 07/02/15  dce  ignore lines to do with logfile
# 23/06/15  dce  add error 1638
# 03/08/15  dce  ignore packages not required
# 06/08/15  dce  special unignore for Java 8
#                version string to 15 ch
# 07/08/15  dce  add zombie state
# 31/08/15  dce  reformat to show current data first
# 14/09/15  dce  add domain to computername
# 26/10/15  dce  add error 1612
# 20/11/15  dce  be optimistic, assume all packages have success unless they actually fail
# 08/12/16  dce  show win10 version
# 09/12/16  dce  remove PRO or PROFESSIONAL, it's just noise
# 22/12/16  dce  exit with status of just how many failed today
# 04/01/17  dce  simplify microsoft windows server xxxx r2 standard
# 17/01/17  dce  fail only if Fail/zombie, all else (inc no packages) is OK
# 24/01/17  dce  fix showing of username bug introduced with "add domain to computername" change
#                load usernames via an array
# 07/04/17  dce  show rsync results where applicable
#                add code for win 10.2
# 26/04/17  dce  cope with a second check (Verified)
# 13/05/17  dce  add code 1636
# 15/06/17  dce  3.5 sorting the output turned out to be surprisingly easy
#                however it relies upon running GNU awk (gawk), default (old) Debian has mawk, so update that everywhere
#                symptom is root gets a message: awk: /opt/updates/scripts/wpkgreports.awk: line 397: function asorti never defined
# 11/09/17  dce  report package timeout
# 14/05/18  dce  add current windows 10 editions + Home
# 16/05/18  dce  sanitise for github
# 20/05/18  dce  allow username to be inserted anywhere in the file
# 01/06/18  dce  we now add LastLoggedOnUser to the file
#                add architecture if x86, minor formatting changes

# be aware that packages may not be processed in strict sequential order, you may get messages from the end of a previous installation embedded in 
# the start of the next package.

BEGIN {
	# set script version
	script_version = 3.8
	
	IGNORECASE = 1
	pc_count = pc_ok = package_count = package_success = package_fail = package_undefined = not_checked = 0
    # these for formatting the output
    hostlen = 20
    oslen   = 18
    userlen = 15
    
	# msiexec error codes here http://support.microsoft.com/kb/290158
	errortext[1603] = "fatal, prob permissions"
	errortext[1605] = "only valid for installed product"
	errortext[1612] = "installation source not available"
	errortext[1618] = "another installation is in progress"
	errortext[1619] = "installation package could not be opened"
    errortext[1636]	= "the package could not be opened. "
	errortext[1638] = "another version is already installed"
    errortext[1642] = "not valid patch"
    
    sline = "---------------------------------------------------------------------------------\n"
    dline = "=================================================================================\n"
}

# count the number of files
FNR == 1 { ++pc_count }

# if it's the first line of the (anything but the first) file, print the summary for the previous machine
((FNR == 1) && (NR != 1)) {
	format_results()
	# and clear the data for this pc
    head_data = ""
	this_data = ""
	for (i in package_status)
		delete package_status[i]
}

# we have added a line with the username, but it may have something that's not /[A-Za-z0-9]/ at the end
/^username/ { 
	username = substr($0, index($0,"=") + 1)
	# we've written the file with windows so it has DOS line endings, but we're processing it on linux
	sub(/[^A-Za-z0-9]+$/, "", username)
   	hostname = tolower(FILENAME)
	sub(/^.*wpkg-/, "", hostname)
	sub(/.log/, "", hostname)
	sub(/.usr/, "", hostname)
    # print hostname, username, FILENAME, $0
	# and load it into an array so we can pull it out again
    usernames[hostname] = username
}

# somewhere in the file we've dumped the contents of HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\LastLoggedOnUser
# but it may have something that's not /[A-Za-z0-9]/ at the end
#    LastLoggedOnUser    REG_SZ    DAVENTRY\simonw

$1 ~ /LastLoggedOnUser/ { 
	username = substr($3, index($3,"\\") + 1)
	# we've written the file with windows so it has DOS line endings, but we're processing it on linux
	sub(/[^A-Za-z0-9]+$/, "", username)
   	hostname = tolower(FILENAME)
	sub(/^.*wpkg-/, "", hostname)
	sub(/.log/, "", hostname)
	sub(/.usr/, "", hostname)
    # print hostname, username, FILENAME, $0
	# and load it into an array so we can pull it out again
    usernames[hostname] = username
}

# ignore lines to do with logfile
/(logfile)/ { next } 

/Host properties: hostname=/ {
	# we can just split this up on "'"
    # 2014-01-13 08:22:26, DEBUG   : Host properties: hostname='system03'|architecture='x64'|os='microsoft windows 7 professional, , sp1, 6.1.7601'|ipaddresses='10.10.10.10,192.192.192.192'|domain name='thedomain.com'|groups=''|lcid='809'|lcidOS='409'
	# 2014-01-13 08:28:33, DEBUG   : Host properties: hostname='farsight'|architecture='x86'|os='microsoft windows xp professional, , sp3, 5.1.2600'|ipaddresses='10.10.10.10'|domain name='thisdomain'|groups='Domain Computers'|lcid='809'|lcidOS='409'
    # 2016-12-08 09:58:26, DEBUG   : Host properties: hostname='system04'|architecture='x64'|os='microsoft windows 10 pro, , , 10.0.14393'|ipaddresses='10.10.10.10,192.192.192.192'|domain name='thedomain.com'|groups=''|lcid='809'|lcidOS='409'
    # 2017-01-04 01:00:38, DEBUG   : Host properties: hostname='server01'|architecture='x64'|os='microsoft windows server 2008 r2 standard, , sp1, 6.1.7601'|ipaddresses='10.10.10.10'|domain name='thedomain.com'|groups='Domain Controllers'|lcid='809'|lcidOS='409'
    # 2016-12-08 09:58:26, DEBUG   : Host properties: hostname='system05'|architecture='x86'|os='microsoft windows 10 pro, , , 10.0.16299'|ipaddresses='192.192.192.192'|domain name='thedomain.com'|groups=''|lcid='809'|lcidOS='409'

	split ($0, stringparts, "'")
	hostname     = stringparts[2]
	architecture = stringparts[4]
	os           = stringparts[6]
    domain       = stringparts[10]
	# and munge this about
	split (os, osparts, ",")
	osparts[1] = toupper(osparts[1])
	sub (/MICROSOFT WINDOWS SERVER/, "svr", osparts[1])
	sub (/MICROSOFT WINDOWS/, "win", osparts[1])
	sub (/ PROFESSIONAL/, "", osparts[1])
	sub (/ STANDARD/, "", osparts[1])
	sub (/ HOME/, "H", osparts[1])
	sub (/ PRO/, "", osparts[1])
    
    # remove spaces from service pack
    sub (/ /, "", osparts[3])
    
    # win 10
    print "os =" osparts[1] ":" osparts[3] ":"
    print "os =" os ":"
    if (osparts[4] ~ /10586/) { sub(/10/, "10.0",    osparts[1]) } # 1511
    if (osparts[4] ~ /14393/) { sub(/10/, "10.1607", osparts[1]) } # 1607
    if (osparts[4] ~ /15063/) { sub(/10/, "10.1703", osparts[1]) } # 1703
    if (osparts[4] ~ /16299/) { sub(/10/, "10.1709", osparts[1]) } # 1709
    if (osparts[4] ~ /17134/) { sub(/10/, "10.1803", osparts[1]) } # 1803

    
    # now add service pack or x86 to the os string as applicable
	os = osparts[1] osparts[3]
    if (osparts[3] == " ") { os = osparts[1] }
    if (architecture !~ "x64") { 
    print "here"
    os = os " " architecture }
    
    # truncate the os string to oslen
    # print "os =" osparts[1] ":" osparts[3] ":"
	# os = substr(osparts[1] osparts[3],1 ,oslen)
    print "os =" os ":arch:" architecture
    # and add the architecture
    # os = os ":" architecture
    
    
    # add as much of the domain as will fit into hostlen char
    hostnamelen = hostlen - length(hostname) - 1
    shortdomain = substr(domain,1,hostnamelen)
    
    # initialise this
    rsync_status = ""
    
	format_head(shortdomain, hostname, os)
}

# print out warnings
/Unable to find any matching host definition!/ {
	# 2013-11-01 08:35:05, ERROR   : Message:      Unable to find any matching host definition!|Description:  Unable to...
	# 2013-11-01 08:35:05, DEBUG   : Initializing new log file: 'C:\wpkg-system01.log' in replace mode.
	hostname = FILENAME
	sub(/^.*wpkg-/, "", hostname)
	sub(/.log/, "", hostname)
	format_head("", hostname, "unknown")
	this_data = this_data sprintf("Unable to find any matching host definition for: %s\n", hostname)
}

# and this is where we've used the login script to copy the log file to the central folder, but there wasn't one for this machine.
/WPKG log file not found/ { 
	hostname = FILENAME
	sub(/^.*wpkg-/, "", hostname)
	sub(/.log/, "", hostname)
	format_head("", hostname, "unknown")
	this_data = this_data sprintf("WPKG log file not found on %s\n", hostname)
	++log_not_found
}

# pairs we are looking for are:
# nothing to do:
# 2013-09-25 08:29:57, DEBUG   : Package 'Adobe Flash Player' (AdobeFlashPlayer) found in profile packages.
# 2013-09-25 08:30:07, DEBUG   : Package 'Adobe Flash Player' (AdobeFlashPlayer): Already installed.

# installing...success
# 2013-09-25 08:29:57, DEBUG   : Package 'Mozilla Firefox' (firefox) found in profile packages.
# 2013-08-12 12:22:28, INFO    : Package 'Mozilla Firefox' (firefox): Package and all chained packages installed successfully.
# 2013-08-12 12:22:28, INFO    : Processing (upgrade) of Mozilla Firefox successful.

# "upgrading", will be followed by "installing" and then success or failure
# 2013-07-11 16:52:10, INFO    : Package 'Adobe Flash Player' (AdobeFlashPlayer): Already installed but version mismatch.|Installed revision: '11.7.700.224'|Available revision: '11.8.800.94'.|Preparing upgrade.

# 2013-09-25 08:29:57, DEBUG   : Package 'Adobe Reader XI' (AdobeReader) found in profile packages.
# 2013-09-25 08:29:57, DEBUG   : Package 'Java Runtime Environment 7' (java7) found in profile packages.
# 2013-09-25 08:29:57, DEBUG   : Package 'LibreOffice' (libreoffice) found in profile packages.
# 2013-09-25 08:29:57, DEBUG   : Package 'LibreOffice Helppack en-GB' (libreofficehelppackengb) found in profile packages.
# 2013-09-25 08:29:57, DEBUG   : Package 'Mozilla Thunderbird' (thunderbird) found in profile packages.
# 2013-09-25 08:29:57, DEBUG   : Package 'Java Runtime Environment 7' (java7): Prepared for upgrade.
# 2013-09-25 08:29:57, INFO    : Installing 'Java Runtime Environment 7' (java7)...
# 2013-09-25 08:30:07, DEBUG   : Package 'LibreOffice' (libreoffice): Already installed.
# 2013-09-25 08:30:07, DEBUG   : Package 'Adobe Reader XI' (AdobeReader): Already installed.
# 2013-09-25 08:30:07, DEBUG   : Package 'Mozilla Thunderbird' (thunderbird): Already installed.
# 2013-09-25 08:30:07, DEBUG   : Package 'Mozilla Firefox' (firefox): Already installed.
# 2013-09-25 08:30:07, DEBUG   : Package 'LibreOffice Helppack en-GB' (libreofficehelppackengb): Already installed.
# 2013-08-12 12:22:28, INFO    : User notification suppressed. Message: The automated software installation utility has completed installing or updating software on your system. No reboot was necessary. All updates are complete.

# this is for a conditional install of a package (only update if installed)
# 2015-08-03 15:00:06, DEBUG   : Going to install package 'GIMP (Photo Editor)' (gimp), Revision 2.8.14, (execute flag is '', notify flag is 'true').
# 2015-08-03 15:00:06, DEBUG   : Reading variables from package 'GIMP (Photo Editor)'.
# 2015-08-03 15:00:48, DEBUG   : Uninstall entry for GIMP.* missing: test failed.
# 2015-08-03 15:00:48, DEBUG   : Result of logical 'NOT' check is true.
# 2015-08-03 15:00:48, DEBUG   : Result of logical 'OR' check is true.
# 2015-08-03 15:00:48, DEBUG   : Package 'GIMP (Photo Editor)' (gimp): Already installed.

# /found in profile packages/ {
/Found package node/ {
	# the part enclosed in ' is the package name
	split ($0, stringparts, "'")
	package_name = stringparts[2]
	
	# count the number of unique packages
	if ((package_name in packages) == 0 ) {
		++unique_package_count 
		++packages[package_name]
	}
	
	# and update the status of this one
	package_status[package_name] = "not checked"
	++package_count
}

/Reading variables from package/ {
	# the part enclosed in ' is the package name
	# /2013-08-12 12:22:05, DEBUG   : Reading variables from package 'Mozilla Thunderbird'.
	split ($0, stringparts, "'")
	package_name = stringparts[2]
}

/Going to install package/ {
	# Going to install package 'Mozilla Thunderbird' (thunderbird), Revision 31.0, (execute flag is '', notify flag is 'true').
	# the part enclosed in the first ' is the package name
	split ($0, stringparts, "'")
	package_name = stringparts[2]
    # now we want the wpkg package version (this is not the software version, though they're often kept the same for convenience)
    split ($0, stringparts, ",")
	wpkg_version = stringparts[3]
    sub(/ Revision /, "", wpkg_version)
    # Skype revision is like 6.18.32.106-201408031341 which is silly
    if (index(wpkg_version,"-") > 10) {
        wpkg_version = substr(wpkg_version, 1, index(wpkg_version,"-") - 1)
    }
    # and make sure it's not too long (see also format_results())
    package_version[package_name] = substr(wpkg_version,1,15)
   	package_status[package_name] = "installing"
    package_timeout[package_name] = ""
}

# Uninstall entry for ... missing: test failed.
# The path ... does not exist: the test failed.
/Uninstall entry .* test failed.$/ {
    # need special for Java until next version updates the saved checks
   	if ($0 !~ /Java 8/) { package_status[package_name] = "no entry" }
}

# Package 'Visual C++ Redistributable' (vc_redist): Already installed.
# Package 'Visual C++ Redistributable' (vc_redist): Already installed once during this session.|Checking if package is properly installed.
# Package 'Visual C++ Redistributable' (vc_redist): Verified; package successfully installed during this session.
/Already installed\.|Verified; package successfully installed/ {
	# the part enclosed in ' is the package name
	split ($0, stringparts, "'")
	package_name = stringparts[2]
    if (package_status[package_name] == "no entry") { package_status[package_name] = "not required"} else {	package_status[package_name] = "ok" }
}

/installed successfully/ {
    # probably overwritten by "Processing" clause every time
	# the part enclosed in ' is the package name
	# 2013-08-12 12:22:28, INFO    : Package 'Mozilla Firefox' (firefox): Package and all chained packages installed successfully.
	split ($0, stringparts, "'")
	package_name = stringparts[2]
	package_status[package_name] = "installed success"
}

/: Package/ {
	# the part enclosed in ' is the package name
	# 2014-01-30 11:16:53, INFO    : Package 'Adobe Reader XI'
	split ($0, stringparts, "'")
	package_name = stringparts[2]
}

/Processing \(/ {
	# 2014-01-30 11:16:53, DEBUG   : Installation of references (chained) for 'Adobe Reader XI' (AdobeReader) successfully finished.
	# 2014-01-30 11:16:53, INFO    : Package 'Adobe Reader XI' (AdobeReader): Package and all chained packages installed successfully.
	# 2014-01-30 11:16:53, INFO    : Processing (upgrade) of Adobe Reader XI successful.
	process_status = $NF
    # remove any trailing period
    sub(/\.$/, "", process_status)
    # discard the status
    package_name = substr($0, 1, index($0, $NF) - 2)
    # and remove the line up to the package_name
    sub(/^.*\) of /, "", package_name)
    process_action = substr($0, index($0,"(") + 1,index($0,")") - index($0,"(") - 1)
    package_status[package_name] = process_action " " process_status
    # we run Time Synchronization every time, so don't report it as "install"
	if ((package_name ~ /Time Synchronization/) && (process_status ~ /successful/)) { package_status[package_name] = "ok" }
}

/INFO    : Removal of / {
    # this ones's a little more tricky
    # 2014-08-20 08:28:06, INFO    : Removal of Retina Scan identd successful.
   	process_status = $NF
    # remove any trailing period
    sub(/\.$/, "", process_status)
    # discard the status
    package_name = substr($0, 1, index($0, $NF) - 2)
    # and remove the line up to the package_name
    sub(/^.*Removal of /,"", package_name)
    package_status[package_name] = "removal " process_status
}

/Timeout reached while executing/ {
    # 2017-09-11 09:05:43, ERROR   : Command 'cscript //nologo %SOFTWARE%\..\scripts\instfont.vbs /D:"\\software\fonts"' ('cscript //nologo \\software\updates\packages\..\scripts\instfont.vbs /D:"\\software\fonts"') was unsuccessful.|Timeout reached while executing.
    # 2017-09-11 09:05:45, ERROR   : Could not process (install) package 'install fonts from server' (fonts):|Exit code returned non-successful value (-1) on command 'cscript //nologo %SOFTWARE%\..\scripts\instfont.vbs /D:"\\software\fonts"'.
    package_timeout[package_name] = "timeout "
}

/non-successful/ {
	# don't match on "ERROR" as it may occur elsewhere in the file
	# 2013-09-25 07:09:21, ERROR   : Could not process (upgrade) package 'Java Runtime Environment 7' (java7):|Exit code returned non-successful value (1603) on command '%SOFTWARE%\jre\jre-7u%version%-windows-i586.exe /s REBOOT=Suppress'.
	# get the bit within the brackets after the "|"
	errorcode = substr($0, index($0,"|"))
	errorcode = substr(errorcode, index(errorcode, "(") + 1 )
	errorcode = substr(errorcode, 1, index(errorcode, ")") - 1 )
	if (errorcode in errortext) errorcode = errorcode ", " errortext[errorcode]
	package_status[package_name] = "Fail " package_timeout[package_name] errorcode
}

/Failed checking after installation/ {
	# the package name is the bit between the ")" and the "|"
	# 2013-08-12 12:22:12, ERROR   : Could not process (install) Mozilla Thunderbird.|Failed checking after installation.
	package_status[package_name] = "Failed checking after installation."
}

# Could not process (remove) Adobe CC Auto-Update.|Package still installed.
/Could not process .*Package still installed/ {
	# get the package name
    package_name = $0
    sub(/^.* \(remove\) /, "", package_name)
    sub(/\.\|.*$/, "", package_name)
    package_status[package_name] = "zombie"
}

# the rsync process for remote machines produces these lines at the end
# 2017/04/07 08:32:57 [2380] total: matches=213719  hash_hits=213720  false_alarms=3 data=226467103
# 2017/04/07 08:32:57 [2380] sent 1.41M bytes  received 227.39M bytes  686.07K bytes/sec
# 2017/04/07 08:32:57 [2380] total size is 1.58G  speedup is 6.89
# or
# 2017/04/03 08:08:10 [2008] rsync: fork: Resource temporarily unavailable (11)
# 2017/04/03 08:08:10 [2008] rsync error: error in IPC code (code 14) at pipe.c(65) [Receiver=3.1.1]
/] total|] sent|] rsync/ { rsync_status =  rsync_status $0 "\n" }
/] total |] rsync /      { rsync_status =  rsync_status sline }

END {
	# gather the summary for the last file
	format_results() 
	
    # print the header
	print "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
	print " computers checked:", pc_count", of which", pc_ok, "complete =", int(100 * pc_ok/pc_count) "% success"
	if (log_not_found > 0) {
	print "log file not found:", log_not_found, "    ( wpkg not installed? )"
	}
	print "   unique packages:", unique_package_count
	if (package_count > 0) {
	print " package instances:", package_count", of which", package_fail, "failed, &", not_checked, "not checked = " int(100 * (package_count - package_fail - not_checked)/package_count) "% success"
	}
	print "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
	
	if ("*" in fdata)   { printf("%sfailed installs today:\n%s%s\n",     dline, dline, fdata["*"]) }
	if ("*" in rdata)   { printf("%ssuccessful installs today:\n%s%s\n", dline, dline, rdata["*"]) }
	if ("OLD" in fdata) { printf("%sfailed OLD installs:\n%s%s\n",       dline, dline, fdata["OLD"]) }
	if ("OLD" in rdata) { printf("%ssuccessful OLD installs:\n%s%s\n",   dline, dline, rdata["OLD"]) }
	
	print "wpkgreports version", script_version
	
	# quit with a count of how many recent computers are not complete
	exit (pc_fail_today)
}

function format_head(shortdomain, hostname, os) {
	date_time = $1 " " substr($2, 1, 5)
	if (date_time < date) { date_late = "OLD" } else { date_late = "*" }
	# this_data = this_data sprintf("%s\n", sline)
	# rdata = rdata pc_count "  "  # debug
    
    _shortdomain[hostname] = shortdomain
    _os[hostname] = os
    # usernames[hostname] 
    _date_time[hostname] = date_time
    _date_late[hostname] = date_late
    
 	# this_data = this_data sprintf("%-20s %-" oslen "s user: %-16s%20s %3s\n", shortdomain "\\" hostname, os, usernames[hostname], date_time, date_late)
	# this_data = this_data sprintf("%s", sline)
	# username = ""
}

function format_results() {
    # at this point date_late is a string = * if the date is current, so we can use this to show the current data first (as that's most interesting)
	pc_state = 1
    
 	head_data = sprintf("%-" hostlen "s %-" oslen "suser :%-" userlen "s %16s %3s\n", _shortdomain[hostname] "\\" hostname, substr(_os[hostname],1,oslen), substr(usernames[hostname],1,userlen), _date_time[hostname],  _date_late[hostname])
    
    # use gawk's asorti function to sort on the index, the index values become the values of the second array
    n = asorti(package_status, package_status_index)
    for (j = 1; j <= n; j++) {
        i = package_status_index[j] # this is the original index
        this_data = this_data sprintf("%30s : %15s : %s\n", i, package_version[i], package_status[i])
        # be optimistic, assume packages have success unless they actually fail
        if ((package_status[i] ~ "Fail") || (package_status[i] ~ "zombie")) {
            ++package_fail
            pc_state = 0 
        } else {
            ++package_success 
        }
        if (package_status[i] == "not checked") { ++not_checked }
    }
	# if the packages were all ok (or if there were none), then this is a success
	if (pc_state == 1) {
		++pc_ok
		rdata[date_late] = rdata[date_late] head_data sline this_data sline rsync_status
    } else {
        if (date_late == "*") { ++pc_fail_today }
		fdata[date_late] = fdata[date_late] head_data sline this_data sline rsync_status
	}
}