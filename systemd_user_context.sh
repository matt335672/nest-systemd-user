#!/bin/sh

# Workarounds for enabling multiple sessions when using systemd
#
# Mainly the issue is that a desktop session needs a dedicated dbus,
# but systemd creates a single one for every logged on user.
#
# Using systemd-run it is possible to create a separate systemd-user instance
# with dedicated XDG_RUNTIME_DIR and DBUS
#
# Main ideas in this script by mwsys.mine.bz

# Units to mask in the created instance
# Uncomment this line and fill in as appropriate for your installation
#UNITS_TO_MASK="pipewire-pulseaudio.service pipewire-pulseaudio.socket"

# We're probably going to use file descriptor 1 for output. Stash it away
# in fd 3 and redirect our fd 1 to stderr to talk to the user
exec 3>&1 >&2

# -----------------------------------------------------------------------------
get_unit_name()
{
    if [ -z "$DISPLAY" ]; then
        echo "** Warning - no DISPLAY. Assuming test mode" >&2
        unit_name=xrdp-display-test
    else
        unit_name=xrdp-display-${DISPLAY##*:} ; # e.g. xrdp-display-10.0
        unit_name=${unit_name%.*} ; # e.g. xrdp-display-10
    fi
}

# -----------------------------------------------------------------------------
# Param : Unit name
get_session_runtime_dir()
{
    session_runtime_dir=/run/user/`id -u`/$1
}

# -----------------------------------------------------------------------------
cmd_get()
{
    get_unit_name  ; # Output in 'unit_name'
    get_session_runtime_dir $unit_name ; # Output in 'session_runtime_dir'

    # Send the required commands to the saved file descriptor
    {
        echo "XDG_RUNTIME_DIR=\"$session_runtime_dir\"" >&3
        echo "DBUS_SESSION_BUS_ADDRESS=\"unix:path=$session_runtime_dir/bus\""
        echo "export XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS"
    } >&3
}

# -----------------------------------------------------------------------------
cmd_init()
{
    if [ $# != 2 -a "$1" != -p ]; then
        echo "** Need to specify a PID to monitor"
        false
    elif ! kill -0 "$2" >/dev/null 2>&1 ; then
        echo "** '$2' is not a PID which can be monitored"
        false
    else
        target_pid="$2"
        get_unit_name  ; # Output in 'unit_name'
        get_session_runtime_dir $unit_name ; # Output in 'session_runtime_dir'

        # Be aware the session runtime directory may still be around
        # from last time
        install -dm 0700 $session_runtime_dir
        rm -rf $session_runtime_dir/systemd/user.control/
        mkdir -p $session_runtime_dir/systemd/user.control/

        if [ -n "$UNITS_TO_MASK" ]; then
            for unit in $UNITS_TO_MASK; do
                ln -s /dev/null \
                    $session_runtime_dir/systemd/user.control/$unit
            done
        fi

        # Create a unit to wait for the target pid to finish
        {
            echo "[Unit]"
            echo "Description=Wait for XRDP session to finish"
            echo "Requires=default.target"
            echo
            echo "[Service]"
            echo "Type=simple"
            echo "ExecStart=/bin/sh -c 'while /bin/kill -0 $target_pid; do sleep 5; done'"
            echo "ExecStopPost=/usr/bin/systemctl --user exit"
        } >$session_runtime_dir/systemd/user.control/wait-for-xrdp-session.service

        # start systemd service. this must be done using systemd-run to get a
        # proper scope. This mimics user@.service
        #
        # Within the system --user process we run wait-for-xrdp-session.service.
        # That kills the systemd --user instance when the target process
        # finishes.
        systemd-run --user -u $unit_name \
            -E "XDG_RUNTIME_DIR=$session_runtime_dir" \
            -E "DBUS_SESSION_BUS_ADDRESS=unix:path=$session_runtime_dir/bus" \
            systemd --user --unit wait-for-xrdp-session.service

        # Use the 'get' command to display the results. We don't need
        # the command to generate any warnings
        cmd_get >/dev/null 2>&1
    fi
}

# -----------------------------------------------------------------------------
cmd_status()
{
    get_unit_name  ; # Output in 'unit_name'
    systemctl --user status $unit_name >&3
}

# -----------------------------------------------------------------------------
cmd_help()
{
    cat <<EOF
Usage: $0 [ init | get | help ]

    init -p <pid>
            Sets up a new systemd --user instance for this DISPLAY.
            Outputs the shell commands needed to communicate with this
            instance.

            The specified pid is polled. When it disappears, the
            systemd --user instance is wound up.

    get     Used after 'init' to find the existing private systemd --user
            instance for this DISPLAY.
            Outputs the shell commands needed to communicate with this
            instance.

    status  Displays the status of any private systemd --user
            instance for this DISPLAY.
            Does not work within the context created by 'init' or 'get'

    help    Displays this help
EOF
}

# -----------------------------------------------------------------------------
case "$1" in
    get | init | status | help)
        func=cmd_$1
        shift
        $func "$@"
        exit $?
        ;;
    *)  echo "Unrecognised command '$1'. Use \"$0 help\" for info" >&2
        false
esac

exit $?
