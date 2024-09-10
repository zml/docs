#!/bin/bash
# - clone zml
# - check out optional REF passed in via args
#     - REF can also be -b ...
set -xe

if [ -d zml ] ; then
    echo "Omitting cloning of zml, it's already present!"
else
    git clone git@github.com:zml/zml.git zml
fi

if [ -n "$1" ] ; then
    git -C zml checkout $@
fi
