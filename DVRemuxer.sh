#!/bin/bash

# DVRemuxer - Dolby Vision profile 7 to 8.1 converter
# Scans for DV files and remuxes DV7 to DV8.1 for better compatibility

# Settings
keepFiles=0
targetDir=$PWD

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
    echo ""
    echo "Arguments:"
    echo "  PATH              Target directory (default: current directory)"
    echo ""
    echo "The script will scan for DV files and offer to remux DV7 files to DV8.1"
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
        local mkvBase=$(basename "$mkvFile" .mkv)
        echo ""
        echo "Processing: $mkvBase"
        echo "========================================="
        
        # Working file names
        local BL_EL_RPU_HEVC="${mkvBase}.BL_EL_RPU.hevc"
        local DV7_EL_RPU_HEVC="${mkvBase}.DV7.EL_RPU.hevc"
        local DV8_BL_RPU_HEVC="${mkvBase}.DV8.BL_RPU.hevc"
        
        echo "Extracting HEVC stream..."
        mkvextract "$mkvFile" tracks 0:"$BL_EL_RPU_HEVC"
        
        if [[ ! -f "$BL_EL_RPU_HEVC" ]]; then
            echo "ERROR: Failed to extract HEVC track from $mkvFile"
            continue
        fi
        
        echo "Extracting DV7 EL+RPU for archival..."
        dovi_tool demux --el-only "$BL_EL_RPU_HEVC" -e "$DV7_EL_RPU_HEVC"
        
        echo "Converting to DV8.1 (profile 8.1)..."
        dovi_tool convert --discard -m 2 "$BL_EL_RPU_HEVC" -o "$DV8_BL_RPU_HEVC"
        
        if [[ ! -f "$DV8_BL_RPU_HEVC" ]]; then
            echo "ERROR: Failed to convert to DV8.1"
            [[ $keepFiles == 0 ]] && rm -f "$BL_EL_RPU_HEVC" "$DV7_EL_RPU_HEVC"
            continue
        fi
        
        [[ $keepFiles == 0 ]] && rm -f "$BL_EL_RPU_HEVC"
        
        echo "Creating L1 plot..."
        local DV8_RPU_BIN="${mkvBase}.DV8.RPU.bin"
        dovi_tool extract-rpu "$DV8_BL_RPU_HEVC" -o "$DV8_RPU_BIN"
        dovi_tool plot "$DV8_RPU_BIN" -o "${mkvBase}.DV8.L1_plot.png"
        [[ $keepFiles == 0 ]] && rm -f "$DV8_RPU_BIN"
        
        echo "Remuxing to MKV..."
        mkvmerge -o "${mkvBase}.DV8.mkv" -D "$mkvFile" "$DV8_BL_RPU_HEVC" --track-order 1:0
        
        [[ $keepFiles == 0 ]] && rm -f "$DV8_BL_RPU_HEVC"
        
        if [[ -f "${mkvBase}.DV8.mkv" ]]; then
            echo "✓ Successfully converted: ${mkvBase}.DV8.mkv"
            processedFiles+=("$mkvFile")
        else
            echo "✗ Conversion failed for: $mkvFile"
        fi
    done
    
    # Offer to delete original files
    if [[ ${#processedFiles[@]} -gt 0 ]]; then
        echo ""
        echo "Successfully converted ${#processedFiles[@]} file(s)."
        echo -n "Delete original DV7 files? [y/N] "
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            for file in "${processedFiles[@]}"; do
                rm -f "$file"
                echo "Deleted: $file"
            done
        fi
    fi
    
    echo ""
    echo "Done."
}

# Parse command line arguments
while (( "$#" )); do
    case "$1" in
        -h|--help)
            printHelp;;
        -k|--keep-files)
            keepFiles=1
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
scanAndConvert