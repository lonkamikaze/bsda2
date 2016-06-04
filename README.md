	    ______  ______  ___     _____    _________
	   /  _  / /   __/ /   \   /  _  /   \
	  /  ___/  \  \   /  /  \ /     /    /  /  /
	 /  __  /__/   \ /  /   //  //  /   /  /  /
	/______//______//______//__//__/  ________\

BSD Administration Scripts II
=============================

I started this long overdue overhaul of the BSD Administration Scripts
at the 31C3 (Hamburg, 2014).

It provides a recode of pkg_libchk, and a cleaned up version of
the buildflags toolset.

pkg_libchk
----------

The pkg_libchk tool provides the means to find packages that need to be
rebuild/reinstalled, because they have been linked to a library that
is no longer around.

What sets its apart from other such tools or pkg-check, is that it makes
a decent job of avoiding false positives.

The recode is also 6 times faster than the old script.

buildflags
----------

Buildflags provides a configuration wrapper to set `make` flags  depending
on the current location in the file system.

A `buildflags.conf` may look like this:

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

It results in the following `make` output:

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

[bsda:obj](bsda_obj.md)
-----------------------

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
following way:

	-parameter=value

* -destidr=
  This is prepended to prefix and can be used to install into a
  jail/chroot, other mounted systems etc. It does not affect
  where installed scripts assume they are.
* -prefix=/usr/local
  The prefix that separates the files to be installed from the
  base system.
* -datadir=$prefix/share/bsdadminscripts2
  The data dir where shared code is installed.
* -nodoc
  Set this to not install manual pages.

Be aware that install.sh and deinstall.sh have to be called with the same
parameters.
