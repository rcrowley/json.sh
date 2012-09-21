set -e

# Source the `json.sh` library.
. "lib/json.sh"

# Call the `json` function, passing JSON on standard input and diffing
# standard output against a known-good copy.
find "tests" -type f -name "*.json" | while read PATHNAME
do
	echo "$PATHNAME" >&2
	json <"$PATHNAME" | diff -u "$PATHNAME.out" -
done
