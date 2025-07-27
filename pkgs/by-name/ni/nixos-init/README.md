# nixos-init

A system for bashless initialization.

This tries to do the minimal work required to start systemd. Everything that
can be done later SHOULD be done later (i.e. after systemd has already
started).

Extending the init in constrast should be done with care and only when
necessary. It should not be done for third party extensions but instead only do
the bare minium that is necessary to get systemd running. Most notably, this
means working around the constraints of the Filesystem Hierarchy Standard (FHS)
that is imposed by other tools (e.g. systemd).

## Benefits

Benefits of making the init as minimal as possible and starting thing as late
as possible:

- systemd has an API that can be used to easily extend the system
  (`systemd.services`).
- systemd services are parallelized by default so this improves startup time

## Boot Flow

### systemd initrd

Previously: initrd-systemd -> prepare-root -> switch-root -> systemd
Now: initrd-systemd -> switch-root -> nixos-init -> systemd

### Scripted initrd

stage-1-init.sh -> switch-root -> stage-2-init.sh -> systemd
