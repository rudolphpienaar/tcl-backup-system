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

namespace eval appUtils {
    # -- Private Namespace Variables --
    variable _self "appUtils"
    variable _errors {}
    variable _no_color 0
    variable _color

    # -- Public API --
    namespace export init log errorLog validate set_option get_option colorize

    # -- Implementation --

    proc init {args} {
        #
        # ARGS
        # args      in          A dict-style list of options:
        #                       -self <name>      (req) The name of the calling application.
        #                       -nocolor <bool>   (opt) Boolean to disable color output.
        #                       -errors <dict>    (req) The dictionary of error definitions.
        #                                         The dictionary structure must be:
        #                                         {
        #                                             errorName {
        #                                                 ERR_context "Context of the error"
        #                                                 ERR_message "User-friendly message"
        #                                                 ERR_code    "Exit code"
        #                                             }
        #                                             ...
        #                                         }
        #
        # DESC
        # Initializes the utility library with application-specific settings.
        # This must be called once before using other procedures.
        #
        variable _self "appUtils"
        variable _errors {}
        variable _no_color 0
        variable _color

        # Parse the input arguments
        array set options $args
        if {[info exists options(-self)]} {set _self $options(-self)}
        if {[info exists options(-errors)]} {set _errors $options(-errors)}
        if {[info exists options(-nocolor)]} {set _no_color $options(-nocolor)}

        # Setup internal state
        _colors_setup
        validate
    }

    proc set_option {option value} {
        #
        # ARGS
        # option    in      The name of the option to set (e.g., -nocolor).
        # value     in      The new value for the option.
        #
        # DESC
        # Updates a configuration option after initialization.
        #
        variable _no_color

        switch -- $option {
            "-nocolor" {
                set _no_color $value
                # Re-run the color setup to apply the change immediately
                _colors_setup
            }
            default {
                return -code error "Unknown or read-only option '$option'"
            }
        }
    }

    proc get_option {option} {
        # ARGS
        # option    in      The name of the option to get (e.g., -nocolor).
        #
        # DESC
        # Retrieves the value of a configuration option.
        #
        variable _no_color
        variable _self

        switch -- $option {
            "-nocolor" {return $_no_color}
            "-self" {return $_self}
            default {return -code error "Unknown option '$option'"}
        }
    }

    proc log {level message} {
        #
        # ARGS
        # level     in          Log level (e.g., INFO, WARN, ERROR).
        # message   in          The message text to log.
        #
        # DESC
        # Logs a timestamped message to stdout with color coding.
        #
        variable _color
        set timestamp [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]

        switch -- $level {
            "INFO" {puts "$_color(blue)\[$timestamp\] $level:$_color(reset) $message"}
            "WARN" {puts "$_color(yellow)\[$timestamp\] $level:$_color(reset) $message"}
            "ERROR" {puts "$_color(red)\[$timestamp\] $level:$_color(reset) $message"}
            default {puts "\[$timestamp\] $level: $message"}
        }
    }

    proc errorLog {error_type details {fatal 1}} {
        #
        # ARGS
        # error_type    in          The key for the error from the errors dictionary.
        # details       in          Specific details about the runtime error.
        # fatal         in (opt)    If 1, exit the application; otherwise, continue.
        #
        # DESC
        # Handles a fatal or non-fatal error using the pre-configured dictionary.
        #
        variable _self
        variable _errors
        variable _color

        if {![dict exists $_errors $error_type]} {
            puts stderr \
                "$_color(red)INTERNAL ERROR: Unknown error type '$_error_type'$_color(reset)"
            puts stderr "Valid error types: [dict keys $_errors]"
            exit 99
        }

        set error_info [dict get $_errors $error_type]
        set context [dict get $error_info ERR_context]
        set message [dict get $error_info ERR_message]
        set code [dict get $error_info ERR_code]

        puts stderr "\n$_color(red)$_color(bold)$_self ERROR$_color(reset)"
        puts stderr "\tWhile $context,"
        puts stderr "\t$message"
        if {$details ne ""} {
            puts stderr "\t$_color(yellow)Specific error:$_color(reset) $details"
        }
        puts stderr "\tat [exec date]"

        if {$fatal} {
            puts stderr "\n$_color(red)Exiting with code $code$_color(reset)"
            exit $code
        } else {
            puts stderr "\n$_color(yellow)Continuing despite error (code $code)...$_color(reset)"
        }
    }

    proc validate {} {
        #
        # DESC
        # Validates the structure of the configured error dictionary.
        # Exits with code 99 on failure. This is intended for internal use.
        #
        variable _errors
        if {
            [catch {
                dict for {type info} $_errors {
                    if {
                        ![dict exists $info ERR_context] ||
                        ![dict exists $info ERR_message] ||
                        ![dict exists $info ERR_code]
                    } {
                        error "Incomplete error definition for type: $type"
                    }
                    set code [dict get $info ERR_code]
                    if {![string is integer $code] || $code < 1} {
                        error "Invalid error code for type $type: must be positive integer"
                    }
                }
            } err]
        } {
            puts stderr "FATAL: Error dictionary validation failed: $err"
            exit 99
        }
    }

    proc colorize {attribute_list text} {
        #
        # ARGS
        # attribute_list  in      A Tcl list of attributes (e.g., {blue bold}).
        # text            in      The string to colorize.
        #
        # DESC
        # Wraps a string with the specified ANSI color/style codes.
        #
        variable _color
        set ansi_codes ""
        foreach attr $attribute_list {
            if {[info exists _color($attr)]} {
                append ansi_codes $_color($attr)
            }
        }

        if {$ansi_codes eq ""} {
            return $text ;# Return plain text if no valid attributes found
        }
        # Apply all collected codes at once, followed by the reset code
        return "$ansi_codes$text$_color(reset)"
    }

    proc _colors_setup {} {
        #
        # DESC
        # Internal procedure to initialize the color array.
        #
        variable _color
        variable _no_color
        if {$_no_color} {
            array set _color {red "" green "" yellow "" blue "" bold "" reset ""}
        } else {
            array set _color {
                red     "\033\[31m"
                green   "\033\[32m"
                yellow  "\033\[33m"
                blue    "\033\[34m"
                bold    "\033\[1m"
                reset   "\033\[0m"
            }
        }
    }
}

proc ip_validate {ip} {
    #
    # ARGS
    # ip              in              IP address string to validate
    # valid           return          1 if valid IP, 0 otherwise
    #
    # DESC
    # Validates IP address format (simple dotted decimal check)
    #
    if {[catch {split $ip "."} parts]} {
        return 0
    }

    if {[llength $parts] != 4} {
        return 0
    }

    foreach part $parts {
        if {![string is integer $part] || $part < 0 || $part > 255} {
            return 0
        }
    }
    return 1
}

proc port_validate {port} {
    #
    # ARGS
    # port            in              port number to validate
    # valid           return          1 if valid port, 0 otherwise
    #
    # DESC
    # Validates port number (1-65535)
    #
    if {![string is integer $port] || $port < 1 || $port > 65535} {
        return 0
    }
    return 1
}

proc email_validate {email} {
    #
    # ARGS
    # email           in              email address to validate
    # valid           return          1 if valid format, 0 otherwise
    #
    # DESC
    # Basic email validation using regular expression
    #
    if {[catch {regexp {^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$} $email} match]} {
        return 0
    }
    return $match
}

proc directory_validate {dir} {
    #
    # ARGS
    # dir             in              directory path to validate
    # valid           return          1 if valid/creatable, 0 otherwise
    #
    # DESC
    # Validates directory exists or can be created
    #
    if {[file exists $dir]} {
        if {![file isdirectory $dir]} {
            return 0
        }
        if {![file writable $dir]} {
            return 0
        }
        return 1
    }

    # Try to create directory
    if {[catch {file mkdir $dir} error]} {
        return 0
    }
    return 1
}

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
