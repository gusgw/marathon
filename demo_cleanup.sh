#!/bin/bash
# demo_cleanup.sh: Quick demonstration of cleanup modes
#
# Shows what each cleanup mode does without running full jobs

echo "Marathon Cleanup Modes Demonstration"
echo "===================================="
echo
echo "This demonstrates what files are retained/removed by each cleanup mode."
echo

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}1. KEEP mode${NC}"
echo "   Command: ./run.sh keep myjob"
echo "   Behavior: Preserves all files after job completion"
echo -e "   ${GREEN}✓ Retained:${NC}"
echo "     - Work directory (/mnt/data/marathon/work/myjob/)"
echo "     - Job logs (/mnt/data/marathon/log/jobs/myjob/)"
echo "     - All input files (*.input)"
echo "     - All output files (*.output)"
echo "     - All encrypted files (*.gpg)"
echo "   Use case: Development, debugging, or inspecting intermediate files"
echo

echo -e "${BLUE}2. OUTPUT mode${NC}"
echo "   Command: ./run.sh output myjob"
echo "   Behavior: Cleans work and logs, keeps only output archive"
echo -e "   ${GREEN}✓ Retained:${NC}"
echo "     - Output archive (/mnt/data/marathon/output/*.logs.tar.xz)"
echo -e "   ${RED}✗ Removed:${NC}"
echo "     - Work directory"
echo "     - Job log directory"
echo "   Use case: Production runs where only final results matter"
echo

echo -e "${BLUE}3. GPG mode${NC}"
echo "   Command: ./run.sh gpg myjob"
echo "   Behavior: Keeps only encrypted files, removes unencrypted data"
echo -e "   ${GREEN}✓ Retained:${NC}"
echo "     - Work directory (but only with *.gpg files)"
echo "     - Job logs"
echo -e "   ${RED}✗ Removed:${NC}"
echo "     - All unencrypted files from work directory"
echo "   Use case: Security-sensitive environments"
echo

echo -e "${BLUE}4. ALL mode${NC}"
echo "   Command: ./run.sh all myjob"
echo "   Behavior: Complete cleanup (default for AWS)"
echo -e "   ${GREEN}✓ Retained:${NC}"
echo "     - Output archive only"
echo -e "   ${RED}✗ Removed:${NC}"
echo "     - Work directory"
echo "     - Job log directory"
echo "   Use case: Cloud deployments to minimize storage costs"
echo

echo -e "${YELLOW}Important Notes:${NC}"
echo "- System logs (logs/system/) are ALWAYS retained"
echo "- Reports (logs/reports/) are ALWAYS retained"
echo "- Transfer logs (logs/transfers/) are ALWAYS retained"
echo "- Job metadata is generated before cleanup"
echo "- Output archives are always created and uploaded"
echo

echo -e "${YELLOW}Current Log Structure:${NC}"
if [[ -d "/mnt/data/marathon/log" ]]; then
    echo "logs/"
    echo "├── jobs/          # Job-specific logs (cleaned based on mode)"
    echo "├── system/        # System metrics (always retained)"
    echo "├── transfers/     # Transfer logs (always retained)"
    echo "└── reports/       # Job index, metrics (always retained)"
    echo "    ├── job_index.txt"
    echo "    ├── error_index.txt"
    echo "    ├── daily/"
    echo "    ├── failures/"
    echo "    └── performance/"
fi