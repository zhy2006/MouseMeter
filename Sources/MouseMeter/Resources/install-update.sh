#!/bin/bash
# Invoked with positional arguments by the validated, running application.
set -euo pipefail
parent_pid="$1"
app="$2"
staging="$3"
work="$4"
backup="$staging/Previous.app"

completed=false
cleanup() {
    # Never discard the only copy of the old app if replacement or rollback fails.
    if [[ -d "$backup" && "$completed" != true ]]; then
        if [[ ! -e "$app" ]]; then
            mv "$backup" "$app" || return
        else
            return
        fi
    fi
    rm -rf "$staging" "$work"
}
trap cleanup EXIT

# Abort rather than replacing an app which has not exited.
for ((attempt = 0; attempt < 120; attempt++)); do
    if ! kill -0 "$parent_pid" 2>/dev/null; then
        break
    fi
    sleep 1
done
if kill -0 "$parent_pid" 2>/dev/null; then
    exit 1
fi

# Staging and destination share a filesystem, so moves do not partially copy an app.
mv "$app" "$backup"
if ! mv "$staging/MouseMeter.app" "$app"; then
    mv "$backup" "$app"
    /usr/bin/open "$app"
    exit 1
fi
if ! /usr/bin/open "$app"; then
    rm -rf "$app"
    mv "$backup" "$app"
    /usr/bin/open "$app"
    exit 1
fi

completed=true
