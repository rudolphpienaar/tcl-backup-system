#!/bin/sh
# the next line restart with wish \
 exec tclsh "$0" $@

set BACKUP_CONFIG_SYNOPSIS "

NAME

      backup_config.tcl

SYNOPSIS

      backup_config.tcl --create <backup_name>          \\
                        \[--template <template_type>\]  \\
                        \[--output-dir <directory>\]    \\
                        \[--daily-sets <count>\]        \\
                        \[--weekly-sets <count>\]       \\
                        \[--monthly-sets <count>\]      \\
                        \[--non-interactive\]           \\
                        \[--validate-only\]             \\
                        \[--no-color\]                  \\
                        \[--help\]

DESCRIPTION

      Interactive wizard for creating backup configuration files. Guides you
      through setting up backup schedules, target hosts, storage locations,
      and notification preferences. Generates .object configuration files
      compatible with the backup_mgr.tcl system.

ARGS

    --create <backup_name>
          Name of the backup configuration to create. This becomes the filename
          (with .object extension) and backup set identifier.

    \[--template <template_type>\]
          Load predefined configuration template. Available templates:
          server, desktop, database, minimal.

    \[--output-dir <directory>\]
          Directory where configuration file will be created.
          Default: /tmp/backup_configs

    \[--daily-sets <count>\]
          Number of daily backup tapes/volumes for rotation.
          Default: 7

    \[--weekly-sets <count>\]
          Number of weekly backup tapes/volumes for rotation.
          Default: 4

    \[--monthly-sets <count>\]
          Number of monthly backup tapes/volumes for rotation.
          Default: 3

    \[--non-interactive\]
          Use command-line values and defaults without prompting.
          Default mode is interactive.

    \[--validate-only\]
          Validate configuration without creating file.

    \[--no-color\]
          Disable colored output.

    \[--help\]
          Show this help and exit.

"

# Package requirements
lappend auto_path [file dirname [info script]]
package require class_struct
package require misc
package require parval

# Global variables
set ::SELF [file tail [info script]]
# catch {source [file join [file dirname [info script]] backup_object.tcl]}

# Main data structure
# This structure maps:
# internal member variables (Col 1)
# external  CLI  flag/names (Col 2)
# internal  default  values (Col 3)
set lst_members_flags_defaults {
    config_name     create          ""
    template_type   template        ""
    output_dir      output-dir      ""
    daily_sets      daily-sets      25
    weekly_sets     weekly-sets     5
    monthly_sets    monthly-sets    12
    non_interactive non-interactive 0
    validate_only   validate-only   0
    no_color        no-color        0
    show_help       help            0
}

# set config_name ""
# set template_type ""
# set output_dir "/root/backup_data"
# set daily_sets ""
# set weekly_sets ""
# set monthly_sets ""
# set non_interactive 0
# set validate_only 0
# set no_color 0
# set show_help 0
#
# # Default tape counts
# set DEFAULT_DAILY_SETS 7
# set DEFAULT_WEEKLY_SETS 4
# set DEFAULT_MONTHLY_SETS 3
#
# # CLI parameter list for parval
# set lst_commargs \
#     {create template output-dir daily-sets weekly-sets
#      monthly-sets non-interactive validate-only no-color help}

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

appUtils::init -self $SELF -errors $error_definitions -nocolor "0"

###\\\
# Function definitions
###///

# proc errors_validate {} {
#     #
#     # DESC
#     # Validates that all error definitions in the errors dictionary contain
#     # required fields: ERR_context, ERR_message, and ERR_code
#     #
#     global errors
#
#     if {
#         [catch {
#             dict for {type info} $errors {
#                 if {
#                     ![dict exists $info ERR_context] ||
#                     ![dict exists $info ERR_message] ||
#                     ![dict exists $info ERR_code]
#                 } {
#                     error "Incomplete error definition for type: $type"
#                 }
#
#                 # Validate error code is integer
#                 set code [dict get $info ERR_code]
#                 if {![string is integer $code] || $code < 1} {
#                     error "Invalid error code for type $type: $code (must be positive integer)"
#                 }
#             }
#         } error]
#     } {
#         puts stderr "ERROR: Error dictionary validation failed: $error"
#         exit 99
#     }
# }
#
# proc config_error {error_type details {fatal 1}} {
#     #
#     # ARGS
#     # error_type      in              type of error from errors dictionary
#     # details         in              specific error details from system
#     # fatal           in (opt)        1 to exit, 0 to continue (default: 1)
#     #
#     # DESC
#     # Handles configuration errors using dictionary-based error definitions.
#     # Provides rich error context and exits with appropriate code if fatal.
#     #
#     global SELF errors color
#
#     if {![dict exists $errors $error_type]} {
#         puts stderr "${color(red)}INTERNAL ERROR: Unknown error type '$error_type'$color(reset)"
#         puts stderr "Valid error types: [dict keys $errors]"
#         exit 99
#     }
#
#     set error_info [dict get $errors $error_type]
#     set context [dict get $error_info ERR_context]
#     set message [dict get $error_info ERR_message]
#     set code [dict get $error_info ERR_code]
#
#     puts stderr "\n$color(red)$color(bold)$SELF ERROR$color(reset)"
#     puts stderr "\tSorry, but there seems to be an error."
#     puts stderr "\tWhile $context,"
#     puts stderr "\t$message"
#     if {$details != ""} {
#         puts stderr "\t${color(yellow)}Specific error:$color(reset) $details"
#     }
#     puts stderr "\tat [exec date]"
#
#     if {$fatal} {
#         puts stderr "\n${color(red)}Exiting with code $code$color(reset)"
#         exit $code
#     } else {
#         puts stderr "\n${color(yellow)}Continuing despite error (code $code)...$color(reset)"
#     }
# }
#
# proc message_log {level message} {
#     #
#     # ARGS
#     # level           in              log level (INFO, WARN, ERROR)
#     # message         in              message text to log
#     #
#     # DESC
#     # Logs timestamped messages to stdout with level indication and color coding
#     #
#     global color
#     set timestamp [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
#
#     switch -- $level {
#         "INFO" {
#             puts "$color(blue)\[$timestamp\] $level:$color(reset) $message"
#         }
#         "WARN" {
#             puts "$color(yellow)\[$timestamp\] $level:$color(reset) $message"
#         }
#         "ERROR" {
#             puts "$color(red)\[$timestamp\] $level:$color(reset) $message"
#         }
#         default {
#             puts "\[$timestamp\] $level: $message"
#         }
#     }
# }
#
# proc colors_setup {} {
#     #
#     # DESC
#     # Initialize color support based on terminal capabilities
#     #
#     global color no_color
#
#     # ANSI color codes - always define them
#     if {$no_color} {
#         set color(red) ""
#         set color(green) ""
#         set color(yellow) ""
#         set color(blue) ""
#         set color(bold) ""
#         set color(reset) ""
#     } else {
#         set color(red) "\033\[31m"
#         set color(green) "\033\[32m"
#         set color(yellow) "\033\[33m"
#         set color(blue) "\033\[34m"
#         set color(bold) "\033\[1m"
#         set color(reset) "\033\[0m"
#     }
# }
#

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
            appUtils::errorLog "invalidArgs" "Non-interactive mode requires default for: $question"
        }
        return $default
    }

    while {1} {
        set ask [appUtils::colorize {bold yellow} $question]
        set def [appUtils::colorize {green} \[$default\]]
        if {$default != ""} {
            printf "$ask $def:"
        } else {
            printf "$ask:"
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
            if {[catch {$validate_proc [list $answer]} valid] || !$valid} {
                puts [appUtils::colorize "red" "✗ Invalid input. Please try again."]
                continue
            }
        }

        return $answer
    }
}

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

    if {
        [catch {
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
        } error]
    } {
        appUtils::errorLog "templateLoad" "Template '$template_name': $error"
    }

    appUtils::log "INFO" "Loaded template: $template_name"
}

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

    set header [appUtils::colorize {bold blue} "=== Gathering Basic Configuration ==="]
    puts "\n$header"

    set config(name) $config_name

    if {
        [catch {
            set config(description) [user_prompt "Backup description" $config(description)]
        } error]
    } {
        config_error "inputValidation" "Backup description: $error"
    }

    if {
        [catch {
            set config(managerHost) [user_prompt "Manager host IP" "127.0.0.1" ip_validate]
            set config(managerPort) [user_prompt "Manager SSH port" "22" port_validate]
            set config(managerUser) [user_prompt "Manager SSH user" "root"]
        } error]
    } {
        config_error "inputValidation" "Manager information: $error"
    }
}

proc targetHosts_gather {class} {
    #
    # ARGS
    # class           in/out          configuration class to populate
    #
    # DESC
    # Collects target host information and their backup directories
    #
    upvar $class config
    global color

    set header [appUtils::colorize {bold blue} "=== Configuring Target Hosts and Directories ==="]
    puts "\n$header"

    if {
        [catch {
            set host_list [user_prompt "Target hosts (comma-separated)" "localhost"]
            if {$host_list == ""} {
                appUtils::errorLog "invalidArgs" "At least one target host must be specified"
            }

            set config(targetHosts) [split $host_list ","]
            set clean_hosts {}
            set partitions {}

            foreach host $config(targetHosts) {
                set clean_host [string trim $host]
                if {$clean_host != ""} {
                    lappend clean_hosts $clean_host

                    # Get directories for this specific host
                    set dirs \
                        [user_prompt \
                            "Directories to backup on $clean_host (comma-separated)" "/etc"]
                    foreach dir [split $dirs ","] {
                        set clean_dir [string trim $dir]
                        if {$clean_dir != ""} {
                            lappend partitions "$clean_host:$clean_dir"
                        }
                    }
                }
            }

            set config(targetHosts) $clean_hosts
            set config(partitions) [join $partitions ","]
        } error]
    } {
        appUtils::errorLog "inputValidation" "Target hosts: $error"
    }
}

proc schedule_gather {class} {
    #
    # ARGS
    # class           in/out          configuration class to populate
    #
    # DESC
    # Configures backup schedule day by day
    #
    upvar $class config
    global color

    set mesg [appUtils::colorize {bold blue} "=== Configuring Backup Schedule ==="]
    puts "\n$mesg"
    set monthly [appUtils::colorize green monthly]
    set weekly [appUtils::colorize yellow weekly]
    set daily [appUtils::colorize blue daily]
    set none [appUtils::colorize red none]
    puts "For each day, choose: $monthly, $weekly, $daily, $none"

    if {
        [catch {
            set days {Mon Tue Wed Thu Fri Sat Sun}
            array set rules {}

            foreach day $days {
                while {1} {
                    set rule [user_prompt "$day backup type" "daily"]
                    if {[lsearch {monthly weekly daily none} $rule] != -1} {
                        set rules($day) $rule
                        break
                    } else {
                        puts "${color(red)}Invalid choice. Use: monthly, weekly, daily, or none$color(reset)"
                    }
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
        } error]
    } {
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
    global output_dir daily_sets weekly_sets monthly_sets color
    global DEFAULT_DAILY_SETS DEFAULT_WEEKLY_SETS DEFAULT_MONTHLY_SETS

    puts "\n$color(blue)$color(bold)=== Configuring Storage ===$color(reset)"

    if {
        [catch {
            set config(workingDir) \
                [user_prompt "Log directory" "/root/backup_logs" directory_validate]
            set config(archiveDir) \
                [user_prompt "Archive storage directory" $output_dir directory_validate]
            set config(listFileDir) \
                [user_prompt "Incremental file list directory" "/tmp/backup_lists"]

            # Configure tape set counts
            if {$daily_sets == ""} {
                set daily_sets [user_prompt "Daily backup sets" $DEFAULT_DAILY_SETS]
            }
            set config(dailySets) $daily_sets

            if {$weekly_sets == ""} {
                set weekly_sets [user_prompt "Weekly backup sets" $DEFAULT_WEEKLY_SETS]
            }
            set config(weeklySets) $weekly_sets

            if {$monthly_sets == ""} {
                set monthly_sets [user_prompt "Monthly backup sets" $DEFAULT_MONTHLY_SETS]
            }
            set config(monthlySets) $monthly_sets
        } error]
    } {
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

    if {
        [catch {
            set config(adminUser) \
                [user_prompt "Admin email address" "" email_validate]
            set config(notifyTape) \
                [user_prompt "Tape notification command" "echo 'Starting backup operation'"]
            set config(notifyTar) \
                [user_prompt "Archive notification command" "echo 'Starting archive creation'"]
            set config(notifyError) \
                [user_prompt "Error notification command" "echo 'Backup error occurred'"]
        } error]
    } {
        config_error "inputValidation" "Notification configuration: $error"
    }
}

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

    if {
        [catch {
            puts $fileID "name>$config(name)"
            puts $fileID "archiveDate>[clock format [clock seconds]]"
            puts $fileID "workingDir>$config(workingDir)"
            puts $fileID "currentRule>none"
            puts $fileID "remoteHost>$config(managerHost)"
            puts $fileID "remoteUser>$config(managerUser)"
            puts $fileID "remoteDevice>$config(archiveDir)"
            puts $fileID "rsh>ssh"
            puts $fileID "adminUser>$config(adminUser)"
            puts $fileID "notifyTape>$config(notifyTape)"
            puts $fileID "notifyTar>$config(notifyTar)"
            puts $fileID "notifyError>$config(notifyError)"
            puts $fileID "partitions>$config(partitions)"
            puts $fileID "listFileDir>$config(listFileDir)"
            puts $fileID "status>"
            puts $fileID "command>"

            # Add current/total set counts
            puts $fileID "currentSet,daily>0"
            puts $fileID "currentSet,weekly>0"
            puts $fileID "currentSet,monthly>0"
            puts $fileID "currentSet,none>0"
            puts $fileID "totalSet,daily>$config(dailySets)"
            puts $fileID "totalSet,weekly>$config(weeklySets)"
            puts $fileID "totalSet,monthly>$config(monthlySets)"
            puts $fileID "totalSet,none>0"

            # Add schedule rules
            puts $fileID "rules,Mon>$config(rulesMon)"
            puts $fileID "rules,Tue>$config(rulesTue)"
            puts $fileID "rules,Wed>$config(rulesWed)"
            puts $fileID "rules,Thu>$config(rulesThu)"
            puts $fileID "rules,Fri>$config(rulesFri)"
            puts $fileID "rules,Sat>$config(rulesSat)"
            puts $fileID "rules,Sun>$config(rulesSun)"

            close $fileID
        } error]
    } {
        catch {close $fileID}
        config_error "fileCreate" "Failed to write configuration file: $error"
    }

    puts "\n$color(green)Configuration file created: $filename$color(reset)"
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
# Main execution using your parval system
###///

proc off {} {
    # Validate error dictionary before proceeding
    errors_validate

    # Setup colors IMMEDIATELY after functions are defined
    colors_setup

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
                        config_error "invalidArgs" "Invalid template \
                            '$template_type'. Valid: [join $valid_templates {, }]"
                    }
                }
                "output-dir" {
                    set output_dir $arr_PARVAL(clargs,value)
                }
                "non-interactive" {
                    set non_interactive 1
                }
                "daily-sets" {
                    set daily_sets $arr_PARVAL(clargs,value)
                    if {![string is integer $daily_sets] || $daily_sets < 1} {
                        config_error "invalidArgs" \
                            "Daily sets must be positive integer, got: $daily_sets"
                    }
                }
                "weekly-sets" {
                    set weekly_sets $arr_PARVAL(clargs,value)
                    if {![string is integer $weekly_sets] || $weekly_sets < 1} {
                        config_error "invalidArgs" \
                            "Weekly sets must be positive integer, got: $weekly_sets"
                    }
                }
                "monthly-sets" {
                    set monthly_sets $arr_PARVAL(clargs,value)
                    if {![string is integer $monthly_sets] || $monthly_sets < 1} {
                        config_error "invalidArgs" \
                            "Monthly sets must be positive integer, got: $monthly_sets"
                    }
                }
                "validate-only" {
                    set validate_only 1
                }
                "no-color" {
                    set no_color 1
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

    message_log "INFO" "Starting backup configuration wizard for '$config_name'"

    # Prompt for output directory if interactive and not specified
    if {!$non_interactive && $output_dir == "/root/backup_data"} {
        set output_dir [user_prompt "Output directory" "/tmp/backup_configs" directory_validate]
    }

    # Create output directory if it doesn't exist
    if {![file exists $output_dir]} {
        message_log "INFO" "Creating output directory: $output_dir"
        if {[catch {file mkdir $output_dir} error]} {
            config_error "directoryAccess" "Cannot create output directory '$output_dir': $error"
        }
    }

    # Initialize configuration class using your class system
    set lst_base_struct [configClass_struct]
    if {
        [catch {
            class_Initialise configClass $lst_base_struct {} void
        } error]
    } {
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
    if {
        [catch {
            basicInfo_gather configClass
            targetHosts_gather configClass
            schedule_gather configClass
            storage_gather configClass
            notifications_gather configClass
        } error]
    } {
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

    message_log "INFO" "Configuration wizard completed successfully"
}

proc class_cliBuild {class parval} {
    # parval    in  the context of the command line interpreter
    #
    upvar $class cli
    global lst_members_flags_defaults

    set lst_memberVars {}
    set lst_commargs {}
    set lst_commvalues {}

    list_unzipTriplets $lst_members_flags_defaults lst_memberVars lst_commargs lst_commvalues

    # Define the list of all possible command-line flags
    set lst_commargs {
        create template output-dir
        daily-sets weekly-sets monthly-sets
        non-interactive validate-only no-color help
    }

    # Create a list to hold the values passed on the command line
    set lst_commvalues {}

    # Loop through each possible flag and get its value from the command line
    foreach flag $lst_commargs {
        # PARVAL_return will get the value, or an empty string if not present
        # For boolean flags like --help, it will return "1" if present.
        set val [PARVAL_return $parval $flag ""]
        lappend lst_commvalues [PARVAL_return $parval $flag ""]
    }

    # Now, create the 'cli' class using the flags as keys and the parsed values
    class_Initialise cli $lst_memberVars $lst_commvalues
    class_Dump cli
}

proc main {} {
    global argv G_SYNOPSIS

    if {![CLI_parse "clargs" $argv]} {
        exit 1
    }

    if {[PARVAL_return "clargs" "help"]} {
        exit_with $G_SYNOPSIS
    }

    errors_validate
    colors_setup
    class_cliBuild ccli clargs

    foreach flag [PARVAL_passedFlags "clargs"] {
        puts $flag
        switch -- $flag {
            "create" {
                set config_name [PARVAL_return "clargs" "create"]
            }
            "template" {
                set template_type [PARVAL_return "clargs" "template"]
                set valid_templates {server desktop database minimal}
                if {[lsearch $valid_templates $template_type] == -1} {
                    config_error "invalidArgs" \
                        "Invalid template '$template_type'. Valid: [join $valid_templates {, }]"
                }
            }
            "output-dir" {
                set output_dir [PARVAL_return "clargs" "output-dir"]
            }
            "non-interactive" {
                set non_interactive 1
            }
            "daily-sets" {
                set daily_sets [PARVAL_return "clargs" "daily-sets"]
                if {![string is integer $daily_sets] || $daily_sets < 1} {
                    config_error "invalidArgs" \
                        "Daily sets must be positive integer, got: $daily_sets"
                }
            }
            "weekly-sets" {
                set weekly_sets [PARVAL_return "clargs" "weekly-sets"]
                if {![string is integer $weekly_sets] || $weekly_sets < 1} {
                    config_error "invalidArgs" \
                        "Weekly sets must be positive integer, got: $weekly_sets"
                }
            }
            "monthly-sets" {
                set monthly_sets [PARVAL_return "clargs" "monthly-sets"]
                if {![string is integer $monthly_sets] || $monthly_sets < 1} {
                    config_error "invalidArgs" \
                        "Monthly sets must be positive integer, got: $monthly_sets"
                }
            }
            "validate-only" {
                set validate_only 1
            }
            "no-color" {
                set no_color 1
            }
            "help" {
                synopsis_show
            }
        }
    }
}

# Run main if called directly
if {[info script] eq $::argv0} {
    main
}
