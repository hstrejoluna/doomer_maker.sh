#!/bin/bash
###############################################################################
#
# Doomer Maker - Professional Audio Effect Processor
# Version: 2.0.0
#
# Creates "doomer" versions of audio files with various effects including:
# - Speed/tempo adjustment
# - Reverb effects
# - Low-pass filtering
# - Vinyl crackle overlay
#
# Author: User
# License: MIT
#
###############################################################################

# Strict mode
set -euo pipefail

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------

# Script identification
readonly SCRIPT_NAME="Doomer Maker"
readonly SCRIPT_VERSION="2.0.0"

# Get script location
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

# Process ID for temp files
readonly PID="$$"

# File paths
readonly CONFIG_DIR="${SCRIPT_DIR}/config"
readonly TEMP_DIR="${SCRIPT_DIR}/.doomer_tmp_${PID}"
readonly LOG_FILE="${SCRIPT_DIR}/doomer_maker_${PID}.log"
readonly STATS_FILE="${TEMP_DIR}/stats.json"

# Default effect parameters
readonly DEFAULT_SPEEDS=(0.8 0.9 1.0)
readonly DEFAULT_REVERB_LEVELS=(50 60 70)
readonly DEFAULT_LOWPASS_FREQS=(800 900 990)
readonly DEFAULT_VINYL_VOLUME=0.005
readonly MAX_MIXES=27
readonly DEFAULT_MIXES=9

# Debug level: 0=off, 1=normal, 2=verbose
DEBUG_LEVEL=1

# Keep temp files (for debugging): 0=clean, 1=keep
KEEP_TEMP=0

# Audio quality (kbps)
AUDIO_QUALITY=192

#------------------------------------------------------------------------------
# Utilities
#------------------------------------------------------------------------------

# Display help
show_help() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}

Usage: $(basename "$0") [options]

Options:
  -h, --help        Show this help message
  -d, --debug       Enable debug mode (more verbose output)
  -v, --verbose     Enable verbose debug mode (maximum detail)
  -k, --keep-temp   Keep temporary files (for debugging)
  -q, --quality N   Set output audio quality in kbps (default: ${AUDIO_QUALITY})
  -c, --cli         Run in CLI mode (no GUI dialogs)

Examples:
  $(basename "$0") --debug
  $(basename "$0") --keep-temp --quality 256

EOF
}

# Color definitions
if [[ -t 1 ]]; then
    readonly COLOR_RESET="\033[0m"
    readonly COLOR_RED="\033[1;31m"
    readonly COLOR_GREEN="\033[1;32m" 
    readonly COLOR_YELLOW="\033[1;33m"
    readonly COLOR_BLUE="\033[1;34m"
    readonly COLOR_MAGENTA="\033[1;35m"
    readonly COLOR_CYAN="\033[1;36m"
else
    readonly COLOR_RESET=""
    readonly COLOR_RED=""
    readonly COLOR_GREEN=""
    readonly COLOR_YELLOW=""
    readonly COLOR_BLUE=""
    readonly COLOR_MAGENTA=""
    readonly COLOR_CYAN=""
fi

# Logging function
log() {
    local level="$1"
    local color=""
    local level_display=""
    shift
    
    case "$level" in
        "ERROR")
            color="$COLOR_RED"
            level_display="ERROR"
            ;;
        "WARNING")
            color="$COLOR_YELLOW"
            level_display="WARN "
            ;;
        "SUCCESS")
            color="$COLOR_GREEN"
            level_display="OK   "
            ;;
        "INFO")
            color="$COLOR_BLUE"
            level_display="INFO "
            if [[ "$DEBUG_LEVEL" -lt 1 ]]; then return 0; fi
            ;;
        "DEBUG")
            color="$COLOR_MAGENTA"
            level_display="DEBUG"
            if [[ "$DEBUG_LEVEL" -lt 1 ]]; then return 0; fi
            ;;
        "TRACE")
            color="$COLOR_CYAN"
            level_display="TRACE"
            if [[ "$DEBUG_LEVEL" -lt 2 ]]; then return 0; fi
            ;;
        *)
            level_display="     "
            ;;
    esac
    
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Separate colored output for console and plain output for logs
    local console_message="${color}[${timestamp}] [${level_display}]${COLOR_RESET} $*"
    local log_message="[${timestamp}] [${level_display}] $*"
    
    # Log to stdout with colors
    echo -e "$console_message"
    
    # Log to file without color codes
    echo "$log_message" >> "$LOG_FILE"
}

# Command execution with logging
execute_cmd() {
    local cmd="$1"
    local output
    
    log "TRACE" "Executing: $cmd"
    
    if output=$( { eval "$cmd"; } 2>&1 ); then
        if [[ -n "$output" && "$DEBUG_LEVEL" -ge 2 ]]; then
            log "TRACE" "Command output:"
            echo "$output" | sed 's/^/    /' | tee -a "$LOG_FILE" > /dev/null
        fi
        return 0
    else
        local exit_code=$?
        log "ERROR" "Command failed with exit code $exit_code:"
        echo "$output" | sed 's/^/    /' | tee -a "$LOG_FILE" >&2
        return $exit_code
    fi
}

# Check if command exists
cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check file existence and readability
check_file() {
    local file="$1"
    local description="$2"
    
    # Remove any ANSI color codes that might be in the file path
    file=$(echo "$file" | sed 's/\x1b\[[0-9;]*m//g')
    
    if [[ ! -f "$file" ]]; then
        log "ERROR" "$description file does not exist: $file"
        return 1
    fi
    
    if [[ ! -r "$file" ]]; then
        log "ERROR" "Cannot read $description file: $file"
        return 1
    fi
    
    if [[ -f "$file" && ! -s "$file" ]]; then
        log "ERROR" "$description file is empty: $file"
        return 1
    fi
    
    log "TRACE" "$description file is valid: $file"
    return 0
}

# Safe cleanup
cleanup() {
    if [[ "$KEEP_TEMP" -eq 1 ]]; then
        log "INFO" "Keeping temporary files in: $TEMP_DIR"
    else
        log "INFO" "Cleaning up temporary files"
        [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
    fi
}

# Error handler
error_handler() {
    local line_no=$1
    local error_code=$2
    
    log "ERROR" "=================================================================="
    log "ERROR" "Script failed at line ${line_no} with exit code ${error_code}"
    log "ERROR" "Last 10 lines from log file:"
    tail -n 10 "$LOG_FILE" | sed 's/^/    /' >&2
    log "ERROR" "=================================================================="
    log "ERROR" "Check the complete log file for details: $LOG_FILE"
    
    # Perform cleanup unless keep_temp is set
    if [[ "$KEEP_TEMP" -eq 0 ]]; then
        cleanup
    fi
    
    exit "${error_code}"
}

# Format time in seconds to a readable format
format_time() {
    local seconds=$1
    local minutes=$((seconds / 60))
    local remaining_seconds=$((seconds % 60))
    
    printf "%d:%02d" "$minutes" "$remaining_seconds"
}

# Check required disk space (in MB)
check_disk_space() {
    local dir="$1"
    local required_mb="$2"
    
    local available
    if cmd_exists "df"; then
        # Get available disk space in KB and convert to MB
        available=$(df -k "$dir" | awk 'NR==2 {print int($4/1024)}')
        
        if [[ "$available" -lt "$required_mb" ]]; then
            log "WARNING" "Low disk space: ${available}MB available, ${required_mb}MB recommended"
            return 1
        fi
    fi
    
    return 0
}

# Convert relative path to absolute
get_absolute_path() {
    local path="$1"
    
    # Remove any ANSI color codes
    path=$(echo "$path" | sed 's/\x1b\[[0-9;]*m//g')
    
    # Handle paths with spaces and special characters
    if [[ -d "$path" ]]; then
        (cd "$path" && pwd)
    elif [[ -f "$path" ]]; then
        local dir
        dir=$(dirname "$path")
        echo "$(cd "$dir" && pwd)/$(basename "$path")"
    else
        # Path doesn't exist, just clean and return it
        echo "$path"
    fi
}

# Update stats file with current processing status
update_stats() {
    local key="$1"
    local value="$2"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$STATS_FILE")"
    
    # Simple JSON update (would use jq in production)
    local temp_file="${TEMP_DIR}/stats_temp.json"
    if [[ -f "$STATS_FILE" ]]; then
        # Extract existing JSON
        grep -v "\"$key\":" "$STATS_FILE" > "$temp_file" 2>/dev/null || echo "{" > "$temp_file"
        
        # Remove trailing closing brace if it exists
        sed -i 's/}$//' "$temp_file" 2>/dev/null || true
        
        # Check if we need a comma
        if grep -q ":" "$temp_file"; then
            echo "  ,\"$key\": \"$value\"" >> "$temp_file"
        else
            echo "  \"$key\": \"$value\"" >> "$temp_file"
        fi
        
        # Close JSON
        echo "}" >> "$temp_file"
        mv "$temp_file" "$STATS_FILE"
    else
        # Create new JSON
        echo "{" > "$STATS_FILE"
        echo "  \"$key\": \"$value\"" >> "$temp_file"
        echo "}" >> "$STATS_FILE"
    fi
    
    # Force flush to disk to ensure progress monitor can read updates
    sync
}

# Clean a value to ensure it's free of unwanted characters
sanitize_value() {
    local value="$1"
    local pattern="$2"
    
    # Default to numeric pattern if none provided
    if [[ -z "$pattern" ]]; then
        pattern='[0-9.]+'
    fi
    
    # Remove ANSI color codes and other non-printing characters
    value=$(echo "$value" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r\n')
    
    # Extract the pattern we want - use grep -E for extended regex
    value=$(echo "$value" | grep -E -o "$pattern" | head -1)
    
    # Add debug output
    log "TRACE" "sanitize_value input: '$1', pattern: '$pattern', output: '$value'"
    
    echo "$value"
}

#------------------------------------------------------------------------------
# Dependency Check
#------------------------------------------------------------------------------

check_dependencies() {
    log "INFO" "Checking system dependencies"
    
    # Required tools
    local required_deps=("ffmpeg" "sox" "zenity")
    local missing_deps=()
    
    # Optional tools
    if ! cmd_exists "bc"; then
        log "WARNING" "bc command not found - will use internal math functions"
    fi
    
    # Check each dependency
    for dep in "${required_deps[@]}"; do
        if ! cmd_exists "$dep"; then
            missing_deps+=("$dep")
            log "ERROR" "Missing required dependency: $dep"
        else
            local version
            version=$(command -v "$dep")
            log "DEBUG" "Found $dep at: $version"
            
            # Log version info for major tools
            if [[ "$dep" == "ffmpeg" ]]; then
                "$dep" -version | head -n 1 | sed 's/^/    /' >> "$LOG_FILE"
            elif [[ "$dep" == "sox" ]]; then
                "$dep" --version | head -n 1 | sed 's/^/    /' >> "$LOG_FILE"
            fi
        fi
    done
    
    # Exit if any dependencies are missing
    if [[ ${#missing_deps[@]} -ne 0 ]]; then
        log "ERROR" "Missing required dependencies: ${missing_deps[*]}"
        log "ERROR" "Please install them using your package manager."
        return 1
    fi
    
    # Check write permissions
    if [[ ! -w "$SCRIPT_DIR" ]]; then
        log "ERROR" "Cannot write to script directory: $SCRIPT_DIR"
        log "ERROR" "Please make sure you have write permissions to the directory containing the script."
        return 1
    fi
    
    log "SUCCESS" "All dependencies are available"
    return 0
}

#------------------------------------------------------------------------------
# Audio Processing Functions
#------------------------------------------------------------------------------

# Generate vinyl crackle noise
generate_vinyl_crackle() {
    local output_file="$1"
    local duration="$2"
    local volume="$3"
    
    log "INFO" "Generating vinyl crackle effect (${duration}s)"
    
    if ! execute_cmd "sox -r 44100 -n \"$output_file\" synth \"$duration\" pinknoise vol $volume"; then
        log "ERROR" "Failed to generate vinyl noise"
        return 1
    fi
    
    if ! check_file "$output_file" "Vinyl noise"; then
        return 1
    fi
    
    log "DEBUG" "Vinyl crackle generated: $output_file"
    return 0
}

# Apply speed/pitch change
apply_speed_change() {
    local input_file="$1"
    local output_file="$2"
    local speed="$3"
    
    log "INFO" "Applying speed change (${speed}x)"
    
    if ! execute_cmd "ffmpeg -y -v warning -stats -i \"$input_file\" -filter:a \"asetrate=44100*$speed,aresample=44100\" -vn \"$output_file\""; then
        log "ERROR" "Failed to apply speed change"
        return 1
    fi
    
    if ! check_file "$output_file" "Speed-modified audio"; then
        return 1
    fi
    
    log "DEBUG" "Speed change applied: $output_file"
    return 0
}

# Apply low-pass filter
apply_lowpass() {
    local input_file="$1"
    local output_file="$2"
    local frequency="$3"
    
    log "INFO" "Applying lowpass filter (${frequency}Hz)"
    
    if ! execute_cmd "sox \"$input_file\" \"$output_file\" lowpass \"$frequency\""; then
        log "ERROR" "Failed to apply lowpass filter"
        return 1
    fi
    
    if ! check_file "$output_file" "Lowpass-filtered audio"; then
        return 1
    fi
    
    log "DEBUG" "Lowpass filter applied: $output_file"
    return 0
}

# Apply reverb effect
apply_reverb() {
    local input_file="$1"
    local output_file="$2"
    local reverb_amount="$3"
    
    log "INFO" "Applying reverb effect (${reverb_amount}%)"
    
    if ! execute_cmd "sox \"$input_file\" \"$output_file\" reverb \"$reverb_amount\" 0.5 100 100 0 0"; then
        log "ERROR" "Failed to apply reverb"
        return 1
    fi
    
    if ! check_file "$output_file" "Reverb-processed audio"; then
        return 1
    fi
    
    log "DEBUG" "Reverb effect applied: $output_file"
    return 0
}

# Mix audio tracks
mix_audio() {
    local main_file="$1"
    local vinyl_file="$2"
    local output_file="$3"
    
    log "INFO" "Mixing audio with vinyl effect"
    
    # Try ffmpeg first (higher quality mixing)
    if execute_cmd "ffmpeg -y -i \"$main_file\" -i \"$vinyl_file\" -filter_complex \"[0:a][1:a]amix=inputs=2:duration=longest:dropout_transition=2\" -b:a ${AUDIO_QUALITY}k \"$output_file\""; then
        log "DEBUG" "Mixed using ffmpeg: $output_file"
    else
        log "WARNING" "ffmpeg mixing failed, trying sox method..."
        
        # Fallback to sox
        if ! execute_cmd "sox -m \"$main_file\" \"$vinyl_file\" \"$output_file\""; then
            log "ERROR" "Failed to mix audio with vinyl noise"
            return 1
        fi
        log "DEBUG" "Mixed using sox: $output_file"
    fi
    
    if ! check_file "$output_file" "Final mixed audio"; then
        return 1
    fi
    
    return 0
}

# Get audio duration
get_audio_duration() {
    local input_file="$1"
    local duration_file="${TEMP_DIR}/duration.txt"
    local duration_value
    
    # Execute ffprobe directly with minimal logging and store output to file
    ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input_file" > "$duration_file" 2>/dev/null
    
    if [[ ! -f "$duration_file" || ! -s "$duration_file" ]]; then
        log "ERROR" "Failed to create valid duration file"
        return 1
    fi
    
    # Read the raw duration file - NO logging here to avoid contamination
    duration_value=$(cat "$duration_file")
    
    # Now we can log the value
    log "DEBUG" "Raw duration output: $duration_value"
    
    # Return success code but don't output anything to stdout
    return 0
}

# Process a single mix
process_mix() {
    local input_file="$1"
    local output_folder="$2"
    local filename_base="$3"
    local speed="$4"
    local reverb="$5"
    local lowpass="$6"
    local mix_number="$7"
    local total_mixes="$8"
    
    # Generate unique pattern for this mix
    local mix_id="${speed}_${reverb}_${lowpass}"
    
    # Update progress 
    update_stats "current_mix" "$mix_number"
    update_stats "total_mixes" "$total_mixes"
    update_stats "status" "processing"
    update_stats "mix_id" "$mix_id"
    
    log "INFO" "Processing mix $mix_number/$total_mixes: Speed=${speed}, Reverb=${reverb}, Lowpass=${lowpass}"
    
    # Create mix temp directory
    local mix_temp_dir="${TEMP_DIR}/mix_${mix_id}"
    mkdir -p "$mix_temp_dir"
    
    # Define file paths
    local output_file="${output_folder}/${filename_base}_speed${speed}_reverb${reverb}_lowpass${lowpass}.mp3"
    local temp_vinyl="${mix_temp_dir}/vinyl.wav"
    local temp_speed="${mix_temp_dir}/speed.mp3"
    local temp_lowpass="${mix_temp_dir}/lowpass.mp3"
    local temp_reverb="${mix_temp_dir}/reverb.mp3"
    
    # Get audio duration directly from file
    local duration_file="${TEMP_DIR}/duration.txt"
    
    # First run the duration extraction function (no output)
    if ! get_audio_duration "$input_file"; then
        log "ERROR" "Failed to get audio duration"
        update_stats "status" "error"
        return 1
    fi
    
    # Now read the duration directly from the file
    if [[ ! -f "$duration_file" ]]; then
        log "ERROR" "Duration file not found"
        update_stats "status" "error"
        return 1
    fi
    
    local duration=$(cat "$duration_file" | tr -d '\r\n')
    
    # Validate duration format
    if ! [[ "$duration" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log "ERROR" "Invalid duration format: '$duration'"
        update_stats "status" "error"
        return 1
    fi
    
    log "INFO" "Processing audio with duration: ${duration}s"
    
    # STEP 1: Generate vinyl noise with direct command
    log "INFO" "Generating vinyl crackle effect (${duration}s)"
    
    # Use direct command execution to avoid any issues
    sox -r 44100 -n "$temp_vinyl" synth "$duration" pinknoise vol "$DEFAULT_VINYL_VOLUME"
    
    if [[ $? -ne 0 || ! -f "$temp_vinyl" ]]; then
        log "ERROR" "Failed to generate vinyl noise"
        update_stats "status" "error" 
        return 1
    fi
    
    log "DEBUG" "Vinyl crackle successfully generated"
    
    # STEP 2: Apply speed change
    if ! apply_speed_change "$input_file" "$temp_speed" "$speed"; then
        update_stats "status" "error"
        return 1
    fi
    
    # STEP 3: Apply lowpass filter
    if ! apply_lowpass "$temp_speed" "$temp_lowpass" "$lowpass"; then
        update_stats "status" "error"
        return 1
    fi
    
    # STEP 4: Apply reverb effect
    if ! apply_reverb "$temp_lowpass" "$temp_reverb" "$reverb"; then
        update_stats "status" "error"
        return 1
    fi
    
    # STEP 5: Mix with vinyl crackle
    if ! mix_audio "$temp_reverb" "$temp_vinyl" "$output_file"; then
        update_stats "status" "error"
        return 1
    fi
    
    # Verify output file
    if ! check_file "$output_file" "Final output"; then
        update_stats "status" "error"
        return 1
    fi
    
    # Verify file size
    local file_size
    file_size=$(stat -c %s "$output_file" 2>/dev/null || stat -f %z "$output_file" 2>/dev/null || echo "0")
    log "DEBUG" "Output file size: $file_size bytes"
    
    if [ "$file_size" -eq 0 ]; then
        log "ERROR" "Output file was created but is empty"
        update_stats "status" "error"
        return 1
    fi
    
    # Clean up mix temp files unless keep_temp is set
    if [[ "$KEEP_TEMP" -eq 0 && "$DEBUG_LEVEL" -lt 2 ]]; then
        rm -rf "$mix_temp_dir"
    fi
    
    log "SUCCESS" "Created: $(basename "$output_file")"
    update_stats "status" "complete"
    return 0
}

#------------------------------------------------------------------------------
# User Interface Functions
#------------------------------------------------------------------------------

# Diagnostic function for file paths
diagnose_path() {
    local path="$1"
    
    if [[ "$DEBUG_LEVEL" -lt 2 ]]; then
        return 0
    fi
    
    log "TRACE" "Path diagnosis for: '$path'"
    log "TRACE" "Character by character analysis:"
    
    # Analyze each character with hexdump if available
    if cmd_exists "xxd"; then
        xxd -p <<< "$path" | fold -w2 | paste -sd' ' | sed 's/^/    /' >> "$LOG_FILE"
    fi
    
    # Check if file exists
    if [[ -f "$path" ]]; then
        log "TRACE" "File exists"
        execute_cmd "ls -la \"$path\""
    else
        log "TRACE" "File does not exist"
        execute_cmd "ls -la \"$(dirname \"$path\")\""
    fi
}

# Select input file with GUI
select_input_file_gui() {
    log "INFO" "Waiting for input file selection"
    
    local input_file
    local temp_path_file="${TEMP_DIR}/selected_input_path.txt"
    
    # Create temp directory if it doesn't exist yet
    mkdir -p "$TEMP_DIR"
    
    if ! input_file=$(zenity --file-selection --file-filter='Audio files (mp3 wav ogg) | *.mp3 *.MP3 *.wav *.WAV *.ogg *.OGG' --title="Select an audio file"); then
        log "ERROR" "File selection cancelled or failed"
        return 1
    fi
    
    if [[ -z "$input_file" ]]; then
        log "ERROR" "No input file selected"
        return 1
    fi
    
    # Write the path to a temporary file instead of returning it
    # This avoids any issues with output capturing
    echo "$input_file" > "$temp_path_file"
    
    # Convert to absolute path and strip any color codes
    input_file=$(get_absolute_path "$input_file" | sed 's/\x1b\[[0-9;]*m//g')
    log "DEBUG" "Selected input file: $input_file"
    
    # Run diagnostics on path if in verbose mode
    diagnose_path "$input_file"
    
    return 0
}

# Select output folder with GUI
select_output_folder_gui() {
    log "INFO" "Waiting for output folder selection"
    
    local output_folder
    local temp_folder_file="${TEMP_DIR}/selected_output_folder.txt"
    
    if ! output_folder=$(zenity --file-selection --directory --title="Select the output folder"); then
        log "ERROR" "Folder selection cancelled or failed"
        return 1
    fi
    
    if [[ -z "$output_folder" ]]; then
        log "ERROR" "No output folder selected"
        return 1
    fi
    
    # Write to temporary file
    echo "$output_folder" > "$temp_folder_file"
    
    # Convert to absolute path
    output_folder=$(get_absolute_path "$output_folder")
    log "DEBUG" "Selected output folder: $output_folder"
    
    # Create output directory
    mkdir -p "$output_folder"
    
    # Check write permissions
    if [[ ! -w "$output_folder" ]]; then
        log "ERROR" "Cannot write to output folder: $output_folder"
        zenity --error --title="Permission Error" \
            --text="Cannot write to the selected output folder.\nPlease select a folder you have permission to write to."
        return 1
    fi
    
    return 0
}

# Get number of mixes with GUI
get_num_mixes_gui() {
    log "INFO" "Waiting for number of mixes input"
    
    local num_mixes
    local temp_mixes_file="${TEMP_DIR}/selected_mixes.txt"
    
    if ! num_mixes=$(zenity --entry --title="Number of mixes" \
        --text="Enter the number of doomer mixes to generate (max ${MAX_MIXES}):" \
        --entry-text="${DEFAULT_MIXES}"); then
        log "ERROR" "Number of mixes input cancelled or failed"
        return 1
    fi
    
    if [[ -z "$num_mixes" ]]; then
        log "ERROR" "Number of mixes not provided"
        return 1
    fi
    
    # Validate number of mixes
    if ! [[ "$num_mixes" =~ ^[0-9]+$ ]] || [[ "$num_mixes" -lt 1 ]]; then
        log "ERROR" "Invalid number of mixes. Please enter a positive number"
        return 1
    fi
    
    # Cap at maximum
    if [[ "$num_mixes" -gt "$MAX_MIXES" ]]; then
        num_mixes=$MAX_MIXES
        log "WARNING" "Requested mixes exceed maximum. Capped at $MAX_MIXES"
    fi
    
    # Write to temporary file
    echo "$num_mixes" > "$temp_mixes_file"
    
    return 0
}

# Show progress bar
show_progress() {
    local total="$1"
    
    # Use progress bar from zenity
    (
        # Set initial progress
        echo "# Starting processing..."
        echo "0"
        
        # Monitor stats file for changes
        while true; do
            sleep 0.5
            
            if [[ -f "$STATS_FILE" ]]; then
                # Extract current mix number - use grep with -m1 to avoid getting multiple matches
                current=$(grep -m1 -o '"current_mix": "[0-9]*"' "$STATS_FILE" 2>/dev/null | grep -o '[0-9]*' || echo "0")
                status=$(grep -m1 -o '"status": "[^"]*"' "$STATS_FILE" 2>/dev/null | cut -d'"' -f4 || echo "waiting")
                mix_id=$(grep -m1 -o '"mix_id": "[^"]*"' "$STATS_FILE" 2>/dev/null | cut -d'"' -f4 || echo "")
                
                if [[ -n "$current" && "$current" != "0" && -n "$total" && "$total" != "0" ]]; then
                    # Calculate percentage - ensure current is between 1 and total
                    current=$(( current > total ? total : current ))
                    current=$(( current < 1 ? 1 : current ))
                    
                    # Calculate percentage with special handling for first and last mix
                    percent=0
                    if [[ "$current" -eq "$total" && "$status" == "complete" ]]; then
                        percent=100
                    elif [[ "$current" -eq 1 ]]; then
                        # First mix starts at 5%
                        percent=$(( status == "complete" ? 15 : 5 ))
                    else
                        # Other mixes evenly distributed between 15% and 95%
                        percent=$(( 15 + ((current - 1) * 80 / (total - 1)) ))
                    fi
                    
                    echo "# Processing mix $current of $total ${mix_id:+($mix_id)}: $status"
                    echo "$percent"
                    
                    # Exit loop when all mixes are complete
                    if [[ "$status" == "complete" && "$current" -eq "$total" ]]; then
                        echo "# Processing complete"
                        echo "100"
                        break
                    fi
                    
                    # Exit loop on error
                    if [[ "$status" == "error" ]]; then
                        echo "# Error occurred in processing"
                        break
                    fi
                fi
            else
                echo "# Initializing..."
                echo "0"
            fi
        done
    ) | zenity --progress \
       --title="Processing Doomer Mixes" \
       --text="Starting processing..." \
       --percentage=0 \
       --auto-close
    
    return 0
}

#------------------------------------------------------------------------------
# Main Program
#------------------------------------------------------------------------------

main() {
    # Initialize stats
    mkdir -p "$TEMP_DIR"
    update_stats "status" "starting"
    update_stats "version" "$SCRIPT_VERSION"
    
    # Initialize log file
    : > "$LOG_FILE"
    
    # Welcome message
    log "INFO" "========================================================"
    log "INFO" "${SCRIPT_NAME} v${SCRIPT_VERSION}"
    log "INFO" "========================================================"
    log "DEBUG" "Debug level: $DEBUG_LEVEL"
    log "DEBUG" "Temporary directory: $TEMP_DIR"
    log "DEBUG" "Log file: $LOG_FILE"
    
    # System information
    log "DEBUG" "System information:"
    execute_cmd "uname -a"
    execute_cmd "df -h \"$SCRIPT_DIR\""
    
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
    
    # Get input file using the temporary file method
    local input_file
    local temp_path_file="${TEMP_DIR}/selected_input_path.txt"
    
    if ! select_input_file_gui; then
        exit 1
    fi
    
    # Read the path from the temporary file
    if [[ ! -f "$temp_path_file" ]]; then
        log "ERROR" "Path file not created"
        exit 1
    fi
    
    input_file=$(cat "$temp_path_file")
    rm -f "$temp_path_file"  # Clean up the temporary file
    
    # Clean the file path to be absolutely sure
    input_file=$(echo "$input_file" | sed 's/\x1b\[[0-9;]*m//g')
    log "INFO" "Processing file: $input_file"
    
    # Validate input file with simple direct check first
    if [[ ! -f "$input_file" ]]; then
        log "ERROR" "Input file does not exist: $input_file"
        zenity --error --title="File Not Found" \
            --text="The selected file cannot be found.\nPlease select a different audio file."
        exit 1
    fi
    
    # Now do the full validation
    if ! check_file "$input_file" "Input audio"; then
        zenity --error --title="Invalid File" \
            --text="The selected file appears to be invalid or does not exist.\nPlease select a different audio file."
        exit 1
    fi
    
    # Test file with ffmpeg
    log "DEBUG" "Testing input file with ffmpeg"
    if ! execute_cmd "ffmpeg -v error -i \"$input_file\" -f null -"; then
        log "ERROR" "The input file appears to be corrupt or not a valid audio file"
        zenity --error --title="Invalid File" \
            --text="The selected file appears to be corrupt or not a valid audio file.\nPlease select a different audio file."
        exit 1
    fi
    
    # Get output folder
    local output_folder
    local temp_folder_file="${TEMP_DIR}/selected_output_folder.txt"
    
    if ! select_output_folder_gui; then
        exit 1
    fi
    
    # Read the folder from the temporary file
    if [[ ! -f "$temp_folder_file" ]]; then
        log "ERROR" "Output folder file not created"
        exit 1
    fi
    
    output_folder=$(cat "$temp_folder_file")
    rm -f "$temp_folder_file"  # Clean up
    
    # Clean and validate
    output_folder=$(echo "$output_folder" | sed 's/\x1b\[[0-9;]*m//g')
    
    # Get number of mixes
    local num_mixes
    local temp_mixes_file="${TEMP_DIR}/selected_mixes.txt"
    
    if ! get_num_mixes_gui; then
        exit 1
    fi
    
    # Read the number from the temporary file
    if [[ ! -f "$temp_mixes_file" ]]; then
        log "ERROR" "Number of mixes file not created"
        exit 1
    fi
    
    num_mixes=$(cat "$temp_mixes_file")
    rm -f "$temp_mixes_file"  # Clean up
    
    # Get base filename without extension
    local filename
    filename=$(basename -- "$input_file")
    local filename_no_ext="${filename%.*}"
    
    # Calculate total mixes
    local total_mixes=$((num_mixes < MAX_MIXES ? num_mixes : MAX_MIXES))
    
    log "INFO" "Starting processing of $total_mixes mixes..."
    log "DEBUG" "Using input file: $input_file"
    log "DEBUG" "Output folder: $output_folder"
    log "DEBUG" "Base filename: $filename_no_ext"
    
    # Initialize counters
    local successful_mixes=0
    local failed_mixes=0
    
    update_stats "input_file" "$input_file"
    update_stats "output_folder" "$output_folder"
    update_stats "total_mixes" "$total_mixes"
    
    # Process single mix directly (no progress bar)
    if [[ "$total_mixes" -eq 1 ]]; then
        log "INFO" "Processing single mix directly"
        
        if process_mix "$input_file" "$output_folder" "$filename_no_ext" \
                      "${DEFAULT_SPEEDS[0]}" "${DEFAULT_REVERB_LEVELS[0]}" "${DEFAULT_LOWPASS_FREQS[0]}" \
                      1 1; then
            successful_mixes=$((successful_mixes + 1))
        else
            failed_mixes=$((failed_mixes + 1))
        fi
        
        if [[ "$successful_mixes" -eq 1 ]]; then
            log "SUCCESS" "Processing complete. Generated 1 mix in: $output_folder"
            zenity --info --title="Doomer Mix Ready" \
                --text="Successfully generated 1 mix in folder:\n${output_folder}\n\nLog file: ${LOG_FILE}"
        else
            log "ERROR" "Failed to process the mix"
            zenity --error --title="Processing Failed" \
                --text="Failed to generate the mix.\nCheck the log file for details: ${LOG_FILE}"
        fi
    else
        # Process multiple mixes with progress tracking
        log "INFO" "Processing $total_mixes mixes with progress bar"

        # Initialize stats to starting state
        update_stats "current_mix" "0"  
        update_stats "status" "starting"
        
        # Start progress monitoring in background
        show_progress "$total_mixes" &
        local progress_pid=$!
        
        # Create combinations of effects
        local combinations=()
        for speed in "${DEFAULT_SPEEDS[@]}"; do
            for reverb in "${DEFAULT_REVERB_LEVELS[@]}"; do
                for lowpass in "${DEFAULT_LOWPASS_FREQS[@]}"; do
                    combinations+=("$speed $reverb $lowpass")
                done
            done
        done
        
        # Process files sequentially with better tracking
        local current_mix=0
        local mix_count=${#combinations[@]}
        
        for (( i=0; i<total_mixes && i<mix_count; i++ )); do
            # Get the current combination
            IFS=' ' read -r speed reverb lowpass <<< "${combinations[$i]}"
            current_mix=$((i + 1))
            
            log "INFO" "Processing mix $current_mix of $total_mixes"
            
            # Process current mix
            if process_mix "$input_file" "$output_folder" "$filename_no_ext" \
                           "$speed" "$reverb" "$lowpass" \
                           "$current_mix" "$total_mixes"; then
                successful_mixes=$((successful_mixes + 1))
            else
                failed_mixes=$((failed_mixes + 1))
            fi
        done
        
        # Wait for progress dialog to close
        if [[ -n "$progress_pid" ]]; then
            wait "$progress_pid" 2>/dev/null || true
        fi
        
        # Show completion message
        if [[ "$failed_mixes" -gt 0 ]]; then
            log "WARNING" "$failed_mixes mix(es) failed to process"
            zenity --warning --title="Processing Complete with Warnings" \
                --text="$failed_mixes mix(es) failed to process.\nSuccessfully generated $successful_mixes mixes in folder:\n${output_folder}\n\nCheck the log file for details: ${LOG_FILE}"
        else
            log "SUCCESS" "Processing complete. Generated $successful_mixes mixes in: $output_folder"
            zenity --info --title="Doomer Mixes Ready" \
                --text="Successfully generated ${successful_mixes} mixes in folder:\n${output_folder}\n\nLog file: ${LOG_FILE}"
        fi
    fi
    
    # Show completion in terminal
    log "INFO" "Processing complete. Output files are in: $output_folder"
    log "INFO" "Log file available at: $LOG_FILE"
    
    # Cleanup
    update_stats "status" "finished"
    update_stats "successful_mixes" "$successful_mixes"
    update_stats "failed_mixes" "$failed_mixes"
    
    return 0
}

#------------------------------------------------------------------------------
# Parameter Processing
#------------------------------------------------------------------------------

# Process command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--debug)
            DEBUG_LEVEL=1
            shift
            ;;
        -v|--verbose)
            DEBUG_LEVEL=2
            shift
            ;;
        -k|--keep-temp)
            KEEP_TEMP=1
            shift
            ;;
        -q|--quality)
            AUDIO_QUALITY="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Set up error handling
trap 'error_handler ${LINENO} $?' ERR
trap 'cleanup' EXIT

# Start the program
main

exit 0

