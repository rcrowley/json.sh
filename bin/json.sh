#!/bin/sh

# `json.sh`, a pure-shell JSON parser.

set -e

# Load the `json` function and its friends.  These are assumed to be
# in the `lib` directory in the same tree as this `bin` directory.
. "$(dirname "$(dirname "$0")")/lib/json.sh"

json
