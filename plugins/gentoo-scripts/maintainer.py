#!/usr/bin/python -O

# Copyright (C) 2007 
# Distributed under the terms of the GNU General Public License, v2 or later

# I changed stuff. solar@gentoo.org
# marienz@g.o also changed stuff.

import sys

import os
import re

# temporarily redirect stderr to dev/null to avoid spammage
stderr = sys.stderr
sys.stderr = open('/dev/null', 'w')
import portage
# and reset it
sys.stderr = stderr

from stat import *
from output import *

try:
    import cElementTree as etree
except ImportError:
    import xml.etree.cElementTree as etree

nocolor()

version="0.0.2"

def usage(code):
	"""Prints the uage information for this script"""
	print green("metadata v" + version + "\n")
	print "Usage: metadata [package-cat/]package"
	sys.exit(code)


def check_metadata(full_package):
	"""Returns a string of metadata data or None if missing."""
	metadata_file = '%s/%s/metadata.xml' % (
		portage.settings["PORTDIR"],
		portage.pkgsplit(full_package)[0])
	if not os.path.exists(metadata_file):
		return None
	metadata = etree.parse(metadata_file)
	ret = []

	herds = []
	maintainers = []

	for maint in metadata.findall('maintainer'):
		email = maint.findtext('email')
		if email:
			maintainers.append(email)


	if not maintainers:
		for herd in metadata.findall('herd'):
			if herd.text:
				herds.append(herd.text)
		ret.append(" ".join(herds))
	else:
		ret.append(" ".join(maintainers))

	return ''.join(ret).encode('ascii', 'replace')


def main ():
	if len( sys.argv ) < 2:
		usage( 1 )


	for pkg in sys.argv[1:]:
		pkg = portage.dep_getkey(pkg)
		package_list = portage.portdb.xmatch("match-all", pkg)
		if not package_list:
			return
		metadata = check_metadata(package_list[0])
		if metadata is not None:
			print(' '.join(metadata.split()))


if __name__ == '__main__':
	main()
