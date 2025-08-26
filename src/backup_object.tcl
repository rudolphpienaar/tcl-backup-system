#!/usr/bin/env tclsh
#
# NAME
#
#       backup_object.tcl
#
# DESCRIPTION
#
#       Backup object specification and handler. Provides pseudo-class
#       implementation for backup configuration objects with YAML-based
#       schema definition and field mapping capabilities.
#

lappend auto_path [file join [file dirname [info script]] tcl_packages]
package require yaml
package require parval

set ::SELF [file tail [info script]]
set G_SYNOPSIS "

NAME

      backup_object.tcl

SYNOPSIS

      backup_object.tcl       \[--schema <schema_file>\]              \\
                              \[--help\]

DESCRIPTION

      'backup_object.tcl' provides the backup object specification and
      handler system. It reads YAML-based schema definitions and creates
      pseudo-class field mappings for backup configuration objects.

      The schema file defines the mapping between internal field names
      (used within the application) and external .object file keys
      (used for persistent storage). This allows clean separation of
      internal semantics from legacy file format compatibility.

ARGS

    o --schema <schema_file>
            Specify the YAML schema file to load. If not provided,
            defaults to 'backup_schema.yaml' in the current directory.

    o --help
            Display this synopsis and exit.

"

###\\\
# Schema loading
###///

proc backupObject_fieldMap {{schemaFile "backup_schema.yaml"}} {
    #
    # ARGS
    # schemaFile    in (opt)  YAML schema file path (default: backup_schema.yaml)
    # fieldMap      return    flattened dict mapping internal->external keys
    #
    # DESC
    # Loads YAML schema and flattens nested structure into field mappings
    # Converts nested keys like manager.hostIP -> managerHostIP internally
    #
    if {![file exists $schemaFile]} {
        error "Schema file not found: $schemaFile"
    }

    set fd [open $schemaFile r]
    set yamlContent [read $fd]
    close $fd

    set schema [::yaml::yaml2dict $yamlContent]

    if {![dict exists $schema field_mappings]} {
        error "Schema missing field_mappings section"
    }

    set mappings [dict get $schema field_mappings]
    set flatMap {}

    # Flatten nested structure recursively
    backupObject_flattenMappings $mappings "" flatMap

    return $flatMap
}

proc backupObject_flattenMappings {mappings prefix flatMapVar} {
    #
    # ARGS
    # mappings      in      nested dict structure from YAML
    # prefix        in      current nesting prefix for internal names
    # flatMapVar    in/out  variable name for result dict
    #
    # DESC
    # Recursively flattens nested YAML structure into flat key mappings
    # Rule: non-nested unchanged, nested = first_level + FirstCharCapitalizedLevels
    #
    upvar $flatMapVar flatMap

    dict for {key value} $mappings {
        if {[string is list $value] && [llength $value] % 2 == 0} {
            # This is a dict - check if it's a leaf or branch
            set hasStringValues 0
            dict for {subKey subValue} $value {
                if {[string is list $subValue] && [llength $subValue] % 2 == 0} {
                    # Nested dict - continue recursion
                } else {
                    # String value - this is a leaf
                    set hasStringValues 1
                    break
                }
            }

            if {$hasStringValues} {
                # This level has string values - recurse
                if {$prefix eq ""} {
                    # First level - use key unchanged
                    set newPrefix $key
                } else {
                    # Subsequent levels - capitalize first character only
                    set firstChar [string toupper [string index $key 0]]
                    set restChars [string range $key 1 end]
                    set newPrefix "${prefix}${firstChar}${restChars}"
                }
                backupObject_flattenMappings $value $newPrefix flatMap
            } else {
                # All values are dicts - recurse
                if {$prefix eq ""} {
                    # First level - use key unchanged
                    set newPrefix $key
                } else {
                    # Subsequent levels - capitalize first character only
                    set firstChar [string toupper [string index $key 0]]
                    set restChars [string range $key 1 end]
                    set newPrefix "${prefix}${firstChar}${restChars}"
                }
                backupObject_flattenMappings $value $newPrefix flatMap
            }
        } else {
            # This is a leaf node with string value
            if {$prefix eq ""} {
                # Non-nested - use key unchanged
                set internalKey $key
            } else {
                # Nested - capitalize first character only
                set firstChar [string toupper [string index $key 0]]
                set restChars [string range $key 1 end]
                set internalKey "${prefix}${firstChar}${restChars}"
            }
            dict set flatMap $internalKey $value
        }
    }
}

proc schema_load {schema_file classStruct} {
    global SELF
    upvar 1 $classStruct class

    # Load and display field mappings
    if {
        [catch {
            puts "Loading schema: $schema_file"
            set fieldMap [backupObject_fieldMap $schema_file]

            puts "\nField Mappings (Internal -> External):"
            puts "======================================"

            dict for {internal external} $fieldMap {
                puts [format "%-25s -> %s" $internal $external]
                set class($external) ""
            }

            puts "\nTotal fields: [dict size $fieldMap]"
        } error]
    } {
        puts stderr "$SELF: Error: $error"
        return 0
    }
    return 1
}

###\\\
# Main execution and CLI handling
###///

proc main {} {
    #
    # DESC
    # Main entry point with CLI argument processing
    #
    global argv G_SYNOPSIS

    if {![CLI_parse "clargs" $argv]} {
        puts $G_SYNOPSIS
        exit 1
    }

    array set classStruct {}
    if {![schema_load [PARVAL_return "clargs" schema "backup_schema.yaml"] classStruct]} {
        exit 2
    }
    parray classStruct

    exit 0
}

# Run main if called directly
if {[info script] eq $::argv0} {
    main
}
