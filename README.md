# DVRemuxer

Converts Dolby Vision profile 7 (dual-layer) to profile 8.1 (single-layer) for better compatibility. The conversion is fully reversible as the original enhancement layer is preserved.

## Requirements

- `mediainfo` - Detects Dolby Vision profiles
- `dovi_tool` - Processes DV metadata ([GitHub](https://github.com/quietvoid/dovi_tool))
- `mkvtoolnix` - MKV muxing/demuxing

```bash
# Ubuntu/Debian
sudo apt install mediainfo mkvtoolnix

# macOS
brew install mediainfo mkvtoolnix
```

## Quick Start

```bash
git clone <repository-url>
cd DVRemuxer
chmod +x DVRemuxer.sh

# Scan and convert current directory
./DVRemuxer.sh

# Scan specific directory
./DVRemuxer.sh /path/to/videos
```

## What It Does

1. **Scans** for Dolby Vision MKV files
2. **Identifies** DV7 files that need conversion
3. **Converts** DV7 → DV8.1 (keeps original audio/subtitles)
4. **Creates** restoration files:
   - `.DV7.EL_RPU.hevc` - Original enhancement layer
   - `.DV8.L1_plot.png` - Brightness metadata graph

## Example

```
Scanning for DV files in: /Videos

Filename                          Type    Size    Status
--------------------------------------------------------
movie1.mkv                        DV7     45G     ○
movie2.mkv                        DV5     32G     ✓
movie3.mkv                        DV7     40G     ✓
  └─ movie3.DV8.mkv              DV8.1   38G     ✓

Found 1 DV7 files that need conversion to DV8.1
Convert them now? [y/N]
```

## Notes

- Profile 8.1 maintains DV7 quality with better device compatibility
- Outputs both CMv4.0 and CMv2.9 metadata
- Original DV7 can be restored using the `.DV7.EL_RPU.hevc` file
- Compatible with all Apple TV 4K models (2021 uses CMv2.9, 2023 uses CMv4.0)

## Technical Details

For each conversion of `movie.mkv`, the following files are created:

**Input:**
- `movie.mkv` - Original DV7 file with dual-layer HEVC video + audio/subtitles

**Intermediate files (deleted unless using `-k`):**
- `movie.BL_EL_RPU.hevc` - Extracted dual-layer HEVC stream (base + enhancement + RPU)
- `movie.DV8.BL_RPU.hevc` - Converted single-layer HEVC stream (base + RPU only)
- `movie.DV8.RPU.bin` - Extracted RPU metadata for analysis

**Output files:**
- `movie.DV8.mkv` - Final DV8.1 file with converted video + original audio/subtitles
- `movie.DV7.EL_RPU.hevc` - Preserved enhancement layer + RPU (for restoration)
- `movie.DV8.L1_plot.png` - Graph of L1 brightness metadata over time

The converter extracts the HEVC stream, separates the enhancement layer for archival, converts to profile 8.1 (removing EL but keeping RPU), then remuxes with the original audio/subtitle tracks.

## Restoring to DV7

To restore a file back to DV7 using the preserved enhancement layer:

```bash
# Extract base layer from DV8 file
mkvextract movie.DV8.mkv tracks 0:BL.hevc

# Mux base layer with preserved enhancement layer
dovi_tool mux --bl BL.hevc --el movie.DV7.EL_RPU.hevc --output movie.DV7.hevc

# Remux into MKV container
mkvmerge -o movie.DV7.restored.mkv -D movie.DV8.mkv movie.DV7.hevc --track-order 1:0
```