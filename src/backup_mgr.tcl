#!/bin/sh
# the next line restart with wish \
 exec tclsh "$0" ${1+"$@"}

set G_SYNOPSIS "
NAME

    backup_mgr.tcl - Main backup process manager.

SYNOPSIS

    backup_mgr.tcl --config-dir <directory>             \\
                    [--archive <name>]                  \\
                    [--rule <force_rule>]               \\
                    [--day <force_day>]                 \\
                    [--no-color]                        \\
                    [--usage]

DESCRIPTION

    `backup_mgr.tcl` is the main backup manager. It discovers and reads all YAML
    configuration files in a specified directory, sorts them by priority
    (none, daily, weekly, monthly), and executes the backup process for each.

    After each successful backup, it saves the updated state back to the
    corresponding YAML file.

ARGS

    --config-dir <directory>
        (Required) The full path to the directory containing the .yml backup
        configuration files.

    --archive <name>
        (Optional) Process only a single backup configuration from the directory.
        The <name> must match the 'meta,name' field inside a YAML file.

    --rule <force_rule>
        (Optional) Force the manager to use <force_rule> (e.g., 'monthly')
        irrespective of what is scheduled for the current day.

    --day <force_day>
        (Optional) Force the manager to operate as if the current day is
        <force_day> (e.g., 'Sun').

    --no-color
        (Optional) Disable colored output from the logging system.

    --usage
        Show this synopsis.

CONFIGURATION

    This manager operates on YAML (.yml) configuration files. Each file represents
    a complete backup set and contains both static configuration and dynamic state.

    ## Object Structure
    The YAML file is structured into several sections:
    - meta: Basic information (`name`, `description`).
    - manager: Details for the backup host (`managerHost`, `remoteUser`).
    - targets: What to back up (`partitions`, a list of `host:/path`).
    - schedule: The backup rule for each day of the week (`Mon: daily`).
    - storage: Paths and rotation counts (`logDir`, `remoteDevice`, `dailySets`).
    - notifications: Hooks for email and commands (`adminUser`, `notifyError`).
    - state: Runtime data updated by this script (`currentSet`, `archiveDate`).

    ## Bootstrapping a New Backup Set
    To create a new backup configuration from scratch, use the interactive wizard:

        backup_config.tcl --create <your-backup-name>

    This wizard will guide you through all the necessary questions and generate a
    valid YAML file that you can then place in your config directory.
"
# HISTORY
# ... (Full history remains here) ...
#   17 September 2025
#   o   Refactored to use the central appUtils for logging and error handling.
#   o   Consolidated flat error message globals into a single dictionary.

###\\\
# include --->
###///
package require group
package require misc
package require tape_misc
package require parval

###\\\
# globals --->
###///

set SELF "backup_mgr.tcl"
set ext "yml"

# Error definitions for the appUtils library
set error_definitions {
    cliArgs {
        ERR_context "parsing command-line arguments"
        ERR_message "A required argument was missing or invalid."
        ERR_code 1
    }
    dirNotFound {
        ERR_context "validating configuration directory"
        ERR_message "The specified directory does not exist."
        ERR_code 2
    }
    yamlLoad {
        ERR_context "loading YAML configuration file"
        ERR_message "The file could not be parsed. It may be malformed."
        ERR_code 3
    }
    yamlSave {
        ERR_context "saving state to YAML configuration file"
        ERR_message "The application could not write the updated state to the file."
        ERR_code 4
    }
    backupFailed {
        ERR_context "running backup processes"
        ERR_message "One or more backups failed to complete successfully."
        ERR_code 5
    }
}

# Week day index
set lst_weekdays [weekdays_list]

###\\\
# Function definitions --->
###///

proc synopsis_show {} {
    global G_SYNOPSIS
    puts "$G_SYNOPSIS"
    exit 0
}

proc shutdown {exitcode} {
    global SELF
    appUtils::log INFO "'$SELF' shutting down with exit code $exitcode."
    exit $exitcode
}

###\\\
# main --->
###///
set date [exec date]
set today [lindex $date 0]
set todayDate [lindex $date 2]

# --- Parse Command Line Arguments ---
set config_dir ""
set archive_filter ""
set rule "void"
set day $today
set no_color 0
set usage 0

set lst_commargs {config-dir archive rule day no-color usage}
set arr_PARVAL(0) 0
PARVAL_build commswitch $argv "--"
foreach element $lst_commargs {
    PARVAL_interpret commswitch $element
    if {$arr_PARVAL(commswitch,argnum) >= 0} {
        set $element $arr_PARVAL(commswitch,value)
    }
}
if {[info exists archive]} {set archive_filter $archive}

# --- Initialize Utilities ---
appUtils::init -self $SELF -errors $error_definitions -nocolor $no_color

if {$usage} {synopsis_show}
if {$config_dir == ""} {
    appUtils::errorLog "cliArgs" "Required argument --config-dir was not provided."
}
if {![file isdirectory $config_dir]} {
    appUtils::errorLog "dirNotFound" "Configuration directory not found at '$config_dir'"
}

# --- Discover, Load, and Sort Backup Configurations ---
set config_files [glob -nocomplain -join $config_dir *.yml]
append config_files [glob -nocomplain -join $config_dir *.yaml]

set groups_to_sort {}
set group_to_file_map [dict create]
set i 0
foreach file $config_files {
    set group_name "backup_[clock clicks]_[incr i]"
    if {[catch {group::fromYaml $group_name %$file} err]} {
        appUtils::log WARN "Skipping invalid config file '$file': $err"
        continue
    }

    if {$archive_filter ne "" && [set ${group_name}(meta,name)] ne $archive_filter} {
        rename $group_name ""
        continue
    }

    set current_rule [tape_todayRule_get $group_name $day]
    set priority [lsearch -exact {none daily weekly monthly} $current_rule]
    if {$priority < 0} {set priority 0}

    lappend groups_to_sort [list $priority $group_name]
    dict set group_to_file_map $group_name $file
}

if {[llength $groups_to_sort] == 0} {
    appUtils::log WARN "No backup configurations found or matched in '$config_dir'. Exiting."
    shutdown 0
}

set sorted_groups_with_priority [lsort -integer -index 0 $groups_to_sort]

appUtils::log INFO "Processing backups for day '$day'."
appUtils::log INFO "Execution order (by priority):"
set sorted_group_names {}
foreach item $sorted_groups_with_priority {
    set group [lindex $item 1]
    lappend sorted_group_names $group
    appUtils::log INFO "\t- [set ${group}(meta,name)] ([set ${group}(state,currentRule)])"
}

# --- Main Execution Loop ---
set overall_status 1
foreach group $sorted_group_names {
    set config_file [dict get $group_to_file_map $group]
    set group_meta_name [set ${group}(meta,name)]
    appUtils::log INFO "Executing backup: '$group_meta_name' from '$config_file'..."

    set ok [tape_backup_manage $group $rule $day]

    if {$ok} {
        appUtils::log INFO "Status ok. Saving updated state to $config_file."
        if {[catch {group::toYaml $group %$config_file} err]} {
            appUtils::log ERROR "Failed to save state for '$group_meta_name' to '$config_file': $err"
            set overall_status 0
        }
    } else {
        appUtils::log ERROR "Backup process for '$group_meta_name' reported a failure."
        set overall_status 0
    }
    rename $group ""
}

# --- Shutdown with Final Status ---
if {$overall_status} {
    appUtils::log INFO "All backups completed successfully."
    shutdown 0
} else {
    appUtils::errorLog "backupFailed" "One or more backup processes failed to complete."
}
