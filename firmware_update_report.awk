# read all the wpkg report files
# read the firmware update parts
# report them seprately


# this is the output:
# Checking for updates...
# Checking for application component updates...
# Scanning system devices...
# Determining available updates...
# Check for updates completed
# Number of applicable updates for the current system configuration: 6
# FF17M: Intel AX210/AX200/AX201/9560/9260/8265/3165 Bluetooth UWD Driver - Driver -- Recommended -- NI
# VCVY6: Dell Latitude 7300 and 7400 System BIOS - BIOS -- Urgent -- BI
# 5P9YY: Intel AX200/AX201/9260/9560/8265 Wi-Fi UWD Driver - Driver -- Urgent -- NI
# 77XNV: Intel AX211/AX210/AX200/AX201/9560/9260/9462/8265/3165 Bluetooth UWD Driver - Driver -- Urgent -- NI
# 88J36: Dell ControlVault3 Driver and Firmware - Driver -- Recommended -- SY
# 3K7FF: Realtek USB GBE Ethernet Controller Driver - Driver -- Recommended -- DK
# Execution completed.

# we have added a line with the username, but it may have something that's not /[A-Za-z0-9]/ at the end
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
    
	# format_head(shortdomain, hostname, os)
}

$1 ~ /LastLoggedOnUser/ { 
	username = substr($3, index($3,"\\") + 1)
	# we've written the file with windows so it has DOS line endings, but we're processing it on linux
	sub(/[^A-Za-z0-9]+$/, "", username)
   	hostname = tolower(FILENAME)
	sub(/^.*wpkg-/, "", hostname)
	sub(/.log/, "", hostname)
	sub(/.usr/, "", hostname)
	# and load it into an array so we can pull it out again
    usernames[hostname] = username
}



# /^[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]:.*BIOS/ { 
/^[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]:/ { 
	print "----------------------------------------------------------------------------"
    print hostname, username
	
	print 
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
