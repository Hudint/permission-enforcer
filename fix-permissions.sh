#!/bin/sh

# Only numeric UID and GID are accepted (no usernames or group names)
# TARGET_PERMISSIONS is optional — if not set, permissions are not checked or changed
# EXCLUDE_PATTERNS is optional — colon-separated list of path patterns to exclude (e.g. /data/logs:/data/tmp/*)
WATCH_DIR="${WATCH_DIR:-/data}"
TARGET_UID="${TARGET_UID:-1000}"
TARGET_GID="${TARGET_GID:-1000}"
TARGET_PERMISSIONS="${TARGET_PERMISSIONS:-}"
EXCLUDE_PATTERNS="${EXCLUDE_PATTERNS:-}"

# Validate that UID and GID are numeric
if ! echo "$TARGET_UID" | grep -qE '^[0-9]+$'; then
    echo "ERROR: TARGET_UID must be a numeric UID, not a username." >&2
    exit 1
fi
if ! echo "$TARGET_GID" | grep -qE '^[0-9]+$'; then
    echo "ERROR: TARGET_GID must be a numeric GID, not a group name." >&2
    exit 1
fi

# Helper: check if a path matches any exclude pattern
is_excluded() {
    [ -z "$EXCLUDE_PATTERNS" ] && return 1
    _path="$1"
    _OLD_IFS="$IFS"
    IFS=":" 
    for _pattern in $EXCLUDE_PATTERNS; do
        case "$_path" in
            $_pattern) IFS="$_OLD_IFS"; return 0 ;;
        esac
    done
    IFS="$_OLD_IFS"
    return 1
}

echo "=== Permission Watcher ==="
echo "Directory:   $WATCH_DIR"
echo "Target:      $TARGET_UID:$TARGET_GID"
echo "Permissions: ${TARGET_PERMISSIONS:-"(not managed)"}"
if [ -n "$EXCLUDE_PATTERNS" ]; then
    echo "Excludes:    $(echo "$EXCLUDE_PATTERNS" | tr ':' '\n' | sed 's/^/             /' | sed '1s/             //')"
else
    echo "Excludes:    (none)"
fi

# Initialer Scan
echo "Running initial scan..."

#Search for wrong uid and gid
FIXED=$(find "$WATCH_DIR" \( ! -user "$TARGET_UID" -o ! -group "$TARGET_GID" \) -print | while IFS= read -r f; do
    is_excluded "$f" && continue
    chown "$TARGET_UID:$TARGET_GID" "$f"
    echo "$f"
done | wc -l)
echo "Fixed $FIXED file(s) with wrong uid or gid."

#If wanted search for wrong permissions
if [ -n "$TARGET_PERMISSIONS" ]; then
    FIXED=$(find "$WATCH_DIR" ! -perm "$TARGET_PERMISSIONS" -print | while IFS= read -r f; do
        is_excluded "$f" && continue
        chmod "$TARGET_PERMISSIONS" "$f"
        echo "$f"
    done | wc -l)
    echo "Fixed $FIXED file(s) with wrong permissions."
fi
echo "Initial scan done."

# Event-basiertes Watching
echo "Watching for changes..."
inotifywait -m -r -e create -e moved_to -e attrib --format '%w%f' "$WATCH_DIR" | while read FILE; do
    if [ -e "$FILE" ] && ! is_excluded "$FILE"; then
        CURRENT_UID=$(stat -c '%u' "$FILE")
        CURRENT_GID=$(stat -c '%g' "$FILE")
        NEEDS_FIX=0
        LOG_SUFFIX=""

        if [ "$CURRENT_UID" != "$TARGET_UID" ] || [ "$CURRENT_GID" != "$TARGET_GID" ]; then
            NEEDS_FIX=1
            LOG_SUFFIX="owner: $CURRENT_UID:$CURRENT_GID -> $TARGET_UID:$TARGET_GID"
        fi

        if [ -n "$TARGET_PERMISSIONS" ]; then
            CURRENT_PERMS=$(stat -c '%a' "$FILE")
            if [ "$CURRENT_PERMS" != "$TARGET_PERMISSIONS" ]; then
                NEEDS_FIX=1
                LOG_SUFFIX="$LOG_SUFFIX perms: $CURRENT_PERMS -> $TARGET_PERMISSIONS"
            fi
        fi

        if [ "$NEEDS_FIX" = "1" ]; then
            chown "$TARGET_UID:$TARGET_GID" "$FILE"
            [ -n "$TARGET_PERMISSIONS" ] && chmod "$TARGET_PERMISSIONS" "$FILE"
            echo "$(date '+%Y-%m-%d %H:%M:%S') Fixed: $FILE ($LOG_SUFFIX)"
        fi
    fi
done