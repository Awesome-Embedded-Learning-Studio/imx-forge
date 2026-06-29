---
title: NFS-Ganesha ESTALE After Bind-Mount
---

# 2026-06-23 NFS-Ganesha Stale File Handle After Bind-Mount

A sequel to [2026-06-08 WSL2 NFS Rootfs Troubleshooting](2026-06-08-wsl2-nfsroot-ganesha-troubleshoot.md).
That note set up **nfs-ganesha** (VFS FSAL) to serve `rootfs/nfs` to the i.MX6ULL
over NFSv3. This note covers a different, subtler failure that appears **after
the setup is already working**: the board suddenly cannot mount the NFS root
again, with no config change on the board side.

## Context

Goal: boot **CFBox** (a BusyBox replacement) as PID 1 on the i.MX6ULL, served
over the existing ganesha NFS root. A CFBox armhf static rootfs was assembled at
`out/rootfs-cfbox` and bound onto the export point:

```bash
sudo ./scripts/manual_mount_nfs.sh --source=out/rootfs-cfbox
# i.e.  mount --bind out/rootfs-cfbox  rootfs/nfs
```

The board was then booted with the usual NFS-root bootargs (unchanged from the
06-08 note): `root=/dev/nfs nfsroot=192.168.60.1:.../rootfs/nfs,vers=3,proto=tcp,nolock,port=2049,mountport=20048`.

## Symptom

The kernel came up, Ethernet linked, DHCP completed — then froze for ~96 s and
panicked:

```text
[ 120.192454] VFS: Unable to mount root fs via NFS.
[ 120.192602] devtmpfs: mounted
[ 120.192640] VFS: Failed to pivot into new rootfs
[ 120.196824] Run /sbin/init as init process
[ 120.196930] Run /etc/init as init process
[ 120.197004] Run /bin/init as init process
[ 120.197070] Run /bin/sh as init process
[ 120.197141] Kernel panic - not syncing: No working init found.
```

## Key Insight — the freeze point exonerated the rootfs content

The board never printed `VFS: Mounted root (nfs filesystem)` nor `Run /sbin/init`
**successfully**. It died at the NFS **mount** stage, then fell through the
kernel's init fallback list (`/sbin/init` → `/etc/init` → `/bin/init` → `/bin/sh`)
and panicked because none existed on the (absent) rootfs.

This is the shortcut that saved the most time: **the content of the rootfs
(CFBox vs BusyBox) cannot affect whether the NFS mount succeeds** — mounting is
transport-level (obtain the root file handle), independent of what files live
under it. Since the mount itself failed, CFBox was not the suspect. The fault
was on the host/NFS side.

## Investigation

### Step 1 — Confirm init was never reached

The init fallback cascade (`Run /sbin/init … Run /bin/sh … No working init
found`) means the kernel had **no rootfs at all** — not a bad init, a missing
root. This pushed the fault to "NFS mount did not complete".

### Step 2 — Rule out stale `mountport` / wrong host IP

The bootargs hardcode `port=2049,mountport=20048`. First hypothesis: ganesha's
mountd had drifted off 20048 (a classic NFSv3 breakage). Checked:

```bash
sudo ss -lntu | grep -E ':2049|:20048'
# udp/tcp LISTEN on both 2049 and 20048  ✅

ip -4 addr | grep 'inet 192.168.60'
# inet 192.168.60.1/24 ... eth6  ✅   (this host IS the NFS server)
```

Both ruled out. Ports correct, host IP correct.

### Step 3 — ganesha log silence

```bash
sudo tail -80 /var/log/ganesha/ganesha.log
# only startup lines at 18:41:31; nothing from the board's boot attempt
```

Suspicious — but `ganesha.nfsd` runs at `-N NIV_EVENT`, which does not log every
MNT call, so silence alone is not conclusive. Needed packet-level proof.

### Step 4 — `tcpdump` on eth6: the smoking gun

```bash
sudo tcpdump -ni eth6 host 192.168.60.200 and \(port 2049 or port 20048 or port 111\)
```

The board's packets **did** arrive. The mountd (20048) MNT exchange completed and
handed the client a root file handle. The client then took that handle to nfsd
(2049) for `fsinfo` — and ganesha rejected it:

```text
.200.675 > .1.2049  NFS request  fsinfo fh 430000011A4375545A1B9701451EA034...
.1.2049  > .200.675 NFS reply   fsinfo ERROR: Stale NFS file handle     ← ESTALE
```

`MNT` (mountd) gave the client a handle that `nfsd` — the **same ganesha
process** — then declared stale. That internal contradiction is the signature of
a stale export cache, not a network or config problem.

## Root Cause

ganesha's **VFS FSAL caches the export's root file handle**, built from the inode
that the export `Path` resolves to at startup / export-load time.

Timeline:

1. ganesha started **18:41:31**, when `rootfs/nfs` was still the original
   (empty / previously-bound) directory. Its export root handle was pinned to
   **that** inode.
2. **Later**, `mount --bind out/rootfs-cfbox rootfs/nfs` changed which inode the
   path `rootfs/nfs` resolves to.
3. ganesha does **not** detect bind-mount changes. On the next client `MNT` it
   still returns the **old, cached** root handle.
4. The client uses that handle for `fsinfo`; ganesha's own nfsd can no longer
   resolve it against the current VFS state → **ESTALE**.
5. The kernel treats the root-fsinfo failure as a mount failure →
   `Unable to mount root fs via NFS` → init cascade → panic.

> The localhost self-mount test from the 06-08 note would have reproduced this
> immediately (`mount -t nfs -o vers=3 127.0.0.1:.../rootfs/nfs /tmp/nfs-test`
> would also ESTALE). Lesson reinforced: **prove the host can mount its own
> export first**, before looking at the board.

## Fix

After **any** bind-mount source change on the exported path, restart ganesha so
it rebuilds the export root handle against the new inode:

```bash
# 1) make sure the bind-mount you want is live
mountpoint rootfs/nfs && ls -l rootfs/nfs/sbin/init

# 2) restart ganesha — this is the actual fix
sudo systemctl restart nfs-ganesha

# 3) sanity: ports back up
sudo ss -lntu | grep -E ':2049|:20048'
```

Then reboot the board. The `MNT → fsinfo` flow now succeeds, the NFS root mounts,
and the kernel proceeds to `Run /sbin/init` (i.e. CFBox finally gets its turn).

## Operational Rule (the real takeaway)

**Every time you change the bind-mount source under `rootfs/nfs`, restart
ganesha.** In this project's workflow that means:

```bash
sudo ./scripts/manual_mount_nfs.sh --source=<some-rootfs>   # changes the bind-mount
sudo systemctl restart nfs-ganesha                            # MUST follow, else ESTALE
```

This applies to **every** rootfs swap — not just CFBox. Switching back to the
BusyBox release rootfs, or to any `out/...` rootfs, needs the same restart.

> Optional future improvement: `manual_mount_nfs.sh` could `systemctl reload
> nfs-ganesha` (or restart) after a successful bind mount, so this step cannot
> be forgotten. Not done yet — tracked as a possible enhancement.

## Triage One-Liner

> `Unable to mount root fs via NFS` **and** `tcpdump` shows the MOUNT RPC
> succeeding but the first `fsinfo` returning **`Stale NFS file handle`** →
> restart ganesha after your bind-mount change. Do not blame the board, bootargs,
> firewall, or the rootfs content.

## Command Cheat-Sheet

```bash
# Are nfs (2049) and mountd (20048) listening, and is it ganesha?
sudo ss -lntup | grep -E ':2049|:20048'

# Is this host the NFS server the board expects (192.168.60.1)?
ip -4 addr | grep 'inet 192.168.60'

# Did the board's requests reach ganesha? (reboot board while this runs)
sudo tcpdump -ni eth6 host 192.168.60.200 and \(port 2049 or port 20048 or port 111\)

# ganesha health + recent errors
sudo systemctl status nfs-ganesha --no-pager | head -5
sudo tail -120 /var/log/ganesha/ganesha.log

# The fix, after any bind-mount change
sudo systemctl restart nfs-ganesha
```

## Verified (2026-06-23)

After `sudo systemctl restart nfs-ganesha` (with the CFBox bind-mount in place),
the board mounted the NFS root and **CFBox ran as PID 1** on the i.MX6ULL:

```text
[   23.046167] Run /sbin/init as init process
=== CFBox rcS: mount -a ===
=== CFBox rcS: devpts ===
=== CFBox rcS: mdev -s ===
=== CFBox rcS: done ===
$                                    ← interactive shell on the serial console
```

cfbox init parsed the busybox-format `/etc/inittab`, ran `::sysinit:/etc/init.d/rcS`,
and respawned `/bin/sh` on the console. The fix is confirmed end-to-end.

One benign warning surfaced during rcS — `cfbox mount: /sys: Device or resource
busy` — caused by cfbox init already mounting `/sys` internally during sysinit,
so the busybox-style `mount -a` redundantly re-mounts it. Harmless; the CFBox
rcS just needs to drop the now-redundant `mount -a` for proc/sysfs. This is a
BusyBox→CFBox migration note, separate from the NFS issue above.

## See Also

- [2026-06-08 WSL2 NFS Rootfs Troubleshooting](2026-06-08-wsl2-nfsroot-ganesha-troubleshoot.md) — why we use ganesha (not kernel nfsd) in WSL2, the full `ganesha.conf`, and why `mountport=20048` is pinned.
- [manual_mount_nfs.sh](../scripts/manual_mount_nfs.sh.md) — the bind-mount helper (`--source=<rootfs> --target=rootfs/nfs`).
