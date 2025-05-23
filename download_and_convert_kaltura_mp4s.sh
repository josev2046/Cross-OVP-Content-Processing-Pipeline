#!/bin/bash

# Cross-OVP Content Processing Pipeline
# This script automates the acquisition and preparation of video content from Kaltura for platforms like Vimeo.
# It streamlines the workflow of downloading specific Kaltura entries and re-encoding them to ensure optimal
# compatibility and performance on target video hosting services.

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

# Path to a static image file (e.g., a logo, title card, or black background)
# This image will be used as the video stream for your audio-only MP4s.
# If left empty or the file doesn't exist, a plain black 1080p image will be generated.
STATIC_IMAGE_PATH="" # e.g., "$HOME/Desktop/My_Logo.png"

# --- End Configuration ---

# --- Global Variables ---
KALTURA_API_URL="https://cdnapisec.kaltura.com/api_v3/index.php"
OUTPUT_BASE_PATH="$HOME/Desktop/$OUTPUT_ROOT_DIR"
LOG_FILE="$OUTPUT_BASE_PATH/script_log_$(date +%Y%m%d_%H%M%S).log"
DEFAULT_STATIC_IMAGE="$OUTPUT_BASE_PATH/black_background_1920x1080.png"

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

    # Filter for MP4 files with status 2 (ready)
    # We are now expecting these to be audio-only MP4s
    local flavour_asset=$(echo "$response" | jq -r ".result[] | select(.fileExt == \"mp4\" and .status == 2)")

    if [ -z "$flavour_asset" ]; then
        local error_message=$(echo "$response" | jq -r '.error.message')
        if [ "$error_message" == "null" ]; then
            error_message="No suitable MP4 flavour found for entry ID: $entry_id. It might not be processed yet, or no MP4 audio derivative exists."
        fi
        log_message "WARN" "$error_message"
        return 1
    fi

    local url=$(echo "$flavour_asset" | jq -r '.url')
    
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
check_tool "ffprobe" # Still good to have for general debugging, though not used for input video stream analysis here

# Prepare static image for video stream
CURRENT_STATIC_IMAGE_PATH="$STATIC_IMAGE_PATH"
if [ -z "$CURRENT_STATIC_IMAGE_PATH" ] || [ ! -f "$CURRENT_STATIC_IMAGE_PATH" ]; then
    log_message "INFO" "Static image path not set or file not found. Generating a default black background image: $DEFAULT_STATIC_IMAGE"
    ffmpeg -y -f lavfi -i "color=c=black:s=1920x1080:r=1" -vframes 1 "$DEFAULT_STATIC_IMAGE" &> /dev/null
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to generate default black background image. Please ensure FFmpeg is working correctly and you have write permissions. Aborting."
        exit 1
    fi
    CURRENT_STATIC_IMAGE_PATH="$DEFAULT_STATIC_IMAGE"
else
    log_message "INFO" "Using provided static image: $CURRENT_STATIC_IMAGE_PATH"
fi


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

    DOWNLOAD_PATH="$OUTPUT_BASE_PATH/Originals/${local_filename}_original_audio.mp4" # Renamed for clarity
    VIMEO_PATH="$OUTPUT_BASE_PATH/Vimeo_Optimised/${local_filename}_Vimeo.mp4"

    # Step 1: Get MP4 flavour URL from Kaltura (which will be audio-only)
    MP4_URL=$(get_kaltura_entry_url "$entry_id" "$KALTURA_SESSION_TOKEN")
    if [ $? -ne 0 ]; then
        log_message "WARN" "Skipping processing for '$local_filename' due to URL retrieval failure."
        continue
    fi

    # Step 2: Download the original audio-only MP4
    if [ -f "$DOWNLOAD_PATH" ]; then
        log_message "INFO" "Original audio file '$DOWNLOAD_PATH' already exists. Skipping download."
    else
        log_message "INFO" "Downloading original audio-only MP4 from Kaltura to '$DOWNLOAD_PATH'..."
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

    # Step 3: Create Vimeo-compatible video by combining static image with audio-only MP4
    if [ -f "$VIMEO_PATH" ]; then
        log_message "INFO" "Vimeo-optimised file '$VIMEO_PATH' already exists. Skipping re-encoding."
    else
        log_message "INFO" "Creating Vimeo-compatible video for '$local_filename' by combining static image and audio..."
        
        # FFmpeg command to combine static image and audio-only MP4
        ffmpeg -y \
          -loop 1 -i "$CURRENT_STATIC_IMAGE_PATH" \ # Input 1: Static image (loops indefinitely)
          -i "$DOWNLOAD_PATH" \                     # Input 2: Your Kaltura-derived audio-only MP4
          -c:v libx264 \
          -tune stillimage \                        # Optimises H.264 encoding for static images
          -crf 18 \                                 # Video quality for the static image
          -preset medium \
          -profile:v high \
          -level:v 4.0 \                            # H.264 level for 1080p output
          -pix_fmt yuv420p \
          -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,format=yuv420p" \
                                                    # Scale image to 1080p, add black padding if aspect ratio differs.
          -r 25 \                                   # Output frame rate for the video stream (fixed to 25fps for consistency)
          -g 50 \                                   # Keyframe interval (2 seconds at 25fps)
          -keyint_min 25 \                          # Minimum keyframe interval
          -sc_threshold 0 \                         # Disable scene change detection for consistent keyframes
          -force_key_frames "expr:gte(t,n_forced*2)" \ # Alternative/additional way to force keyframes
          -c:a aac \                                # Audio codec: AAC
          -b:a 320k \                               # Audio bitrate: 320kbps (Vimeo recommended)
          -ar 48000 \                               # Audio sample rate: 48 kHz (will resample if input is 44.1kHz)
          -shortest \                               # CRITICAL: Ensures video duration matches the audio's duration
          -movflags +faststart \                    # Place 'moov atom' at beginning. CRITICAL for web video.
          -max_muxing_queue_size 1024 \             # Increase muxing queue size for robustness
          "$VIMEO_PATH"
        
        if [ $? -ne 0 ]; then
            log_message "ERROR" "FFmpeg video creation failed for '$local_filename'. Check FFmpeg output above."
            rm -f "$VIMEO_PATH" # Clean up potentially corrupted output
            continue
        fi
        log_message "INFO" "Video creation complete for '$local_filename'. Output: '$VIMEO_PATH'."
    fi
done

log_message "INFO" "Cross-OVP Content Processing Pipeline finished."
log_message "INFO" "Check '$LOG_FILE' for detailed execution logs."

exit 0
