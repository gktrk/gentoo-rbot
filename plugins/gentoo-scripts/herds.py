#!/usr/bin/python

# must exist because marienz is lazy
cache_dir = './cachedir'
# in seconds
cache_max_age = 100

# python, pyxml
import sys, string, os
import urllib2
import os
import time
try:
    import cElementTree as etree
except ImportError:
    import xml.etree.cElementTree as etree

if len(sys.argv) < 2:
    print "usage: herds.py herdname"
    sys.exit(1)


root_node = elementtree.parse('./herds.xml')

if (sys.argv[1] == "-a"):
    herds = root_node.findall('herd/name')
    for herd in root_node.findall('herd/name'):
        print herd.text.strip()
    print
    sys.exit(0)

emails = []

for herd in root_node.findall('herd'):
    if herd.findtext('name') == sys.argv[1]:
        for dev in herd.findall('maintainer'):
            role = dev.findtext('role')
            email = dev.findtext('email').split('@')[0]
            if role and os.getenv("VERBOSE") == "1":
                email = '%s(%s)' % (email, role)
            emails.append(email)
        projects = list(herd.findall('maintainingproject'))
        if len(projects) > 1:
            print >> sys.stderr, ("I don't like multiple maintainingprojects "
                                  "per herd, Please fix me")
        if projects:
            project_path = projects[0].text
            cache_file = os.path.join(cache_dir, '%s.xml' % sys.argv[1])
            if (not os.path.exists(cache_file) or
                (time.time() - os.path.getmtime(cache_file) > cache_max_age)):
                # update the cached file
                cache_file_obj = open(cache_file, 'w')
                try:
                    f = urllib2.urlopen(
                        'http://www.gentoo.org%s?passthru=1' % project_path)
                    while True:
                        data = f.read(1024)
                        if not data:
                            break
                        cache_file_obj.write(data)
                    cache_file_obj.close()
                except:
                    # Do not keep a stale cache file around.
                    os.unlink(cache_file)
                    raise

            try:
                project_node = elementtree.parse(cache_file)
            except:
                # Force a reload by killing the cache.
                os.unlink(cache_file)
                raise
            for dev in project_node.findall('dev'):
                emails.append(dev.text.strip())
        break

else:
    print >> sys.stderr, 'no such herd!'

        
if len(emails) < 1:
        print "herd doesn't exist or has no maintainers or herds.xml is out of date"
        # or the mtimedb bug around line 7263 in the portageexit() function is still present"
        sys.exit(1)

emails.sort()
print ", ".join(emails)
