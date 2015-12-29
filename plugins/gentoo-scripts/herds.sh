HERDS_SRC='https://api.gentoo.org/packages/herds.xml'
wget -O herds.xml -q "${HERDS_SRC}"
if [ ! -s herds.xml ]; then
	cp /usr/portage/metadata/herds.xml .
fi
