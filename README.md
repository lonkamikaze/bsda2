BSD Administration Scripts II
=============================

      ______  ______  ___     _____    _________
     /  _  / /   __/ /   \   /  _  /   \
    /  ___/  \  \   /  /  \ /     /    /  /  /
   /  __  /__/   \ /  /   //  //  /   /  /  /
  /______//______//______//__//__/  ________\


I started this long overdue overhaul of the BSD Administration Scripts
at the 31C3 (Hamburg, 2014).

Right now this collection only provides a recode of pkg_libchk,

pkg_libchk
----------

The pkg_libchk tool provides the means to find packages that need to be
rebuild/reinstalled, because they have been linked to a library that
is no longer around.

What sets its apart from other such tools or pkg-check, is that it makes
a decent job of avoiding false positives.

The recode is also 6 times faster than the old script.

bsda:obj
--------

The bsda:obj framework dates back to the hacker conference GPN8 
(Karlsruhe, 2009). It provides OO foo for shell scripts, like classes with
introspection, return by reference, serialisation or lazy garbage collection.

Along with it comes a bunch of libraries targeted at common tasks like
rich status line display, formatting and inter process communication.

It was presented at EuroBSDCon 2010.

Install
-------

To install the scripts go into the src/ directory and run the command:
	./install.sh

The install script supports the following parameters, which are set in the
following way: -parameter=value

	-destidr=
		This is prepended to prefix and can be used to install into a
		jail/chroot, other mounted systems etc. It does not affect
		where installed scripts assume they are.

	-prefix=/usr/local
		The prefix that separates the files to be installed from the
		base system.

	-datadir=$prefix/share/bsdadminscripts2
		The data dir where shared code is installed.

	-nodoc
		Set this to not install manual pages.

Be aware that install.sh and deinstall.sh have to be called with the same
parameters.
