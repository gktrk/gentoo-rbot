#!/bin/sh

x="$1"

cd ~
if [ "${x/\// }" == "${x}" ]; then
        wget -q -O ~/rindex.cache http://qa-reports.gentoo.org/output/genrdeps/rindex/.rindex
        x=$(grep /${x}$ ~/rindex.cache)
        x=$(echo -n ${x} |tr '\n' ' ')
        if [ "${x/ /}" != "${x}" ]; then
                echo "ambiguous short name $1.  Please specify one of the following fully-qualified ebuild names instead: $(echo $x | tr '\n' ' ')"
                exit 1
        fi
        [[ $x == "" ]] && exit 1
fi

foo=$(wget -q -O - http://qa-reports.gentoo.org/output/genrdeps/rindex/$x)
if [[ $foo != "" ]]; then
    for pkg in ${foo}; do
        cpv=${pkg%:*}
        use=${pkg/"${cpv}"}
        result=${result:+${result}$'\n'}$(qatom -C ${cpv} | cut -f 1-2 -d " " --output-delimiter "/" | tr -d "\n")${use}
    done
    echo $x '<-' $(sort -u <<< "${result}" | tr "\n" " ")
    exit $?
fi
exit 0
