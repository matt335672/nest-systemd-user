# nest-systemd-user
Runs `systemd --user` within `systemd --user`

On systemd-based systems, there is an implicit assumption that the user
will only have one graphical session active at any one time. This is because
the `systemd --user` environment is shared between all user sessions, and
there is only room for one DISPLAY variable.

This has been of some inconvenience for the [xrdp](/neutrinolabs/xrdp) project.
A commonly requested feature is for users to be able to log in to the
machine console and xrdp at the same time. This is particularly true
for lesser-experienced users, maybe using a smaller machine such as a
Raspberry PI.

@akarl10 has discovered that is possible to run one `systemd
--user` instance within another. This allows for the possibility of one or more
xrdp sessions to use private `systemd --user` instances.
This was announced in xrdp issue [#2491](/neutrinolabs/xrdp/issues/2491).

This repository contains a tool which can be retro-fitted to xrdp v0.9.x
installations.

At the moment this is an alpha-quality tool. Feedback and issuea are welcome.

# how to use this tool in conjunction with xrdp
To use this tool with xrdp the script startwm.sh should be adapted

First you should place `systemd_user_context.sh` in `/etc/xrdp/`

The next step is putting this somewhere near the top of `startwm.sh`.
It can be anywhere in the script as long as it is before the Xsession call

```bash
# On systemd system?
#
# If so, start a private "systemd --user" instance
if [ -x /usr/bin/systemctl -a "$XDG_RUNTIME_DIR" = "/run/user/"`id -u` ]
then
    eval "`${0%/*}/systemd_user_context.sh init -p $$`"

    # may be used by reconnect.sh to find the matching logind session
    if [ -n "$XDG_SESSION_ID" ]; then
        echo $XDG_SESSION_ID > $XDG_RUNTIME_DIR/login-session-id
    fi
fi
```

If you also want to unlock your xrdp screen when you reconnect to your session
preventing to type you password twice you might put something like this in `reconnectwh.sh`

```bash
# xrdp-sesman knows nothing about the nested session, so try to guess
# XDG_RUNTIME_DIR
[ -z "$XDG_RUNTIME_DIR" -a -e /run/user/$(id -u) ] && XDG_RUNTIME_DIR=/run/user/$(id -u)

eval "`${0%/*}/systemd_user_context.sh get`"

test -e $XDG_RUNTIME_DIR/login-session-id && \
        loginctl unlock-session $(cat $XDG_RUNTIME_DIR/login-session-id)
```
