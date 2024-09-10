#!/bin/bash
WORKSPACE=WORKSPACE

# loop over all .smd files in WORKSPACE/content
#     - split their YAML off into the file ./content....
#     - split their markdown off into the file ./zml/docs/content....

if ! python --version > /dev/null 2>&1  ; then
    echo "!!!!! PYTHON REQUIRED !!!!"
    echo "Aborting."
    exit 1
fi

for i in $(find ${WORKSPACE}/content -iname '*.smd') ; do
    SMD_FILE=$(basename $i)
    MD_FILE=$(echo $SMD_FILE | sed 's/.smd/.md/')
    SUBDIR=$(echo $(dirname $i) | sed "s/$WORKSPACE\///")
    MD_DEST=zml/docs/$SUBDIR/$MD_FILE
    SMD_DEST=./$SUBDIR/$SMD_FILE
    echo "$i -> $SMD_DEST + $MD_DEST"
    python split.py $i $SMD_DEST $MD_DEST
done

echo ""
echo ""
echo ""
echo "======================================================================"
echo "Changes in this repo:"
echo "======================================================================"
git status

echo ""
echo ""
echo ""
echo "======================================================================"
echo "Changes in zml repo:"
echo "======================================================================"
git -C zml status
