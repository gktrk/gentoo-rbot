#!/usr/bin/python -O

# Copyright (C) 2004 Eric Olinger, http://evvl.rustedhalo.net
# Distributed under the terms of the GNU General Public License, v2 or later
# Author : Eric Olinger <EvvL AT RustedHalo DOT net>

# I changed stuff. solar@gentoo.org

import os,sys

sys.stderr=open("/dev/null","w")

import portage,string,re
from stat import *
from output import *
from xml.sax import saxutils, make_parser, handler
from xml.sax.handler import feature_namespaces

nocolor()

version="0.2.5"

def usage(code):
	"""Prints the uage information for this script"""
	print green("metadata v" + version + "\n")
	print "Usage: metadata [package-cat/]package"
	sys.exit(code)

def grab_changelog_stuff(catpkg):
	try:
		foo=""
		os.chdir(portage.settings["PORTDIR"] + "/" + catpkg)
		r=re.compile("<[A-Za-z_0-9]+@gentoo.org>", re.I)

		s="\n".join(portage.grabfile("ChangeLog"))

		d={}
		for x in r.findall(s):
			if x not in d:
				d[x] = 0
			d[x] += 1

		l=[(d[x], x) for x in d.keys()]
		l.sort(lambda x,y: cmp(y[0], x[0]))
		for x in l:
			p = str(x[0]) +" "+ x[1].lstrip("<").rstrip(">")
			foo += p[:p.find("@")]+", "
		return foo
	except:
		raise

def main ():
	if len( sys.argv ) < 2:
		usage( 1 )

	for pkg in sys.argv[1:]:
		package_list = portage.portdb.xmatch("match-all", pkg)
		print darkgreen("Package: ") + portage.pkgsplit(package_list[0])[0] + " " + darkgreen("ChangeLog: ") + grab_changelog_stuff(portage.pkgsplit(package_list[0])[0])

if __name__ == '__main__':
	main()
