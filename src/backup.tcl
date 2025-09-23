#!/bin/sh
# the next line restart with wish \
 exec tclsh "$0" ${1+"$@"}

set G_SYNOPSIS "
NAME

    backup.tcl - Client-side archive creation worker.

SYNOPSIS

    backup.tcl --user <user>                  \\
               --listFileDir <dir>            \\
               --host <host>                  \\
               --device <device>              \\
               --label <label>                \\
               --filesys <path>               \\
               --currentRule <rule>           \\
               --buffer <cmd>                 \\
               --incReset <yes|no>            \\
               --verbose <on|off>             \\
               --nocolor

DESCRIPTION

    `backup.tcl` is the \"thin\" end of the backup_mgr.tcl process. It is
    designed to run on the client machine being backed up and is typically
    called only by the controlling manager program.

    The script is machine-specific: it archives local filesystem directories
    and does not follow cross-links. It receives all necessary parameters
    via the command line to construct a `tar` command with the correct
    incremental options. This `tar` command is then written to a temporary
    child shell script (`archive.sh`) which is then executed.

    This method creates a pipeline that streams the archive over an SSH
    connection to a `buffer` command (typically 'cat') on the manager host,
    where it is written to the final device or file.

    Incremental backups for weekly and daily runs are referenced to a base
    backup (e.g., daily is referenced to weekly, weekly to monthly). If a
    base is non-existent, a full backup is performed to create it.

ARGS

    --user <user>
        The username for the SSH connection to the manager host.

    --listFileDir <dir>
        The directory on the client where `tar`'s incremental state files
        and the temporary `archive.sh` script will be stored.

    --host <host>
        The hostname or IP address of the manager host where the archive
        will be streamed.

    --device <device>
        The destination for the backup stream on the manager host. This can
        be a tape device path (e.g., /dev/nst0) or a directory path for
        disk-based backups.

    --label <label>
        The archive label that gets embedded in the `tar` header.

    --filesys <path>
        The absolute path to the directory or filesystem to be archived on
        this client.

    --currentRule <rule>
        The backup rule for the current execution (e.g., 'daily', 'weekly',
        'monthly'), which controls the incremental backup logic.

    --buffer <cmd>
        The command to use on the manager host to receive the `tar` stream
        (typically 'cat').

    --incReset <yes|no>
        A flag from the manager indicating whether to reset the `tar`
        incremental state files, forcing a new full backup for the current
        rule's base.

    --verbose <on|off>
        Controls whether the `tar` command includes the '--verbose' flag for
        logging all archived files.

    --nocolor
        (Optional) Disables colored output from the logging system.
"
# HISTORY
#
#   4-20-1998 / 04-24-1998
#   o   Initial development, testing and debugging.
#
#   6-25-1998
#   o   Added -force flag to copy command.
#
#   6-26-1998
#   o   Tracking down segmentation fault behaviour during monthly
#       vulcan backups. The tar command will be written to the command
#       line and run manually to narrow down the scope of the error.
#
#   6-29-1998
#   o   Changed the construction of the pipeCmd - removed curly brackets
#       and replaced them with single quotes.
#
#   6-30-1998
#   o   Re-implemented the basic archiving mechanism... too many
#       difficulties with quoting between tcl grouping commands. Now this
#       script creates a child script which contains the archive command
#       with necessary quoting. This child is then executed.
#
#   7-2-1998
#   o   Still getting segmentation violation on large archives. I suspect
#       that the tcl interpreter dies while trying to catch the *huge*
#       output of the tar command. Verbose is removed.
#
#   7-13-1998
#   o   Added additional command line parameter, incReset, that
#       controls whether or not to erase the incremental data base used
#       by `tar`.
#
#   7-22-1998
#   o   Added archive set name to incremental title.
#
#   7-28-1998
#   o   Added -v on flag for verbose logging.
#
#   01-11-2000
#   o   Re-evaluation.
#   o   Beautify.
#
#   01-13-2000
#   o   Command line arguments need two dashes ("--")!
#
#   01-14-2000
#   o   Changed command line arguments to new GNU style.
#   o   Forced `verbose` on all archives.
#
#   02 December 2000
#   o   Added -force to all file delete references.
#
#   18 September 2025
#   o   Refactored to use appUtils for logging and error handling.
#   o   Added full docstrings for all CLI arguments and script mechanism.
#   o   Applied final fixes: Corrected error handling logic, removed redundant
#       --rsh flag, and removed hardcoded auto_path.
#   o   Restored original description context and reformatted synopsis.

package require misc
package require parval

###\\\
# Globals --->
###///

set SELF "backup.tcl"

set error_definitions {
    cliArgs {
        ERR_context "parsing command-line arguments"
        ERR_message "A required argument was missing."
        ERR_code 10
    }
    childExec {
        ERR_context "executing child archive process"
        ERR_message "The tar command pipeline failed during execution."
        ERR_code 11
    }
}

###\\\
# main --->
###///

# --- Argument Parsing ---
set lst_commargs {
    user host device label filesys currentRule buffer incReset verbose listFileDir nocolor
}
foreach var $lst_commargs {set $var ""}

set arr_PARVAL(0) 0
PARVAL_build commswitch $argv "--" "1"
foreach element $lst_commargs {
    PARVAL_interpret commswitch $element
    if {$arr_PARVAL(commswitch,argnum) >= 0} {
        set $element $arr_PARVAL(commswitch,value)
    }
}
if {$nocolor == ""} {set nocolor 0}

# --- Initialize Utilities & Validate Args ---
appUtils::init -self $SELF -errors $error_definitions -nocolor $nocolor

foreach var $lst_commargs {
    # nocolor is optional, all others are required
    if {$var != "nocolor" && [set $var] == ""} {
        appUtils::errorLog "cliArgs" "Could not find a value for the '--$var' argument."
    }
}

set child_script_path "${listFileDir}/archive.sh"

# --- Build the tar Command ---
set tar_binary ""
switch -- [exec uname] {
    Linux   {set tar_binary "/bin/tar"}
    FreeBSD {set tar_binary "/usr/bin/tar"}
    Darwin  {set tar_binary "/opt/local/bin/tar"}
    default {set tar_binary "/bin/tar"}
}

set tar_cmd_list [list $tar_binary]
lappend tar_cmd_list "--create" "--file" "-" "--totals" "--gzip"
lappend tar_cmd_list "--label" "\"$label\""
if {$verbose=="on"} {
    lappend tar_cmd_list "--verbose"
}

# --- Determine Incremental Backup Settings ---
set hostname [exec hostname]
set filesys_path_safe [string map {"/" ":"} $filesys]
set backup_set_name [lindex [split $label :] 0]
set incremental_base_path "${listFileDir}/${backup_set_name}::${hostname}:${filesys_path_safe}"

if {$currentRule == "monthly"} {
    # For a monthly backup, we create a new incremental file and delete old ones.
    catch {file delete -force "${incremental_base_path}-*"}
    set incremental_file "${incremental_base_path}-monthly"
    lappend tar_cmd_list "--listed-incremental" "\"$incremental_file\""
    file delete -force $incremental_file
} else {
    # For weekly/daily, we may need to reset the incremental history.
    if {$incReset == "yes"} {
        catch {file delete -force "${incremental_base_path}-*"}
    }
    set base_rule [switch -- $currentRule {
        weekly  {"monthly"}
        daily   {"weekly"}
        default {""}
    }]
    if {$base_rule ne ""} {
        set incremental_file "${incremental_base_path}-${base_rule}"
        lappend tar_cmd_list "--listed-incremental" "\"$incremental_file\""
    }
}

lappend tar_cmd_list "\"$filesys\""
set tarcmd [join $tar_cmd_list " "]

# --- Determine Destination Device Path ---
# If the device isn't a /dev path, treat it as a file and generate a unique name.
if {[string first "/dev" $device] != 0} {
    set timestamp [clock format [clock seconds] -format "%a"]
    set label_safe [string map {":" "_" "/" "."} $label]
    set device "${device}/${label_safe}.${currentRule}.${timestamp}.tgz"
}

# --- Create and Execute the Child Script ---
# This method is used to avoid complex shell quoting issues within Tcl's exec.
if {[catch {open $child_script_path w 0755} childID]} {
    appUtils::errorLog "childExec" "Could not create
