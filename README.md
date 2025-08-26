# TCL Backup Management System

A distributed, incremental backup system originally developed in the late 1990s for enterprise Unix/Linux environments. Features a sophisticated 3-tier backup strategy with intelligent tape rotation and network-based remote execution.

## Quick Start

### 1. Setup
```bash
# Install TCL
sudo apt-get install tcl tk  # Debian/Ubuntu

# Setup SSH keys for passwordless access
ssh-keygen -t rsa -b 2048
ssh-copy-id root@target-host
```

### 2. Create Configuration
```bash
# Interactive wizard
./backup_config.tcl --create my-backup

# Non-interactive with template
./backup_config.tcl --create server-backup --template server --non-interactive
```

### 3. Run Backup
```bash
# Run scheduled backup
./backup_mgr.tcl --archive my-backup

# Force specific backup type
./backup_mgr.tcl --archive my-backup --rule daily
```

## Key Features

- **3-Tier Incremental Strategy**: Monthly (full) → Weekly → Daily backups
- **Distributed Execution**: SSH-based remote backup operations
- **Cross-Platform**: Linux, FreeBSD, Darwin, and other Unix variants
- **Intelligent Scheduling**: Day-of-week rules with conflict resolution
- **Tape Management**: Automatic rotation with cycle tracking
- **Configuration Management**: Persistent state in .object files

## System Components

| Component | Purpose |
|-----------|---------|
| `backup_mgr.tcl` | Main orchestrator and scheduler |
| `backup.tcl` | Remote backup execution engine |
| `backup_config.tcl` | Interactive configuration wizard |
| `*.object` | Backup configuration files |

## Architecture

```
┌─────────────────┐    SSH    ┌─────────────────┐
│  backup_mgr.tcl │──────────►│   backup.tcl    │
│   (Manager)     │           │ (Remote Agent)  │
└─────────────────┘           └─────────────────┘
         │                             │
         ▼                             ▼
  ┌─────────────┐              ┌─────────────┐
  │.object files│              │tar archives │
  └─────────────┘              └─────────────┘
```

## Example Usage

```bash
# Create server backup configuration
./backup_config.tcl --create prod-servers \
  --template server \
  --daily-sets 7 \
  --weekly-sets 4 \
  --output-dir /etc/backup

# Schedule with cron (2 AM daily)
echo "0 2 * * * /root/backup/backup_mgr.tcl --archive prod-servers" | crontab -

# Manual backup with specific rule
./backup_mgr.tcl --archive prod-servers --day Mon --rule daily

# Test configuration without backup
./backup_config.tcl --create test-config --validate-only
```

## Documentation

- **[Architecture](docs/architecture.md)** - System design and components
- **[Backup Strategy](docs/backup-strategy.md)** - 3-tier incremental model with visual matrix
- **[Installation](docs/installation.md)** - Detailed setup and configuration
- **[Configuration](docs/configuration.md)** - .object file format and options
- **[Operations](docs/operations.md)** - Daily operations and troubleshooting
- **[API Reference](docs/api-reference.md)** - Command-line options and parameters
- **[Examples](docs/examples.md)** - Configuration templates and use cases

## Requirements

- **TCL**: Version 8.4 or higher
- **SSH**: Key-based authentication to target hosts
- **Tar**: GNU tar with incremental backup support
- **Storage**: Local disk, NFS, or tape device access

## Support

This backup system represents decades of proven reliability in enterprise environments. The core incremental backup logic and distributed architecture remain sound and effective for modern deployments.

For configuration questions, see the [documentation](docs/) or examine the example .object files.
