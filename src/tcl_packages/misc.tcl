#
# NAME
#
#   misc.tcl
#
# DESCRIPTION
#
#   Miscellaneous Tcl routines.
#
# HISTORY
#
#   05-11-1998: Initial transfer and testing.
#   01-10-2000: Re-evaluation and beautification.
#   08-26-2025: Reformat and modernization of docstrings.
#

package provide misc 0.1

proc weekdays_list {} {
	#
	# DESC
	# Returns a list of three-letter abbreviations for weekdays.
	#
	# RETURN
	# A list of weekdays: { Mon Tue Wed Thu Fri Sat Sun }
	#
	set weekdays {Mon Tue Wed Thu Fri Sat Sun}
	return $weekdays
}

proc exit_with {text} {
	#
	# DESC
	# Display usage information and exit
	#
	puts $text
	exit 0
}

proc deref {pointer {level 1}} {
	#
	# ARGS
	# pointer   in          Name of the variable to dereference.
	# level     in (opt)    Stack level reference (default: 1).
	#
	# DESC
	# "Dereferences" a "pointer" by returning the value of the variable
	# whose name is stored in the 'pointer' variable.
	#
	upvar $level $pointer contents
	return $contents
}

proc list_unzipPairs {flat_list keys_var values_var} {
	#
	# ARGS
	# flat_list     in          A list of alternating keys and values.
	# keys_var      in/out      The name of the variable to populate with the list of keys.
	# values_var    in/out      The name of the variable to populate with the list of values.
	#
	# DESC
	# "Unzips" a flat list of key-value pairs into two separate lists.
	# This procedure modifies the variables in the caller's scope.
	#
	# RETURN
	# This procedure does not return a value.
	#

	upvar 1 $keys_var keys
	upvar 1 $values_var values

	set keys {}
	set values {}

	foreach {key value} $flat_list {
		lappend keys $key
		lappend values $value
	}
}

proc list_unzipTriplets {flat_list list1_var list2_var list3_var} {
	#
	# ARGS
	# flat_list     in          A list of alternating items for three lists.
	# list1_var     in/out      The name of the variable to populate with the first list.
	# list2_var     in/out      The name of the variable to populate with the second list.
	# list3_var     in/out      The name of the variable to populate with the third list.
	#
	# DESC
	# Decomposes a flat list into three separate lists.
	# This procedure modifies the variables in the caller's scope.
	#
	# RETURN
	# This procedure does not return a value.
	#

	upvar 1 $list1_var list1
	upvar 1 $list2_var list2
	upvar 1 $list3_var list3

	set list1 {}
	set list2 {}
	set list3 {}

	foreach {item1 item2 item3} $flat_list {
		lappend list1 $item1
		lappend list2 $item2
		lappend list3 $item3
	}
}


proc list_unzip_ntuple {flat_list n args} {
	#
	# ARGS
	# flat_list in          The list of items to unzip.
	# n         in          The size of the tuple (e.g., 2 for pairs, 3 for triplets).
	# args      in/out      A list of variable names to populate.
	#
	if {$n <= 0} {error "Tuple size n must be positive"}
	if {[llength $args] != $n} {
		error "Number of variable names provided ([llength $args]) does not match tuple size ($n)"
	}

	# Initialize the output lists in the caller's scope
	foreach var_name $args {
		upvar 1 $var_name var
		set var {}
	}

	# Unzip the list
	for {set i 0} {$i < [llength $flat_list]} {incr i $n} {
		for {set j 0} {$j < $n} {incr j} {
			set var_name [lindex $args $j]
			upvar 1 $var_name var
			lappend var [lindex $flat_list [expr {$i + $j}]]
		}
	}
}


proc clint {argv lst_commargs {prefix ""}} {
	#
	# ARGS
	# argv          in          List of command line arguments.
	# lst_commargs  in          List of variables to search for.
	# prefix        in (opt)    String to prefix to the variable name.
	#
	# DESC
	# DEPRECATED: A very simple command line interpreter. This has been
	# superseded by the more robust 'parval' library. It is recommended
	# to refactor code to use 'parval' instead.
	#
	# NOTE
	# It is assumed that flags in lst_commargs are prefixed by "--".
	#
	set state flag
	foreach arg $argv {
		set found 0
		switch -- $state {
			flag {
				foreach commline $lst_commargs {
					set firstChar [string range $commline 0 0]
					if {[string first $firstChar $arg] == 2} {
						set state value
						set var $commline
						set found 1
						break
					}
				}
				if {!$found} {
					puts "unknown flag $arg"
					exit 100
				}
			}
			value {
				set state flag
				upvar ${prefix}${var} variable
				set variable $arg
			}
		}
	}
}
