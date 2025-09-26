#
# NAME
#
#   tape_misc.tcl
#
# DESCRIPTION
#
#   Miscellaneous tape controlling routines - largely used by the
#   backup_mgr.tcl process
#
# TODO
#
#   o   Class expansions: buffer, misc tar commands
#   o   Remove verbose considerations pending testing
#
# HISTORY
#
#   04-28-1998
#   o   After a week of development and debugging, version 0.1 (alpha) is ready
#
#   05-12-1998
#   o   Miscellaneous bug tracking
#
#   05-13-1998
#   o   Removed `offline' command for montly backups... it seems to be
#       problematic on alibaba - whether the drive is giving problems or
#       alibaba's kernel is finicky I don't know.
#       Anyway, no more offline commands after montly backup. At least
#       that way I can actually visually verify that a backup has been made.
#
#   06-24-1998
#   o   Examined ways of improving error catching around tape commands -
#       specifically if no tape is present.
#
#   06-25-1998
#   o   Used working directory of class definition to specify location
#       of working files in tape_admin_init.
#   o   Added error checking to tape_admin_close - largely redundant, but
#       at least it's a deeper level of error checking.
#   o   Basic backup behaviour redefined -
#
#       Each backup operation is preceded by a `rewind' command. This
#       allows error checking routines to ascertain whether or not a tape
#       is actually present in the remote device.
#
#       Additionally, this implies that each backup - daily/weekly/monthly
#       is performed on its own tape. Of course, the first daily backup
#       after a weekly or monthly will by necessity have less incremental
#       data than the backup for several days later, implying an
#       inefficient use of tape space. However, this should be weighed
#       against the ease of program operation and is considered to be a
#       worthwhile trade-off (i.e. using many tapes for simplicity, and
#       having each incremental increase on an own tape).
#
#   o   Moved class definition from backup_mgr into this file
#   o   Wrapped class definition into relevant method
#
#   06-29-1998
#   o   Correct behaviour when target host is dead... non-fatal error
#       should terminate host-related backups, but not the entire process.
#
#   07-01-1998
#   o   Increment rollover fixed.
#   o   Fixed return values and end behaviour of tape_backup_manage
#
#   07-06-1998
#   o   Added tape_todayRule_get
#
#   07-13-1998
#   o   Began implementing code for cycling incremental records of
#       non-monthly archive sets.
#
#   07-21-1998
#   o   Added `archiveDate' to class structure. This records the date of
#       the last successful archive for current set, and is used primarily
#       to determine when a forced delete of an incremental record set is
#       required. For sets that have only a daily and/or weekly backup
#       defined, incremental backups are made relative to the first time
#       that the set is processed. The `archiveDate' is used to determine
#       when this `base' should be erased.
#
#   07-28-1998
#   o   Added verbose flag to client backup program
#
#   01-11-1999
#   o   Resurrected code.
#   o   Beautify
#
#   01-13-1999
#   o   Flags to backup.tcl now require two dashes ("--")
#
#   01-14-2000
#   o   Changed calling arguments to backup.tcl (GNU style)
#   o   Added -force to delete command in admin_init
#   o   Improved error checking around tape commands
#
#   01-17-2000
#   o   Added `fortune' (need full path for cron!)
#
#   01-26-2000
#   o   delete tape_global(file_results) and not file_results in
#       tape_admin_init!
#   o   Changed behaviour of tape_backup_do:
#       - Dumps object after each partition backup. Each object has the
#         current volume appended to the name
#
#   01-28-2000
#   o   Fixed up incorrect name forming for each volume backup
#
#   09-22-2004
#   o   Resurrected. Again.
#       This time, began design changes for backing up to hard drive
#       as opposed to using a tape device.
#
#   02-05-2005
#   o   Replaced 'buffer' with 'cat'. After upgrading kernel to 2.6.10
#       'buffer' reported write problems. Since it's a hold over from the
#       early 1990's, perhaps it's time to retire 'buffer' anyway.
#
#   09-16-2025
#   o   Refactored to use 'group' object model instead of legacy 'class_struct'
#   o   Hardcoded 'rsh' commands to use 'ssh' exclusively.
#   o   Added explicit RETURN docstrings and values to all procedures.
#

package provide tape_misc 0.1
package require group 1.0

set tape_global(file_results) ""
set tape_global(file_status) ""

###\\\
# Methods --->
###///

proc tape_shut_down {exitcode} {
    #
    # ARGS
    # exitcode        in        code returned to system
    #
    # DESC
    # process shut down and exit
    #
    # RETURN
    # Does not return; terminates the script.
    #
    global SELF

    puts "`$SELF' shutting down..."
    puts "Sending system exitcode of $exitcode\n"
    exit $exitcode
}

proc tape_error {group_name action errorCondition exitcode {type "fatal"}} {
    #
    # ARGS
    # group_name            in              group in which error occurred
    # action                in              action being performed when error
    #                                       occurred
    # errorCondition        in              error message caught
    # exitcode              in              internal error number (sent to system
    #                                       on shutdown)
    # type                  in (opt)        error type - if "fatal" shutdown,
    #                                       else continue
    #
    # DESC
    # process error handling procedure
    #
    # RETURN
    # Does not return if error type is "fatal". Otherwise, returns an empty string.
    #
    upvar #0 $group_name tape
    global ext

    catch "exec ssh -l $tape(manager,remoteUser) $tape(manager,managerHost) \
        $tape(notifications,notifyError)"
    puts "\n\n"
    if {$type == "fatal"} {puts "FATAL ERROR"} else {puts "WARNING"}
    puts "\tSorry, but there seems to be an error."
    puts "\tFor archive process `$tape(meta,name)',"
    puts "\twhile I was $action, I sent \n\t`$tape(command)'"
    puts "\tand received an error:-\n\t`$errorCondition'"
    puts "\tat current date, [exec date]"
    set tape(state,status) "failed"
    set dump_file [file join $tape(storage,logDir) "$tape(meta,name).error.${ext}"]
    group::toYaml $group_name %$dump_file
    if {$type == "fatal"} {
        puts "\nExiting with internal code $exitcode"
        tape_shut_down $exitcode
    } else {
        puts "\nInternal error code is $exitcode"
        puts "Non fatal... continuing.\n"
    }
}

proc tape_do_nothing {group_name} {
    #
    # ARGS
    # group_name                   in                group currently being processed
    #
    # DESC
    # Basic `nop' procedure
    #
    # RETURN
    # Returns 1 to indicate successful execution.
    #
    upvar #0 $group_name tape
    global today

    puts "No backup performed for $tape(meta,name) on $today"
    return 1
}

proc tape_canDoMonthly {{when ""}} {
    #
    # ARGS
    # when                        in (opt)        targetDate
    #
    # DESC
    # Simply checks whether or not today's date falls within the first
    # week (7 days) of the month. Monthly backups, per design, occur during
    # the first week
    #
    # RETURN
    # Returns 1 if the date is within the first 7 days of the month, 0 otherwise.
    #
    global todayDate

    set targetDate $todayDate
    if {[set when] != ""} {set targetDate $when}
    if {$targetDate <= 7} {
        return 1
    } else {return 0}
}

proc tape_ruleDays_find {group_name rule} {
    #
    # ARGS
    # group_name            in              target group
    # rule                  in              target rule
    #
    # DESC
    # Scans a group for rules of type `rule'
    #
    # RETURN
    # On success, returns a list where the first element is the count of matching
    # days and the second element is a list of those day names. Returns 0 if no
    # match is found.
    #
    upvar #0 $group_name tape

    set count 0
    set ruleDays {}
    foreach day [weekdays_list] {
        if {$tape(schedule,$day) == $rule} {
            lappend ruleDays $day
            incr count
        }
    }
    if {$count} {
        return [list $count $ruleDays]
    } else {return 0}
}

proc tape_todayRule_get {group_name {forceDay "void"}} {
    #
    # ARGS
    # group_name            in              target group
    # forceDay              in (opt)        today=forceDay
    #
    # DESC
    # Given an input group, determine "today's" rule
    #
    # RETURN
    # Returns the backup rule string (e.g., "daily", "weekly") for the specified day.
    #
    upvar #0 $group_name tape
    global today

    if {$forceDay != "void"} {
        set day $forceDay
    } else {
        set day $today
    }
    set rule [string trimleft $tape(schedule,$day)]
    return $rule
}

proc tape_tomorrowRule_get {group_name} {
    #
    # ARGS
    # group_name            in              target group
    #
    # DESC
    # Given an input group, determine "tomorrow's" rule
    #
    # RETURN
    # Returns the backup rule string for the following day.
    #
    upvar #0 $group_name tape
    global today lst_weekdays

    set dayOrd [expr {[lsearch -exact $lst_weekdays $today] + 1}]
    if {$dayOrd >= [llength $lst_weekdays]} {set dayOrd 0}
    set tomorrow [lindex $lst_weekdays $dayOrd]
    set tomorrowRule $tape(schedule,$tomorrow)
    set tomorrowRule [string trimleft $tomorrowRule]
    return $tomorrowRule
}

proc tape_notice_sendMail {group_name subject {bodyFile "void"} {bodyContents "void"}} {
    #
    # ARGS
    # group_name            in              group being processed
    # subject               in              subject of mail message
    # bodyFile              in (opt)        filename containing body of message
    # bodyContents          in (opt)        body string
    #
    # DESC
    # Sends a mail message to a group's adminUser
    #
    # RETURN
    # Returns 1 on success, 0 on failure.
    #
    set str_pid [pid]
    set tmpfile "/tmp/msg-$str_pid"
    set status 1

    upvar #0 $group_name tape

    if {$bodyFile == "void" && $bodyContents == "void"} {
        if {[catch {exec mail -s "$subject" $tape(notifications,adminUser) < /dev/null}]} {
            set status 0
        }
    } elseif {$bodyFile != "void" && $bodyContents == "void"} {
        if {[catch {exec mail -s "$subject" $tape(notifications,adminUser) < $bodyFile}]} {
            set status 0
        }
    } elseif {$bodyContents != "void"} {
        if {![catch {exec echo $bodyContents >$tmpfile} commline]} {
            if {[catch {exec mail -s "$subject" $tape(notifications,adminUser) < $tmpfile}]} {
                set status 0
            }
            file delete -force $tmpfile
        } else {
            set status 0
        }
    }
    return $status
}

proc tape_admin_init {group_name} {
    #
    # ARGS
    # group_name    in              group archive about to be processed
    #
    # DESC
    # Perform initial admin operations for a backup set.
    #
    # RETURN
    # Returns 1 to indicate successful execution.
    #
    upvar #0 $group_name tape
    global tape_global

    set rule $tape(state,currentRule)
    set current_set $tape(state,currentSet,$rule)
    set file_results "$tape(meta,name).${rule}.${current_set}.results.log"
    set tape_global(file_results) [file join $tape(storage,logDir) $file_results]
    file delete -force $tape_global(file_results)
    set file_status "$tape(meta,name).${rule}.${current_set}.status.log"
    set tape_global(file_status) [file join $tape(storage,logDir) $file_status]
    file delete -force $tape_global(file_status)
    return 1
}

proc tape_admin_close {group_name volume label results} {
    #
    # ARGS
    # group_name    in              group being processed
    # volume        in              current partition that has been backed up
    # label         in              name of current archive
    # results       in              the path/filenames that have been backed up
    #
    # DESC
    # Perform closing admin for each successfully backed up set.
    #
    # The results of an archive process (the path/files that are returned
    # from the remote backup.tcl process) are written to a results file.
    # Additionally, these results are parsed and some status information
    # is also extracted and written to a status file.
    #
    # The error checking on the $results string is somewhat redundant... if
    # validResults != -1 then validStatus is per definition == -1 as well.
    #
    # RETURN
    # Returns 1 on success. Does not return on fatal error.
    #
    upvar #0 $group_name tape
    global tape_global
    global AM_parseResults AM_parseStatus
    global EC_parseResults EC_parseStatus

    set tape(state,status) "ok"
    puts "ok.\n"
    puts "Backup of $volume complete."
    puts "End date: [exec date]\n"
    set fileResults [open $tape_global(file_results) a]
    # Check for valid results
    set validResults [lsearch $results "killed:"]
    if {$validResults != -1} {
        set tape(state,status) "failed"
        tape_error $group_name $AM_parseResults \
            "Remote backup process was killed!" $EC_parseResults fatal
    }
    puts $fileResults "$results"
    set fileStatus [open $tape_global(file_status) a]
    # Check for valid status
    set validStatus [lsearch $results bytes]
    if {$validStatus == -1} {
        set tape(state,status) "failed"
        tape_error $group_name $AM_parseStatus \
            "No `bytes' string found" $EC_parseStatus fatal
    }
    set bytesWritten [lindex $results [expr {[lsearch $results bytes] + 2}]]
    puts $fileStatus "Archive status for backup `$label':"
    puts $fileStatus "\tResults parsed at [exec date]"
    puts $fileStatus "\tTotal bytes written: $bytesWritten\n"
    close $fileResults
    close $fileStatus
    return 1
}

proc tape_currentSet_inc {group_name} {
    #
    # ARGS
    # group_name    in                target group
    #
    # DESC
    # Increment the current rule's set number for group with implied rollover.
    #
    # RETURN
    # Returns the new, incremented value of the current set for the active rule.
    #
    upvar #0 $group_name tape

    set rule $tape(state,currentRule)
    set total_sets_key [switch -- $rule {
        daily {storage,dailySets}
        weekly {storage,weeklySets}
        monthly {storage,monthlySets}
        default {storage,noneSets}
    }]

    if {![info exists tape(state,currentSet,$rule)]} {
        set tape(state,currentSet,$rule) 0
    } else {
        incr tape(state,currentSet,$rule)
    }

    if {$tape(state,currentSet,$rule) > [expr {$tape($total_sets_key) - 1}]} {
        set tape(state,currentSet,$rule) 0
    }
    return $tape(state,currentSet,$rule)
}

proc tape_control {group_name command} {
    #
    # ARGS
    # group_name    in              current group being processed
    # command       in              command sent to tape control program `mt'
    #
    # DESC
    # Wrapper built around the tape controller.
    #
    # RETURN
    # Returns the string "ok" on success or "failed" on error.
    #
    upvar #0 $group_name tape
    global AM_remoteDevice EC_remoteDevice

    set tape(command) $command
    set MT "mt"
    puts -nonewline "\nTape: $tape(command)... "
    flush stdout

    catch "exec ssh -l $tape(manager,remoteUser) $tape(manager,managerHost) \
        $tape(notifications,notifyTape)" notifyResult

    # Check on the remoteDevice. If this is /dev/something we can assume that
    # it is a tape device. If not, then assume we are backing up to hard
    # drive. Replace the MT with "echo"
    set path [split $tape(storage,remoteDevice) "/"]
    set dev [lindex $path 1]
    if {$dev != "dev"} {
        set MT "echo"
    }

    set err [catch {
        exec ssh -l $tape(manager,remoteUser) $tape(manager,managerHost) $MT -f $tape(storage,remoteDevice) \
            $tape(command)
    } result]

    if {$err} {
        set status "failed"
        puts "$err ${status}. :-("
        tape_error $group_name $AM_remoteDevice $result $EC_remoteDevice
    } else {
        set status "ok"
        puts "${status}."
    }

    return $status
}

proc tape_incReset {group_name date {silent "void"}} {
    #
    # ARGS
    # group_name    in              current group being processed
    # date          in              target date
    # silent        in (opt)        optional verbose flag. If set, don't
    #                               echo output
    #
    # DESC
    # Determines whether or not an incremental is required for tape
    # on date `date' - only relevant to sets that have no monthly backup defined.
    #
    # RETURN
    # Returns the string "yes" if an incremental reset is required, otherwise "no".
    #
    upvar #0 $group_name tape

    set monthlyDays [tape_ruleDays_find $group_name monthly]
    set incReset "no"
    if {![lindex $monthlyDays 0]} {
        if {$silent == "void"} {
            puts "\nNo monthly backup rule found in set `$tape(meta,name)'"
        }
        if {![info exists tape(state,archiveDate)]} {
            puts "Forcing incremental reset (no archive date found)"
            return "yes"
        }
        set lastArchive $tape(state,archiveDate)
        set lastMonth [lindex $lastArchive 1]
        set thisMonth [lindex $date 1]
        if {$lastMonth != $thisMonth} {
            if {$silent == "void"} {
                puts "Forcing incremental reset"
            }
            set incReset "yes"
        } else {
            if {$silent == "void"} {
                puts "No incremental reset required"
            }
            set incReset "no"
        }
        puts ""
    }
    return $incReset
}

proc tape_label_create {group_name volumeName {maxLength 80}} {
    #
    # ARGS
    # group_name    in              current group being processed
    # volumeName    in              label pathname
    #
    # DESC
    # Constructs the label name for a volume archive. Note that there is
    # length limit for the tar command. This proc creates a tar-friendly label.
    #
    # RETURN
    # Returns the generated tape label as a string.
    #
    upvar #0 $group_name tape
    global date

    set month [lindex $date 1]
    set day [lindex $date 2]
    set year [lindex $date 5]
    set host [lindex [split $volumeName ":"] 0]
    set filesys [lindex [split $volumeName ":"] 1]

    set label "$tape(meta,name)::${host}:${filesys}-$tape(state,currentRule)"

    # If label is too long, hack a shorter one...
    if {[string length $label] > $maxLength} {
        puts "Volume label name is too long! Creating a shorter name."
        set ldir [split $filesys "/"]
        set basename [lindex $ldir [expr {[llength $ldir] - 1}]]
        set label "$tape(meta,name)::${host}:${basename}-$tape(state,currentRule)"
    }
    append label "-${month}.${day}.${year}"
    return $label
}

proc _tape_get_worker_paths {group_name host} {
    #
    # ARGS
    #   group_name      in      The name of the main backup group object.
    #   host            in      The hostname of the client to check.
    #
    # DESC
    #   Determines the correct worker script and library paths for a given host,
    #   implementing the "override-then-fallback" logic. It checks for a
    #   host-specific configuration first before using the global default.
    #
    # RETURN
    #   A Tcl dictionary with 'scriptDir' and 'tclLibPath' keys.
    #
    upvar #0 $group_name tape

    # Check for a host-specific config block first
    if {[info exists tape(worker,$host,scriptDir)]} {
        set scriptDir $tape(worker,$host,scriptDir)
        set tclLibPath $tape(worker,$host,tclLibPath)
    } else {
        # Otherwise, fall back to the default config block
        set scriptDir $tape(worker,default,scriptDir)
        set tclLibPath $tape(worker,default,tclLibPath)
    }
    return [dict create scriptDir $scriptDir tclLibPath $tclLibPath]
}

proc _tape_check_host_liveness {host} {
    #
    # ARGS
    #   host            in      The hostname or IP address to ping.
    #
    # DESC
    #   Checks if a remote host is reachable via a simple ping command.
    #
    # RETURN
    #   Returns 1 if the host is alive, 0 otherwise.
    #
    puts -nonewline "\nChecking if $host is alive... "
    flush stdout

    if {[catch {exec ping -c 3 $host} result]} {
        puts "failed."
        return 0
    }

    puts "ok."
    return 1
}

proc _tape_build_worker_command {group_name host filesys label worker_paths incReset} {
    #
    # ARGS
    #   group_name      in      The name of the main backup group object.
    #   host            in      The target hostname for this command.
    #   filesys         in      The filesystem path to be backed up.
    #   label           in      The tar archive label.
    #   worker_paths    in      A dict containing the scriptDir and tclLibPath.
    #   incReset        in      The 'yes'/'no' flag for resetting incrementals.
    #
    # DESC
    #   Builds the full, explicit command list for executing the remote
    #   backup.tcl worker script. It assembles all necessary CLI arguments
    #   and wraps them in a self-contained command string for SSH.
    #
    # RETURN
    #   A Tcl list suitable for execution with 'exec {*}'.
    #
    upvar #0 $group_name tape

    set scriptDir [dict get $worker_paths scriptDir]
    set tclLibPath [dict get $worker_paths tclLibPath]

    set remote_script [file join $scriptDir "backup.tcl"]

    set worker_args [list]
    lappend worker_args --user $tape(manager,remoteUser)
    lappend worker_args --host $tape(manager,managerHost)
    lappend worker_args --device $tape(storage,remoteDevice)
    lappend worker_args --label "\"$label\""
    lappend worker_args --listFileDir $tape(storage,listFileDir)
    lappend worker_args --filesys "\"$filesys\""
    lappend worker_args --currentRule $tape(state,currentRule)
    lappend worker_args --buffer cat
    lappend worker_args --incReset $incReset
    if {$tape(state,currentRule) != "monthly"} {
        lappend worker_args --verbose on
    } else {
        lappend worker_args --verbose off
    }

    set remote_command_string "TCLLIBPATH='${tclLibPath}' '${remote_script}' [join $worker_args]"

    return [list ssh $host $remote_command_string]
}

proc tape_backup_do {group_name} {
    #
    # ARGS
    #   group_name      in      The name of the group object to be processed.
    #
    # DESC
    #   Orchestrates the backup process for all partitions defined in a group.
    #   It iterates through each target, checks host liveness, builds the
    #   remote command, executes the backup, and handles the results.
    #
    # RETURN
    #   Returns 1 if all backups in the set completed successfully, 0 otherwise.
    #
    upvar #0 $group_name tape
    global AM_pingHost AM_rsh EC_pingHost EC_rsh date tape_global

    set backup_done 1
    set partitions [split $tape(targets,partitions) ","]
    set incReset [tape_incReset $group_name $date]
    tape_admin_init $group_name

    foreach volume $partitions {
        set host [lindex [split $volume ":"] 0]
        set filesys [lindex [split $volume ":"] 1]

        set worker_paths [_tape_get_worker_paths $group_name $host]

        if {![_tape_check_host_liveness $host]} {
            tape_error $group_name $AM_pingHost "Host unreachable" $EC_pingHost warn
            set backup_done 0
            continue ;# Skip to the next host in the list
        }

        set label [tape_label_create $group_name $volume]
        puts "Starting $tape(state,currentRule) backup of $volume..."
        puts "Start date: [exec date]"
        puts -nonewline "\n\t$label - "

        set exec_list \
            [_tape_build_worker_command $group_name $host $filesys $label $worker_paths $incReset]
        set tape(command) [join $exec_list " "]

        # Audio notification of backup start
        catch {
            exec ssh -l $tape(manager,remoteUser) $tape(manager,managerHost) \
                eval $tape(notifications,notifyTar)
        } notifyResult

        # Start the backup using the list expansion operator {*} to avoid eval
        set someError [catch {exec {*}$exec_list} results]
        if {$someError} {
            tape_error $group_name $AM_rsh $results $EC_rsh
            set backup_done 0
        } else {
            tape_admin_close $group_name $volume $label $results
            set tape(state,archiveDate) [exec date]
        }
    }

    if {$backup_done} {
        tape_currentSet_inc $group_name
        set mail_body $tape_global(file_status)
        set mail_subject "Backup status for tape -$tape(meta,name)-"
        tape_notice_sendMail $group_name $mail_subject $mail_body
    }

    return $backup_done
}

proc _tape_execute_backup_for_rule {group_name forceRule tapeInit} {
    #
    # ARGS
    #   group_name      in      The name of the group object to be processed.
    #   forceRule       in      The value of the forceRule flag, if any.
    #   tapeInit        in      A list of pre-backup commands, if any.
    #
    # DESC
    #   Executes the appropriate backup type based on the 'state,currentRule'
    #   value, incorporating logic for forced runs and tape initialization.
    #
    # RETURN
    #   Returns 1 if the backup was successful, 0 otherwise.
    #
    upvar #0 $group_name tape
    global today

    set backup_status 1
    if {$tape(state,currentRule) != "none"} {
        switch -- $tape(state,currentRule) {
            monthly {
                if {[tape_canDoMonthly] || $forceRule == "monthly"} {
                    puts "Performing monthly backup for `$tape(meta,name)` on $today"
                    tape_control $group_name rewind
                    set backup_status [tape_backup_do $group_name]
                    if {$backup_status} {tape_control $group_name offline}
                } else {
                    tape_do_nothing $group_name
                }
            }
            weekly {
                puts "Performing weekly backup for `$tape(meta,name)` on $today"
                if {$tapeInit != "void"} {
                    puts "Performing tape initialisation."
                    foreach command $tapeInit {
                        tape_control $group_name $command
                    }
                }
                tape_control $group_name rewind
                set backup_status [tape_backup_do $group_name]
                if {$backup_status} {tape_control $group_name offline}
            }
            daily {
                puts "Performing daily backup for `$tape(meta,name)` on $today"
                if {$tapeInit != "void"} {
                    puts "Performing tape initialisation."
                    foreach command $tapeInit {
                        tape_control $group_name $command
                    }
                }
                tape_control $group_name rewind
                set backup_status [tape_backup_do $group_name]
                if {$backup_status} {tape_control $group_name offline}
            }
            default {
                tape_do_nothing $group_name
            }
        }
        if {$backup_status == 1} {
            puts "Archive of set `$tape(meta,name)` completed successfully."
        } else {
            puts "Archive of set `$tape(meta,name)` encountered an error."
            puts "Some hosts may not have been backed up! Check log files."
        }
    } else {
        tape_do_nothing $group_name
    }

    return $backup_status
}

proc _tape_send_tomorrow_notification {group_name} {
    #
    # ARGS
    #   group_name      in      The name of the group object to be processed.
    #
    # DESC
    #   Determines the backup rule for the following day and, if a backup is
    #   scheduled, sends a notification email to the administrator.
    #
    # RETURN
    #   Returns 1 if a notification was sent, 0 otherwise.
    #
    upvar #0 $group_name tape
    global todayDate

    set tomorrowRule [tape_tomorrowRule_get $group_name]
    if {($tomorrowRule == "monthly") && !([tape_canDoMonthly [expr {$todayDate + 1}]])} {
        return 0
    }

    if {$tomorrowRule != "none"} {
        set message "Insert -$tape(meta,name)- $tomorrowRule tape no. "
        switch -- [exec uname] {
            Linux {set tomorrowDate [exec date --date "1 day"]}
            FreeBSD {set tomorrowDate [exec date -v+1d]}
            Darwin {set tomorrowDate [exec date -v+1d]}
            default {set tomorrowDate [exec date --date "1 day"]}
        }
        if {[tape_incReset $group_name $tomorrowDate silent] == "yes"} {
            set total_sets_key [switch -- $tomorrowRule {
                daily {storage,dailySets}
                weekly {storage,weeklySets}
                monthly {storage,monthlySets}
                default {storage,noneSets}
            }]
            append message "$tape($total_sets_key) (inc reset tape)"
        } else {
            # Simulate the increment to show the correct *next* tape number.
            set tomorrow_set_val $tape(state,currentSet,$tomorrowRule)
            set total_sets_key [switch -- $tomorrowRule {
                daily {storage,dailySets}
                weekly {storage,weeklySets}
                monthly {storage,monthlySets}
                default {storage,noneSets}
            }]
            incr tomorrow_set_val
            if {$tomorrow_set_val > $tape($total_sets_key) - 1} {
                set tomorrow_set_val 0
            }
            append message "$tomorrow_set_val"
        }
        puts "\nSending notification to $tape(notifications,adminUser)..."
        puts "********************\n"
        tape_notice_sendMail $group_name "$message" "void" [exec /opt/local/bin/fortune]
        return 1
    }

    return 0
}

proc tape_backup_manage {group_name {forceRule "void"} {forceDay "void"} {tapeInit "void"}} {
    #
    # ARGS
    #   group_name      in      The name of the group object being processed.
    #   forceRule       in (opt)  A rule type to force, overriding the schedule.
    #   forceDay        in (opt)  A day name to simulate, using that day's rule.
    #   tapeInit        in (opt)  A list of pre-backup tape commands (e.g., rewind).
    #
    # DESC
    #   The main entry point to manage a backup. It determines the correct rule,
    #   orchestrates the execution, and handles post-backup notifications.
    #
    # RETURN
    #   Returns 1 if the backup process was successful, 0 if it failed.
    #
    upvar #0 $group_name tape
    global today

    # --- Step 1: Determine the correct rule for today ---
    if {$forceDay != "void"} {set today $forceDay}
    set tape(state,currentRule) [tape_todayRule_get $group_name $today]
    if {$forceRule != "void"} {set tape(state,currentRule) $forceRule}

    # --- Step 2: Execute today's backup ---
    set backup_status [_tape_execute_backup_for_rule $group_name $forceRule $tapeInit]

    # --- Step 3: Send notification for tomorrow's backup ---
    _tape_send_tomorrow_notification $group_name

    # --- Step 4: Return the status of today's backup ---
    return $backup_status
}
