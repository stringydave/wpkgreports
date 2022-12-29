# make a list of all packages and profiles defined and how often they are each used in our environment
# call like this: 
# awk -f package_profile_usage.awk <root profiles file> <path to profiles folder> <root package file> <path to packages .xml> <path to logfiles>
# e.g.
# awk -f package_profile_usage.awk /opt/updates/packages/*.xml /opt/wpkgreports/*.log
# uses asorti so needs gawk

# 29/12/22  dce  cover profiles in use as well

# TODO: cover include for profiles
# TODO: cover chain/depends for packages


BEGIN {
	minimum = 1
	IGNORECASE = 1
}

# in the profiles file(s) we see things like :
# <profile id="LaptopStd">
FILENAME ~ /profiles/ && / id=/ {
	# we're interested in the string after the = up to the next " or '
	profile_id = substr($0, index($0,"=")+2)
	gsub(/".*/,"",profile_id) # remove "
	gsub(/'.*/,"",profile_id) # remove '
	gsub(/ */,"",profile_id)  # remove space
	gsub(/\r/,"",profile_id)  # or any extraneous return
	gsub(/\n/,"",profile_id)  # or line feed

	# and initialise the array
	all_profiles[profile_id] = 0
}

# in the packages file(s) we see things like this:
# <package id="edidev"
FILENAME ~ /packages/ && / id=/ {
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

# in the output files we see "Profiles applying to the current host:|remote-it|"
/Profiles applying to the current host/ {
	profile_list_data = substr($0,index($0,":|")+2)
	gsub(/\|\r/, "", profile_list_data)  # dos line endings
	gsub(/\|$/, "", profile_list_data)   # other line endings
	gsub(/\|/, ", ", profile_list_data)  # any other separator lines
	# and make a list of all profiles
	gsub(/,.*/, "", profile_list_data)   # remove anything after the first comma, so we lose any multiples (fix later)
	++all_profiles[profile_list_data]
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
    for (j = 1; j <= n; j++) {
		k = package_index[j]
		if (defined_package_list[k] <= minimum) {
			printf("%3s  %-40s %-s\n", defined_package_list[k], k, package_name_list[k])
		}
	}

}
