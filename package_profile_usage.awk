# make a list of all packages and profiles defined and how often they are each used in our environment
# call like this: 
# awk -f package_profile_usage.awk <root profiles file> <path to profiles folder> <root package file> <path to packages .xml> <path to logfiles>
# e.g.
# awk -f package_profile_usage.awk /opt/updates/packages/*.xml /opt/wpkgreports/*.log
# uses asorti so needs gawk

# 29/12/22  dce  cover profiles in use as well
#                cover include for profiles
#                chain/depends for packages are already included
# 05/01/23  dce  looking for /Applying profile:/ in the log files is a better way of picking up profiles actually used
#                better string match for /\sid=/

BEGIN {
	minimum = 1
	IGNORECASE = 1
}

# in the profiles file(s) we see things like :
# <profile id="LaptopStd">
FILENAME ~ /profiles/ && /\sid=/ {
	# we're interested in the string after the = up to the next " or '
	profile_id = substr($0, index($0,"=")+2)
	gsub(/".*/,"",profile_id) # remove " and anything after
	gsub(/'.*/,"",profile_id) # remove ' and anything after
	gsub(/ */,"",profile_id)  # remove spaces
	gsub(/\r/,"",profile_id)  # or any extraneous return
	gsub(/\n/,"",profile_id)  # or line feed

	# and initialise the array
	all_profiles[profile_id] = 0
}
# and also
# <depends profile-id="standard" />
# in principal there could be multiple depends lines, but in practice we don't do that
# FILENAME ~ /profiles/ && /<depends/ {
	# # we're interested in the string after the = up to the next " or '
	# depends_id = substr($0, index($0,"=")+2)
	# gsub(/".*/,"",depends_id) # remove "
	# gsub(/'.*/,"",depends_id) # remove '
	# gsub(/ */,"",depends_id)  # remove space
	# gsub(/\r/,"",depends_id)  # or any extraneous return
	# gsub(/\n/,"",depends_id)  # or line feed

	# # and add to the array
	# depends[profile_id] = depends_id
# }

# in the packages file(s) we see things like this:
# <package id="packageid"
# or
# <package 
#	id="packageid"
FILENAME ~ /packages/ && /\sid=/ {
	# we're interested in the string after the = up to the next " or '
	package_id = substr($0, index($0,"=")+2)
	# remove all the extra characters
	gsub(/".*/,"",package_id) # remove "
	gsub(/'.*/,"",package_id) # remove '
	gsub(/ */,"",package_id)  # remove space
	gsub(/\r/,"",package_id)  # or any extraneous return
	gsub(/\n/,"",package_id)  # or line feed
	
	# and initialise the array
	defined_package_list[package_id] = 0
}

# and also
# <depends profile-id="standard" />
# in principal there could be multiple chain/depends/include lines, but in practice we don't do that
# <chain   package-id="otherpackage"/>
# <depends package-id="otherpackage"/>
# <include package-id="otherpackage"/>
# but we already pick these up, if they are referenced, then we install them

# in the output files we see "Profiles applying to the current host:|remote|+extrapackage|"
# /Profiles applying to the current host/ {
	# host_profile = substr($0,index($0,":|")+2)
	# gsub(/\|\r/, "", host_profile)  # dos line endings
	# gsub(/\|$/, "", host_profile)   # other line endings
	# gsub(/\|/, ", ", host_profile)  # any other separator lines
	# # and make a list of all profiles
	# gsub(/,.*/, "", host_profile)   # remove anything after the first comma, so we lose any multiples (fix later)
	# # increment profile usage
	# ++all_profiles[host_profile]
	
	# # now if this profile depends on another, we should increment the usage of that too
	# if (host_profile in depends) { ++all_profiles[depends[host_profile]] }
# }

# in the output files we see "Profiles applying to the current host:|remote|+extrapackage|"
# : Profiles applying to the current host:|WorkstationStd|+extrapackage|
# : Getting profiles which apply to this node.
# : Applying profile: WorkstationStd
# : Applying profile: +extrapackage

# : Applying profile: WorkstationStd
/Applying profile:/ {
	# NF is the number of fields, therefore $NF is the last field on the line
	host_profile = $NF
	gsub(/\r/, "", host_profile)  # dos line endings
	gsub(/\n/, "", host_profile)  # other line endings
	# increment profile usage
	++all_profiles[host_profile]
}

# : Adding profile dependencies of profile 'WorkstationStd': 'standard'
/Adding profile dependencies of profile/ {
	host_profile = $NF
	gsub(/'/, "", host_profile)   # remove any quotes
	gsub(/\r/, "", host_profile)  # dos line endings
	gsub(/\n/, "", host_profile)  # other line endings
	# increment profile usage
	++all_profiles[host_profile]
}

# in the output files we see lots of "Found package node", this lists the packages actually used
/Found package node/ {
	# the part enclosed in ' is the package name, 
	split ($0, stringparts, "'")
	package_name = stringparts[2]
	
	# the part enclosed in () is the package ID
    package_id = substr($0, index($0,"(") + 1,index($0,")") - index($0,"(") - 1)

	package_name_list[package_id] = package_name
	# count instances of usage of this package
	++defined_package_list[package_id]
}

END {
	# sort the lists
    n = asorti(all_profiles, profile_index)
    m = asorti(defined_package_list, package_index)
	
	# and show the results
	print "========================================================================="
	print "list of all profiles in use:"
    for (j = 1; j <= n; j++) {
		k = profile_index[j]
		if (all_profiles[k] > minimum) {
			printf("%3s  %-40s\n", all_profiles[k], k)
		}
	}
	print "\nlist of all profiles where usage <=", minimum ":"
    for (j = 1; j <= n; j++) {
		k = profile_index[j]
		if (all_profiles[k] <= minimum) {
			printf("%3s: %-40s\n", all_profiles[k], k)
		}
	}
	print "\n========================================================================="
	print "list of all packages in use:"
    for (j = 1; j <= m; j++) {
		k = package_index[j]
		if (defined_package_list[k] > minimum) {
			printf("%3s  %-40s %-s\n", defined_package_list[k], k, package_name_list[k])
		}
	}
	print "\nlist of all packages where usage <=", minimum ":"
    for (j = 1; j <= m; j++) {
		k = package_index[j]
		if (defined_package_list[k] <= minimum) {
			printf("%3s  %-40s %-s\n", defined_package_list[k], k, package_name_list[k])
		}
	}

}
