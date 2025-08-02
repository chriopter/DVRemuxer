# DVRemuxer

## General

Batch conversion tool that scans directories and converts Dolby Vision profile 7 (dual-layer) to profile 8.1 (single-layer) for improved device compatibility. The tool preserves original quality while ensuring broader playback support, and all conversions are fully reversible.

**Key features:**
- Scans entire directory trees for DV content
- Identifies and converts only DV7 files that need processing
- Preserves all audio tracks and subtitles
- Creates restoration files for reversibility

## Setup

### Requirements

- `mediainfo` - Media file analysis
- `dovi_tool` - Dolby Vision metadata processing ([GitHub](https://github.com/quietvoid/dovi_tool))
- `mkvtoolnix` - MKV container operations

### Installation

```bash
# Ubuntu/Debian
sudo apt install mediainfo mkvtoolnix

# macOS
brew install mediainfo mkvtoolnix

# Install dovi_tool from GitHub releases
```

### Usage

```bash
# Clone and setup
git clone <repository-url>
cd DVRemuxer
chmod +x DVRemuxer.sh

# Scan and convert current directory
./DVRemuxer.sh

# Scan specific directory
./DVRemuxer.sh /path/to/media

# Keep intermediate files
./DVRemuxer.sh -k /path/to/media
```

**Options:**
- `-h, --help` - Display help message
- `-k, --keep-files` - Keep intermediate working files
- `PATH` - Target directory (default: current directory)

## Technical Details

### How It Works

1. **Scans** directory for all MKV files
2. **Detects** Dolby Vision profile using mediainfo
3. **Converts** DV7 to DV8.1 using dovi_tool (removes enhancement layer, keeps RPU metadata)
4. **Preserves** original enhancement layer for potential restoration
5. **Remuxes** converted video with original audio/subtitle tracks

### File Structure

For each `movie.mkv` conversion:

**Created files:**
- `movie.DV8.mkv` - Converted file with DV8.1 video + original audio/subtitles
- `movie.DV7.EL_RPU.hevc` - Preserved enhancement layer for restoration
- `movie.DV8.L1_plot.png` - Visual graph of brightness metadata

**Temporary files (deleted unless using `-k`):**
- `.BL_EL_RPU.hevc` - Extracted video stream
- `.DV8.BL_RPU.hevc` - Converted video stream
- `.DV8.RPU.bin` - RPU metadata

### Restoration Process

To restore a file back to DV7:

```bash
# Extract base layer
mkvextract movie.DV8.mkv tracks 0:BL.hevc

# Recombine with preserved enhancement layer
dovi_tool mux --bl BL.hevc --el movie.DV7.EL_RPU.hevc -o movie.DV7.hevc

# Remux to MKV
mkvmerge -o movie.DV7.restored.mkv -D movie.DV8.mkv movie.DV7.hevc --track-order 1:0
```

## Notes

- **Profile 8.1** maintains DV7 visual quality while ensuring compatibility with more devices
- **Apple TV compatibility**: 2021 models use CMv2.9, 2022+ models use CMv4.0 (tool outputs both)