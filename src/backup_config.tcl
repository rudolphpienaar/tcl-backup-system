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
      and notification preferences. Generates .object configuration file
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
# package require class_struct
package require misc
package require parval
package require group

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


# Error definitions using dictionary with greppable field names
set error_definitions {
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
    groupInit {
        ERR_context "initializing configuration group"
        ERR_message "Could not initialize backup configuration group structure"
        ERR_code 8
    }
    objSave {
        ERR_context "saving object structure"
        ERR_message "Some error was thrown while saving"
        ERR_code 9
    }
}

appUtils::init -self $SELF -errors $error_definitions -nocolor "0"

###\\\
# Function definitions
###///

proc user_prompt {cliGroup question default {validate_proc ""}} {
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
    upvar #0 $cliGroup cli

    if {$cli(non-interactive)} {
        if {$default == ""} {
            appUtils::errorLog "invalidArgs" "Non-interactive mode requires default for: $question"
        }
        return $default
    }

    while {1} {
        set ask [appUtils::colorize {bold yellow} $question]
        set def [appUtils::colorize {green} \[$default\]]
        if {$default != ""} {
            printf "$ask $def: "
        } else {
            printf "$ask: "
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

proc metaInfo_gather {cli_group} {
    #
    # ARGS
    # cli_group     in      The name of the global CLI group, used for context.
    #
    # DESC
    # Interactively gathers the metadata for the backup (its name and a
    # description). It bundles this data into a new, temporary group object
    # and returns the name of that temporary group. This procedure is "stateless."
    #
    # RETURN
    # Returns the unique global name of the temporary group as a string.
    #
    upvar #0 $cli_group cli

    puts [appUtils::colorize {bold blue} "\n=== Configuring Basic Information ==="]

    # --- Step 1: Gather all data into a local key-value list ---
    # Use the value from the '--create' flag as the default name.
    set name [user_prompt $cli_group "Backup name (a single word for the config file)" $cli(create)]
    set description [user_prompt $cli_group "Backup description" "Custom backup configuration"]

    set kv_list [list \
        name $name \
        description $description]

    # --- Step 2: Create the temporary global group ---
    set temp_group_name "_temp_meta_[clock clicks]"
    group::create $temp_group_name $kv_list

    # --- Step 3: Return the name of the temporary group ---
    return $temp_group_name
}

proc managerInfo_gather {cli_group} {
    #
    # ARGS
    # cli_group     in      The name of the global CLI group, used for context.
    #
    # DESC
    # Interactively collects the basic backup configuration information. It
    # bundles this data into a new, temporary group object and returns the
    # unique name of that temporary group for the caller to process.
    # This procedure is "stateless" and does not modify any external groups.
    #
    # RETURN
    # Returns the unique global name of the temporary group as a string.
    #
    upvar #0 $cli_group cli

    puts [appUtils::colorize {bold blue} "\n=== Archive Manager Configuration ==="]

    # --- Step 1: Gather all data into a local key-value list ---
    set kv_list [list]
    # lappend kv_list name $cli(create)

    # set description [user_prompt $cli_group "Backup description" "Backup Archive"]
    # lappend kv_list description $description

    set managerHost [user_prompt $cli_group "Manager host IP" "127.0.0.1" ip_validate]
    lappend kv_list managerHost $managerHost

    set managerPort [user_prompt $cli_group "Manager SSH port" "22" port_validate]
    lappend kv_list managerPort $managerPort

    set managerUser [user_prompt $cli_group "Manager SSH user" "root"]
    lappend kv_list managerUser $managerUser

    # --- Step 2: Create the temporary global group ---
    set temp_group_name "_temp_basic_info_[clock clicks]"
    group::create $temp_group_name $kv_list

    # --- Step 3: Return the name of the temporary group ---
    return $temp_group_name
}

proc workerInfo_gather {cli_group archive_group} {
    #
    # ARGS
    # cli_group         in      The name of the global CLI group.
    # archive_group     in      The name of the main configuration group being built.
    #
    # DESC
    # Gathers all worker-related configuration using the refined structure.
    # It creates a 'default' block and sibling blocks for any per-host overrides.
    #
    # RETURN
    # Returns the unique global name of the temporary group as a string.
    #
    upvar #0 $archive_group archive

    puts [appUtils::colorize {bold blue} "\n=== Configuring Worker Paths ==="]
    puts "These are the paths on the client machines."

    # --- Step 1: Gather the global defaults ---
    set default_scriptDir [user_prompt $cli_group \
        "Default worker script directory" "/usr/local/bin"]
    set default_tclLibPath [user_prompt $cli_group \
        "Default Tcl library path (TCLLIBPATH)" "/usr/local/lib/tcl"]

    # --- Step 2: Build the key-value list, starting with the default block ---
    set kv_list [list]
    lappend kv_list "default,scriptDir" $default_scriptDir
    lappend kv_list "default,tclLibPath" $default_tclLibPath

    # --- Step 3: Find unique hosts and gather overrides ---
    if {[info exists archive(targets,partitions)]} {
        set unique_hosts [dict create]
        foreach partition [split $archive(targets,partitions) ","] {
            set host [lindex [split $partition ":"] 0]
            dict set unique_hosts [string trim $host] 1
        }

        if {[dict size $unique_hosts] > 0} {
            puts "\n--- Per-Host Overrides ---"
            puts "You can now provide specific paths for any host that differs from the default."
        }

        dict for {host _} $unique_hosts {
            set provide_overrides [user_prompt $cli_group \
                "Provide specific worker paths for '$host'? (y/n)" "n"]

            if {[string tolower [string index $provide_overrides 0]] eq "y"} {
                puts "--- Override paths for '$host' ---"
                set scriptDir [user_prompt $cli_group \
                    "Worker script directory for '$host'" $default_scriptDir]
                set tclLibPath [user_prompt $cli_group \
                    "Tcl library path for '$host'" $default_tclLibPath]

                # Append the host-specific block to the key-value list
                lappend kv_list "${host},scriptDir" $scriptDir
                lappend kv_list "${host},tclLibPath" $tclLibPath
            }
        }
    }

    # --- Step 4: Create the final temporary group in one single call ---
    set temp_group_name "_temp_worker_[clock clicks]"
    group::create $temp_group_name $kv_list

    return $temp_group_name
}

proc targetHosts_gather {cli_group} {
    #
    # ARGS
    # cli_group     in      The name of the global CLI group, used for context.
    #
    # DESC
    # Collects target host information and their backup directories. It
    # bundles this data into a new, temporary group object and returns
    # the name of that temporary group.
    #
    # RETURN
    # Returns the unique global name of the temporary group as a string.
    #
    puts [appUtils::colorize {bold blue} "\n=== Configuring Target Hosts and Directories ==="]

    set host_list [user_prompt $cli_group "Target hosts (comma-separated)" "localhost"]
    if {$host_list == ""} {
        appUtils::errorLog "invalidArgs" "At least one target host must be specified"
        return "" ;# Return empty on error
    }

    set partitions {}
    foreach host [split $host_list ","] {
        set clean_host [string trim $host]
        if {$clean_host == ""} {continue}

        set dirs [user_prompt $cli_group \
            "Directories to backup on '$clean_host' (comma-separated)" "/etc"]

        foreach dir [split $dirs ","] {
            set clean_dir [string trim $dir]
            if {$clean_dir != ""} {
                lappend partitions "$clean_host:$clean_dir"
            }
        }
    }

    # Create the temporary global group.
    set temp_group_name "_temp_targets_[clock clicks]"
    group::create $temp_group_name [list partitions [join $partitions ","]]

    return $temp_group_name
}

proc schedule_gather {cli_group} {
    #
    # ARGS
    # cli_group     in      The name of the global CLI group, used for context.
    #
    # DESC
    # Interactively gathers the daily backup schedule from the user. It
    # bundles this data into a new, temporary group object and returns the
    # unique name of that temporary group for the caller to process.
    # This procedure is "stateless" and does not modify any external groups.
    #
    # RETURN
    # Returns the unique global name of the temporary group as a string.
    #
    upvar #0 $cli_group cli

    puts [appUtils::colorize {bold blue} "\n=== Configuring Backup Schedule ==="]
    set monthly [appUtils::colorize green monthly]
    set weekly [appUtils::colorize yellow weekly]
    set daily [appUtils::colorize blue daily]
    set none [appUtils::colorize red none]
    puts "For each day, choose: $monthly, $weekly, $daily, $none"

    # Use a simple local array to gather the data.
    array set rules {}
    set days {Mon Tue Wed Thu Fri Sat Sun}

    # This is the data-gathering loop for each day of the week.
    foreach day $days {
        while {1} {
            set rule [user_prompt $cli_group "$day backup type" "daily"]
            if {[lsearch -exact {monthly weekly daily none} $rule] != -1} {
                set rules($day) $rule
                break
            } else {
                puts [appUtils::colorize {red} \
                    "Invalid choice. Use: monthly, weekly, daily, or none"]
            }
        }
    }

    # Create the temporary global group from the local 'rules' array.
    set temp_group_name "_temp_schedule_[clock clicks]"
    group::create $temp_group_name [array get rules]

    # Return the name of the temporary group.
    return $temp_group_name
}

proc storage_gather {cli_group} {
    #
    # ARGS
    # cli_group     in      The name of the global CLI group, used for context
    #                       and for retrieving default values.
    #
    # DESC
    # Interactively gathers storage path and tape set count information.
    # It bundles this data into a new, temporary group object and returns
    # the unique name of that temporary group for the caller to process.
    # This procedure is "stateless" and does not modify any external groups.
    #
    # RETURN
    # Returns the unique global name of the temporary group as a string.
    #
    upvar #0 $cli_group cli

    puts [appUtils::colorize {bold blue} "\n=== Configuring Storage ==="]

    # --- Step 1: Gather all data into a local key-value list ---
    set kv_list [list]

    set logDir [user_prompt $cli_group "Log directory" "/tmp/backup_logs" directory_validate]
    lappend kv_list logDir $logDir

    # Use the output-dir from the CLI as the default for the archive directory.
    set archiveDir \
        [user_prompt $cli_group "Archive storage directory" $cli(output-dir) directory_validate]
    lappend kv_list archiveDir $archiveDir

    set listFileDir [user_prompt $cli_group "Incremental file list directory" "/tmp/backup_lists"]
    lappend kv_list listFileDir $listFileDir

    # --- Configure tape set counts ---
    # If a value was provided on the command line, use it. Otherwise, prompt the user.
    if {$cli(daily-sets) ne ""} {
        set daily_sets $cli(daily-sets)
    } else {
        set daily_sets [user_prompt $cli_group "Daily backup sets" $cli(daily-sets)]
    }
    lappend kv_list dailySets $daily_sets

    if {$cli(weekly-sets) ne ""} {
        set weekly_sets $cli(weekly-sets)
    } else {
        set weekly_sets [user_prompt $cli_group "Weekly backup sets" $cli(weekly-sets)]
    }
    lappend kv_list weeklySets $weekly_sets

    if {$cli(monthly-sets) ne ""} {
        set monthly_sets $cli(monthly-sets)
    } else {
        set monthly_sets [user_prompt $cli_group "Monthly backup sets" $cli(monthly-sets)]
    }
    lappend kv_list monthlySets $monthly_sets

    # --- Step 2: Create the temporary global group ---
    set temp_group_name "_temp_storage_[clock clicks]"
    group::create $temp_group_name $kv_list

    # --- Step 3: Return the name of the temporary group ---
    return $temp_group_name
}

proc notifications_gather {cli_group} {
    #
    # ARGS
    # cli_group     in      The name of the global CLI group, used for context.
    #
    # DESC
    # Interactively gathers notification settings (email, commands).
    # It bundles this data into a new, temporary group object and returns
    # the unique name of that temporary group. This procedure is "stateless."
    #
    # RETURN
    # Returns the unique global name of the temporary group as a string.
    #
    puts [appUtils::colorize {bold blue} "\n=== Configuring Notifications ==="]

    # --- Step 1: Gather all data into a local key-value list ---
    set kv_list [list]

    set adminUser [user_prompt $cli_group "Admin email address" "" email_validate]
    lappend kv_list adminUser $adminUser

    set notifyTape \
        [user_prompt $cli_group "Tape notification command" "echo 'Starting backup operation'"]
    lappend kv_list notifyTape $notifyTape

    set notifyTar \
        [user_prompt $cli_group "Archive notification command" "echo 'Starting archive creation'"]
    lappend kv_list notifyTar $notifyTar

    set notifyError \
        [user_prompt $cli_group "Error notification command" "echo 'Backup error occurred'"]
    lappend kv_list notifyError $notifyError

    # --- Step 2: Create the temporary global group ---
    set temp_group_name "_temp_notifications_[clock clicks]"
    group::create $temp_group_name $kv_list

    # --- Step 3: Return the name of the temporary group ---
    return $temp_group_name
}

proc group_cliBuild {group_name parval} {
    #
    # ARGS
    # group_name  in      The global name of the group to create (e.g., "ccli").
    # parval      in      The context of the command line interpreter.
    #
    # DESC
    # Builds a group object from command-line arguments. It is data-driven,
    # constructing its list of keys and default values directly from the
    # global 'lst_members_flags_defaults' matrix, making it the single
    # source of truth for CLI argument definitions.
    #
    global lst_members_flags_defaults

    set lst_keys {}
    set lst_values {}

    # Iterate through the global matrix to build our key and value lists.
    # This is an idiomatic Tcl way to process a flat list of triplets.
    foreach {member_var flag default_val} $lst_members_flags_defaults {
        # The key for our group will be the command-line flag itself.
        lappend lst_keys $flag

        # Now, get the value from the command line, using the default
        # from our matrix if the user didn't provide the flag.
        lappend lst_values [PARVAL_return $parval $flag $default_val]
    }

    # Call the constructor with our dynamically generated lists.
    group::createFromLists $group_name $lst_keys $lst_values
}

proc cliArgs_validate {group_name parval_name} {
    #
    # ARGS
    # group_name    in      The name of the CLI group object to validate.
    # parval_name   in      The name of the PARVAL object with the parse results.
    #
    # DESC
    # Iterates over the flags passed on the command line and validates the
    # corresponding values in the provided group object.
    #
    # RETURN
    # Returns 1 if all validations pass, 0 otherwise.
    #
    upvar #0 $group_name ccli

    # We iterate over the flags the user actually provided.
    foreach flag [PARVAL_passedFlags $parval_name] {
        switch -- $flag {
            "template" {
                set valid_templates {server desktop database minimal}
                if {[lsearch -exact $valid_templates $ccli(template)] == -1} {
                    appUtils::errorLog "invalidArgs" \
                        "Invalid template '$ccli(template)'. Valid: [join $valid_templates {, }]"
                    return 0
                }
            }
            "daily-sets" {
                if {![string is integer $ccli(daily-sets)] || $ccli(daily-sets) < 1} {
                    appUtils::errorLog "invalidArgs" \
                        "Daily sets must be a positive integer, got: '$ccli(daily-sets)'"
                    return 0
                }
            }
            "weekly-sets" {
                if {![string is integer $ccli(weekly-sets)] || $ccli(weekly-sets) < 1} {
                    appUtils::errorLog "invalidArgs" \
                        "Weekly sets must be a positive integer, got: '$ccli(weekly-sets)'"
                    return 0
                }
            }
            "monthly-sets" {
                if {![string is integer $ccli(monthly-sets)] || $ccli(monthly-sets) < 1} {
                    appUtils::errorLog "invalidArgs" \
                        "Monthly sets must be a positive integer, got: '$ccli(monthly-sets)'"
                    return 0
                }
            }
        }
    }
    if {$ccli(create) == ""} {
        appUtils::errorLog "invalidArgs" "Backup name required (use --create <name>)"
    }
    # If the loop completes without returning, all validations passed.
    return 1
}

proc outputDir_resolveAndCreate {group_name} {
    #
    # ARGS
    # group_name    in      The name of the CLI group object.
    #
    # DESC
    # Resolves the output directory. If in interactive mode and no directory
    # was specified on the command line, it prompts the user for one.
    # It then ensures the final directory exists, creating it if necessary.
    #
    upvar #0 $group_name ccli

    # Check if the value is an empty string, which indicates
    # it was not provided on the command line.
    if {!$ccli(non-interactive) && $ccli(output-dir) eq ""} {
        set ccli(output-dir) \
            [user_prompt ccli \
                "Output directory (for .object config)" "/tmp/backup_archives" directory_validate]
    }

    # After resolving, ensure the directory exists.
    if {![file exists $ccli(output-dir)]} {
        appUtils::log "INFO" "Creating output directory: $ccli(output-dir)"
        if {[catch {file mkdir $ccli(output-dir)} error]} {
            appUtils::errorLog \
                "directoryAccess" "Cannot create output directory '$ccli(output-dir)': $error"
        }
    }
}

proc user_promptAndVerify {gather_proc cli_group archive_group sub_group_key {order_list ""} args} {
    #
    # ARGS
    # gather_proc   in      The name of the data-gathering procedure to call.
    # cli_group     in      The name of the global CLI group, used for context.
    # archive_group in/out  The name of the main config group to be modified.
    # sub_group_key in      The key under which the new data should be composed.
    # order_list    in (opt) A list of keys to specify the display order.
    # args          in      A list of any additional arguments to pass to the gather_proc.
    #
    # DESC
    # A higher-order procedure that wraps a data-gathering function in a
    # user confirmation loop. It calls the gatherer, displays the result,
    # asks for confirmation, and then composes the data into the main archive.
    #
    while {1} {
        # Execute the data-gathering proc, passing along any extra arguments.
        set temp_group_name [$gather_proc $cli_group {*}$args]

        # --- User Confirmation Step ---
        puts [appUtils::colorize {bold blue} "\n--- Please Confirm ---"]
        print_inTable $temp_group_name $order_list

        set confirmation [user_prompt $cli_group "Is this correct? (y/n)" "y"]

        # Helper to safely clean up the temporary group.
        proc _cleanup_temp_group {name} {
            catch {unset $name}
            catch {rename $name {}}
        }

        if {[string tolower [string index $confirmation 0]] eq "y"} {
            # User confirmed. Compose the temp group into the main one.
            group::add $archive_group $sub_group_key @$temp_group_name
            _cleanup_temp_group $temp_group_name
            break
        }

        # User rejected. Clean up and the loop will repeat.
        _cleanup_temp_group $temp_group_name
        puts [appUtils::colorize {yellow} "Okay, let's try that again..."]
    }
}

proc config_process {cli archive} {
    #
    # ARGS
    # cli       in      The name of the global CLI group.
    # archive   in/out  The name of the main config group to be populated.
    #
    # DESC
    # The main orchestrator for the interactive configuration wizard.
    #
    upvar #0 $cli ccli

    appUtils::log "INFO" "Starting backup configuration wizard for '$ccli(create)'"
    set schedule_order {Mon Tue Wed Thu Fri Sat Sun}

    if {
        [catch {
            outputDir_resolveAndCreate $cli

            user_promptAndVerify metaInfo_gather $cli $archive "meta"
            user_promptAndVerify managerInfo_gather $cli $archive "manager"
            user_promptAndVerify targetHosts_gather $cli $archive "targets"
            user_promptAndVerify workerInfo_gather $cli $archive "worker" "" $archive
            user_promptAndVerify schedule_gather $cli $archive "schedule" $schedule_order
            user_promptAndVerify storage_gather $cli $archive "storage"
            user_promptAndVerify notifications_gather $cli $archive "notifications"
        } error]
    } {
        appUtils::errorLog "inputValidation" "Configuration wizard failed: $error"
    }
    appUtils::log "INFO" "Configuration wizard completed successfully"
}

proc print_inTable {group {order_list ""}} {
    #
    # ARGS
    # group         in      The name of the group object to print.
    # order_list    in (opt) A list of keys to specify the display order.
    #                        If empty, the table is sorted alphabetically.
    #
    # DESC
    # A helper procedure that prints a group object to the console as a
    # nicely formatted and colorized ASCII table.
    #
    set table_color_options [list \
        -headerKeyColor {bold yellow} \
        -headerValColor {bold yellow} \
        -bodyKeyColor {cyan} \
        -bodyValColor {green}]

    # If a specific order was requested, add it to the options.
    if {$order_list ne ""} {
        lappend table_color_options -order $order_list
    }

    # Use the 'toTable' command with all the defined options.
    puts [group::toTable $group {*}$table_color_options]
}

proc archiveSet_save {group} {
    upvar #0 $group archive
    set archiveName [file join $archive(storage,archiveDir) ${archive(meta,name)}.yaml]
    if {
        [catch {
            group::toYaml $group %$archiveName
        } error]
    } {
        appUtils::errorLog "objSave" "While saving archive control data: $error"
    }
    appUtils::log "INFO" "Archive object file saved to $archiveName"
}

###\\\
# Main execution
###///

proc main {} {
    global argv BACKUP_CONFIG_SYNOPSIS
    global ccli
    global backup
    group::create ccli {}
    group::create backup {}

    if {![CLI_parse "clargs" $argv]} {
        exit 1
    }

    if {[PARVAL_return "clargs" "help" 0]} {
        exit_with $BACKUP_CONFIG_SYNOPSIS 1
    }

    group_cliBuild ccli clargs


    if {![cliArgs_validate ccli clargs]} {
        exit 1
    }

    config_process ccli backup
    puts [group::toYaml backup]
    archiveSet_save backup

    # print_inTable backup
}

# Run main if called directly
if {[info script] eq $::argv0} {
    main
}
