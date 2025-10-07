#!/bin/bash

# Storage Speed Test Script
# Tests read/write performance across multiple mount points
# Usage: ./storage_speed_test.sh
# plot resuling CSV data with Rscript plot_storage_results.R <csv_file> 
#
# SP@NC (+AI), 2025-10-07; v1.0

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
WHITE='\033[1;37m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Mount points to test
MOUNTS=(
    "/mnt/hdd_storage"
    "/mnt/ssd_storage"
    "/mnt/syn_hdd"
    "/mnt/syn_ssd"
)

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_TEST_DATA="$SCRIPT_DIR/test_data"
SPEEDTEST_SOURCE_DIR="speedtest_source"
SPEEDTEST_DEST_DIR="speedtest_dest"
SMALL_FILE_SIZE="50M"    # 50 MB (single file test)
LARGE_FILE_SIZE="1G"      # 1 GB
HUGE_FILE_SIZE="5G"       # 5 GB
MANY_FILES_SIZE="150K"    # 150 KB (for many small files test)
NUM_SMALL_FILES=10000     # Number of small files for multi-file test
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="speed_test_results_${TIMESTAMP}.txt"
CSV_FILE="speed_test_results_${TIMESTAMP}.csv"
LOG_FILE="speed_test_${TIMESTAMP}.log"

# Global variables for results
declare -A RESULTS

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}    Storage Speed Test Tool     ${NC}"
    echo -e "${BLUE}================================${NC}"
    echo
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${WHITE}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if mount points exist and are accessible
check_mounts() {
    log_info "Checking mount points..."
    local available_mounts=()
    
    for mount in "${MOUNTS[@]}"; do
        # Detailed diagnostics
        if [ ! -d "$mount" ]; then
            log_warn "✗ $mount does not exist"
            continue
        fi
        
        if [ ! -w "$mount" ]; then
            log_warn "✗ $mount exists but is not writable (trying to create test dir anyway)"
            # Try to create speedtest directory as a workaround
            if mkdir -p "$mount/$SPEEDTEST_SOURCE_DIR" 2>/dev/null; then
                log_info "✓ $mount - successfully created test directory"
                available_mounts+=("$mount")
            else
                log_warn "✗ $mount - cannot create test directory"
            fi
            continue
        fi
        
        log_info "✓ $mount is accessible"
        available_mounts+=("$mount")
    done
    
    if [ ${#available_mounts[@]} -eq 0 ]; then
        log_error "No accessible mount points found!"
        exit 1
    fi
    
    # Update MOUNTS array with only available mounts
    MOUNTS=("${available_mounts[@]}")
    log_info "Found ${#MOUNTS[@]} accessible mount points"
    echo
}

# Create speedtest directories
create_test_dirs() {
    log_info "Creating speedtest directories..."
    for mount in "${MOUNTS[@]}"; do
        local source_dir="$mount/$SPEEDTEST_SOURCE_DIR"
        local dest_dir="$mount/$SPEEDTEST_DEST_DIR"
        
        mkdir -p "$source_dir"
        mkdir -p "$dest_dir"
        log_info "Created directories: $source_dir and $dest_dir"
    done
    echo
}

# Generate test files locally (only once)
generate_local_test_data() {
    # Check if test data already exists
    if [ -f "$LOCAL_TEST_DATA/small_file.dat" ] && \
       [ -f "$LOCAL_TEST_DATA/large_file.dat" ] && \
       [ -f "$LOCAL_TEST_DATA/huge_file.dat" ] && \
       [ -d "$LOCAL_TEST_DATA/many_small_files" ]; then
        log_info "Test data already exists in $LOCAL_TEST_DATA, skipping creation"
        return 0
    fi
    
    log_info "Generating test data in $LOCAL_TEST_DATA..."
    mkdir -p "$LOCAL_TEST_DATA"
    
    # Small file
    if [ ! -f "$LOCAL_TEST_DATA/small_file.dat" ]; then
        log_info "  Creating small file ($SMALL_FILE_SIZE)..."
        # Extract numeric value from size (e.g., "50M" -> 50)
        local small_count=${SMALL_FILE_SIZE%M}
        dd if=/dev/urandom of="$LOCAL_TEST_DATA/small_file.dat" bs=1M count=$small_count status=progress 2>&1 | tail -1
    fi
    
    # Large file
    if [ ! -f "$LOCAL_TEST_DATA/large_file.dat" ]; then
        log_info "  Creating large file ($LARGE_FILE_SIZE)..."
        # Extract numeric value (e.g., "1G" -> 1024M)
        local large_count=${LARGE_FILE_SIZE%G}
        large_count=$((large_count * 1024))
        dd if=/dev/urandom of="$LOCAL_TEST_DATA/large_file.dat" bs=1M count=$large_count status=progress 2>&1 | tail -1
    fi
    
    # Huge file
    if [ ! -f "$LOCAL_TEST_DATA/huge_file.dat" ]; then
        log_info "  Creating huge file ($HUGE_FILE_SIZE)..."
        # Extract numeric value (e.g., "5G" -> 5120M)
        local huge_count=${HUGE_FILE_SIZE%G}
        huge_count=$((huge_count * 1024))
        dd if=/dev/urandom of="$LOCAL_TEST_DATA/huge_file.dat" bs=1M count=$huge_count status=progress 2>&1 | tail -1
    fi
    
    # Directory with many small files
    local small_files_dir="$LOCAL_TEST_DATA/many_small_files"
    if [ ! -d "$small_files_dir" ] || [ $(find "$small_files_dir" -type f | wc -l) -lt $NUM_SMALL_FILES ]; then
        mkdir -p "$small_files_dir"
        log_info "  Creating $NUM_SMALL_FILES small files ($MANY_FILES_SIZE each)..."
        # Extract numeric value from size (e.g., "150K" -> 150)
        local many_count=${MANY_FILES_SIZE%K}
        for i in $(seq 1 $NUM_SMALL_FILES); do
            if [ ! -f "$small_files_dir/file_$i.dat" ]; then
                dd if=/dev/urandom of="$small_files_dir/file_$i.dat" bs=1024 count=$many_count 2>/dev/null
            fi
            if [ $((i % 1000)) -eq 0 ]; then
                log_info "    Created $i/$NUM_SMALL_FILES files..."
            fi
        done
    fi
    
    log_info "Test data ready in $LOCAL_TEST_DATA"
}

# Measure time for a command
measure_time() {
    shift  # Remove description parameter (not used)
    local start_time
    local end_time
    local duration
    
    start_time=$(date +%s)
    "$@"
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    echo "$duration"
}

# Calculate transfer rate
calculate_rate() {
    local size_bytes="$1"
    local time_seconds="$2"
    local rate_mbps
    
    # Avoid division by zero or empty values
    if [ -z "$time_seconds" ] || [ "$time_seconds" -eq 0 ]; then
        echo "N/A"
        return
    fi
    
    if [ -z "$size_bytes" ] || [ "$size_bytes" -eq 0 ]; then
        echo "0.00"
        return
    fi
    
    # Calculate MB/s using integer arithmetic (multiplying by 100 for 2 decimal places)
    rate_mbps=$((size_bytes * 100 / time_seconds / 1048576))
    printf "%d.%02d" $((rate_mbps / 100)) $((rate_mbps % 100))
}

# Get file/directory size in bytes
get_size() {
    local path="$1"
    if [ -f "$path" ]; then
        # macOS uses -f, Linux uses -c
        stat -c%s "$path" 2>/dev/null || stat -f%z "$path" 2>/dev/null
    elif [ -d "$path" ]; then
        du -sb "$path" 2>/dev/null | cut -f1
    fi
}

# Extract short mount name for CSV
get_short_mount_name() {
    local mount_path="$1"
    local name=$(basename "$mount_path")
    # Map to proper mount names
    case "$name" in
        "hdd_storage") echo "nuc5_hdd" ;;
        "ssd_storage") echo "nuc5_ssd" ;;
        "syn_hdd") echo "syn_hdd" ;;
        "syn_ssd") echo "syn_ssd" ;;
        *) echo "$name" ;;
    esac
}

# Test file copy operation
test_copy() {
    local source="$1"
    local dest="$2"
    local test_name="$3"
    local source_mount="$4"
    local dest_mount="$5"
    
    log_info "Testing: $test_name ($source_mount → $dest_mount)"
    
    # Clean destination
    rm -rf "$dest"
    
    # Measure copy time
    local copy_time
    if [ -f "$source" ]; then
        copy_time=$(measure_time "copy" cp "$source" "$dest")
    elif [ -d "$source" ]; then
        copy_time=$(measure_time "copy" cp -r "$source" "$dest")
    fi
    
    # Calculate size and rate
    local size_bytes
    local rate_mbps
    
    size_bytes=$(get_size "$source")
    rate_mbps=$(calculate_rate "$size_bytes" "$copy_time")
    
    # Store results (using pipe delimiter to avoid conflicts with underscores in mount names)
    local result_key="${source_mount}|${dest_mount}|${test_name}"
    RESULTS["$result_key"]="$copy_time,$rate_mbps,$size_bytes"
    
    # Write to CSV immediately
    local csv_file="$PWD/$CSV_FILE"
    echo "$source_mount,$dest_mount,$test_name,$copy_time,$rate_mbps,$size_bytes" >> "$csv_file"
    
    printf "  Time: %d seconds, Rate: %s MB/s, Size: %d bytes\n" "$copy_time" "$rate_mbps" "$size_bytes"
    
    # Clean up destination
    rm -rf "$dest"
}

# Initialize CSV file with headers
init_csv_file() {
    local csv_file="$PWD/$CSV_FILE"
    echo "Source,Destination,TestType,Time_s,Rate_MBps,Size_bytes" > "$csv_file"
    log_info "Initialized CSV file: $csv_file"
}

# Run comprehensive speed tests
run_speed_tests() {
    log_info "Starting comprehensive speed tests..."
    echo
    
    for source_mount in "${MOUNTS[@]}"; do
        local source_dir="$source_mount/$SPEEDTEST_SOURCE_DIR"
        
        # Copy test data from local directory to source
        log_info "Copying test data to $source_dir..."
        cp -r "$LOCAL_TEST_DATA"/* "$source_dir/"
        
        for dest_mount in "${MOUNTS[@]}"; do
            local dest_dir="$dest_mount/$SPEEDTEST_DEST_DIR"
            
            echo -e "${WHITE}Testing: $source_mount → $dest_mount${NC}"
            
            # Get short mount names for CSV
            local source_name=$(get_short_mount_name "$source_mount")
            local dest_name=$(get_short_mount_name "$dest_mount")
            
            # Test small file
            test_copy "$source_dir/small_file.dat" "$dest_dir/small_file.dat" "small_file" \
                "$source_name" "$dest_name"
            
            # Test large file
            test_copy "$source_dir/large_file.dat" "$dest_dir/large_file.dat" "large_file" \
                "$source_name" "$dest_name"
            
            # Test huge file
            test_copy "$source_dir/huge_file.dat" "$dest_dir/huge_file.dat" "huge_file" \
                "$source_name" "$dest_name"
            
            # Test directory with many small files
            test_copy "$source_dir/many_small_files" "$dest_dir/many_small_files" "many_small_files" \
                "$source_name" "$dest_name"
            
            echo
        done
        
        # Clean up source test files
        rm -rf "$source_dir"/*
    done
}

# Generate detailed results report
generate_report() {
    log_info "Generating results report..."
    
    local report_file="$PWD/$RESULTS_FILE"
    local csv_file="$PWD/$CSV_FILE"
    
    log_info "CSV results saved to: $csv_file"
    
    # Generate text report
    {
        echo "Storage Speed Test Results"
        echo "=========================="
        echo "Test Date: $(date)"
        echo "Test Configuration:"
        echo "  Small file size: $SMALL_FILE_SIZE"
        echo "  Large file size: $LARGE_FILE_SIZE"
        echo "  Huge file size: $HUGE_FILE_SIZE"
        echo "  Many files size: $MANY_FILES_SIZE"
        echo "  Number of small files: $NUM_SMALL_FILES"
        echo
        echo "Mount Points Tested:"
        for mount in "${MOUNTS[@]}"; do
            echo "  - $mount"
        done
        echo
        echo "Results Summary:"
        echo "================"
        
        # Create a formatted table
        printf "%-20s %-20s %-15s %-12s %-12s %-12s\n" "Source" "Destination" "Test Type" "Time (s)" "Rate (MB/s)" "Size (bytes)"
        echo "--------------------------------------------------------------------------------"
        
        for key in $(printf '%s\n' "${!RESULTS[@]}" | sort); do
            IFS=',' read -r time rate size <<< "${RESULTS[$key]}"
            
            # Parse key to extract source, dest, and test type
            # Key format: source_to_dest_test_type
            IFS='_' read -ra KEY_PARTS <<< "$key"
            local source="${KEY_PARTS[0]}"
            local dest="${KEY_PARTS[2]}"
            # Test type is everything after index 3, joined by underscore
            local test_type="${KEY_PARTS[3]}"
            for ((i=4; i<${#KEY_PARTS[@]}; i++)); do
                test_type="${test_type}_${KEY_PARTS[i]}"
            done
            
            printf "%-20s %-20s %-15s %-12d %-12s %-12d\n" "$source" "$dest" "$test_type" "$time" "$rate" "$size"
        done
        
        echo
        echo "Performance Analysis:"
        echo "===================="
        
        # Find fastest and slowest operations
        local max_rate=0
        local min_rate=999999
        local max_key=""
        local min_key=""
        
        for key in "${!RESULTS[@]}"; do
            IFS=',' read -r time rate size <<< "${RESULTS[$key]}"
            # Skip N/A values
            if [ "$rate" = "N/A" ]; then
                continue
            fi
            # Convert rate to integer for comparison (remove decimal point)
            local rate_int=${rate//./}
            if [ "$rate_int" -gt "$max_rate" ]; then
                max_rate="$rate_int"
                max_key="$key"
            fi
            if [ "$rate_int" -lt "$min_rate" ] && [ "$rate_int" -gt 0 ]; then
                min_rate="$rate_int"
                min_key="$key"
            fi
        done
        
        # Get actual rate values for display
        if [ -n "$max_key" ]; then
            IFS=',' read -r time max_rate_display size <<< "${RESULTS[$max_key]}"
        else
            max_rate_display="N/A"
            max_key="None"
        fi
        
        if [ -n "$min_key" ]; then
            IFS=',' read -r time min_rate_display size <<< "${RESULTS[$min_key]}"
        else
            min_rate_display="N/A"
            min_key="None"
        fi
        
        echo "Fastest operation: $max_key (${max_rate_display} MB/s)"
        echo "Slowest operation: $min_key (${min_rate_display} MB/s)"
        
    } > "$report_file"
    
    log_info "Results saved to: $report_file"
    
    # Also display summary to console
    echo
    echo -e "${GREEN}Test Summary:${NC}"
    echo -e "Fastest operation: ${GREEN}$max_key${NC} (${GREEN}${max_rate_display} MB/s${NC})"
    echo -e "Slowest operation: ${RED}$min_key${NC} (${RED}${min_rate_display} MB/s${NC})"
    echo
    echo -e "${BLUE}To generate plots, run:${NC} Rscript plot_storage_results.R $csv_file"
}

# Clean up test directories
cleanup() {
    log_info "Cleaning up test directories..."
    for mount in "${MOUNTS[@]}"; do
        local source_dir="$mount/$SPEEDTEST_SOURCE_DIR"
        local dest_dir="$mount/$SPEEDTEST_DEST_DIR"
        
        if [ -d "$source_dir" ]; then
            rm -rf "$source_dir"
            log_info "Removed: $source_dir"
        fi
        
        if [ -d "$dest_dir" ]; then
            rm -rf "$dest_dir"
            log_info "Removed: $dest_dir"
        fi
    done
}

# Main function
main() {
    print_header
    
    generate_local_test_data
    check_mounts
    create_test_dirs
    init_csv_file
    run_speed_tests
    generate_report
    cleanup
    
    log_info "Speed test completed successfully!"
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Run main function and log all output to file
exec > >(tee -a "$LOG_FILE") 2>&1

main "$@"