	    ______ ______ ___    _____ _________
	   /  _  //   __//   \  /  _  /_      _/
	  /  ___/ \  \  /  /  \/     / /  /  /
	 /  __  /_/   \/  /   /  //  //  /  /
	/______/______/______/__//__//  /  /
	                           _/  /  /_
	REVENGE OF THE SCRIPT     /________/

BSD Administration Scripts II
=============================

I started this long overdue overhaul of the BSD Administration Scripts
at the 31C3 (Hamburg, 2014).

It provides a recode of pkg_libchk, distviper and a cleaned up version
of the buildflags toolset. The first tool exclusive to bsda2 is pkg_trim.

Other members of the original bsdadminscripts are not provided, because
they have become obsolete due to changes in the FreeBSD operating
system.

TOC
---

1. [Tools](#tools)
   1. [pkg_libchk](#pkg_libchk)
   2. [pkg_trim](#pkg_trim)
   3. [pkg_validate](#pkg_validate)
   4. [distviper](#distviper)
   5. [buildflags](#buildflags)
   6. [makeplist](#makeplist)
   7. [loaderupdate](#loaderupdate)
   8. [bprintf](#bprintf)
2. [bsda:obj](#bsdaobj)
3. [Install](#install)
3. [LICENSE](#license)

Tools
-----

### pkg_libchk

The pkg_libchk tool provides the means to find packages that need to be
rebuild/reinstalled, because they have been linked to a library that
is no longer around.

What sets its apart from other such tools or pkg-check, is that it makes
a decent job of avoiding false positives.

The recode is also 6 times faster than the old script.

### pkg_trim

The pkg_trim tool provides a convenient means to get rid of (no longer
required) packages.

It presents leaf packages (packages that are not required by other
packages) in a checklist and offers the option to delete them or
mark them for later removal with `pkg autoremove`.

### pkg_validate

The pkg_validate tool lists mismatched and missing files of installed
packages.

Its advantages over running `pkg check -s` are faster execution time
and the ability to run it as an unprivileged user.

### distviper

The distviper tool removes obsolete files from `/usr/ports/distfiles`
(or wherever `DISTDIR` points).

### buildflags

Buildflags provides a configuration wrapper to set `make` flags  depending
on the current location in the file system.

A `buildflags.conf` may look like this:

```mk
/usr/ports/*{
	WRKDIRPREFIX=/tmp/obj

	# Porting
	DEVELOPER
	.sinclude "${HOME}/mk/makeplist.mk"

	# Clustering
	USE_DISTCC
	USE_CCACHE

	# Common settings that are applied to all ports in hope to do some good
	TEX_DEFAULT=texlive
	PAPERSIZE=a4

	# Problems with ccache/distcc
	*/audio/cmus             {!USE_CCACHE !USE_DISTCC}
	*/archivers/lzip         {!USE_CCACHE !USE_DISTCC}
}
```

It results in the following `make` output:

```mk
.if ${.CURDIR:M/usr/ports/*}
WRKDIRPREFIX=/tmp/obj

# Porting
DEVELOPER=              yes
.sinclude "${HOME}/mk/makeplist.mk"

# Clustering
USE_DISTCC=             yes
USE_CCACHE=             yes

# Common settings that are applied to all ports in hope to do some good
TEX_DEFAULT=texlive
PAPERSIZE=a4

# Problems with ccache/distcc
.if ${.CURDIR:M*/audio/cmus}
.undef USE_CCACHE
.undef USE_DISTCC
.endif # */audio/cmus
.if ${.CURDIR:M*/archivers/lzip}
.undef USE_CCACHE
.undef USE_DISTCC
.endif # */archivers/lzip
.endif # /usr/ports/*
```

### makeplist

The makeplist script provides a means for port maintainers and committers
to automatically generate a `pkg-plist` file.

What sets it apart is its support for options and that it plays nice
with a lot of `bsd.port.mk` macros like `DESKTOP_ENTRIES`, `USE_RC_SUBR`
or `PLIST_FILES`.

### loaderupdate

Update the boot loaders of bootable devices, by applying the loaders
from a boot environment to a set of bootable devices.

A boot environment, a mount containing a populated `/boot`, can be
provided via the `-d` parameter or `DESTDIR` environment variable.

The first command to run is `loaderupdate --dump`, it publishes
loaderupdate's understanding of the boot environment and its tasks:

```sh
# loaderupdate -P nvd0
Boot Environment
----------------
destdir:                /
ostype:                 FreeBSD
kernel version:         FreeBSD 12.2-STABLE 760e643de558(kami/12) SCO15M19
kernel arch:            amd64
file system:            zfs
protective MBR:         /boot/pmbr
freebsd-boot loader:    /boot/gptzfsboot
EFI loader:             /boot/loader.efi

Device nvd0
-----------
    install:            /boot/pmbr > nvd0
    install:            /boot/gptzfsboot > nvd0p1
    install:            /boot/loader.efi > nvd0p2:/efi/FreeBSD/bootamd64.efi
    EFI boot entry:     FreeBSD 12.2-STABLE 760e643de558(kami/12) SCO15M19 amd64 [nvd0p2]
```

Before committing to an update `loaderupdate --dry-run` can list all
of the commands it will run:

```sh
# loaderupdate -D nvd0
gpart bootcode -b/boot/pmbr nvd0
gpart bootcode -p/boot/gptzfsboot -i1 nvd0
mkdir -p nvd0p2
mount -tmsdosfs -osync /dev/nvd0p2 nvd0p2
mkdir -p nvd0p2/efi/FreeBSD
cp /boot/loader.efi nvd0p2/efi/FreeBSD/bootamd64.efi
efibootmgr -B 0001
efibootmgr -cl nvd0p2:/efi/FreeBSD/bootamd64.efi -L 'FreeBSD 12.2-STABLE 760e643de558(kami/12) SCO15M19 amd64 [nvd0p2]'
efibootmgr -a 0001
```

This enables users to review every command performed and tweak parameters.

### bprintf

A printf(1) like tool providing string formatting based on named
fields instead of argument order.

- Named arguments enable multiple use of the same argument within
  a string
- Formatting strings that do not use all arguments can be used
- Arithmetic expressions within format specifications provide additional
  formatting flexibility

```sh
# bprintf '| {var:(wx/3-3)} | {value:(wx/3+wx%3-2).3f} {unit:-(wx/3-3)} |\n' wx=36 var=g value=9.81 unit=m/s^2
|         g |      9.810 m/s^2     |
```

[bsda:obj](ref/bsda_obj.md)
---------------------------

The bsda:obj framework dates back to the hacker conference GPN8 
(Karlsruhe, 2009). It provides OO fu for shell scripts, like classes with
introspection, return by reference, serialisation or lazy garbage collection.

Along with it comes a bunch of libraries targeted at common tasks like
rich status line display, formatting and inter process communication.

It was presented at EuroBSDCon 2010.

Install
-------

To install the scripts run `install.sh`:

	./install.sh

The install script supports the following parameters, which are set in the
following way:

	-parameter=value

* `-destidr=`
  This is prepended to prefix and can be used to install into a
  jail/chroot, other mounted systems etc. It does not affect
  where installed scripts assume they are.
* `-prefix=/usr/local`
  The prefix that separates the files to be installed from the
  base system.
* `-datadir=$prefix/share/bsda2`
  The data dir where shared code is installed.
* `-docsdir=$prefix/share/doc/bsda2`
  The location to install markdown documentation files.
* `-ports=/usr/ports`
  The location of the ports tree.
* `-nodoc`
  Set this to not install manual pages and markdown documentation.

Be aware that `install.sh` and `deinstall.sh` have to be called with the same
arguments to install/deinstall the same files.

LICENSE
-------

For those who care about this stuff, this project is available under
the [ISC license](LICENSE.md).
