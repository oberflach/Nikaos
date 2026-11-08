#!/usr/bin/env bash
# Battery conservation mode (charge capped around 60-80%) on laptops whose
# firmware exposes it: Lenovo IdeaPad/Yoga through the ideapad_acpi driver.
# Writing needs permission on the file, e.g. a udev rule such as:
#   ACTION=="add", SUBSYSTEM=="platform", DRIVER=="ideapad_acpi", \
#     RUN+="/bin/chmod a+w /sys%p/conservation_mode"
# Prints 1 (on), 0 (off) or -1 (not available).

CM_FILE=""
for f in /sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode; do
    [ -e "$f" ] && CM_FILE="$f" && break
done

case "$1" in
    "get")
        [ -n "$CM_FILE" ] && [ -r "$CM_FILE" ] && cat "$CM_FILE" || echo -1
        ;;
    "toggle")
        [ -n "$CM_FILE" ] || { echo -1; exit 0; }
        if [ "$(cat "$CM_FILE" 2>/dev/null)" = "1" ]; then
            echo 0 > "$CM_FILE"
        else
            echo 1 > "$CM_FILE"
        fi
        cat "$CM_FILE"
        ;;
esac
