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

python processor.py COMMIT content zml/docs WORKSPACE

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
