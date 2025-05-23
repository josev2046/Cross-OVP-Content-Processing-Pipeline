#!/bin/bash

# Cross-OVP Content Processing Pipeline
# This script automates the acquisition and preparation of video content from Kaltura for platforms like Vimeo.
# It streamlines the workflow of downloading specific Kaltura entries and re-encoding them to ensure optimal
# compatibility and performance on target video hosting services, with a focus on British English conventions.

# --- Configuration ---
# IMPORTANT: Update these variables with your specific Kaltura details and desired content.

# Your Kaltura Partner ID (numerical identifier for your Kaltura account).
PARTNER_ID="YOUR_KALTURA_PARTNER_ID"

# Your Kaltura User Secret (used for API authentication).
# SECURITY WARNING: For production systems, avoid hardcoding secrets. Consider using environment variables
# or a dedicated secret management solution.
USER_SECRET="YOUR_KALTURA_USER_SECRET"

# Associative array mapping desired local filenames to their unique Kaltura Entry IDs.
# You must populate this array with your specific content data.
declare -A KALTURA_ENTRIES=(
    ["My_Series_Episode_01"]="1_abcdef12"   # Key is local desired filename, Value is Kaltura Entry ID
    ["My_Series_Episode_02"]="1_ghijkl34"
    # Example: ["Another_Video_Title"]="1_xyz12345"
    # ... add all your relevant entries here
)

# The name of the folder that the script will create on your Desktop to store
# both the original downloaded MP4s and the Vimeo-compatible re-encoded versions.
OUTPUT_ROOT_DIR="Kaltura_Content_For_Vimeo"

# --- End Configuration ---

# --- Global Variables ---
KALTURA_API_URL="https://cdnapisec.kaltura.com/api_v3/index.php"
OUTPUT_BASE_PATH="$HOME/Desktop/$OUTPUT_ROOT_DIR"
LOG_FILE="$OUTPUT_BASE_PATH/script_log_$(date +%Y%m%d_%H%M%S).log"

# --- Functions ---

# Function to log messages to stdout and a log file
log_message() {
    local type="$1" # INFO, WARN, ERROR
    local message="$2"
    echo "$(date +%Y-%m-%d\ %H:%M:%S) [$type] $message" | tee -a "$LOG_FILE"
}

# Function to check for required command-line tools
check_tool() {
    local tool_name="$1"
    if ! command -v "$tool_name" &> /dev/null; then
        log_message "ERROR" "$tool_name is not installed or not in your PATH. Please install it as per the Prerequisites section."
        exit 1
    fi
    log_message "INFO" "Found $tool_name."
}

# Function to get a Kaltura session token
get_kaltura_session_token() {
    local partner_id="$1"
    local user_secret="$2"

    log_message "INFO" "Attempting to get Kaltura session token..."
    local response=$(curl -s -X POST \
        "$KALTURA_API_URL?service=session&action=start&partnerId=$partner_id&secret=$user_secret&type=2") # type=2 for user session

    local token=$(echo "$response" | jq -r '.result.ks')

    if [ "$token" == "null" ] || [ -z "$token" ]; then
        local error_message=$(echo "$response" | jq -r '.error.message')
        if [ "$error_message" == "null" ]; then
            error_message="Unknown error during session token retrieval."
        fi
        log_message "ERROR" "Failed to get Kaltura session token. Reason: $error_message. Please check your PARTNER_ID and USER_SECRET."
        return 1
    fi

    log_message "INFO" "Successfully obtained Kaltura session token."
    echo "$token"
    return 0
}

# Function to get Kaltura entry details and MP4 flavour URL
get_kaltura_entry_url() {
    local entry_id="$1"
    local ks="$2"
    local flavor_params_id="100" # Common ID for default MP4 flavours suitable for web/mobile

    log_message "INFO" "Fetching details for Kaltura entry ID: $entry_id..."
    local response=$(curl -s -X POST \
        "$KALTURA_API_URL?service=flavorAsset&action=getByEntryId&entryId=$entry_id&ks=$ks")

    local flavour_asset=$(echo "$response" | jq -r ".result[] | select(.flavorParamsId == $flavor_params_id and .fileExt == \"mp4\" and .status == 2)") # status 2 means ready

    if [ -z "$flavour_asset" ]; then
        local error_message=$(echo "$response" | jq -r '.error.message')
        if [ "$error_message" == "null" ]; then
            error_message="No suitable MP4 flavour (flavorParamsId: $flavor_params_id) found for entry ID: $entry_id. It might not be processed yet, or a different flavour ID is required."
        fi
        log_message "WARN" "$error_message"
        return 1
    fi

    local url=$(echo "$flavour_asset" | jq -r '.url')
    local original_filename=$(echo "$flavour_asset" | jq -r '.originalFileName')

    if [ -z "$url" ]; then
        log_message "WARN" "MP4 flavour found for entry ID: $entry_id, but its URL is missing."
        return 1
    fi

    log_message "INFO" "Found MP4 flavour URL for entry ID $entry_id: $url"
    echo "$url"
    return 0
}

# --- Main Script Execution ---

log_message "INFO" "Starting Cross-OVP Content Processing Pipeline."

# Create output directories
mkdir -p "$OUTPUT_BASE_PATH/Originals" || { log_message "ERROR" "Failed to create directory: $OUTPUT_BASE_PATH/Originals"; exit 1; }
mkdir -p "$OUTPUT_BASE_PATH/Vimeo_Optimised" || { log_message "ERROR" "Failed to create directory: $OUTPUT_BASE_PATH/Vimeo_Optimised"; exit 1; }
log_message "INFO" "Output directories created: $OUTPUT_BASE_PATH/Originals and $OUTPUT_BASE_PATH/Vimeo_Optimised"

# Check for required tools
check_tool "curl"
check_tool "jq"
check_tool "ffmpeg"
check_tool "ffprobe"

# Get Kaltura session token
KALTURA_SESSION_TOKEN=$(get_kaltura_session_token "$PARTNER_ID" "$USER_SECRET")
if [ $? -ne 0 ]; then
    log_message "ERROR" "Aborting script due to Kaltura session error."
    exit 1
fi

# Process each entry in the KALTURA_ENTRIES array
for local_filename in "${!KALTURA_ENTRIES[@]}"; do
    entry_id="${KALTURA_ENTRIES[$local_filename]}"
    log_message "INFO" "--- Processing Entry: $local_filename (Kaltura ID: $entry_id) ---"

    DOWNLOAD_PATH="$OUTPUT_BASE_PATH/Originals/${local_filename}_original.mp4"
    VIMEO_PATH="$OUTPUT_BASE_PATH/Vimeo_Optimised/${local_filename}_Vimeo.mp4"

    # Step 1: Get MP4 flavour URL from Kaltura
    MP4_URL=$(get_kaltura_entry_url "$entry_id" "$KALTURA_SESSION_TOKEN")
    if [ $? -ne 0 ]; then
        log_message "WARN" "Skipping processing for '$local_filename' due to URL retrieval failure."
        continue
    fi

    # Step 2: Download the original MP4
    if [ -f "$DOWNLOAD_PATH" ]; then
        log_message "INFO" "Original file '$DOWNLOAD_PATH' already exists. Skipping download."
    else
        log_message "INFO" "Downloading original MP4 from Kaltura to '$DOWNLOAD_PATH'..."
        curl -s -o "$DOWNLOAD_PATH" "$MP4_URL"
        if [ $? -ne 0 ]; then
            log_message "ERROR" "Failed to download '$MP4_URL'. Skipping conversion for this entry."
            continue
        fi
        if [ ! -s "$DOWNLOAD_PATH" ]; then # Check if file is empty
            log_message "ERROR" "Downloaded file '$DOWNLOAD_PATH' is empty. Download likely failed. Skipping conversion."
            rm -f "$DOWNLOAD_PATH" # Clean up empty file
            continue
        fi
        log_message "INFO" "Download complete for '$local_filename'."
    fi

    # Step 3: Analyse original video for dynamic FFmpeg parameters
    log_message "INFO" "Analysing original video '$DOWNLOAD_PATH' with ffprobe..."
    VIDEO_INFO=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$DOWNLOAD_PATH")
    
    if [ -z "$VIDEO_INFO" ]; then
        log_message "ERROR" "Could not get video stream information from '$DOWNLOAD_PATH'. Is it a valid video file? Skipping conversion."
        continue
    fi

    WIDTH=$(echo "$VIDEO_INFO" | sed -n '1p')
    HEIGHT=$(echo "$VIDEO_INFO" | sed -n '2p')
    FPS_NUMERATOR=$(echo "$VIDEO_INFO" | sed -n '3p' | cut -d'/' -f1)
    FPS_DENOMINATOR=$(echo "$VIDEO_INFO" | sed -n '3p' | cut -d'/' -f2)

    # Calculate integer frame rate, handling potential division by zero
    if [ -z "$FPS_NUMERATOR" ] || [ -z "$FPS_DENOMINATOR" ] || [ "$FPS_DENOMINATOR" -eq 0 ]; then
        log_message "WARN" "Could not determine original frame rate for '$local_filename'. Defaulting to 25fps."
        SOURCE_FPS="25" # Default to 25fps if detection fails or is zero
    else
        SOURCE_FPS=$(awk "BEGIN {printf \"%.0f\", $FPS_NUMERATOR / $FPS_DENOMINATOR}")
        # Ensure FPS is a reasonable positive number, default if not.
        if (( $(echo "$SOURCE_FPS <= 0" | bc -l) )); then
            log_message "WARN" "Calculated frame rate is invalid ($SOURCE_FPS). Defaulting to 25fps."
            SOURCE_FPS="25"
        fi
    fi

    log_message "INFO" "Detected original resolution: ${WIDTH}x${HEIGHT}, Frame Rate: ${SOURCE_FPS}fps."

    # Determine optimal output resolution. Prioritise 1080p if source is lower or similar.
    # If source is higher than 1080p, scale down to 1080p. If source is 720p or lower, upscale to 1080p.
    OUTPUT_RESOLUTION="1920:1080" # Default to 1080p (Vimeo preferred)
    if (( WIDTH > 1920 || HEIGHT > 1080 )); then
        # If source is > 1080p, scale down to 1080p to meet Vimeo's typical ingestion resolution.
        # This preserves quality more than blindly upscaling.
        OUTPUT_RESOLUTION="1920:-2" # Maintain aspect ratio, width 1920
        log_message "INFO" "Source resolution is higher than 1080p. Scaling down to 1920px width."
    elif (( WIDTH < 1280 || HEIGHT < 720 )); then
        # If source is very low res, upscale to 1080p for better presentation on Vimeo.
        log_message "INFO" "Source resolution is very low. Upscaling to 1920x1080."
    fi

    # Calculate keyframe interval: 2 seconds of frames, rounded up.
    KEYFRAME_INTERVAL=$((SOURCE_FPS * 2))
    if [ "$KEYFRAME_INTERVAL" -eq 0 ]; then KEYFRAME_INTERVAL=48; fi # Fallback if FPS is 0 or low

    # Step 4: Re-encode for Vimeo using FFmpeg
    if [ -f "$VIMEO_PATH" ]; then
        log_message "INFO" "Vimeo-optimised file '$VIMEO_PATH' already exists. Skipping re-encoding."
    else
        log_message "INFO" "Re-encoding '$local_filename' for Vimeo compatibility..."
        ffmpeg -i "$DOWNLOAD_PATH" \
            -c:v libx264 \
            -crf 18 \                # Constant Rate Factor for quality: 18 (high quality), 23 (default)
            -preset medium \         # H.264 encoding speed/compression: medium (good balance)
            -profile:v high \        # H.264 profile: high (Vimeo recommended)
            -pix_fmt yuv420p \       # Pixel format: yuv420p (most compatible)
            -vf "scale=$OUTPUT_RESOLUTION:flags=lanczos" \ # Video filter for scaling, lanczos for quality
            -r "$SOURCE_FPS" \       # Maintain original frame rate (or closest integer)
            -g "$KEYFRAME_INTERVAL" \ # Keyframe interval (e.g., 2 seconds of frames)
            -keyint_min "$((KEYFRAME_INTERVAL / 2))" \ # Minimum keyframe interval
            -sc_threshold 0 \        # Disable scene change detection for consistent keyframe interval
            -c:a aac \               # Audio codec: AAC
            -b:a 320k \              # Audio bitrate: 320kbps (Vimeo recommended)
            -movflags +faststart \   # Optimise for web playback (metadata at start)
            -y "$VIMEO_PATH"         # Overwrite output file if it exists (-y)
        
        if [ $? -ne 0 ]; then
            log_message "ERROR" "FFmpeg re-encoding failed for '$local_filename'. Check FFmpeg output above."
            rm -f "$VIMEO_PATH" # Clean up potentially corrupted output
            continue
        fi
        log_message "INFO" "Re-encoding complete for '$local_filename'. Output: '$VIMEO_PATH'."
    fi
done

log_message "INFO" "Cross-OVP Content Processing Pipeline finished."
log_message "INFO" "Check '$LOG_FILE' for detailed execution logs."

exit 0
