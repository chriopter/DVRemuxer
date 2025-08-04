#!/bin/bash

# DVRemuxer - Dolby Vision profile 7 to 8.1 converter
# Scans for DV files and remuxes DV7 to DV8.1 for better compatibility

# Settings
keepFiles=0
targetDir=$PWD
cleanupMode=0

# Functions
printHelp() {
    echo ""
    echo "DVRemuxer - Scans and converts Dolby Vision profile 7 to 8.1"
    echo ""
    echo "Usage: $0 [OPTIONS] [PATH]"
    echo ""
    echo "Options:"
    echo "  -h, --help         Display this help message"
    echo "  -k, --keep-files   Keep intermediate working files"
    echo "  -c, --cleanup      Cleanup mode: verify and delete original DV7 files"
    echo ""
    echo "Arguments:"
    echo "  PATH              Target directory (default: current directory)"
    echo ""
    echo "Examples:"
    echo "  $0                 Scan current directory and convert DV7 files"
    echo "  $0 /path/to/media  Scan specific directory"
    echo "  $0 -c              Verify conversions and clean up original files"
    echo ""
    echo "Cleanup mode verifies that DV8 + EL_RPU files match original size (±1%)"
    echo "before offering to delete the original DV7 files."
    echo ""
    exit 1
}

# Scan and optionally convert
scanAndConvert() {
    echo "Scanning for DV files in: $targetDir"
    echo ""
    
    # Check for required tools
    which mediainfo >/dev/null 2>&1 || { echo "Error: mediainfo is required. Install with your package manager."; exit 1; }
    which dovi_tool >/dev/null 2>&1 || { echo "Error: dovi_tool is required. Install from https://github.com/quietvoid/dovi_tool"; exit 1; }
    which mkvextract >/dev/null 2>&1 || { echo "Error: mkvextract is required. Install mkvtoolnix."; exit 1; }
    which mkvmerge >/dev/null 2>&1 || { echo "Error: mkvmerge is required. Install mkvtoolnix."; exit 1; }
    
    local startTime=$(date +%s)
    local dv7Count=0
    local dv7Files=()
    
    # Table header
    printf "%-65s %-10s %-10s %-10s\n" "Filename" "Type" "Size" "Status"
    printf "%s\n" "$(printf '%.0s-' {1..95})"
    
    # Find all MKV files
    while IFS= read -r -d '' mkvFile; do
        local mkvBase=$(basename "$mkvFile")
        local fileSize=$(ls -lh "$mkvFile" | awk '{print $5}')
        
        # Skip .DV8.mkv files
        [[ "$mkvBase" == *.DV8.mkv ]] && continue
        
        # Get DV profile
        local dvProfile=$(mediainfo --ParseSpeed=0.0 --Inform="Video;%HDR_Format_Profile%" "$mkvFile" 2>/dev/null)
        [[ -z "$dvProfile" || "$dvProfile" != *"dv"* ]] && continue
        
        # Determine type
        local dvType="DV?"
        if [[ "$dvProfile" == *"dvav.04"* || "$dvProfile" == *"04"* ]]; then
            dvType="DV4"
        elif [[ "$dvProfile" == *"dvhe.05"* || "$dvProfile" == *"05"* ]]; then
            dvType="DV5"
        elif [[ "$dvProfile" == *"dvhe.07"* || "$dvProfile" == *"07"* ]]; then
            dvType="DV7"
        elif [[ "$dvProfile" == *"dvhe.08"* || "$dvProfile" == *"08"* ]]; then
            dvType="DV8"
        elif [[ "$dvProfile" =~ ([0-9]+) ]]; then
            dvType="DV${BASH_REMATCH[1]}"
        fi
        
        # Check conversion status
        if [[ "$dvType" == "DV7" ]]; then
            if [[ -f "${mkvFile%.mkv}.DV8.mkv" ]]; then
                printf "%-65s %-10s %-10s %-10s\n" "${mkvBase:0:63}" "$dvType" "$fileSize" "✓"
                # Show the DV8 child
                local dv8Base=$(basename "${mkvFile%.mkv}.DV8.mkv")
                local dv8Size=$(ls -lh "${mkvFile%.mkv}.DV8.mkv" | awk '{print $5}')
                printf "  └─ %-56s %-10s %-10s %-10s\n" "${dv8Base:0:56}" "DV8.1" "$dv8Size" "✓"
            else
                ((dv7Count++))
                dv7Files+=("$mkvFile")
                printf "%-65s %-10s %-10s %-10s\n" "${mkvBase:0:63}" "$dvType" "$fileSize" "○"
            fi
        else
            printf "%-65s %-10s %-10s %-10s\n" "${mkvBase:0:63}" "$dvType" "$fileSize" "✓"
        fi
    done < <(find "$targetDir" -name "*.mkv" -type f -print0 2>/dev/null | sort -z)
    
    local endTime=$(date +%s)
    local scanTime=$((endTime - startTime))
    
    printf "%s\n" "$(printf '%.0s-' {1..95})"
    printf "Scan completed in %d seconds\n" "$scanTime"
    echo ""
    
    if [[ $dv7Count -eq 0 ]]; then
        echo "No DV7 files need conversion."
        exit 0
    fi
    
    echo "Found $dv7Count DV7 files that need conversion to DV8.1"
    echo -n "Convert them now? [y/N] "
    read -r response
    
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Conversion cancelled."
        exit 0
    fi
    
    echo ""
    convertFiles "${dv7Files[@]}"
}

# Convert DV7 files to DV8.1
convertFiles() {
    local processedFiles=()
    
    echo "Remuxing to DV8.1 (profile 8.1) with CMv4.0 + CMv2.9..."
    
    for mkvFile in "$@"; do
        local mkvDir=$(dirname "$mkvFile")
        local mkvBase=$(basename "$mkvFile" .mkv)
        echo ""
        echo "Processing: $mkvBase"
        echo "========================================="
        
        # Working file names - all in the source directory
        local BL_EL_RPU_HEVC="${mkvDir}/${mkvBase}.BL_EL_RPU.hevc"
        local DV7_EL_RPU_HEVC="${mkvDir}/${mkvBase}.DV7.EL_RPU.hevc"
        local DV8_BL_RPU_HEVC="${mkvDir}/${mkvBase}.DV8.BL_RPU.hevc"
        
        echo "Extracting HEVC stream..."
        mkvextract "$mkvFile" tracks 0:"$BL_EL_RPU_HEVC"
        
        if [[ ! -f "$BL_EL_RPU_HEVC" ]]; then
            echo "ERROR: Failed to extract HEVC track from $mkvFile"
            continue
        fi
        
        echo "Extracting DV7 EL+RPU for archival..."
        dovi_tool demux --el-only "$BL_EL_RPU_HEVC" -e "$DV7_EL_RPU_HEVC"
        
        echo "Converting to DV8.1 (profile 8.1)..."
        dovi_tool -m 2 convert --discard "$BL_EL_RPU_HEVC" -o "$DV8_BL_RPU_HEVC"
        
        if [[ ! -f "$DV8_BL_RPU_HEVC" ]]; then
            echo "ERROR: Failed to convert to DV8.1"
            [[ $keepFiles == 0 ]] && rm -f "$BL_EL_RPU_HEVC" "$DV7_EL_RPU_HEVC"
            continue
        fi
        
        [[ $keepFiles == 0 ]] && rm -f "$BL_EL_RPU_HEVC"
        
        echo "Creating L1 plot..."
        local DV8_RPU_BIN="${mkvDir}/${mkvBase}.DV8.RPU.bin"
        dovi_tool extract-rpu "$DV8_BL_RPU_HEVC" -o "$DV8_RPU_BIN"
        dovi_tool plot "$DV8_RPU_BIN" -o "${mkvDir}/${mkvBase}.DV8.L1_plot.png"
        [[ $keepFiles == 0 ]] && rm -f "$DV8_RPU_BIN"
        
        echo "Remuxing to MKV..."
        mkvmerge -o "${mkvDir}/${mkvBase}.DV8.mkv" -D "$mkvFile" "$DV8_BL_RPU_HEVC" --track-order 1:0
        
        [[ $keepFiles == 0 ]] && rm -f "$DV8_BL_RPU_HEVC"
        
        if [[ -f "${mkvDir}/${mkvBase}.DV8.mkv" ]]; then
            echo "✓ Successfully converted: ${mkvDir}/${mkvBase}.DV8.mkv"
            processedFiles+=("$mkvFile")
        else
            echo "✗ Conversion failed for: $mkvFile"
        fi
    done
    
    # Show completion summary
    if [[ ${#processedFiles[@]} -gt 0 ]]; then
        echo ""
        echo "Successfully converted ${#processedFiles[@]} file(s)."
        echo ""
        echo "To safely clean up original files after verifying conversions:"
        echo "Run: $0 -c"
    fi
    
    echo ""
    echo "Done."
}

# Cleanup verified conversions
cleanupVerifiedFiles() {
    echo "Scanning for verified DV7 to DV8.1 conversions..."
    echo ""
    
    local verifiedFiles=()
    local totalOriginalSize=0
    local totalSavedSpace=0
    
    # Table header
    printf "%-65s %-10s %-10s %-10s\n" "Filename" "Original" "Converted" "Status"
    printf "%s\n" "$(printf '%.0s-' {1..95})"
    
    # Find all DV7 files that have been converted
    while IFS= read -r -d '' mkvFile; do
        local mkvBase=$(basename "$mkvFile")
        local mkvDir=$(dirname "$mkvFile")
        
        # Skip .DV8.mkv files
        [[ "$mkvBase" == *.DV8.mkv ]] && continue
        
        # Check if it's a DV7 file
        local dvProfile=$(mediainfo --ParseSpeed=0.0 --Inform="Video;%HDR_Format_Profile%" "$mkvFile" 2>/dev/null)
        [[ ! "$dvProfile" =~ (dvhe\.07|07) ]] && continue
        
        # Check if converted files exist
        local dv8File="${mkvFile%.mkv}.DV8.mkv"
        local elFile="${mkvFile%.mkv}.DV7.EL_RPU.hevc"
        
        if [[ -f "$dv8File" && -f "$elFile" ]]; then
            # Get file sizes in bytes
            local origSize=$(stat -f%z "$mkvFile" 2>/dev/null || stat -c%s "$mkvFile" 2>/dev/null)
            local dv8Size=$(stat -f%z "$dv8File" 2>/dev/null || stat -c%s "$dv8File" 2>/dev/null)
            local elSize=$(stat -f%z "$elFile" 2>/dev/null || stat -c%s "$elFile" 2>/dev/null)
            local combinedSize=$((dv8Size + elSize))
            
            # Calculate size difference percentage
            local sizeDiff=$(awk -v orig="$origSize" -v comb="$combinedSize" 'BEGIN {
                diff = (orig - comb) / orig * 100;
                printf "%.2f", (diff < 0) ? -diff : diff
            }')
            
            # Display sizes in human-readable format
            local origSizeH=$(ls -lh "$mkvFile" | awk '{print $5}')
            local dv8SizeH=$(ls -lh "$dv8File" | awk '{print $5}')
            
            # Check if within 1% tolerance
            if awk -v diff="$sizeDiff" 'BEGIN {exit !(diff <= 1.0)}'; then
                verifiedFiles+=("$mkvFile")
                totalOriginalSize=$((totalOriginalSize + origSize))
                totalSavedSpace=$((totalSavedSpace + origSize - dv8Size))
                printf "%-65s %-10s %-10s %-10s\n" "${mkvBase:0:63}" "$origSizeH" "$dv8SizeH" "✓ ${sizeDiff}%"
            else
                printf "%-65s %-10s %-10s %-10s\n" "${mkvBase:0:63}" "$origSizeH" "$dv8SizeH" "✗ ${sizeDiff}%"
            fi
        fi
    done < <(find "$targetDir" -name "*.mkv" -type f -print0 2>/dev/null | sort -z)
    
    printf "%s\n" "$(printf '%.0s-' {1..95})"
    
    if [[ ${#verifiedFiles[@]} -eq 0 ]]; then
        echo "No verified conversions found."
        return
    fi
    
    # Display summary
    local totalSizeH=$(awk -v size="$totalOriginalSize" 'BEGIN {
        if (size >= 1099511627776) printf "%.1fT", size/1099511627776
        else if (size >= 1073741824) printf "%.1fG", size/1073741824
        else if (size >= 1048576) printf "%.1fM", size/1048576
        else printf "%.1fK", size/1024
    }')
    local savedSizeH=$(awk -v size="$totalSavedSpace" 'BEGIN {
        if (size >= 1099511627776) printf "%.1fT", size/1099511627776
        else if (size >= 1073741824) printf "%.1fG", size/1073741824
        else if (size >= 1048576) printf "%.1fM", size/1048576
        else printf "%.1fK", size/1024
    }')
    
    echo ""
    echo "Found ${#verifiedFiles[@]} verified conversion(s)"
    echo "Total size to clean up: $totalSizeH"
    echo "Space to be saved: $savedSizeH"
    echo ""
    echo -n "Delete original DV7 files? [y/N] "
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo ""
        for file in "${verifiedFiles[@]}"; do
            rm -f "$file"
            echo "Deleted: $(basename "$file")"
        done
        echo ""
        echo "Cleanup completed. Freed up $savedSizeH of space."
    else
        echo "Cleanup cancelled."
    fi
}

# Parse command line arguments
while (( "$#" )); do
    case "$1" in
        -h|--help)
            printHelp;;
        -k|--keep-files)
            keepFiles=1
            shift;;
        -c|--cleanup)
            cleanupMode=1
            shift;;
        -*)
            echo "Error: Unknown option '$1'"
            printHelp;;
        *)
            targetDir="$1"
            shift;;
    esac
done

# Verify target directory
if [[ ! -d "$targetDir" ]]; then
    echo "Error: Directory not found: '$targetDir'"
    exit 1
fi

# Main execution
if [[ $cleanupMode -eq 1 ]]; then
    cleanupVerifiedFiles
else
    scanAndConvert
fi