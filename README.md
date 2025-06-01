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

## Architecture

### Core Components

```
marathon/
├── run.sh              # Main orchestrator script
├── settings.sh         # Configuration and environment setup
├── io.sh              # Data transfer operations (rclone)
├── aws.sh             # AWS-specific functionality
├── cleanup.sh         # Cleanup and signal handlers
├── bump/              # Utility function library
│   ├── bump.sh        # Core utility functions
│   ├── parallel.sh    # GNU Parallel-safe functions
│   └── return_codes.sh # Standardized exit codes
├── worker/            # AWS deployment scripts
│   └── user-data.sh   # EC2 instance initialization
└── test/              # Test scripts
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

### Test Mode

Run the test suite to verify process hierarchy and signal handling:

```bash
./test/test.sh
```

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

Comprehensive logs are generated in `${logspace}/${job}/`:

- `${STAMP}.${job}.*.log` - Main execution logs
- `${STAMP}.${job}.*.load` - System load measurements
- `${STAMP}.${job}.*.memory` - Memory usage tracking
- `${STAMP}.${job}.*.free` - Available memory logs
- `status/*.status` - Process status snapshots

## Monitoring

### Real-time Monitoring

Monitor job progress in real-time:

```bash
# Watch parallel job progress
tail -f /mnt/logs/myjob/*.parallel.log

# Monitor system load
tail -f /mnt/logs/myjob/*.load

# Check worker status
cat /dev/shm/myjob-*/workers
```

### Resource Reports

The framework continuously logs:
- System load averages (1, 5, 15 minute)
- Per-process memory usage (VmHWM, VmRSS)
- Available system memory and swap
- Worker process status

## Cleanup Options

Control post-execution cleanup with the `clean` parameter:

- **`keep`**: Preserve all files (workspace, logs, outputs)
- **`output`**: Remove output files, keep inputs and logs
- **`gpg`**: Remove encrypted files, keep raw outputs
- **`all`**: Complete cleanup and shutdown (default for AWS)

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

Run the test suite:

```bash
# Full test
./test/test.sh

# Individual tests
./test/one.sh   # Single process test
./test/two.sh   # Dual process test
./test/three.sh # Triple process test
```

### Code Quality

The codebase follows these standards:
- Comprehensive function documentation
- Consistent error handling with standardized exit codes
- Proper quoting for variable expansion
- Signal-safe operations in cleanup handlers
- GNU Parallel-safe function variants

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