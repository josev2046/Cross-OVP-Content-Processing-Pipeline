#!/bin/bash

# --- Configuration ---
# Your Kaltura Partner ID
PARTNER_ID="YOUR_KALTURA_PARTNER_ID" # e.g., "1234567"

# Your Kaltura User Secret (SECURITY WARNING: Replace with secure handling in production)
USER_SECRET="YOUR_KALTURA_USER_SECRET" # e.g., "abcdef1234567890abcdef1234567890"

# Kaltura API Service URL (usually remains the same for most Kaltura instances)
SERVICE_URL="https://www.kaltura.com/api_v3/index.php"

# Map of desired local filenames (Base Name) to their corresponding Kaltura Entry IDs.
# IMPORTANT: Populate this with your actual content data.
# Each entry should be on a new line.
# Format: ["My_Local_File_Name_001"]="1_kalturaEntryIdXYZ"
declare -A KALTURA_ENTRIES=(
    ["My_Video_Project_A_001"]="1_abcdef12"
    ["My_Video_Project_A_002"]="1_ghijkl34"
    ["My_Video_Project_B_Part1"]="1_mnopqr56"
    # Add all your actual content mappings here.
    # The "1_" prefix is typically part of the Kaltura Entry ID.
)

# Directory where downloaded original MP4s and Vimeo-compatible MP4s will be stored.
# This folder will be created on your Desktop if it doesn't exist.
OUTPUT_ROOT_DIR="Kaltura_Content_For_Vimeo"

# --- Pre-requisite Checks ---

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is not installed."
    echo "jq is a lightweight and flexible command-line JSON processor."
    echo "Please install it: brew install jq (macOS) or sudo apt-get install jq (Ubuntu/Debian)."
    echo "For Windows, download from https://stedolan.github.io/jq/download/."
    exit 1
fi

# Check for ffmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "Error: 'ffmpeg' is not installed."
    echo "Please install ffmpeg to run this script."
    echo "  macOS (Homebrew): brew install ffmpeg"
    echo "  Ubuntu/Debian: sudo apt-get update && sudo apt-get install ffmpeg"
    echo "  Windows: Download from ffmpeg.org and add to PATH, or use a tool like Scoop or Chocolatey."
    exit 1
fi

# Create output directory if it doesn't exist and navigate into it
mkdir -p "$HOME/Desktop/$OUTPUT_ROOT_DIR" || { echo "Failed to create output directory. Exiting."; exit 1; }
cd "$HOME/Desktop/$OUTPUT_ROOT_DIR" || { echo "Failed to change directory to $HOME/Desktop/$OUTPUT_ROOT_DIR. Exiting."; exit 1; }

echo "Working directory: $(pwd)"

# --- Step 1: Get a Kaltura Session (KS) Token ---
echo "Attempting to get Kaltura session token..."
KS_RESPONSE=$(curl -s -X POST \
  "${SERVICE_URL}?service=session&action=start&format=1" \
  -d "secret=${USER_SECRET}&partnerId=${PARTNER_ID}&type=0")

# Remove any leading/trailing quotes from the response, if present.
KS_TOKEN=$(echo "$KS_RESPONSE" | sed 's/^"//;s/"$//')

if [ -z "$KS_TOKEN" ]; then
  echo "Failed to get Kaltura session token. The response was empty."
  echo "Full response was: '$KS_RESPONSE'"
  echo "Please verify PARTNER_ID and USER_SECRET in the script's configuration."
  exit 1
fi

echo "Successfully obtained Kaltura Session Token: ${KS_TOKEN:0:10}..." # Print first 10 chars for brevity

# --- Step 2: Iterate through entries, download original MP4s ---
echo "---"
echo "Starting download of original MP4 files from Kaltura..."

for BASE_NAME in "${!KALTURA_ENTRIES[@]}"; do
  ENTRY_ID="${KALTURA_ENTRIES[$BASE_NAME]}" # Get the corresponding Kaltura ID
  ORIGINAL_MP4_FILENAME="${BASE_NAME}_original.mp4" # Name for the downloaded original file

  echo "Processing download for: ${BASE_NAME} (Kaltura ID: ${ENTRY_ID})..."

  # Get flavor assets for the current entry (response is JSON)
  FLAVORS_RESPONSE=$(curl -s -X POST \
    "${SERVICE_URL}?service=flavorasset&action=getByEntryId&format=1&entryId=${ENTRY_ID}&ks=${KS_TOKEN}")

  # Check if the response contains an error (e.g., ENTRY_ID_NOT_FOUND)
  if echo "$FLAVORS_RESPONSE" | jq -e 'has("code")' &>/dev/null; then
    ERROR_CODE=$(echo "$FLAVORS_RESPONSE" | jq -r '.code')
    ERROR_MESSAGE=$(echo "$FLAVORS_RESPONSE" | jq -r '.message')
    echo "  Kaltura API Error for entry ${ENTRY_ID}: ${ERROR_CODE} - ${ERROR_MESSAGE}. Skipping download."
    continue # Skip to the next entry
  fi

  # Find the best MP4 flavor ID. Prioritize `flavorParamsId` 100 (often web/mobile),
  # then any other MP4 if 100 isn't available.
  MP4_FLAVOR_ID=$(echo "$FLAVORS_RESPONSE" | jq -r '.[] | select(.fileExt=="mp4" and .flavorParamsId=="100") | .id')

  if [ -z "$MP4_FLAVOR_ID" ] || [ "$MP4_FLAVOR_ID" == "null" ]; then
    # Fallback: if flavorParamsId 100 isn't found, get any MP4 flavor.
    MP4_FLAVOR_ID=$(echo "$FLAVORS_RESPONSE" | jq -r '.[] | select(.fileExt=="mp4") | .id' | head -n 1)
  fi

  if [ -z "$MP4_FLAVOR_ID" ] || [ "$MP4_FLAVOR_ID" == "null" ]; then
    echo "  No MP4 flavor found for entry ${ENTRY_ID}. Skipping download."
    continue # Skip to the next entry
  fi

  echo "  Found MP4 Flavor ID: ${MP4_FLAVOR_ID}"

  # Construct the direct download URL for the MP4 flavor
  DOWNLOAD_URL="https://www.kaltura.com/p/${PARTNER_ID}/sp/${PARTNER_ID}00/playManifest/entryId/${ENTRY_ID}/flavorId/${MP4_FLAVOR_ID}/format/url/protocol/https?ks=${KS_TOKEN}"
  
  echo "  Downloading to: ${ORIGINAL_MP4_FILENAME}"
  curl -L -o "$ORIGINAL_MP4_FILENAME" "$DOWNLOAD_URL"

  if [ $? -eq 0 ]; then
    echo "  Download successful for ${BASE_NAME} (Kaltura ID: ${ENTRY_ID})"
  else
    echo "  Download failed for ${BASE_NAME} (Kaltura ID: ${ENTRY_ID})."
  fi
  echo "---"
done

echo "All downloads attempted."

# --- Step 3: Re-encode downloaded MP4s for Vimeo compatibility ---
echo "---"
echo "Starting re-encoding of downloaded MP4 files for Vimeo compatibility..."

# Loop through the downloaded original MP4 files
# Use a wildcard to ensure we process only the files that were actually downloaded
for f in *_original.mp4; do
    if [ -f "$f" ]; then # Ensure the file exists
        VIMEO_MP4_FILENAME="${f%_original.mp4}_Vimeo.mp4" # Create new name: e.g., My_Video_Project_A_001_Vimeo.mp4
        
        echo "Processing re-encode: ${f} -> ${VIMEO_MP4_FILENAME}"

        # Run the ffmpeg command for Vimeo compatibility
        # -y: overwrite output files without asking
        ffmpeg -y -i "$f" \
               -c:v libx264 -tune stillimage -pix_fmt yuv420p -crf 23 \
               -c:a aac -b:a 320k -ar 48000 \
               "$VIMEO_MP4_FILENAME"

        # Check ffmpeg's exit status
        if [ $? -eq 0 ]; then
            echo "  Successfully converted ${f} to ${VIMEO_MP4_FILENAME}"
        else
            echo "  Error converting ${f}. Please check ffmpeg output above for details."
        fi
        echo "---"
    fi
done

echo "All re-encodings attempted."
echo "You can find your original and Vimeo-ready MP4 files in the '$(pwd)' directory."

# Navigate back to the original directory (optional, but good practice)
cd - > /dev/null
