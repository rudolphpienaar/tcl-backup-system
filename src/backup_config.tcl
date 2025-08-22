#!/bin/sh
# the next line restart with wish \
 exec tclsh "$0" $@

set G_SYNOPSIS "

NAME

      backup_config.tcl

SYNOPSIS

      backup_config.tcl --create <backup_name>
                        \[--template <template_type>\]
                        \[--output-dir <directory>\]
                        \[--daily-sets <count>\]
                        \[--weekly-sets <count>\]
                        \[--monthly-sets <count>\]
                        \[--non-interactive\]
                        \[--validate-only\]
                        \[--no-color\]
                        \[--help\]

DESCRIPTION

      Interactive configuration wizard for creating backup .object files.
      Uses your established parval CLI system and class_struct pseudo-OOP
      framework for robust configuration management.

"

# Package requirements
lappend auto_path       [file dirname [info script]]
package require         class_struct
package require         misc
package require         parval

# Global variables
set SELF                "backup_config.tcl"
set config_name         ""
set template_type       ""
set output_dir          "/root/backup_data"
set daily_sets          ""
set weekly_sets         ""
set monthly_sets        ""
set non_interactive     0
set validate_only       0
set no_color            0
set show_help           0

# Default tape counts
set DEFAULT_DAILY_SETS   7
set DEFAULT_WEEKLY_SETS  4
set DEFAULT_MONTHLY_SETS 3

# CLI parameter list for parval
set lst_commargs {create template output-dir daily-sets weekly-sets monthly-sets non-interactive validate-only no-color help}

# Color support detection and definitions
set colors_enabled 0
if {!$non_interactive && !$no_color && [info exists env(TERM)] && $env(TERM) != "dumb"} {
    if {[catch {
        # Write configuration in .object format using your established format
        puts $fileID "name>$config(name)"
        puts $fileID "archiveDate>[clock format [clock seconds]]"
        puts $fileID "workingDir>$config(workingDir)"

        # Current set numbers (start at 0)
        puts $fileID "currentSet,monthly>0"
        puts $fileID "currentSet,weekly>0"
        puts $fileID "currentSet,daily>0"
        puts $fileID "currentSet,none>0"

        # Total set numbers - use configured values
        set has_monthly [expr {$config(rulesMon) == "monthly" || $config(rulesTue) == "monthly" || $config(rulesWed) == "monthly" || $config(rulesThu) == "monthly" || $config(rulesFri) == "monthly" || $config(rulesSat) == "monthly" || $config(rulesSun) == "monthly"}]
        set has_weekly [expr {$config(rulesMon) == "weekly" || $config(rulesTue) == "weekly" || $config(rulesWed) == "weekly" || $config(rulesThu) == "weekly" || $config(rulesFri) == "weekly" || $config(rulesSat) == "weekly" || $config(rulesSun) == "weekly"}]
        set has_daily [expr {$config(rulesMon) == "daily" || $config(rulesTue) == "daily" || $config(rulesWed) == "daily" || $config(rulesThu) == "daily" || $config(rulesFri) == "daily" || $config(rulesSat) == "daily" || $config(rulesSun) == "daily"}]

        if {$has_monthly} {
            puts $fileID "totalSet,monthly>$config(monthlySets)"
        } else {
            puts $fileID "totalSet,monthly>0"
        }

        if {$has_weekly} {
            puts $fileID "totalSet,weekly>$config(weeklySets)"
        } else {
            puts $fileID "totalSet,weekly>0"
        }

        if {$has_daily} {
            puts $fileID "totalSet,daily>$config(dailySets)"
        } else {
            puts $fileID "totalSet,daily>0"
        }

        puts $fileID "totalSet,none>0"

        # Weekly schedule using class structure
        puts $fileID "rules,Mon>$config(rulesMon)"
        puts $fileID "rules,Tue>$config(rulesTue)"
        puts $fileID "rules,Wed>$config(rulesWed)"
        puts $fileID "rules,Thu>$config(rulesThu)"
        puts $fileID "rules,Fri>$config(rulesFri)"
        puts $fileID "rules,Sat>$config(rulesSat)"
        puts $fileID "rules,Sun>$config(rulesSun)"

        puts $fileID "currentRule>none"
        puts $fileID "remoteHost>$config(managerHost)"
        puts $fileID "remoteUser>$config(managerUser)"
        puts $fileID "remoteDevice>$config(archiveDir)"
        puts $fileID "remoteScriptDir>$config(remoteScriptDir)"

        # SSH command with port if not 22
        if {$config(managerPort) == "22"} {
            puts $fileID "rsh>ssh"
        } else {
            puts $fileID "rsh>ssh -p $config(managerPort)"
        }

        puts $fileID "adminUser>$config(adminUser)"
        puts $fileID "notifyTape>$config(notifyTape)"
        puts $fileID "notifyTar>$config(notifyTar)"
        puts $fileID "notifyError>$config(notifyError)"
        puts $fileID "partitions>$config(partitions)"
        puts $fileID "listFileDir>$config(listFileDir)"
        puts $fileID "status>"
        puts $fileID "command>"

        close $fileID

    } error]} {
        catch {close $fileID}
        config_error "fileCreate" "Failed to write configuration file: $error"
    }

    puts "\n  ${color(green)}✓ Configuration file created successfully$color(reset)"

    # Generate summary using class data
    puts "\n$color(blue)$color(bold)=== Configuration Summary ===$color(reset)"
    puts "${color(bold)}Backup name:$color(reset) $config(name)"
    puts "${color(bold)}Manager:$color(reset) $config(managerHost):$config(managerPort)"
    puts "${color(bold)}Target hosts:$color(reset) [join $config(targetHosts) {, }]"
    puts "${color(bold)}Directories:$color(reset) $config(directories)"
    puts "${color(bold)}Archive storage:$color(reset) $config(archiveDir)"
    puts "${color(bold)}Log directory:$color(reset) $config(workingDir)"
    puts "${color(bold)}Configuration file:$color(reset) $filename"

    puts "\n$color(green)$color(bold)=== Next Steps ===$color(reset)"
    puts "${color(green)}1.$color(reset) Review the generated .object file: $color(bold)$filename$color(reset)"
    puts "${color(green)}2.$color(reset) Test the configuration: $color(bold)backup_mgr.tcl --archive $config(name) --day Mon --rule daily$color(reset)"
    puts "${color(green)}3.$color(reset) Schedule with cron if test succeeds"
}
}

###\\\
# Main execution using your parval system
###///

# Initialize parval for command line parsing
set arr_PARVAL(0) 0
if {[catch {PARVAL_build clargs $argv "--"} error]} {
    config_error "invalidArgs" "Failed to initialize command line parser: $error"
}

# Parse all command line arguments using your parval system
foreach element $lst_commargs {
    if {[catch {PARVAL_interpret clargs $element} error]} {
        config_error "invalidArgs" "Failed to parse argument '$element': $error"
    }

    if {$arr_PARVAL(clargs,argnum) >= 0} {
        switch -- $element {
            "create" {
                set config_name $arr_PARVAL(clargs,value)
            }
            "template" {
                set template_type $arr_PARVAL(clargs,value)
                set valid_templates {server desktop database minimal}
                if {[lsearch $valid_templates $template_type] == -1} {
                    config_error "invalidArgs" "Invalid template '$template_type'. Valid: [join $valid_templates {, }]"
                }
            }
            "output-dir" {
                set output_dir $arr_PARVAL(clargs,value)
                if {![directory_validate $output_dir]} {
                    config_error "directoryAccess" "Output directory '$output_dir' is not accessible"
                }
            }
            "daily-sets" {
                set daily_sets $arr_PARVAL(clargs,value)
                if {![string is integer $daily_sets] || $daily_sets < 1} {
                    config_error "invalidArgs" "Daily sets must be positive integer, got: $daily_sets"
                }
            }
            "weekly-sets" {
                set weekly_sets $arr_PARVAL(clargs,value)
                if {![string is integer $weekly_sets] || $weekly_sets < 1} {
                    config_error "invalidArgs" "Weekly sets must be positive integer, got: $weekly_sets"
                }
            }
            "monthly-sets" {
                set monthly_sets $arr_PARVAL(clargs,value)
                if {![string is integer $monthly_sets] || $monthly_sets < 1} {
                    config_error "invalidArgs" "Monthly sets must be positive integer, got: $monthly_sets"
                }
            }
            "non-interactive" {
                set non_interactive 1
            }
            "validate-only" {
                set validate_only 1
            }
            "no-color" {
                set no_color 1
                set colors_enabled 0
                # Reset all color codes to empty
                array set color {red "" green "" yellow "" blue "" bold "" reset ""}
            }
            "help" {
                set show_help 1
            }
        }
    }
}

if {$show_help} {
    synopsis_show
}

if {$config_name == ""} {
    config_error "invalidArgs" "Backup name required (use --create <name>)"
}

# Validate error dictionary before proceeding
errors_validate

# Setup colors after functions are defined
colors_setup

message_log "INFO" "Starting backup configuration wizard for '$config_name'"

# Create output directory if it doesn't exist
if {![file exists $output_dir]} {
    message_log "INFO" "Creating output directory: $output_dir"
    if {[catch {file mkdir $output_dir} error]} {
        config_error "directoryAccess" "Cannot create output directory '$output_dir': $error"
    }
}

# Initialize configuration class using your class system
set lst_base_struct [configClass_struct]
if {[catch {
    class_Initialise configClass $lst_base_struct {} void
} error]} {
    config_error "classInit" "Failed to initialize configuration class: $error"
}

# Load template if specified using your class system
if {$template_type != ""} {
    if {[catch {template_load $template_type configClass} error]} {
        config_error "templateLoad" "Failed to load template: $error"
    }
} else {
    if {[catch {template_load "default" configClass} error]} {
        config_error "templateLoad" "Failed to load default template: $error"
    }
}

# Gather configuration using your class-based approach
if {[catch {
    basicInfo_gather configClass
    targetHosts_gather configClass
    directories_gather configClass
    schedule_gather configClass
    storage_gather configClass
    notifications_gather configClass
} error]} {
    config_error "inputValidation" "Configuration gathering failed: $error"
}

# Generate configuration file
if {!$validate_only} {
    if {[catch {objectFile_generate configClass} error]} {
        config_error "fileCreate" "Object file generation failed: $error"
    }
} else {
    message_log "INFO" "Validation complete (no file generated)"
}

message_log "INFO" "Configuration wizard completed successfully"exec tty} tty_result] == 0} {
        set colors_enabled 1
    }
}

# ANSI color codes
if {$colors_enabled} {
    set color(red)     "\033\[31m"
    set color(green)   "\033\[32m"
    set color(yellow)  "\033\[33m"
    set color(blue)    "\033\[34m"
    set color(bold)    "\033\[1m"
    set color(reset)   "\033\[0m"
} else {
    set color(red)     ""
    set color(green)   ""
    set color(yellow)  ""
    set color(blue)    ""
    set color(bold)    ""
    set color(reset)   ""
}

# Error definitions using dictionary with greppable field names
set errors {
    invalidArgs {
        ERR_context "parsing command line arguments"
        ERR_message "Invalid or missing command line arguments"
        ERR_code 1
    }
    sshConnection {
        ERR_context "testing SSH connectivity"
        ERR_message "Could not establish SSH connection to target host"
        ERR_code 2
    }
    fileCreate {
        ERR_context "creating configuration file"
        ERR_message "Could not create or write to configuration file"
        ERR_code 3
    }
    inputValidation {
        ERR_context "validating user input"
        ERR_message "User provided invalid input that could not be processed"
        ERR_code 4
    }
    templateLoad {
        ERR_context "loading configuration template"
        ERR_message "Could not load the specified configuration template"
        ERR_code 5
    }
    directoryAccess {
        ERR_context "accessing or creating directory"
        ERR_message "Could not access or create the specified directory"
        ERR_code 6
    }
    userAbort {
        ERR_context "gathering user configuration"
        ERR_message "User chose to abort the configuration process"
        ERR_code 7
    }
    classInit {
        ERR_context "initializing configuration class"
        ERR_message "Could not initialize backup configuration class structure"
        ERR_code 8
    }
}

###\\\
# Configuration class structure definition
###///

proc configClass_struct {} {
#
# DESC
# Define the structure for backup configuration class using your
# established pseudo-OOP pattern
#
    set classStruct {
        name
        description
        managerHost
        managerPort
        managerUser
        targetHosts
        directories
        partitions
        workingDir
        archiveDir
        remoteScriptDir
        listFileDir
        dailySets
        weeklySets
        monthlySets
        adminUser
        notifyTape
        notifyTar
        notifyError
        rshCommand
        scheduleType
        rulesMon
        rulesTue
        rulesWed
        rulesThu
        rulesFri
        rulesSat
        rulesSun
    }
    return $classStruct
}

###\\\
# Error handling functions
###///

proc errors_validate {} {
#
# DESC
# Validates that all error definitions in the errors dictionary contain
# required fields: ERR_context, ERR_message, and ERR_code
#
    global errors

    if {[catch {
        dict for {type info} $errors {
            if {![dict exists $info ERR_context] ||
                ![dict exists $info ERR_message] ||
                ![dict exists $info ERR_code]} {
                error "Incomplete error definition for type: $type"
            }

            # Validate error code is integer
            set code [dict get $info ERR_code]
            if {![string is integer $code] || $code < 1} {
                error "Invalid error code for type $type: $code (must be positive integer)"
            }
        }
    } error]} {
        puts stderr "ERROR: Error dictionary validation failed: $error"
        exit 99
    }
}

proc config_error {error_type details {fatal 1}} {
#
# ARGS
# error_type      in              type of error from errors dictionary
# details         in              specific error details from system
# fatal           in (opt)        1 to exit, 0 to continue (default: 1)
#
# DESC
# Handles configuration errors using dictionary-based error definitions.
# Provides rich error context and exits with appropriate code if fatal.
#
    global SELF errors color

    if {![dict exists $errors $error_type]} {
        puts stderr "${color(red)}INTERNAL ERROR: Unknown error type '$error_type'$color(reset)"
        puts stderr "Valid error types: [dict keys $errors]"
        exit 99
    }

    set error_info [dict get $errors $error_type]
    set context [dict get $error_info ERR_context]
    set message [dict get $error_info ERR_message]
    set code [dict get $error_info ERR_code]

    puts stderr "\n$color(red)$color(bold)$SELF ERROR$color(reset)"
    puts stderr "\tSorry, but there seems to be an error."
    puts stderr "\tWhile $context,"
    puts stderr "\t$message"
    if {$details != ""} {
        puts stderr "\t${color(yellow)}Specific error:$color(reset) $details"
    }
    puts stderr "\tat [exec date]"

    if {$fatal} {
        puts stderr "\n${color(red)}Exiting with code $code$color(reset)"
        exit $code
    } else {
        puts stderr "\n${color(yellow)}Continuing despite error (code $code)...$color(reset)"
    }
}

###\\\
# Utility functions
###///

proc synopsis_show {} {
#
# DESC
# Display usage information and exit
#
    global G_SYNOPSIS
    puts $G_SYNOPSIS
    exit 0
}

proc message_log {level message} {
#
# ARGS
# level           in              log level (INFO, WARN, ERROR)
# message         in              message text to log
#
# DESC
# Logs timestamped messages to stdout with level indication and color coding
#
    global color
    set timestamp [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]

    switch -- $level {
        "INFO" {
            puts "$color(blue)\[$timestamp\] $level:$color(reset) $message"
        }
        "WARN" {
            puts "$color(yellow)\[$timestamp\] $level:$color(reset) $message"
        }
        "ERROR" {
            puts "$color(red)\[$timestamp\] $level:$color(reset) $message"
        }
        default {
            puts "\[$timestamp\] $level: $message"
        }
    }
}

proc user_prompt {question default {validate_proc ""}} {
#
# ARGS
# question        in              question to ask user
# default         in              default value if user enters nothing
# validate_proc   in (opt)        validation procedure name
# answer          return          user's validated response
#
# DESC
# Prompts user for input with default value and optional validation.
# In non-interactive mode, returns default value without prompting.
# Repeats prompt until valid input received.
#
    global non_interactive color

    if {$non_interactive} {
        if {$default == ""} {
            config_error "invalidArgs" "Non-interactive mode requires default for: $question"
        }
        return $default
    }

    while {1} {
        if {$default != ""} {
            puts -nonewline "$question $color(green)\[$default\]$color(reset): "
        } else {
            puts -nonewline "$color(bold)$question$color(reset): "
        }
        flush stdout

        if {[catch {gets stdin} answer]} {
            config_error "inputValidation" "Failed to read user input"
        }

        if {$answer == ""} {
            set answer $default
        }

        # Validate if validation proc provided
        if {$validate_proc != "" && $answer != ""} {
            if {[catch {eval $validate_proc [list $answer]} valid] || !$valid} {
                puts "${color(red)}✗ Invalid input. Please try again.$color(reset)"
                continue
            }
        }

        return $answer
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

proc ipAddress_detect {} {
#
# DESC
# Auto-detect manager IP address with multiple fallback methods
#
    global color

    set detection_methods {
        {hostname --ip-addresses | awk {{print $1}}}                           "hostname --ip-addresses"
        {hostname -I | awk {{print $1}}}                                       "hostname -I"
        {ip route get 1.1.1.1 | grep -o {src [0-9.]*} | cut -d' ' -f2}        "ip route"
        {ifconfig | grep "inet " | grep -v "127.0.0.1" | head -1 | awk {{print $2}} | cut -d: -f2}  "ifconfig"
        {netstat -rn | grep "^0.0.0.0" | awk {{print $2}} | head -1}           "netstat route"
    }

    foreach {cmd description} $detection_methods {
        if {[catch {eval exec $cmd} result] == 0} {
            set candidate [string trim $result]
            if {$candidate != "" && [ip_validate $candidate]} {
                puts "  ${color(green)}✓ Auto-detected manager IP ($description):$color(reset) $candidate"
                return $candidate
            }
        }
    }

    puts "  ${color(yellow)}⚠ Could not auto-detect IP address, using localhost$color(reset)"
    return "127.0.0.1"
}

proc sshConnection_test {host port user} {
#
# ARGS
# host            in              hostname or IP to test
# port            in              SSH port number
# user            in              username for connection
# success         return          1 if connection successful, 0 otherwise
#
# DESC
# Tests SSH connectivity to specified host with timeout.
# Uses BatchMode to avoid password prompts.
#
    global color
    message_log "INFO" "Testing SSH connection to $user@$host:$port..."

    set ssh_cmd [list ssh -p $port -o ConnectTimeout=5 -o BatchMode=yes $user@$host echo OK]

    if {[catch {eval exec $ssh_cmd} result]} {
        puts "  ${color(red)}✗ SSH connection failed:$color(reset) $result"
        return 0
    } else {
        puts "  ${color(green)}✓ SSH connection successful$color(reset)"
        return 1
    }
}

###\\\
# Template functions using your class system
###///

proc template_load {template_name class} {
#
# ARGS
# template_name   in              name of template to load
# class           in/out          configuration class to populate
#
# DESC
# Loads predefined configuration templates into class using your
# established class manipulation functions
#
    upvar $class config

    if {[catch {
        switch -- $template_name {
            "server" {
                set config(scheduleType) "full"
                set config(directories) "/etc,/var/log,/root"
                set config(description) "Server system configuration backup"
            }
            "desktop" {
                set config(scheduleType) "daily_weekly"
                set config(directories) "/home,/opt"
                set config(description) "Desktop user data backup"
            }
            "database" {
                set config(scheduleType) "full"
                set config(directories) "/var/lib/mysql,/var/lib/postgresql"
                set config(description) "Database backup with monthly full backups"
            }
            "minimal" {
                set config(scheduleType) "weekly_only"
                set config(directories) "/etc"
                set config(description) "Minimal system backup"
            }
            default {
                set config(scheduleType) "daily_weekly"
                set config(directories) "/etc"
                set config(description) "Custom backup configuration"
            }
        }
    } error]} {
        config_error "templateLoad" "Template '$template_name': $error"
    }

    message_log "INFO" "Loaded template: $template_name"
}

###\\\
# Configuration gathering functions using your class system
###///

proc basicInfo_gather {class} {
#
# ARGS
# class           in/out          configuration class to populate
#
# DESC
# Collects basic backup configuration information using your class structure
#
    upvar $class config
    global config_name color

    puts "\n$color(blue)$color(bold)=== Gathering Basic Configuration ===$color(reset)"

    set config(name) $config_name

    if {[catch {
        set config(description) [user_prompt "Backup description" $config(description)]
    } error]} {
        config_error "inputValidation" "Backup description: $error"
    }

    # Auto-detect manager IP
    set auto_ip [ipAddress_detect]

    if {[catch {
        set config(managerHost) [user_prompt "Manager host IP" $auto_ip ip_validate]
        set config(managerPort) [user_prompt "Manager SSH port" "22" port_validate]
        set config(managerUser) [user_prompt "Manager SSH user" "root"]
    } error]} {
        config_error "inputValidation" "Manager information: $error"
    }
}

proc targetHosts_gather {class} {
#
# ARGS
# class           in/out          configuration class to populate
#
# DESC
# Collects target host information using class structure
#
    upvar $class config
    global non_interactive color

    puts "\n$color(blue)$color(bold)=== Configuring Target Hosts ===$color(reset)"

    if {[catch {
        set host_list [user_prompt "Target hosts (comma-separated)" ""]
        if {$host_list == ""} {
            config_error "invalidArgs" "At least one target host must be specified"
        }

        set config(targetHosts) [split $host_list ","]

        # Clean up whitespace
        set clean_hosts {}
        foreach host $config(targetHosts) {
            set clean_host [string trim $host]
            if {$clean_host != ""} {
                if {![ip_validate $clean_host]} {
                    puts "  ${color(yellow)}⚠ Host '$clean_host' is not a valid IP address (assuming hostname)$color(reset)"
                }
                lappend clean_hosts $clean_host
            }
        }

        if {[llength $clean_hosts] == 0} {
            config_error "invalidArgs" "No valid target hosts specified"
        }

        set config(targetHosts) $clean_hosts

    } error]} {
        config_error "inputValidation" "Target hosts: $error"
    }

    # Test SSH connections if interactive
    if {!$non_interactive} {
        puts "\n${color(blue)}Testing SSH connectivity...$color(reset)"
        foreach host $config(targetHosts) {
            if {[catch {
                set port [user_prompt "SSH port for $host" "22" port_validate]
                set config(hostPort,$host) $port

                # Test connection
                if {![sshConnection_test $host $port "root"]} {
                    set continue [user_prompt "SSH test failed for $host. Continue anyway? (y/n)" "n"]
                    if {![string match -nocase "y*" $continue]} {
                        config_error "sshConnection" "User aborted due to SSH failure for $host"
                    }
                }
            } error]} {
                config_error "inputValidation" "Host $host configuration: $error"
            }
        }
    } else {
        # Set default ports for non-interactive mode
        foreach host $config(targetHosts) {
            set config(hostPort,$host) "22"
        }
    }
}

proc directories_gather {class} {
#
# ARGS
# class           in/out          configuration class to populate
#
# DESC
# Collects directories to backup and builds partition list using class structure
#
    upvar $class config
    global color

    puts "\n$color(blue)$color(bold)=== Configuring Backup Directories ===$color(reset)"

    if {[catch {
        set dirs [user_prompt "Directories to backup (comma-separated)" $config(directories)]
        if {$dirs == ""} {
            config_error "invalidArgs" "At least one directory must be specified"
        }
        set config(directories) $dirs

        # Build partition list
        set partitions {}
        foreach host $config(targetHosts) {
            foreach dir [split $config(directories) ","] {
                set clean_dir [string trim $dir]
                if {$clean_dir != ""} {
                    # Basic path validation
                    if {![string match "/*" $clean_dir]} {
                        puts "  ${color(yellow)}⚠ Directory '$clean_dir' should be absolute path$color(reset)"
                    }
                    lappend partitions "$host:$clean_dir"
                }
            }
        }

        if {[llength $partitions] == 0} {
            config_error "inputValidation" "No valid partitions generated from directories and hosts"
        }

        set config(partitions) [join $partitions ","]
        puts "  ${color(green)}✓ Generated [llength $partitions] backup partitions$color(reset)"

    } error]} {
        config_error "inputValidation" "Directory configuration: $error"
    }
}

proc schedule_gather {class} {
#
# ARGS
# class           in/out          configuration class to populate
#
# DESC
# Configures backup schedule using class structure
#
    upvar $class config
    global color

    puts "\n$color(blue)$color(bold)=== Configuring Backup Schedule ===$color(reset)"

    if {[catch {
        puts "\n${color(bold)}Schedule options:$color(reset)"
        puts "${color(green)}1. full$color(reset)         - Complete 3-tier: Daily Mon-Fri, Weekly Sat, Monthly 1st Sun"
        puts "${color(green)}2. daily_weekly$color(reset) - Daily Mon-Fri, Weekly Sat (no monthly)"
        puts "${color(green)}3. weekly_monthly$color(reset) - Weekly Sat, Monthly 1st Sun (no daily)"
        puts "${color(green)}4. weekly_only$color(reset)  - Weekly backups Sat only"
        puts "${color(green)}5. monthly_only$color(reset) - Monthly backups 1st Sun only"
        puts "${color(green)}6. custom$color(reset)       - Custom schedule"

        set schedule_choice [user_prompt "Select schedule (1-6)" "1"]

        switch -- $schedule_choice {
            "1" -
            "full" {
                array set rules {Mon daily Tue daily Wed daily Thu daily Fri daily Sat weekly Sun monthly}
                puts "  ${color(yellow)}ⓘ Monthly backups run on 1st Sunday of month only$color(reset)"
            }
            "2" -
            "daily_weekly" {
                array set rules {Mon daily Tue daily Wed daily Thu daily Fri daily Sat weekly Sun none}
            }
            "3" -
            "weekly_monthly" {
                array set rules {Mon none Tue none Wed none Thu none Fri none Sat weekly Sun monthly}
                puts "  ${color(yellow)}ⓘ Monthly backups run on 1st Sunday of month only$color(reset)"
            }
            "4" -
            "weekly_only" {
                array set rules {Mon none Tue none Wed none Thu none Fri none Sat weekly Sun none}
            }
            "5" -
            "monthly_only" {
                array set rules {Mon none Tue none Wed none Thu none Fri none Sat none Sun monthly}
                puts "  ${color(yellow)}ⓘ Monthly backups run on 1st Sunday of month only$color(reset)"
            }
            "6" -
            "custom" {
                puts "\n${color(bold)}Enter backup type for each day (daily/weekly/monthly/none):$color(reset)"
                puts "${color(yellow)}Note: Monthly backups only run during 1st week of month$color(reset)"
                foreach day {Mon Tue Wed Thu Fri Sat Sun} {
                    while {1} {
                        set rule [user_prompt "$day" "none"]
                        if {[lsearch {daily weekly monthly none} $rule] != -1} {
                            set rules($day) $rule
                            break
                        } else {
                            puts "${color(red)}✗ Invalid rule type. Use: daily, weekly, monthly, or none$color(reset)"
                        }
                    }
                }
            }
            default {
                array set rules {Mon daily Tue daily Wed daily Thu daily Fri daily Sat weekly Sun monthly}
                puts "  ${color(yellow)}ⓘ Monthly backups run on 1st Sunday of month only$color(reset)"
            }
        }

        # Store rules in class structure
        set config(rulesMon) $rules(Mon)
        set config(rulesTue) $rules(Tue)
        set config(rulesWed) $rules(Wed)
        set config(rulesThu) $rules(Thu)
        set config(rulesFri) $rules(Fri)
        set config(rulesSat) $rules(Sat)
        set config(rulesSun) $rules(Sun)

        # Show summary
        puts "\n  ${color(green)}✓ Schedule configured:$color(reset)"
        set has_monthly 0
        foreach day {Mon Tue Wed Thu Fri Sat Sun} {
            if {$rules($day) != "none"} {
                puts "    $day: $color(bold)$rules($day)$color(reset)"
                if {$rules($day) == "monthly"} {
                    set has_monthly 1
                }
            }
        }

        if {$has_monthly} {
            puts "\n  ${color(blue)}ⓘ Monthly Backup Notes:$color(reset)"
            puts "    • Monthly backups are FULL backups (non-incremental)"
            puts "    • They only run during the first 7 days of the month"
            puts "    • They serve as the base for weekly/daily incrementals"
            puts "    • Require more tapes due to full backup size"
        }

    } error]} {
        config_error "inputValidation" "Schedule configuration: $error"
    }
}

proc storage_gather {class} {
#
# ARGS
# class           in/out          configuration class to populate
#
# DESC
# Configures storage paths and tape set counts using class structure
#
    upvar $class config
    global output_dir color
    global daily_sets weekly_sets monthly_sets
    global DEFAULT_DAILY_SETS DEFAULT_WEEKLY_SETS DEFAULT_MONTHLY_SETS

    puts "\n$color(blue)$color(bold)=== Configuring Storage and Tape Sets ===$color(reset)"

    if {[catch {
        set config(workingDir) [user_prompt "Log directory" "/root/backup_logs" directory_validate]
        set config(archiveDir) [user_prompt "Archive storage directory" $output_dir directory_validate]
        set config(remoteScriptDir) [user_prompt "Remote script directory" "/root/arch/scripts"]
        set config(listFileDir) [user_prompt "Incremental file list directory" "/tmp/backup_lists"]

        # Configure tape set counts - use CLI values or ask user or use defaults
        puts "\n${color(bold)}Tape Set Configuration:$color(reset)"
        puts "${color(yellow)}ⓘ Set counts determine backup rotation (higher = longer retention)$color(reset)"

        # Daily sets
        if {$daily_sets == ""} {
            set daily_sets [user_prompt "Daily backup sets (tapes/volumes)" $DEFAULT_DAILY_SETS]
            if {![string is integer $daily_sets] || $daily_sets < 1} {
                config_error "inputValidation" "Daily sets must be positive integer"
            }
        }
        set config(dailySets) $daily_sets

        # Weekly sets
        if {$weekly_sets == ""} {
            set weekly_sets [user_prompt "Weekly backup sets (tapes/volumes)" $DEFAULT_WEEKLY_SETS]
            if {![string is integer $weekly_sets] || $weekly_sets < 1} {
                config_error "inputValidation" "Weekly sets must be positive integer"
            }
        }
        set config(weeklySets) $weekly_sets

        # Monthly sets
        if {$monthly_sets == ""} {
            set monthly_sets [user_prompt "Monthly backup sets (tapes/volumes)" $DEFAULT_MONTHLY_SETS]
            if {![string is integer $monthly_sets] || $monthly_sets < 1} {
                config_error "inputValidation" "Monthly sets must be positive integer"
            }
        }
        set config(monthlySets) $monthly_sets

        puts "  ${color(green)}✓ Storage paths and tape sets configured$color(reset)"
        puts "    Daily: $daily_sets sets, Weekly: $weekly_sets sets, Monthly: $monthly_sets sets"

    } error]} {
        config_error "directoryAccess" "Storage configuration: $error"
    }
}

proc notifications_gather {class} {
#
# ARGS
# class           in/out          configuration class to populate
#
# DESC
# Configures notification settings using class structure
#
    upvar $class config
    global color

    puts "\n$color(blue)$color(bold)=== Configuring Notifications ===$color(reset)"

    if {[catch {
        set email [user_prompt "Admin email address" "" email_validate]
        set config(adminUser) $email

        set config(notifyTape) [user_prompt "Tape notification command" "echo 'Starting backup operation'"]
        set config(notifyTar) [user_prompt "Archive notification command" "echo 'Starting archive creation'"]
        set config(notifyError) [user_prompt "Error notification command" "echo 'Backup error occurred'"]

        puts "  ${color(green)}✓ Notification settings configured$color(reset)"

    } error]} {
        config_error "inputValidation" "Notification configuration: $error"
    }
}

###\\\
# Object file generation using your class system
###///

proc objectFile_generate {class} {
#
# ARGS
# class           in              populated configuration class
#
# DESC
# Generates .object file using your established class structure and format
#
    upvar $class config
    global output_dir color

    set filename "$output_dir/$config(name).object"

    message_log "INFO" "Generating configuration file: $filename"

    if {[catch {open $filename w} fileID]} {
        config_error "fileCreate" "Cannot create file $filename: $fileID"
    }

    if {[catch {
