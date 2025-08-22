# Tcl Backup System

A sophisticated distributed backup system written in Tcl, featuring:

- Multi-tier incremental backups (daily → weekly → monthly)
- Distributed manager/agent architecture  
- Enterprise scheduling and rotation
- Graceful error handling and notifications
- Flexible storage backends (tape/disk)

## Quick Start

1. Run the configuration wizard: `./tools/backup_config.tcl --create mybackup`
2. Test the setup: `./src/backup_mgr.tcl --archive mybackup --test`
3. Schedule with cron: `crontab -e`

## Documentation

See the `docs/` directory for detailed setup and configuration guides.

