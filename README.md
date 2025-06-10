# Marathon - Parallel Computation Framework

Marathon is a robust bash-based framework for running embarrassingly parallel computational jobs on local machines or AWS EC2 Spot instances. It leverages GNU Parallel for efficient job distribution and rclone for seamless data management with cloud storage.

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [AWS Deployment](#aws-deployment)
- [Data Flow](#data-flow)
- [Monitoring](#monitoring)
- [Cleanup Options](#cleanup-options)
- [Troubleshooting](#troubleshooting)
- [Development](#development)
- [Projects Using Marathon](#projects-using-marathon)

## Features

- **Parallel Processing**: Utilizes GNU Parallel for efficient distribution of work across CPU cores
- **Cloud Storage Integration**: Seamless data transfer with any rclone-supported storage backend
- **AWS Spot Instance Support**: Automatic handling of spot interruptions with graceful shutdown
- **Encryption Support**: Optional GPG encryption/decryption of inputs and outputs
- **Resource Monitoring**: Continuous tracking of system load, memory usage, and job progress
- **Graceful Shutdown**: Comprehensive cleanup with signal handling and data preservation
- **Load Management**: Automatic system load limiting to prevent resource exhaustion
- **Flexible Configuration**: Easily customizable for different workloads and environments
- **Enhanced Logging**: Date-organized log structure with separate directories for jobs, system metrics, and transfers
- **Job Metadata**: Automatic generation of job manifests with checksums and resource usage
- **Performance Tracking**: CSV-based metrics collection for trend analysis
- **Log Archival**: Automatic rotation and compression of old logs with configurable retention
- **Health Monitoring**: Built-in health check endpoint for worker status verification
- **Retry Mechanism**: Exponential backoff retry for transient failures in network operations
- **Error Tracking**: Dedicated error index and failure logs for troubleshooting

## Architecture

### Core Components

```
marathon/
├── run.sh              # Main orchestrator script
├── settings.sh         # Configuration and environment setup
├── io.sh              # Data transfer operations (rclone)
├── aws.sh             # AWS-specific functionality
├── cleanup.sh         # Cleanup and signal handlers
├── metadata.sh        # Job metadata and reporting functions
├── archive.sh         # Log rotation and archival utilities
├── retry.sh           # Retry mechanism with exponential backoff
├── health.sh          # Health check endpoint for monitoring
├── bump/              # Utility function library
│   ├── bump.sh        # Core utility functions
│   ├── parallel.sh    # GNU Parallel-safe functions
│   └── return_codes.sh # Standardized exit codes
├── worker/            # AWS deployment scripts
│   └── user-data.sh   # EC2 instance initialization
├── test/              # Basic test scripts
│   ├── test.sh        # Process hierarchy tests
│   ├── one.sh         # Single process test
│   ├── two.sh         # Dual process test
│   └── three.sh       # Triple process test
├── test_marathon.sh   # Comprehensive test suite
├── test_cleanup_modes.sh # Cleanup mode verification
├── test_performance.sh # Performance and stress tests
└── test_retry.sh      # Retry mechanism tests
```

### Execution Flow

![Execution Flow](run.png)

1. **Initialization**: Load configuration, validate dependencies, setup directories
2. **Data Fetch**: Download input files from cloud storage using rclone
3. **Decryption** (optional): Decrypt GPG-encrypted inputs
4. **Parallel Processing**: Launch GNU Parallel to process files concurrently
5. **Resource Monitoring**: Continuously monitor system resources and sync outputs
6. **Spot Handling** (AWS only): Check for interruption notices
7. **Encryption** (optional): Encrypt outputs with GPG signing
8. **Data Upload**: Transfer results back to cloud storage
9. **Cleanup**: Remove temporary files and optionally shut down instance

## Prerequisites

### Required Software

- **GNU Parallel** - For parallel job execution
- **rclone** - For cloud storage operations
- **GnuPG** (optional) - For encryption/decryption
- **GNU niceload** - For system load management
- **bc** - For arithmetic operations
- **gawk** - For text processing
- **Standard Unix utilities**: sed, grep, find, curl, etc.

### AWS-Specific (for cloud deployment)

- **AWS CLI** - For AWS operations
- **ec2-metadata** - For instance metadata queries
- **IAM Role** - With appropriate S3/storage permissions

## Installation

### Local Installation

1. Clone the repository:
```bash
git clone https://github.com/gusgw/marathon.git
cd marathon
```

2. Make scripts executable:
```bash
chmod +x *.sh
```

3. Configure rclone for your storage backend:
```bash
rclone config
```

4. Copy and modify the configuration:
```bash
cp rclone.conf.example rclone.conf
# Edit rclone.conf with your settings
```

### AWS Installation

Use the provided user-data script when launching EC2 instances. See [AWS Deployment](#aws-deployment) section.

## Configuration

### Environment Variables

Configure these in `run.sh` before the settings import:

```bash
# Job identification
export job="myjob"                    # Unique job name

# Parallelism settings
export MAX_SUBPROCESSES=4             # Number of parallel workers
export target_load=3.5                # System load limit

# Storage paths (rclone syntax)
export input="remote:bucket/input"    # Input data location
export output="remote:bucket/output"  # Output data location

# File patterns
export inglob="*.input"               # Input file pattern
export outglob="*.output"             # Output file pattern

# Workspace settings
export workspace="/mnt/workspace"     # Local working directory
export logspace="/mnt/logs"          # Log directory
export workfactor=2                  # Workspace size multiplier

# Encryption settings (optional)
export encrypt_flag="no"              # Set to "yes" to enable
export encrypt="recipient@email.com"  # GPG recipient
export sign="sender@email.com"       # GPG signing key

# Cleanup mode
export clean="all"                    # all|keep|output|gpg
```

### rclone Configuration

Create `rclone.conf` in the project directory:

```ini
[remote]
type = s3
provider = AWS
region = us-east-1
# Add authentication details or use IAM role
```

## Usage

### Basic Usage

```bash
# Run with default settings
./run.sh

# Run with specific cleanup option
./run.sh keep myjob     # Keep all files after completion
./run.sh output myjob   # Remove output files but keep workspace
./run.sh gpg myjob      # Remove GPG files
./run.sh all myjob      # Full cleanup (default)
```

### Step-by-Step Guide

1. **Prepare Input Data**
   ```bash
   # Upload input files to cloud storage
   rclone copy /local/input/path remote:bucket/input/
   ```

2. **Configure Job Settings**
   ```bash
   # Edit run.sh to set job parameters
   export job="analysis-2025-01"  # Unique job identifier
   export MAX_SUBPROCESSES=8       # Adjust for your CPU cores
   export input="remote:bucket/input"
   export output="remote:bucket/output"
   ```

3. **Run the Job**
   ```bash
   # Execute with desired cleanup mode
   ./run.sh keep analysis-2025-01
   ```

4. **Monitor Progress**
   ```bash
   # Watch real-time logs
   tail -f /mnt/logs/jobs/analysis-2025-01/*.log
   
   # Check system metrics
   tail -f /mnt/logs/system/$(date +%Y/%m/%d)/*.load
   ```

5. **Retrieve Results**
   ```bash
   # Download completed outputs
   rclone copy remote:bucket/output/ /local/output/path/
   
   # Check job manifest
   cat /mnt/logs/jobs/analysis-2025-01/manifest.json
   ```

### Test Mode

Run the test suite to verify process hierarchy and signal handling:

```bash
./test/test.sh
```

### Running All Tests

A comprehensive test script is available to run all tests:

```bash
# Run all tests with detailed output
./test_all.sh

# This executes:
# - Basic functionality tests (always pass)
# - Process hierarchy tests (always pass)
# - Integration tests (if Marathon has been initialized)
# - Retry mechanism tests (always pass)
# - Summary generation tests (always pass)
```

**Note**: Integration tests that require full Marathon job execution are gracefully skipped with informative messages if the environment isn't fully configured. All basic functionality tests pass without requiring Marathon initialization.

### Custom Job Function

Modify the `run()` function in `run.sh` to implement your computation:

```bash
function run {
    # ... initialization code ...
    
    # Replace this section with your actual work
    if [[ "$run_type" == "test" ]]; then
        # Test mode - uses stress for testing
        nice -n "$NICE" stress --verbose --cpu "${stress_cpus}" &
        mainid=$!
    else
        # Production mode - add your computation here
        # Example: process the input file
        your_processor "$input" > "$work/$outname" &
        mainid=$!
    fi
    
    # ... monitoring code ...
}
```

## AWS Deployment

### Launching Spot Instances

1. Prepare user-data script:
```bash
# Customize worker/user-data.sh with your settings
```

2. Launch instance with user-data:
```bash
aws ec2 run-instances \
    --image-id ami-xxxxxxxxx \
    --instance-type c5.xlarge \
    --spot-price "0.10" \
    --user-data file://worker/user-data.sh \
    --iam-instance-profile Name=marathon-role \
    --security-groups marathon-sg
```

### IAM Role Policy

Create an IAM role with necessary permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::your-bucket/*",
                "arn:aws:s3:::your-bucket"
            ]
        }
    ]
}
```

## Data Flow

### Input Processing

1. Files matching `${inglob}` pattern are downloaded from `${input}`
2. GPG-encrypted files (`*.gpg`) are automatically detected and decrypted
3. Each input file is processed by a parallel worker

### Output Generation

1. Workers generate output files matching `${outglob}` pattern
2. Outputs are optionally encrypted and signed with GPG
3. Results are continuously synced to `${output}` during execution
4. Final sync ensures all outputs are uploaded

### Logging

Marathon uses an organized, date-based logging structure:

#### Log Directory Structure

```
${logspace}/
├── jobs/                      # Job-specific logs
│   └── ${job}/
│       ├── manifest.json      # Job metadata with checksums
│       ├── *.log             # Execution logs
│       ├── gpg/              # GPG operation logs
│       ├── run/              # Parallel job logs
│       └── status/           # Process status snapshots
├── system/                    # System metrics organized by date
│   └── YYYY/MM/DD/
│       ├── *.load            # System load measurements
│       ├── *.memory          # Memory usage tracking
│       └── *.free            # Available memory logs
├── transfers/                 # Data transfer logs by date
│   └── YYYY/MM/DD/
│       ├── *.rclone.input.log  # Input transfer logs
│       └── *.rclone.output.log # Output transfer logs
└── reports/                   # Aggregated reports and indices
    ├── job_index.txt         # Central job registry
    ├── error_index.txt       # Failed job tracking
    ├── daily/YYYY/MM/DD/     # Daily summaries
    │   └── summary.txt
    ├── performance/          # Performance metrics
    │   └── metrics_YYYYMM.csv
    └── failures/             # Copies of failed job logs
```

#### Job Metadata

Each job generates a `manifest.json` containing:
- Job identification (ID, name, hostname, PID)
- Timestamps (start and end times)
- Input/output file listings with SHA256 checksums
- File sizes for all inputs and outputs
- Resource usage statistics
- Exit code and status

#### Performance Metrics

Performance data is collected in CSV format:
- Job duration and timestamps
- Maximum memory usage
- Average system load
- Input/output data sizes
- Suitable for trend analysis and optimization

#### Log Archival

Use the archive utility to manage log retention:

```bash
# Archive logs older than 7 days
./archive.sh rotate 7

# Remove archives older than 90 days
./archive.sh clean 90

# Archive completed work directories
./archive.sh work

# Generate archive summary report
./archive.sh report

# Run all maintenance tasks
./archive.sh all
```

## Monitoring

### Real-time Monitoring

Monitor job progress in real-time:

```bash
# Watch parallel job progress
tail -f ${logspace}/jobs/${job}/*.parallel.log

# Monitor system load
tail -f ${logspace}/system/$(date +%Y/%m/%d)/*.load

# Check worker status
cat /dev/shm/${job}-*/workers

# View recent transfer activity
tail -f ${logspace}/transfers/$(date +%Y/%m/%d)/*.log
```

### Health Checks

Marathon includes a built-in health check system:

```bash
# Run single health check
./health.sh check

# Get JSON health status
./health.sh json

# Start HTTP health endpoint (port 8080)
./health.sh serve

# Use custom port
./health.sh serve 8081
```

Health checks verify:
- Critical directories exist
- Sufficient disk space (>10% free)
- Required tools available (rclone, GNU Parallel)
- System load within limits
- Adequate memory available
- Recent error rates

### Resource Reports

The framework continuously logs:
- System load averages (1, 5, 15 minute)
- Per-process memory usage (VmHWM, VmRSS)
- Available system memory and swap
- Worker process status
- Transfer rates and progress
- Job completion statistics

## Cleanup Options

Control post-execution cleanup behavior with the first parameter to `run.sh`:

```bash
./run.sh [cleanup_mode] [job_name]
```

### Cleanup Modes

- **`keep`**: Preserve all files after job completion
  - Retains: Work directory, log directory, all input/output files
  - Use case: Development, debugging, or when you need to inspect intermediate files

- **`output`**: Clean work and logs, keep only output archive
  - Retains: Output archive in `${output}` directory
  - Removes: Work directory, job log directory
  - Use case: Production runs where only final results matter

- **`gpg`**: Keep only encrypted files, remove unencrypted data
  - Retains: Work directory with only `*.gpg` files, log directory
  - Removes: All unencrypted files from work directory
  - Use case: Security-sensitive environments requiring encrypted data only

- **`all`**: Complete cleanup (default for AWS)
  - Retains: Output archive only
  - Removes: Work directory, job log directory
  - Use case: Cloud deployments to minimize storage costs

### Important Notes

- System logs (`logs/system/`) and reports (`logs/reports/`) are **always retained** regardless of cleanup mode
- Transfer logs (`logs/transfers/`) are organized by date and retained for troubleshooting
- The output archive is always created and uploaded to the configured output location
- Job metadata and performance metrics are generated before cleanup occurs

## Troubleshooting

### Common Issues

1. **Missing Dependencies**
   ```bash
   # Check all dependencies
   for cmd in parallel rclone gpg niceload bc gawk; do
       command -v $cmd || echo "Missing: $cmd"
   done
   ```

2. **rclone Authentication**
   ```bash
   # Test rclone configuration
   rclone lsd remote:
   ```

3. **Insufficient Workspace**
   - Increase `workfactor` in configuration
   - Ensure adequate disk space in `workspace` path

4. **Signal Handling**
   - The framework traps SIGINT and SIGTERM for graceful shutdown
   - Use `kill -TERM` to trigger cleanup

### Debug Mode

Enable verbose logging:

```bash
# Add to run.sh
set -x  # Enable command tracing
export PARALLEL="--verbose"  # Verbose GNU Parallel
```

## Development

### Adding New Features

1. **New Job Types**: Modify the `run()` function in `run.sh`
2. **Storage Backends**: Update `rclone.conf` for new backends
3. **Monitoring Metrics**: Extend functions in `bump.sh`

### Testing

Marathon includes comprehensive test suites to verify all functionality:

#### Basic Process Tests

Test process hierarchy and signal handling:

```bash
# Full process test
./test/test.sh

# Individual tests
./test/one.sh   # Single process test
./test/two.sh   # Dual process test
./test/three.sh # Triple process test
```

#### Comprehensive Test Suite

Run all framework tests to verify proper operation:

```bash
# Run complete test suite
./test_marathon.sh

# Tests include:
# - Directory structure creation
# - Metadata generation
# - All cleanup modes
# - Resource monitoring
# - Health checks
# - Archive system
# - Retry mechanism
# - Transfer logging
# - Error tracking
```

#### Cleanup Mode Tests

Verify each cleanup mode behaves correctly:

```bash
# Test all cleanup modes with detailed output
./test_cleanup_modes.sh

# This will run jobs with each mode (keep, output, gpg, all)
# and verify that the correct files are retained/removed
```

#### Performance Tests

Test system under load and verify performance tracking:

```bash
# Run performance test suite
./test_performance.sh

# Configurable options:
export PERF_TEST_DURATION=60      # Test duration in seconds
export PERF_TEST_PARALLEL=8       # Number of parallel jobs
./test_performance.sh

# Tests include:
# - Parallel job execution
# - Memory usage tracking
# - Load average monitoring
# - Transfer performance
# - Concurrent job stress test
# - Performance report generation
```

#### Retry Mechanism Tests

Verify retry logic and exponential backoff:

```bash
# Test retry functionality
./test_retry.sh

# Tests include:
# - Successful retry after failures
# - Retry exhaustion handling
# - Non-retryable error detection
# - Exponential backoff timing
# - Retry policy configuration
# - Rclone-specific retry wrapper
# - Retry metrics recording
# - Error code classification
```

#### Test Requirements and Behavior

**Tests that always pass:**
- `test_basic.sh` - Validates script existence, syntax, and basic functionality
- `test/test.sh` - Process hierarchy tests (runs in quick mode during test_all.sh)
- `test_retry.sh` - Retry mechanism validation
- `test_summary.sh` - Testing documentation

**Tests requiring Marathon initialization:**
- `test_marathon.sh` - Full framework integration tests
- `test_cleanup_modes.sh` - Cleanup mode verification
- `test_performance.sh` - Performance and stress testing
- `test_report.sh` - Comprehensive validation report

**To initialize Marathon for full testing:**
```bash
# First run a test job to create directories and test data
./run.sh keep test_job

# Then run full test suite
./test_all.sh
```

#### Making Tests Executable

Ensure all test scripts are executable:

```bash
chmod +x test*.sh test/*.sh
```

### Code Quality

The codebase follows these standards:
- Comprehensive function documentation
- Consistent error handling with standardized exit codes
- Proper quoting for variable expansion
- Signal-safe operations in cleanup handlers
- GNU Parallel-safe function variants

## Directory Structure During Execution

### Workspace Directory

During job execution, Marathon creates this structure:

```
${workspace}/
├── ${job}/                # Job-specific workspace
│   ├── input/            # Downloaded input files
│   │   ├── file1.input
│   │   └── file2.input.gpg (if encrypted)
│   ├── work/             # Active processing directory
│   │   ├── file1.output  # Generated output files
│   │   └── file2.output
│   └── output/           # Staging for upload
│       ├── file1.output
│       └── file2.output.gpg (if encryption enabled)
└── lost+found/           # Recovery directory for interrupted jobs
```

### Logs Directory Structure

See [Logging](#logging) section for detailed log directory structure.

### Status Directory (RAM Disk)

During execution, process status is tracked in:

```
/dev/shm/
└── ${job}-${PID}/
    ├── workers           # Active worker PIDs
    ├── master            # Master process PID
    └── status            # Current job status
```

## Script Descriptions

### Core Scripts

- **run.sh**: Main orchestrator that coordinates the entire job execution
- **settings.sh**: Sets up environment variables, directories, and paths
- **io.sh**: Handles all data transfers using rclone (upload/download)
- **aws.sh**: AWS-specific functions including spot interruption detection
- **cleanup.sh**: Manages graceful shutdown and cleanup operations
- **metadata.sh**: Creates job manifests and performance reports
- **archive.sh**: Rotates and compresses old logs
- **retry.sh**: Implements exponential backoff retry for failed operations
- **health.sh**: Provides health check endpoint and system status

### Utility Scripts (bump/)

- **bump.sh**: Core utility functions (logging, validation, dependencies)
- **parallel.sh**: GNU Parallel-safe versions of utility functions
- **return_codes.sh**: Standardized exit codes for consistent error handling

### Test Scripts

- **test_marathon.sh**: Comprehensive framework testing
- **test_cleanup_modes.sh**: Verifies all cleanup modes work correctly
- **test_performance.sh**: Tests system under load
- **test_retry.sh**: Verifies retry mechanism
- **test_report.sh**: Quick smoke test
- **test_basic.sh**: Basic functionality test
- **test_summary.sh**: Tests summary generation

### Demonstration Scripts

- **demo_cleanup.sh**: Interactive demonstration of cleanup modes

## Projects Using Marathon

### Supervised classification of natural gas price movements

We use supervised machine-learning methods to predict price changes in the US Henry Hub market for options on natural gas. Despite increases in the sizes of price movements for a particular contract as maturity approaches, we identify stable statistical properties that allow comparisons of prices at different times, and increase the body of data used for learning. The predictions are used to assist investment decisions.

### Multiweek prediction of the state of the northern hemisphere

Imperfect knowledge of the state of the Earth system, combined with sensitivity to initial state, limits predictions. Useful advanced warning of extreme weather requires multi-week lead times, as do decisions on investments sensitive to energy markets. An original mathematical method, and the design of data structures that describe the Earth System, reduce the computational complexity and make possible multi-week predictions not possible with traditional methods, better even than with supercomputers used by facilities such as [NOAA in the USA](https://www.ncei.noaa.gov/products/weather-climate-models/global-ensemble-forecast), the [Met. Office in the UK](https://www.metoffice.gov.uk), and the [ECMWF in Europe](https://www.ecmwf.int/). This new, lightweight method outperforms for variables of critical interest the large scale, computationally expensive, [monolithic models that I developed and debugged for the Bureau of Meteorology.](http://www.bom.gov.au/research/projects/ACCESS-S/)

## Possible Extensions

- **MPI Support**: Replace GNU Parallel with MPI for inter-process communication
- **Multi-Cloud**: Extend spot instance support to GCP, Azure, etc.
- **Container Support**: Package as Docker/Singularity for easier deployment
- **Machine Images**: Pre-built AMIs to skip software installation

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## Contact

For access or information about projects and publications that use this code: [github.com.h3com@passmail.net](mailto:github.com.h3com@passmail.net)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- GNU Parallel for powerful job distribution
- rclone for versatile cloud storage access
- The AWS EC2 team for spot instance functionality
- GnuPG for secure data handling

## Author

Angus Gray-Weale, 2024