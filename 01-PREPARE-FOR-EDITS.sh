#!/bin/bash

if ! python --version > /dev/null 2>&1  ; then
    echo "!!!!! PYTHON REQUIRED !!!!"
    echo "Aborting."
    exit 1
fi

set -e
WORKSPACE=WORKSPACE

# create the workspace
if [ -d $WORKSPACE ] ; then
    echo "Omitting workspace creation. ${WORKSPACE} already exists"
else
    mkdir $WORKSPACE
fi

# link-in the assets and layouts
for d in assets layouts zig_docs; do
    if [ ! -h ${WORKSPACE}/$d ] ; then
        ln -s ../$d ${WORKSPACE}/$d
    fi
done

# now create the .smd files
# NOTE: the .smd files are the authoritative source of existence
#       meaning: if there is no .smd file in contents, its associated
#       `.md` file will not move into the workspace.
# You can use above as a feature, adding .md files that are intended only for
# GH browsing use, even in the content/ directory; although, I'd advise against
# such shenanigans

# Note: the below is necessary to copy over .smd (only, no associated .md)
# files that would not be touched by processor.py because they don't need
# translation
mkdir -p ${WORKSPACE}/content
for i in $(find content -iname '*.smd') ; do
    SMD_FILE=$(basename $i)
    SUBDIR=$(dirname $i)
    SMD_SOURCE=$i
    SMD_DEST=${WORKSPACE}/${SUBDIR}/${SMD_FILE}
    echo "$SMD_DEST <-- $SMD_SOURCE"
    mkdir -p $(dirname $SMD_DEST)
    cat $SMD_SOURCE > $SMD_DEST
done
python processor.py EDIT content zml/docs WORKSPACE
