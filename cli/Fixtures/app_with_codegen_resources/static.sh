#!/bin/sh
set -e
/usr/bin/python3 -c '
import json, os
for output in json.load(open(os.environ["TUIST_OUTPUTS_FILE"])):
    open(os.path.join(output["path"], "static.txt"), "w").write("Static")
'
