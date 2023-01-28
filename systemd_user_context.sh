#!/bin/sh

# Workarounds for enabling multiple sessions when using systemd
#
# Mainly the issue is that a desktop session needs a dedicated dbus,
# but systemd creates a single one for every logged on user.
#
# Using systemd-run or a systemd user unit file it is possible to create 
# a separate systemd-user instance with dedicated XDG_RUNTIME_DIR and DBUS
#
# Main ideas in this script by mwsys.mine.bz

# Units to mask in the created instance
# Uncomment this line and fill in as appropriate for your installation
#UNITS_TO_MASK="pipewire-pulseaudio.service pipewire-pulseaudio.socket"

# We're probably going to use file descriptor 1 for output. Stash it away
# in fd 3 and redirect our fd 1 to stderr to talk to the user
exec 3>&1 >&2

# prepare user environment
prepare_user_environment()
{
    test -f $XDG_RUNTIME_DIR/systemd/user.control/xrdp-display@.service && return
    install -dm 0700 $XDG_RUNTIME_DIR/systemd/user.control
    # Create a unit to wait for the target pid to finish
    {
        echo "[Unit]"
        echo "Description=Wait for XRDP session %i to finish"
        echo "Requires=xrdp-display@%i.service"
        echo
        echo "[Service]"
        echo "Type=simple"
        echo "ExecStart=/bin/sh -c 'XRDP_STARTWM_PID=\$(cat %t/xrdp-display@%i/startwm.pid); while /bin/kill -0 \$XRDP_STARTWM_PID 2>/dev/null; do sleep 5; done'"
        echo "ExecStopPost=/usr/bin/systemctl --user stop xrdp-display@%i.service"
        echo "ExecStopPost=rm -r %t/xrdp-display@%i"
    } >$XDG_RUNTIME_DIR/systemd/user.control/wait-for-xrdp-display@.service

    #Create the systemd-user session unit file
    {
        echo "[Unit]"
        echo "Description=XRDP systemd User Manager for display %i"
        echo
        echo "[Service]"
        echo "Type=notify"
        echo "ExecStart=sh %t/systemd_user_session.sh xrdp-display@%i"
    } > $XDG_RUNTIME_DIR/systemd/user.control/xrdp-display@.service
    
    #create the systemd --user wrapper to launch systemd with a clean environment
    echo '#/bin/sh
test -z XDG_RUNTIME_DIR && exit 1
test "$1" = "" && exit 1

SESSION_RUNTIME_DIR="$XDG_RUNTIME_DIR/$1"
install -dm 0700 "$SESSION_RUNTIME_DIR"
oIFS="$IFS"
IFS="
"

for ev in `env`; do
    evn=${ev%%=*}
    [ "$evn" != "HOME" -a \
      "$evn" != "SHELL" -a \
      "$evn" != "LANG" -a \
      "$evn" != "PATH" -a \
      "$evn" != "SYSTEMD_EXEC_PID" -a \
      "$evn" != "INVOCATION_ID" -a \
      "$evn" != "NOTIFY_SOCKET" -a \
      "$evn" != "MANAGERPID" ] \
    && unset $evn;
done

IFS="$oIFS"

XDG_RUNTIME_DIR="$SESSION_RUNTIME_DIR"

export XDG_RUNTIME_DIR

exec /lib/systemd/systemd --user
' > $XDG_RUNTIME_DIR/systemd_user_session.sh
    systemctl --user daemon-reload
}

# -----------------------------------------------------------------------------
get_unit_name()
{
    if [ -z "$DISPLAY" ]; then
        echo "** Warning - no DISPLAY. Assuming test mode" >&2
        unit_name=xrdp-display@test
    else
        unit_name=xrdp-display@${DISPLAY##*:} ; # e.g. xrdp-display-10.0
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

        prepare_user_environment ;

        #pass pid to monitor to wait-for- unit
        echo $target_pid > $session_runtime_dir/startwm.pid
        
        # this will pull also start xrdp-display@
        systemctl --user start wait-for-$unit_name
        
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
