#!/bin/sh
/usr/bin/python `dirname $0`/earch $1 | tr '\n' ' '
echo
