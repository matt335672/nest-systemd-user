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
