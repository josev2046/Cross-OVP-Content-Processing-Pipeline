# Cross-OVP Content Processing Pipeline

This repository provides a Bash script designed to automate the acquisition and preparation of video content from Kaltura for platforms like Vimeo. It streamlines the workflow of downloading specific Kaltura entries and re-encoding them to ensure optimal compatibility and performance on target video hosting services.

---

## Features

* **Configurable Kaltura Integration**: Easily set up with your Kaltura Partner ID and User Secret to access your content.
* **Selective Entry Processing**: Specify exactly which Kaltura entries to download using a simple mapping of desired local filenames to their unique Kaltura Entry IDs.
* **Automated MP4 Flavour Retrieval**: Programmatically identifies and downloads the most suitable MP4 flavour for each specified entry from Kaltura's CDN.
* **Vimeo-Optimised Re-encoding**: Utilises FFmpeg with a pre-defined set of parameters (H.264 video, AAC audio, specific quality settings) to create videos highly compatible with Vimeo's ingestion requirements.
* **Clear Output Structure**: Organises processed files into a dedicated directory on your desktop, with original downloads and re-encoded versions clearly distinguished by filename suffixes (`_original.mp4` and `_Vimeo.mp4`).
* **Robust Error Handling**: Includes comprehensive checks for essential command-line tools (`jq`, `ffmpeg`), handles Kaltura API errors (e.g., entry not found, no suitable flavours), and manages file system operations gracefully.

---

## Prerequisites

Before running the script, ensure your system has the following tools installed:

* **`bash`**: The script is written in Bash.
* **`curl`**: For making HTTP requests to the Kaltura API. (Typically pre-installed on macOS/Linux).
* **`jq`**: A lightweight and flexible command-line JSON processor.
    * **macOS**: `brew install jq`
    * **Ubuntu/Debian**: `sudo apt-get update && sudo apt-get install jq`
    * **Windows**: [Download `jq`](https://stedolan.github.io/jq/download/) and add its executable to your system's PATH.
* **`ffmpeg`**: A powerful open-source multimedia framework.
    * **macOS**: `brew install ffmpeg`
    * **Ubuntu/Debian**: `sudo apt-get update && sudo apt-get install ffmpeg`
    * **Windows**: [Download FFmpeg](https://ffmpeg.org/download.html) and add its binaries to your system's PATH.

---

## Configuration

To use the script, you must edit the `download_and_convert_kaltura_mp4s.sh` file and update the following variables within the `--- Configuration ---` section:

* **`PARTNER_ID`**: Your Kaltura **Partner ID**. This is a numerical identifier for your Kaltura account.
* **`USER_SECRET`**: Your Kaltura **User Secret**. This secret key is used for API authentication. **SECURITY WARNING**: For production systems, avoid hardcoding secrets. Consider using environment variables or a dedicated secret management solution.
* **`KALTURA_ENTRIES`**: This is an associative array that defines the relationship between your desired local filenames and the actual Kaltura Entry IDs. **You must populate this array with your specific content data.**
    ```bash
    # Example structure for KALTURA_ENTRIES:
    declare -A KALTURA_ENTRIES=(
        ["My_Series_Episode_01"]="1_abcdef12"   # Key is local desired filename, Value is Kaltura Entry ID
        ["My_Series_Episode_02"]="1_ghijkl34"
        # ... add all your relevant entries here
    )
    ```
    Ensure the Kaltura Entry IDs are correct, often prefixed with `1_` or `0_`.
* **`OUTPUT_ROOT_DIR`**: The name of the folder that the script will create on your Desktop to store both the original downloaded MP4s and the Vimeo-compatible re-encoded versions. Default is `Kaltura_Content_For_Vimeo`.

---

## Usage

1.  **Save the script**: Copy the content of the script into a file named `download_and_convert_kaltura_mp4s.sh`.
2.  **Make it executable**: Open your terminal or command prompt, navigate to where you saved the file, and run:
    ```bash
    chmod +x download_and_convert_kaltura_mp4s.sh
    ```
3.  **Run the script**: Execute the script from your terminal:
    ```bash
    ./download_and_convert_kaltura_mp4s.sh
    ```

The script will provide verbose output on its progress, including download and conversion status for each entry. Upon completion, you'll find your processed video files in the specified `OUTPUT_ROOT_DIR` folder on your Desktop.

---

## Troubleshooting

* **"`jq` is not installed" / "`ffmpeg` is not installed"**: Install the missing tools as per the "Prerequisites" section.
* **"Failed to get Kaltura session token"**:
    * Double-check your `PARTNER_ID` and `USER_SECRET` in the script's configuration.
    * Ensure your `USER_SECRET` has the necessary permissions to start a session and access content.
* **"Kaltura API Error for entry ... ENTRY_ID_NOT_FOUND"**:
    * The Kaltura Entry ID you've provided in the `KALTURA_ENTRIES` array is incorrect or does not exist in the Kaltura account associated with your `PARTNER_ID`.
    * Verify the exact Entry IDs directly from your Kaltura Management Console (KMC).
* **"No MP4 flavour found for entry ..."**:
    * The specified entry might not have a published MP4 flavour.
    * The `flavorParamsId` (defaulting to `100` for common web/mobile MP4s) used by the script might not be available for that specific entry. You might need to inspect the available flavours via the Kaltura API manually if this is a recurring issue.
* **FFmpeg Conversion Errors**:
    * Review the FFmpeg output in your terminal for specific error messages. These can indicate issues with the source file, disk space, or encoding parameters.
