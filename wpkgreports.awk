# process a wpkg report into a helpful output
# uses asorti so requires gawk (not debian standard mawk)

# show:
#    summary
#    failed installs today
#    successfull installs today
#    failed OLD installs
#    successful OLD installs

# 22/08/19  dce  more work to cope with microsoft(r) & microsoft® in o/s string
#                print errors for broken xml
# 17/01/20  dce  add 1909
# 22/01/20  dce  ignore wpkgtidy
# 26/02/20  dce  add profile(s) to header
# 03/03/20  dce  profile line endings
# 13/04/20  dce  ignore wpkgtidy as "tidy temp files"
# 07/05/20  dce  show boot date if not today
# 14/05/20  dce  cope with boot date from wmic
# 28/05/20  dce  cope with win10 enterprise ltsb, add 10.2004
# 31/07/20  dce  show boot date always, add "*" if today
# 25/08/20  dce  for package failed get the package name from the line instead of assuming it's set correctly.
# 09/11/20  dce  add model, serial, bios to header
# 16/11/20  dce  file is written by windows with DOS (CRLF) line endings, but we may be processing it on linux, so remove extraneous CR (0x0d)
#                20H2 os code
# 17/11/20  dce  minor formatting
# 23/11/20  dce  minor formatting
# 24/11/20  dce  better handling of different error conditions
# 25/12/20  dce  if multiple rsync messages, just show the last one
# 12/03/21  dce  add note that gawk is required
# 19/03/21  dce  better reporting of broken xml files
# 26/03/21  dce  revert previous reporting of broken xml files as it was too verbose, just report unique instances.
# 18/04/21  dce  ignore boot time from sysinfo as it's locale dependant.
# 15/06/21  dce  add 21H1 os code
# 09/11/21  dce  cope with Windows 10 IOT ENTERPRISE
# 15/11/21  dce  more DE language specifics
# 27/12/21  dce  add 21H2
# 12/06/22  dce  check for Bitlocker = off
# 13/06/22  dce  and in German
# 25/06/22  dce  check for no TPM
# 28/07/22  dce  for broken packages, report the log file again so we can see if it's just one machine
# 06/09/22  dce  print list of all profiles in use
# 26/12/22  dce  print sorted list of all packages in use
# 10/01/23  dce  package / profile usage moved to separate script
# 28/01/23  dce  list required Dell Updates
# 28/02/23  dce  better handling of System Manufacturer and Model in German
# 24/03/23  dce  add better check for BitLocker = off for Portables only
# 18/04/23  dce  cosmetic changes to BIOS reporting
# 21/04/23  dce  update code at "Failed checking after installation"
# 22/04/23  dce  cosmetic restructure
# 17/05/23  dce  new processing of delldcuscan
# 13/06/23  dce  better processing of missing: test failed
# 19/06/23  dce  dell update scan sometimes fails with network error
# 26/06/23  dce  print a table of operating systems

# be aware that packages may not be processed in strict sequential order, you may get messages from the end of a previous installation embedded in 
# the start of the next package.

BEGIN {
	# set script version
	script_version = "3.16.0"
	
	IGNORECASE = 1
	pc_count = pc_ok = package_count = package_success = package_fail = package_undefined = not_checked = bitlocker_off = 0
    # these for formatting the output
    hostlen  = 20
    oslen    = 19
    userlen  = 19
	pkverlen = 17
    
	# msiexec error codes here http://support.microsoft.com/kb/290158
	errortext[1603] = "version or permissions"
	errortext[1605] = "only valid for installed product"
	errortext[1612] = "installation source not available"
	errortext[1618] = "another installation is in progress"
	errortext[1619] = "installation package could not be opened"
    errortext[1636]	= "the package could not be opened. "
	errortext[1638] = "another version is already installed"
    errortext[1642] = "not valid patch"
	
	# translation table between ver strings and release names
	# https://docs.microsoft.com/en-gb/windows/release-health/release-information
    osrelease["10.0.10586"] = "10.0"        # 1511
    osrelease["10.0.14393"] = "10.1607"
    osrelease["10.0.15063"] = "10.1703"
    osrelease["10.0.16299"] = "10.1709"
    osrelease["10.0.17134"] = "10.1803"
    osrelease["10.0.17763"] = "10.1809"		# Redstone 5
    osrelease["10.0.18362"] = "10.1903"		# 19H1
    osrelease["10.0.18363"] = "10.1909"		# 19H2
    osrelease["10.0.19041"] = "10.2004"		# 20H1
    osrelease["10.0.19042"] = "10.20H2"
    osrelease["10.0.19043"] = "10.21H1"
    osrelease["10.0.19044"] = "10.21H2"
    osrelease["10.0.19045"] = "10.22H2"
    
    sline = "-------------------------------------------------------------------------------\n"
    dline = "===============================================================================\n"
}

# --------------------------------------------------------------------------------------------------------
# Initialise
# --------------------------------------------------------------------------------------------------------

# count the number of files
FNR == 1 { ++pc_count }

# if it's the first line of the (anything but the first) file, print the summary for the previous machine
((FNR == 1) && (NR != 1)) {
	format_results()
	# and clear the data for this pc
    head_data = ""
	this_data = ""
	ChassisType = TpmPresent = ""
	bitlocker_status = "  "
	dell_updates_this = 0
	for (i in package_status)
		delete package_status[i]
}

{
	# on every line, we've written the file with windows so it has DOS line endings, but we may be processing it on linux, so remove extraneous CR (0x0d)
	sub(/\r/, "")
}

# --------------------------------------------------------------------------------------------------------
# Parse WPKG logfile
# --------------------------------------------------------------------------------------------------------

# ignore lines to do with some packages which are run for information
/(logfile)/        { next } 
/tidy temp files/  { next } 
# /(delldcuscan)/    { next } 

# check if a package file is broken (1)
# 2019-03-12 12:34:16, ERROR   : Error parsing xml '//wpkgserver.uk.accuride.com/wpkg/packages/fsclient.xml': The stylesheet does not contain a document element.  The stylesheet may be empty, or it may not be a well-formed XML document.|
# 2019-08-02 07:02:57, ERROR   : Error parsing xml '//wpkgserver.de.accuride.com/wpkg/packages/greenshot.xml': Das Stylesheet enthält kein Dokumentelement.  Das Stylesheet ist möglicherweise leer, oder es ist kein wohlgeformtes XML-Dokument.|
# 2019-08-02 07:02:57, ERROR   : No root element found in '//wpkgserver.de.accuride.com/wpkg/packages/greenshot.xml'.
# 2019-08-02 07:02:57, ERROR   : Error parsing xml '//wpkgserver.de.accuride.com/wpkg/packages/klio.xml': Das Stylesheet enthält kein Dokumentelement.  Das Stylesheet ist möglicherweise leer, oder es ist kein wohlgeformtes XML-Dokument.|
# for these ones we don't have a package name (because the file's broken)
/Error parsing xml/ {
	# the part enclosed in ' is the file path, characters like "ä" break awk, so avoid them
	split ($0, stringparts, "'")
	package_file = stringparts[2]
	# at this point we haven't got to the hostname line, for diags show the log file name
	report_file = substr(FILENAME,index(FILENAME,"wpkg-"))
	# print thisfile ": Error parsing xml:", package_file

	# potentially we'll get this reported in every file, so we should just keep track of the ones which are unique
	if (!(report_file in broken_report_file)) {
		print "Error parsing log:", report_file
		broken_report_file[report_file] = 1
	}
	if (!(package_file in broken_package_file)) {
		print "Error parsing xml:", package_file
		broken_package_file[package_file] = 1
	}
}

/Host properties: hostname=/ {
	# we can just split this up on "'"
    # 2014-01-13 08:22:26, DEBUG   : Host properties: hostname='system03'|architecture='x64'|os='microsoft windows 7 professional, , sp1, 6.1.7601'|ipaddresses='10.10.10.10,192.192.192.192'|domain name='thedomain.com'|groups=''|lcid='809'|lcidOS='409'
	# 2014-01-13 08:28:33, DEBUG   : Host properties: hostname='farsight'|architecture='x86'|os='microsoft windows xp professional, , sp3, 5.1.2600'|ipaddresses='10.10.10.10'|domain name='thisdomain'|groups='Domain Computers'|lcid='809'|lcidOS='409'
    # 2016-12-08 09:58:26, DEBUG   : Host properties: hostname='system04'|architecture='x64'|os='microsoft windows 10 pro, , , 10.0.14393'|ipaddresses='10.10.10.10,192.192.192.192'|domain name='thedomain.com'|groups=''|lcid='809'|lcidOS='409'
    # 2017-01-04 01:00:38, DEBUG   : Host properties: hostname='server01'|architecture='x64'|os='microsoft windows server 2008 r2 standard, , sp1, 6.1.7601'|ipaddresses='10.10.10.10'|domain name='thedomain.com'|groups='Domain Controllers'|lcid='809'|lcidOS='409'
    # 2016-12-08 09:58:26, DEBUG   : Host properties: hostname='system05'|architecture='x86'|os='microsoft windows 10 pro, , , 10.0.16299'|ipaddresses='192.192.192.192'|domain name='thedomain.com'|groups=''|lcid='809'|lcidOS='409'
	# 2019-07-24 10:06:31, DEBUG   : Host properties: hostname='de6'|architecture='x64'|os='microsoft(r) windows(r) server 2003 standard x64 edition, , sp2, 5.2.3790'|ipaddresses='10.81.1.200,10.81.1.200'|domain name='de.accuride.com'|groups='Domain Computers'|lcid='409'|lcidOS='409'
	# 2019-08-02 07:03:00, DEBUG   : Host properties: hostname='desql2'|architecture='x64'|os='microsoft® windows server® 2008 standard, , sp2, 6.0.6002'|ipaddresses='10.81.1.202,10.81.1.202,10.81.35.34'|domain name='de.accuride.com'|groups='Domain Computers'|lcid='407'|lcidOS='407'
    # 2020-05-10 05:20:34, DEBUG   : Host properties: hostname='zoomuk'|architecture='x64'|os='microsoft windows 10 enterprise 2016 ltsb, , , 10.0.14393'|ipaddresses='10.71.7.40'|domain name=''|groups=''|lcid='409'|lcidOS='409'
	# 2021-11-08 05:26:34, DEBUG   : Host properties: hostname='nb033'|architecture='x64'|os='microsoft windows 10 iot enterprise, , , 10.0.18363'|ipaddresses='192.186.0.99,10.81.35.115,192.168.0.99'|domain name='de.accuride.com'|groups='Domain Computers'|lcid='407'|lcidOS='407'


	split ($0, stringparts, "'")
	hostname     = stringparts[2]
	architecture = stringparts[4]
	os           = stringparts[6]
    domain       = stringparts[10]
	# and munge this about
	split (os, osparts, ",")
	osparts[1] = toupper(osparts[1])
	# remove any weird characters
	gsub (/\xAE/, "", osparts[1])                   # e.g. in "microsoft® windows server®"
	gsub (/\(R\)/, "", osparts[1])                  # e.g. in "microsoft(r) windows(r) server"
	sub (/MICROSOFT.*SERVER/, "svr", osparts[1])
	sub (/MICROSOFT WINDOWS/, "win", osparts[1])
	sub (/ FOR WORKSTATIONS/, "", osparts[1])
	sub (/ PROFESSIONAL/, "", osparts[1])
	sub (/ ENTERPRISE.*LTSB/, " Ent", osparts[1])
	sub (/ ENTERPRISE/, " Ent", osparts[1])
	sub (/ STANDARD/, "", osparts[1])
	sub (/ ULTIMATE/, "", osparts[1])
	sub (/ EDITION/, "", osparts[1])
	sub (/ HOME/, "H", osparts[1])
	sub (/ EVALUATION/, "Ev", osparts[1])
	sub (/ PRO/, "", osparts[1])
    
    # remove spaces from service pack & string
    sub (/ /, "", osparts[3])
    sub (/ /, "", osparts[4])
    
    # win 10
    if (osparts[4] in osrelease ) { sub(/10/, osrelease[osparts[4]],    osparts[1]) }
    # if we've not matched by now, just use the unique part of the version string
    # if (osparts[1] !~ /10\./) { sub(/10/, "10." osparts[4], osparts[1]);  sub(/10\.0\./, "10.", osparts[1])} # everything else
    
    # now add service pack or x86 to the os string as applicable
	os = osparts[1] osparts[3]
    if (osparts[3] == " ") { os = osparts[1] }
    if (architecture !~ "x64") { 
    os = os " " architecture }
    
    # add as much of the domain as will fit into hostlen char
    hostnamelen = hostlen - length(hostname) - 1
    shortdomain = substr(domain,1,hostnamelen)
    
    # initialise this
    rsync_status = ""
	# count os versions
	++os_list[os]
    
	format_head(shortdomain, hostname, os)
}

# Profiles applying to the current host:|remote-it|
/Profiles applying to the current host/ {
	profile_list_data = substr($0,index($0,":|")+2)
	gsub(/\|\r/, "", profile_list_data)  # dos line endings
	gsub(/\|$/, "", profile_list_data)   # other line endings
	gsub(/\|/, ", ", profile_list_data)  # any other separator lines
	profile_list[hostname] = profile_list_data
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

# if a package file is broken (2)
# 2019-08-04 10:49:34, WARNING : Database inconsistency: Package with package ID 'windows10settings' missing in package database. Package information found on local installation:|Package ID: Database inconsistency: Package with package ID 'windows10settings' missing in package database. Package information found on local installation:|Package Name: Windows 10 Settings|Package Revision: 1.4|
# 2019-03-12 12:34:18, ERROR   : Database inconsistency: Package with ID 'fsclient' does not exist within the package database or the local settings file. Please contact your system administrator!
/Database inconsistency: Package with/ {
	# the part enclosed in ' is the package name
	split ($0, stringparts, "'")
	package_name = stringparts[2]
	package_status[package_name] = "package broken"
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
	if ((package_name in packages) == 0 ) { ++unique_package_count }
	# count instances of this package
	++packages[package_name]
	# and update the status of this one
	package_status[package_name] = "not checked"
	++package_count
}

# this is redundant
# /Reading variables from package/ {
	# # the part enclosed in ' is the package name
	# # /2013-08-12 12:22:05, DEBUG   : Reading variables from package 'Mozilla Thunderbird'.
	# split ($0, stringparts, "'")
	# package_name = stringparts[2]
# }

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
    package_version[package_name] = substr(wpkg_version,1,pkverlen)
   	package_status[package_name] = "installing"
    package_timeout[package_name] = ""
}

# Uninstall entry for ... missing: test failed.  :: products which are not required
# when only updating DocuWare client when it's installed already
# Uninstall entry for DocuWare Desktop Framework missing: test failed.
# when installing Sophos, but not over Symantec
# Uninstall entry for Symantec Endpoint Protection missing: test failed
/Uninstall entry .* test failed/ {
	missing_package_name = substr($0, index($0, "Uninstall entry") + 20)
	sub(/ missing: .*$/, "", missing_package_name)
	# just test the first word for a match
	test_package_name = package_name
	sub(/ .*$/, "", test_package_name)
	# print package_name ":" test_package_name ":" missing_package_name ":\n"
   	if (missing_package_name ~ test_package_name) { package_status[package_name] = "no uninstall entry" }
}

# Package 'Visual C++ Redistributable' (vc_redist): Already installed.
# Package 'Visual C++ Redistributable' (vc_redist): Already installed once during this session.|Checking if package is properly installed.
# Package 'Visual C++ Redistributable' (vc_redist): Verified; package successfully installed during this session.
/Already installed\.|Verified; package successfully installed/ {
	# the part enclosed in ' is the package name
	split ($0, stringparts, "'")
	package_name = stringparts[2]
    # if we've already determined it's not installed, then it will be because it's not required, otherwise status is OK
    if (package_status[package_name] == "no uninstall entry") { package_status[package_name] = "not required"} else {	package_status[package_name] = "ok" }
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

/non-successful value / {
	# don't match on "ERROR" as it may occur elsewhere in the file
	# 2013-09-25 07:09:21, ERROR   : Could not process (upgrade) package 'Java Runtime Environment 7' (java7):|Exit code returned non-successful value (1603) on command '%SOFTWARE%\jre\jre-7u%version%-windows-i586.exe /s REBOOT=Suppress'.
	# get the bit within the brackets after the "|"
	errorcode = substr($0, index($0,"|"))
	errorcode = substr(errorcode, index(errorcode, "(") + 1 )
	errorcode = substr(errorcode, 1, index(errorcode, ")") - 1 )
	if (errorcode in errortext) errorcode = errorcode ", " errortext[errorcode]
	# get the package name, between ''
	split ($0, stringparts, "'")
	package_name = stringparts[2]
	# then set the status
	package_status[package_name] = "Fail " package_timeout[package_name] errorcode
}

/non-successful value:/ {
	# don't match on "ERROR" as it may occur elsewhere in the file
	# 2020-11-24 13:05:05, ERROR   : Exit code returned non-successful value: -1|Package: PuTTY.|Command:|"%PKG_DESTINATION%\unins000.exe" /sp- /verysilent /suppressmsgboxes /norestart
	split ($0, stringparts, "|")
	errorcode = stringparts[1]
	# remove everything we don't want
	sub(/^.*value: /,"",errorcode)
	if (errorcode in errortext) errorcode = errorcode ", " errortext[errorcode]
	# get the package name "|Package: PuTTY.|"
	package_name = stringparts[2]
	package_name = substr(package_name, index(package_name,":") + 2)
	package_name = substr(package_name, 1, index(package_name,".") - 1 )
	# then set the status
	package_status[package_name] = "Fail " package_timeout[package_name] errorcode
}

# 2013-08-12 12:22:12, ERROR   : Could not process (install) Mozilla Thunderbird.|Failed checking after installation.
/Failed checking after installation/ {
	# the package name is the bit between the ")" and the "|"
    package_name = $0
    sub(/^.*) /, "", package_name)
    sub(/\.\|.*$/, "", package_name)
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

# --------------------------------------------------------------------------------------------------------
# Process other stuff
# --------------------------------------------------------------------------------------------------------

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

# LastBootUpTime
# 20200507101250.501359+060
# use the simplest form here to make sure it works, other locales might use a comma
/^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][,\.][0-9][0-9][0-9][0-9]/ {
	yy = substr($1,1,4)
	mm = substr($1,5,2)
	dd = substr($1,7,2)
	hh = substr($1,9,2)
	mi = substr($1,11,2)
	boot_time[hostname] = yy "-" mm "-" dd " " hh ":" mi
}

# somewhere in the file we've dumped the output of Systemino, we want to show the boot date if it's not today's date, so munge it into yyyy-mm-dd
# however this will report wrong if the locale is wrong:
# System Boot Time:          20/04/2020, 12:08:53		# Input Locale:              en-gb;English (United Kingdom)
# System Boot Time:          5/14/2020, 7:00:09 AM		# Input Locale:              en-us;English (United States)
# /^System Boot Time/ {
	# dd = substr($4,1,2)
	# mm = substr($4,4,2)
	# yy = substr($4,7,4)
	# system_boot_date = yy "-" mm "-" dd
	# system_boot_time = substr($5,1,5)
	# boot_time[hostname] = system_boot_date " " system_boot_time
# }

# System Manufacturer:       Dell Inc.
# Systemhersteller:          Dell Inc.
# Systemhersteller:          LENOVO.
/^System Manufacturer|^Systemhersteller/ {
	system_manufacturer[hostname] = substr($0, index($0, ":"))
	sub(/: */,"",system_manufacturer[hostname])
}
# System Model:              Latitude 7300
# Systemmodell:              OptiPlex 7010
# Systemmodell:              10M70007GE
/^System Model|^Systemmodell/ {
	system_model[hostname] = substr($0, index($0, ":"))
	sub(/: */,"",system_model[hostname])
}

# BIOS Version:              Dell Inc. 1.9.1, 12/06/2020
# BIOS-Version:              Dell Inc. A29, 28.06.2018
/^BIOS.Version/ {
	system_bios[hostname] = substr($0, index($0, ":"))
	sub(/: */,"",system_bios[hostname])
	# remove the manufacturer name if it matches
	sub(system_manufacturer[hostname], "", system_bios[hostname])
	# and these we see a lot
	sub("Award Software International, Inc.", "Award", system_bios[hostname])
	sub("Phoenix Technologies LTD", "Phoenix", system_bios[hostname])
	sub("American Megatrends Inc.", "AMI", system_bios[hostname])
	# remove any leading space
	sub("^ ", "", system_bios[hostname])
}

# SerialNumber      : GVZKQV2
/^SerialNumber/ {
	serial = $3
	# we've written the file with windows so it has DOS line endings, but we may be processing it on linux, so remove extraneous CR (0x0d)
	# sub(/\r/, "", serial)
	system_serial[hostname] = serial
}

# Protection Status:    Protection Off or Protection status: Protection is disabled
#    Protection Status:    Protection On
#    Lock Status:          Unlocked
#    Identification Field: Unknown
#    Key Protectors:
#       TPM
#       External Key
#       Numerical Password
# or fail:
#   Protection Status:    Protection Off
#   Lock Status:          Unlocked
#   Identification Field: None
#   Key Protectors:       None Found
# odd character in this string
# 	Schl.sselschutzvorrichtungen: Keine gefunden

/Protection Status:.*Protection Off|Schutzstatus:.*Der Schutz ist deaktiviert/ {
	bitlocker_status = "BL OFF"
	++bitlocker_off
}

# Protection Status:    Protection Off
/Schutzstatus:.*Der Schutz ist deaktiviert/ {
	bitlocker_status = "BL OFF"
	++bitlocker_off
}

/Key Protectors:.*None Found|sselschutzvorrichtungen:.*Keine gefunden/ {
	bitlocker_status = bitlocker_status " (no TPM)"
}

# we use a script to write:
# BitLocker-Chassis: @{ChassisType=Portable}
# BitLocker-TPM: @{TpmPresent=True}
# BitLocker-Status: @{ProtectionStatus=On}

# if the Chassis is not Portable, we're not worried
/BitLocker-Chassis:/ {
	if ($2 ~ /ChassisType=Portable/) {
		ChassisType = "Portable"
	}
}
# does it have a TPM
/BitLocker-TPM:/ {
	if ($2 ~ /TpmPresent=True/) {
		TpmPresent = "True"
	}
}

/BitLocker-Status:/ {
	if ((ChassisType == "Portable") && ($2 ~ /ProtectionStatus=On/)) {
		bitlocker_status = "bl"
	} 
	if ((ChassisType == "Portable") && ($2 !~ /ProtectionStatus=On/)) {
		bitlocker_status = "BL OFF"
		++bitlocker_off	
	}
	if ((ChassisType == "Portable") && (TpmPresent !~ /True/)) {
		bitlocker_status = "BL OFF (no TPM)"
		++bitlocker_off
	}
	if (ChassisType != "Portable") {
		bitlocker_status = " -"
	} 
}

# Dell Command Update produces these lines about applicable updates
# 3DC3X: Intel Management Engine Components Installer - Driver -- Recommended -- CS
# 442GK: Dell Latitude 7300 and 7400 System BIOS - BIOS -- Urgent -- BI
# 6621F: Realtek USB GBE Ethernet Controller Driver - Driver -- Recommended -- DK
# 6GP36: Intel UHD Graphics Driver - Driver -- Urgent -- VI
# 8GG09: DBUtil Removal Utility - Application -- Urgent -- SY
# MVJH7: Dell SupportAssist OS Recovery Plugin for Dell Update - Application -- Recommended -- AP
# PV7R1: Dell Power Manager Service - Application -- Recommended -- SM
# V9PPW: Intel AX211/AX210/AX200/AX201/9560/9260/9462/8265/3165 Bluetooth UWD Driver - Driver -- Urgent -- NI
# 88J36: Dell ControlVault3 Driver and Firmware - Driver -- Recommended -- SY

/^.....:.*--/ {
	# extract update code and description
	dell_update_code = substr($1,1,5)
	dell_update_desc = substr($0, index($0,": ") + 2)
	++dell_updates_this
	
	# and load them into an array
	++dell_update_reqd[dell_update_code]
	dell_update_description[dell_update_code] = dell_update_desc
	# and get the max number of updates required
	if (dell_update_reqd[dell_update_code] > dell_update_max ) { dell_update_max = dell_update_reqd[dell_update_code] }
}


# Dell Command Update produces these lines about applicable updates
# [2023-05-17 06:30:05] : The computer manufacturer is 'Dell' 
# [2023-05-17 06:30:05] : Checking for updates... 
# [2023-05-17 06:30:05] : Checking for application component updates... 
# [2023-05-17 06:30:12] : Scanning system devices... 
# [2023-05-17 06:30:20] : Determining available updates... 
# [2023-05-17 06:30:24] : The scan result is VALID_RESULT 
# [2023-05-17 06:30:24] : Check for updates completed 
# [2023-05-17 06:30:24] : Number of applicable updates for the current system configuration: 6 
# [2023-05-17 06:30:24] : 0V76N: Dell Latitude 7300 and 7400 System BIOS - BIOS -- Urgent -- BI 
# [2023-05-17 06:30:24] : 3DC3X: Intel Management Engine Components Installer - Driver -- Recommended -- CS 
# [2023-05-17 06:30:24] : 6GP36: Intel UHD Graphics Driver - Driver -- Urgent -- VI 
# [2023-05-17 06:30:24] : 8678V: Dell Power Manager Service - Application -- Urgent -- SM 
# [2023-05-17 06:30:24] : 8GG09: DBUtil Removal Utility - Application -- Urgent -- SY 
# [2023-05-17 06:30:24] : HN6RG: Dell SupportAssist OS Recovery Plugin for Dell Update - Application -- Recommended -- AP 
# [2023-05-17 06:30:25] : Execution completed. 
# [2023-05-17 06:30:25] : The program exited with return code: 0 
# [2023-05-17 06:30:25] : State monitoring instance total elapsed time = 00:00:21.9968067, Execution time = 51mS, Overhead = 0.236081085351357% 
# [2023-05-17 06:30:25] : State monitoring disposed for application domain dcu-cli.exe 
/ : .....:.*--/ {
	# extract update code and description
	dell_update_code = substr($4,1,5)
	dell_update_desc = substr($0, index($0,$4) + 7)
	++dell_updates_this
	
	# and load them into an array
	++dell_update_reqd[dell_update_code]
	dell_update_description[dell_update_code] = dell_update_desc
	# and get the max number of updates required
	if (dell_update_reqd[dell_update_code] > dell_update_max ) { dell_update_max = dell_update_reqd[dell_update_code] }
}

# [2023-06-15 08:29:33] : The scan result is DOWNLOAD_ERROR 
# [2023-06-15 08:29:33] : INDEX_CATALOG_FAILED_DOWNLOAD is flagged in the scan results 
# [2023-06-15 08:29:33] : NETWORK_ERROR is flagged in the scan results 
/\[.*\] : .*ERROR/ {
	# dell_update_code = substr($4,1,5)
	# dell_update_desc = substr($0, index($0,$4) + 7)
	dell_update_code = substr($0, 24)
	sub(/_ERROR.*/, "", dell_update_code)
	sub(/.* /, "", dell_update_code)
	dell_update_desc = "ERROR"

	++dell_updates_this
	
	# and load them into an array
	++dell_update_reqd[dell_update_code]
	dell_update_description[dell_update_code] = dell_update_desc
	# and get the max number of updates required
	if (dell_update_reqd[dell_update_code] > dell_update_max ) { dell_update_max = dell_update_reqd[dell_update_code] }
	
}

# the rsync process for remote machines produces these lines at the end, just pick up the last one of each type
# 2017/04/07 08:32:57 [2380] total: matches=213719  hash_hits=213720  false_alarms=3 data=226467103
# 2017/04/07 08:32:57 [2380] sent 1.41M bytes  received 227.39M bytes  686.07K bytes/sec
# 2017/04/07 08:32:57 [2380] total size is 1.58G  speedup is 6.89
# or
# 2017/04/03 08:08:10 [2008] rsync: fork: Resource temporarily unavailable (11)
# 2017/04/03 08:08:10 [2008] rsync error: error in IPC code (code 14) at pipe.c(65) [Receiver=3.1.1]
# /] total|] sent|] rsync/ { rsync_status =  $0 "\n" }
/] total/ { rsync_total  = $0 "\n" }
/] sent/  { rsync_sent   = $0 "\n" }
/] rsync/ { rsync_status = $0 "\n" }
# /] total |] rsync /      { rsync_status =  rsync_status }

# --------------------------------------------------------------------------------------------------------
# Output the results
# --------------------------------------------------------------------------------------------------------

END {
	# gather the summary for the last file
	format_results() 
	
    # print the header
	# list the operating systems
	os_list_max = asorti(os_list, os_list_index)
	w = s = 0
	for (q = 1; q <= os_list_max; q++) {
		# if (os_list_index[q] ~ /win/) {
			# os_wks_all = os_wks_all wks_sep sprintf ("%s: %d", os_list_index[q], os_list[os_list_index[q]])
			# wks_sep = ", "
		# } else {
			# os_svr_all = os_svr_all svr_sep sprintf ("%s: %d", os_list_index[q], os_list[os_list_index[q]])
			# svr_sep = ", "
		# }
		if (os_list_index[q] ~ /win/) {
			os_wks[w] = os_list_index[q]
			os_wks_count[w] = os_list[os_list_index[q]]
			w++
		} else {
			os_svr[s] = os_list_index[q]
			if (os_list_index[q] ~ /NUL/) {os_svr[s] = "unknown"}
			os_svr_count[s] = os_list[os_list_index[q]]
			s++
		}
	}
	
	os_max = w
	if (os_max < s) {os_max = s}
	label_wks = "workstation o/s"
	label_svr = "server o/s"
	
	print "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
	print " computers checked:", pc_count", of which", pc_ok, "complete =", int(100 * pc_ok/pc_count) "% success"
	if (log_not_found > 0) {
	print "log file not found:", log_not_found, "    ( wpkg not installed? )"
	}
	print "   unique packages:", unique_package_count, "bitlocker off:", bitlocker_off
	if (package_count > 0) {
	print " package instances:", package_count", of which", package_fail, "failed, &", not_checked, "not checked = " int(100 * (package_count - package_fail - not_checked)/package_count) "% success"
	}
	# if (length(os_wks_all) > 1) { print "   workstation o/s:", os_wks_all }
	# if (length(os_svr_all) > 1) { print "        server o/s:", os_svr_all }
	
	# if we've got o/s counts, then print them
	for (k = 0; k <= os_max -1; k++) {
		printf(" %17s: %-20s %3s %12s: %-15s %3s\n", label_wks, os_wks[k] "", os_wks_count[k] "", label_svr, os_svr[k] "", os_svr_count[k] "")
		label_wks = label_svr = ""
	}
	print "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
	
	if ("*" in fdata)   { printf("%sfailed installs today:\n%s%s\n",     dline, dline, fdata["*"]) }
	if ("*" in rdata)   { printf("%ssuccessful installs today:\n%s%s\n", dline, dline, rdata["*"]) }
	if ("OLD" in fdata) { printf("%sfailed OLD installs:\n%s%s\n",       dline, dline, fdata["OLD"]) }
	if ("OLD" in rdata) { printf("%ssuccessful OLD installs:\n%s%s\n",   dline, dline, rdata["OLD"]) }


	# and report on Dell updates required
	printf("Dell updates required:\n%s", sline)
    for (j = dell_update_max; j >= 1; j--) {
		for ( dell_update_code in dell_update_reqd ) {
			if ( dell_update_reqd[dell_update_code] == j ) {printf ("%3d\t%s\t%s\n", j, dell_update_code, dell_update_description[dell_update_code]) }
		}
	}
	
	print "\nwpkgreports version", script_version
	
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
    
	# if boot_date is today, show it with a "*", we could try to be clever & calculate days since boot
	if ((hostname in boot_time) && (substr(_date_time[hostname],1,10) ~ substr(boot_time[hostname],1,10))) {
		boot_date_string = boot_time[hostname] "   *"
	} else {
		boot_date_string = boot_time[hostname]
	}
	
 	head_data =           sprintf("%-" hostlen "s      user : %-" userlen "s  run: %-16s %3s\n", _shortdomain[hostname] "\\" hostname, substr(usernames[hostname],1,userlen), _date_time[hostname],  _date_late[hostname])
 	head_data = head_data sprintf("%-" oslen   "s %s profile : %-"   userlen "s boot: %-22s\n", substr(_os[hostname],1,oslen), bitlocker_status, substr(profile_list[hostname],1,userlen), boot_date_string)
 	head_data = head_data sprintf("%-" hostlen "s    serial : %-"   userlen "s bios: %-22s\n", substr(system_model[hostname],1,hostlen), system_serial[hostname], system_bios[hostname])
	
    # use gawk's asorti function to sort on the index, the index values become the values of the second array
    n = asorti(package_status, package_status_index)
    for (j = 1; j <= n; j++) {
        i = package_status_index[j] # this is the original index
        this_data = this_data sprintf("%30s : %" pkverlen "s : %s\n", i, package_version[i], package_status[i])
        # be optimistic, assume packages have success unless they actually fail
        if ((package_status[i] ~ "Fail") || (package_status[i] ~ "zombie")) {
            ++package_fail
            pc_state = 0 
        } else {
            ++package_success 
        }
        if (package_status[i] == "not checked") { ++not_checked }
    }
	
	if ( dell_updates_this > 0 ) {
		# this_data = this_data sprintf("%30s : %15s : %s\n", "Dell Updates Required", dell_updates_this, "<<")
		this_data = this_data sprintf("%30s : %" pkverlen "s\n", "Dell Updates Required", dell_updates_this)
	}
	
	# if the packages were all ok (or if there were none), then this is a success
	if (pc_state == 1) {
		++pc_ok
		rdata[date_late] = rdata[date_late] head_data sline this_data sline rsync_sent rsync_total rsync_status sline
    } else {                                                                 
        if (date_late == "*") { ++pc_fail_today }
		fdata[date_late] = fdata[date_late] head_data sline this_data sline rsync_sent rsync_total rsync_status sline
	}
}
