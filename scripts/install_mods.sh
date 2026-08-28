#!/bin/bash
# API-based mod manager using sp-mod.com
# Replaces the old URL-based download_unzip_install_mods.sh

set -e

# Configuration
API_BASE="https://sp-mod.com/api/v0"
MODS_CSV="${MODS:-}"
AUTO_UPDATE="${AUTO_UPDATE_MODS:-false}"
SPT_VERSION="${SPT_VERSION:-}"
FIKA_MODE="${FIKA_MODE:-disabled}"

# Paths
mounted_dir="${1:-/opt/server}"
mod_download_dir="$mounted_dir/mod_download"
state_file="$mod_download_dir/installed_mods.json"
log_file="$mod_download_dir/install_mods.log"
tmp_dir="/tmp/mod_install"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging
log() {
    echo -e "$1" | tee -a "$log_file"
}

log_error() {
    echo -e "${RED}ERROR: $1${NC}" | tee -a "$log_file" >&2
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}" | tee -a "$log_file"
}

log_warn() {
    echo -e "${YELLOW}⚠ $1${NC}" | tee -a "$log_file"
}

# Initialize
init() {
    mkdir -p "$mod_download_dir"
    mkdir -p "$tmp_dir"
    
    # Initialize state file if it doesn't exist
    if [ ! -f "$state_file" ]; then
        echo '{"mods":[]}' > "$state_file"
    fi
    
    # Clear log
    echo "=== Mod Install Run: $(date -Iseconds) ===" > "$log_file"
    log "SPT Version: $SPT_VERSION"
    log "Fika Mode: $FIKA_MODE"
    log "Auto Update: $AUTO_UPDATE"
    log ""
}

# API helper
api_get() {
    local endpoint="$1"
    curl -s -H "User-Agent: fika-spt-server-docker" "$API_BASE$endpoint"
}

# Resolve mod slug to ID
resolve_mod_id() {
    local slug="$1"
    
    # If it's a number, assume it's already an ID
    if [[ "$slug" =~ ^[0-9]+$ ]]; then
        echo "$slug"
        return 0
    fi
    
    # Search by slug
    local response
    response=$(api_get "/mods?search=$slug&per_page=10")
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        log_error "Failed to search for mod: $slug"
        return 1
    fi
    
    # Find exact slug match
    local mod_id
    mod_id=$(echo "$response" | jq -r --arg slug "$slug" '.data[] | select(.slug == $slug) | .id' | head -1)
    
    if [ -z "$mod_id" ] || [ "$mod_id" = "null" ]; then
        log_error "Mod not found: $slug"
        return 1
    fi
    
    echo "$mod_id"
}

# Get best version for current SPT version
get_best_version() {
    local mod_id="$1"
    local mod_name="$2"
    
    local response
    response=$(api_get "/mod/$mod_id/versions?per_page=50")
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        log_error "Failed to get versions for mod $mod_id"
        return 1
    fi
    
    local versions
    versions=$(echo "$response" | jq -r '.data')
    
    if [ -z "$versions" ] || [ "$versions" = "null" ]; then
        log_error "No versions found for mod $mod_id"
        return 1
    fi
    
    # Filter by SPT version compatibility
    # Supports: exact match, ~major.minor (patch-agnostic), >=version, ~major.minor <major.minor.patch
    local compatible_versions
    if [ -n "$SPT_VERSION" ]; then
        compatible_versions=$(echo "$versions" | jq -c --arg spt "$SPT_VERSION" '
            def parse_version: split(".") | map(tonumber);
            def version_gte(a; b):
                (a[0] > b[0]) or
                (a[0] == b[0] and a[1] > b[1]) or
                (a[0] == b[0] and a[1] == b[1] and a[2] >= b[2]);
            def version_lt(a; b):
                (a[0] < b[0]) or
                (a[0] == b[0] and a[1] < b[1]) or
                (a[0] == b[0] and a[1] == b[1] and a[2] < b[2]);
            def matches_constraint($spt):
                .spt_version_constraint as $c |
                ($c | gsub("^\\s+|\\s+$"; "")) as $trimmed |
                if $c == null or $c == "" then true
                elif $trimmed == $spt then true
                elif ($trimmed | test("^~[0-9]+\\.[0-9]+$")) then
                    $spt | startswith($trimmed | ltrimstr("~"))
                elif ($trimmed | test("^>=[0-9]")) then
                    ($spt | parse_version) as $current |
                    ($trimmed | ltrimstr(">=") | parse_version) as $min |
                    version_gte($current; $min)
                elif ($trimmed | test("^~[0-9]+\\.[0-9]+\\s+<[0-9]")) then
                    ($trimmed | capture("~(?<min>[0-9]+\\.[0-9]+)\\s+<(?<max>[0-9]+\\.[0-9]+\\.[0-9]+)")) as $m |
                    ($spt | parse_version) as $current |
                    ($m.min | split(".") | map(tonumber)) as $min_ver |
                    ($m.max | split(".") | map(tonumber)) as $max_ver |
                    ($current[0] == $min_ver[0] and $current[1] == $min_ver[1]) and
                    version_lt($current; $max_ver)
                else false
                end;
            [.[] | select(matches_constraint($spt))]
        ')
    else
        compatible_versions="$versions"
    fi

    # If Fika is active, prefer Fika-compatible versions
    if [ "$FIKA_MODE" != "disabled" ]; then
        local fika_versions
        fika_versions=$(echo "$compatible_versions" | jq -c '
            [.[] | select(.fika_compatibility == "compatible" or .fika_compatibility == true)]
        ')

        if [ "$(echo "$fika_versions" | jq 'length')" -gt 0 ]; then
            compatible_versions="$fika_versions"
        else
            log_warn "No Fika-compatible versions found for $mod_name, using best available"
        fi
    fi

    # Sort by semver descending and pick the latest
    compatible_versions=$(echo "$compatible_versions" | jq -c '
        sort_by(.version | split(".") | map(tonumber)) | reverse
    ')

    # Get the latest (first after sort) compatible version
    local best_version
    best_version=$(echo "$compatible_versions" | jq -c '.[0]')
    
    if [ -z "$best_version" ] || [ "$best_version" = "null" ]; then
        log_error "No compatible version found for $mod_name (SPT $SPT_VERSION)"
        return 1
    fi
    
    echo "$best_version"
}

# Check if mod version is already installed
is_installed() {
    local mod_id="$1"
    local version="$2"
    
    if [ ! -f "$state_file" ]; then
        return 1
    fi
    
    local installed_version
    installed_version=$(jq -r --arg id "$mod_id" '.mods[] | select(.id == ($id | tonumber)) | .version' "$state_file")
    
    if [ "$installed_version" = "$version" ]; then
        return 0
    fi
    
    return 1
}

# Download mod
download_mod() {
    local mod_id="$1"
    local mod_name="$2"
    local download_link="$3"
    local version="$4"
    
    log "Downloading $mod_name v$version..."
    
    local filename="$mod_id-$version.zip"
    local download_path="$tmp_dir/$filename"
    
    # Download with redirect following
    if ! curl -sL -o "$download_path" "$download_link"; then
        log_error "Failed to download $mod_name"
        return 1
    fi
    
    # Verify file was downloaded
    if [ ! -f "$download_path" ] || [ ! -s "$download_path" ]; then
        log_error "Downloaded file is empty or missing: $mod_name"
        return 1
    fi
    
    log_success "Downloaded $mod_name v$version"
    echo "$download_path"
}

# Extract and install mod
install_mod() {
    local archive_path="$1"
    local mod_name="$2"
    
    log "Installing $mod_name..."
    
    local extract_dir="$tmp_dir/extract"
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    
    # Extract based on file type
    local filename=$(basename "$archive_path")
    case "$filename" in
        *.zip)
            unzip -q "$archive_path" -d "$extract_dir" 2>>"$log_file"
            ;;
        *.7z)
            7z x "$archive_path" -o"$extract_dir" >>"$log_file" 2>&1
            ;;
        *.tar.gz|*.tgz)
            tar -xzf "$archive_path" -C "$extract_dir" 2>>"$log_file"
            ;;
        *.tar)
            tar -xf "$archive_path" -C "$extract_dir" 2>>"$log_file"
            ;;
        *)
            log_error "Unknown archive format: $filename"
            return 1
            ;;
    esac
    
    # Install files to correct locations
    local plugins_dir=$(dirname "$mounted_dir")/BepInEx/plugins
    local user_mods_dir="$mounted_dir/user/mods"
    
    mkdir -p "$plugins_dir"
    mkdir -p "$user_mods_dir"
    
    # Move BepInEx plugins
    if [ -d "$extract_dir/BepInEx/plugins" ]; then
        cp -rf "$extract_dir/BepInEx/plugins"/* "$plugins_dir/" 2>/dev/null || true
        rm -rf "$extract_dir/BepInEx"
    fi
    if [ -d "$extract_dir/BepInEx/Plugins" ]; then
        cp -rf "$extract_dir/BepInEx/Plugins"/* "$plugins_dir/" 2>/dev/null || true
        rm -rf "$extract_dir/BepInEx"
    fi
    
    # Move SPT mods
    if [ -d "$extract_dir/SPT" ]; then
        cp -rf "$extract_dir/SPT"/* "$mounted_dir/" 2>/dev/null || true
        rm -rf "$extract_dir/SPT"
    fi
    
    # Move loose DLLs to plugins
    if ls "$extract_dir"/*.dll 1> /dev/null 2>&1; then
        cp "$extract_dir"/*.dll "$plugins_dir/" 2>/dev/null || true
        rm "$extract_dir"/*.dll 2>/dev/null || true
    fi
    
    # Move executables to server root
    if ls "$extract_dir"/*.exe 1> /dev/null 2>&1; then
        cp "$extract_dir"/*.exe "$mounted_dir/" 2>/dev/null || true
        rm "$extract_dir"/*.exe 2>/dev/null || true
    fi
    
    # Move documentation to server root
    if ls "$extract_dir"/*.txt 1> /dev/null 2>&1; then
        cp "$extract_dir"/*.txt "$mounted_dir/" 2>/dev/null || true
        rm "$extract_dir"/*.txt 2>/dev/null || true
    fi
    if ls "$extract_dir"/*.md 1> /dev/null 2>&1; then
        cp "$extract_dir"/*.md "$mounted_dir/" 2>/dev/null || true
        rm "$extract_dir"/*.md 2>/dev/null || true
    fi
    
    # Check for remaining files
    if [ "$(ls -A "$extract_dir" 2>/dev/null)" ]; then
        local remains_dir="$mod_download_dir/remains"
        mkdir -p "$remains_dir"
        cp -rf "$extract_dir"/* "$remains_dir/" 2>/dev/null || true
        log_warn "Some files from $mod_name moved to mod_download/remains/"
    fi
    
    log_success "Installed $mod_name"
}

# Update state file
update_state() {
    local mod_id="$1"
    local slug="$2"
    local mod_name="$3"
    local version="$4"
    
    local now
    now=$(date -Iseconds)
    
    # Remove existing entry if present
    local updated_mods
    updated_mods=$(jq --arg id "$mod_id" '.mods | map(select(.id != ($id | tonumber)))' "$state_file")
    
    # Add new entry
    updated_mods=$(echo "$updated_mods" | jq --arg id "$mod_id" --arg slug "$slug" --arg name "$mod_name" --arg ver "$version" --arg date "$now" \
        '. + [{"id": ($id | tonumber), "slug": $slug, "name": $name, "version": $ver, "installed_at": $date}]')
    
    # Write back
    jq --argjson mods "$updated_mods" '.mods = $mods' "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
}

# Process a single mod
process_mod() {
    local slug="$1"
    
    log ""
    log "Processing: $slug"
    
    # Resolve mod ID
    local mod_id
    mod_id=$(resolve_mod_id "$slug")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Get mod details
    local mod_info
    mod_info=$(api_get "/mod/$mod_id")
    local mod_name
    mod_name=$(echo "$mod_info" | jq -r '.data.name')
    
    log "Found: $mod_name (ID: $mod_id)"
    
    # Get best version
    local version_info
    version_info=$(get_best_version "$mod_id" "$mod_name")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local version
    version=$(echo "$version_info" | jq -r '.version')
    local download_link
    download_link=$(echo "$version_info" | jq -r '.link')
    
    log "Best version: $version"
    
    # Check if already installed
    if is_installed "$mod_id" "$version"; then
        if [ "$AUTO_UPDATE" != "true" ]; then
            log_success "$mod_name v$version already installed, skipping"
            return 0
        else
            log "$mod_name v$version installed, checking for updates..."
        fi
    fi
    
    # Download
    local archive_path
    archive_path=$(download_mod "$mod_id" "$mod_name" "$download_link" "$version")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Install
    install_mod "$archive_path" "$mod_name"
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Update state
    update_state "$mod_id" "$slug" "$mod_name" "$version"
    
    # Cleanup
    rm -f "$archive_path"
    
    return 0
}

# Main
main() {
    init
    
    if [ -z "$MODS_CSV" ]; then
        log "No mods specified in MODS environment variable"
        exit 0
    fi
    
    log "Mods to process: $MODS_CSV"
    log ""
    
    # Parse comma-separated list
    IFS=',' read -ra MOD_SLUGS <<< "$MODS_CSV"
    
    local success_count=0
    local fail_count=0
    
    for slug in "${MOD_SLUGS[@]}"; do
        # Trim whitespace
        slug=$(echo "$slug" | xargs)
        
        if [ -z "$slug" ]; then
            continue
        fi
        
        if process_mod "$slug"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done
    
    # Cleanup temp directory
    rm -rf "$tmp_dir"
    
    log ""
    log "==================================="
    log "Mod installation complete"
    log "  Successful: $success_count"
    log "  Failed: $fail_count"
    log "  State file: $state_file"
    log "  Full log: $log_file"
    log "==================================="
    
    if [ $fail_count -gt 0 ]; then
        exit 1
    fi
}

main
