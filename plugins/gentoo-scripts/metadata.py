#!/usr/bin/python -O

# Copyright (C) 2004 Eric Olinger, http://evvl.rustedhalo.net
# Distributed under the terms of the GNU General Public License, v2 or later
# Author : Eric Olinger <EvvL AT RustedHalo DOT net>

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
from portage.output import *

try:
    import cElementTree as etree
except ImportError:
    import xml.etree.cElementTree as etree

nocolor()

version="0.2.5"

MAX_LONGDESC_LEN = os.getenv("MAX_LONGDESC_LEN")
if MAX_LONGDESC_LEN == None:
	MAX_LONGDESC_LEN = 80
else:
	MAX_LONGDESC_LEN = int(MAX_LONGDESC_LEN)

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
	for herd in metadata.findall('herd'):
		if herd.text:
			herds.append(herd.text)
		else:
			herds.append(red('bogus empty herd'))
	if herds:
		ret.append(darkgreen(" Herd: ") + ", ".join(herds))

	maintainers = []
	for maint in metadata.findall('maintainer'):
		email = maint.findtext('email')
		desc = maint.findtext('description')
		if email:
			maintainers.append(email)
		else:
			maintainers.append(red('bogus (empty?) maintainer'))
		if desc:
			maintainers.append("(Maint-desc: "+desc+")")

	if not maintainers:
		ret.append(darkgreen(" Maintainer: ") + ", ".join(herds))
	else:
		ret.append(darkgreen(" Maintainer: ") + ", ".join(maintainers))
	longdesc = metadata.findtext('longdescription')
	if longdesc:
		longdesc = longdesc.replace('\n', ' ')
		if len(longdesc) > MAX_LONGDESC_LEN:
			longdesc = longdesc[:MAX_LONGDESC_LEN] + '...'
		ret.append(darkgreen(" Description: ") + longdesc)
	return ''.join(ret).encode('ascii', 'replace')


def grab_changelog_stuff(catpkg):
	foo=""
	os.chdir(portage.settings["PORTDIR"] + "/" + catpkg)
	r=re.compile("<[^@]+@gentoo.org>", re.I)

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


def main ():
	if len( sys.argv ) < 2:
		usage( 1 )


	for pkg in sys.argv[1:]:
		package_list = portage.portdb.xmatch("match-all", pkg)
		if not package_list:
			print red('%r does not exist' % pkg)
			return
		metadata = check_metadata(package_list[0])
		if metadata is not None:
			print(darkgreen("Package: ") + portage.pkgsplit(package_list[0])[0] + " " + ' '.join(metadata.split()))
		else:
			print darkgreen("Package: ") + portage.pkgsplit(package_list[0])[0] + " " + darkgreen("Metadata: missing? candidate for tree removal") +" "+ darkgreen("ChangeLog: ") + grab_changelog_stuff(portage.pkgsplit(package_list[0])[0])

if __name__ == '__main__':
	main()
