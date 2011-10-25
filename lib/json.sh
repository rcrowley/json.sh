# json.sh, a pure-shell JSON parser

set -e

# File descriptor 3 is commandeered for debug output, which may end up being
# forwarded to standard error.
[ -z "$JSON_DEBUG" ] && exec 3>/dev/null || exec 3>&2

# File descriptor 4 is commandeered for use as a sink for literal and
# variable output of (inverted) sections that are not destined for standard
# output because their condition is not met.
exec 4>/dev/null

json() {

	# Initialize the file descriptor to be used to emit characters.  At
	# times this value will be 4 to send output to `/dev/null`.
	_J_FD=1

	_J_PATHNAME="/" _J_STATE="whitespace" _J_STATE_DEFAULT="whitespace"

	# IFS must only contain '\n' so as to be able to read space and tab
	# characters from standard input one-at-a-time.  The easiest way to
	# convince it to actually contain the correct byte, and only the
	# correct byte, is to use a single-quoted literal newline.
	IFS='
'

	# Consuming standard input one character at a time is quite a feat
	# within the confines of POSIX shell.  Bash's `read` builtin has
	# `-n` for limiting the number of characters consumed.  Here it is
	# faked using `sed`(1) to place each character on its own line.
	# The subtlety is that real newline characters are chomped so they
	# must be indirectly detected by checking for zero-length
	# characters, which is done as the character is emitted.
	sed -r "
		s/./&\\n/g
		s/\\\\/\\\\\\\\/g
	" | _json

	# TODO Replace the original value of IFS.  Be careful if it's unset.

}

_json() {
	while read _J_C
	do
		echo " _J_C: $_J_C (${#_J_C}), _J_STATE: $_J_STATE" >&3
		case "$_J_STATE" in

			"array"|"whitespace")
				if [ "$_J_STATE" = "array" ]
				then
					case "$_J_C" in
						",")
							_J_DIRNAME="$(dirname "$_J_PATHNAME")"
							[ "$_J_DIRNAME" = "/" ] && _J_DIRNAME=""
							_J_BASENAME="$(basename "$_J_PATHNAME")"
							_J_BASENAME="$(($_J_BASENAME + 1))"
							_J_PATHNAME="$_J_DIRNAME/$_J_BASENAME"
							continue;;
						"]") exit;;
					esac
				fi
				case "$_J_C" in
					"\"") _J_STATE="string" _J_V="";;
					"-") _J_STATE="number-negative" _J_V="$_J_C";;
					0) _J_STATE="number-leading-zero" _J_V="$_J_C";;
					[1-9]) _J_STATE="number-leading-nonzero" _J_V="$_J_C";;
					"[")
						(
							[ "$_J_PATHNAME" = "/" ] && _J_PATHNAME=""
							_J_PATHNAME="$_J_PATHNAME/0"
							_J_STATE="array" _J_STATE_DEFAULT="array"
							_json
						)
						exit;;
					"f"|"t") _J_STATE="boolean" _J_V="$_J_C";;
					"n") _J_STATE="null" _J_V="$_J_C";;
					"{")
						(
							_J_STATE="object" _J_STATE_DEFAULT="object"
							_json
						)
						exit;;
					"	"|""|" ") ;;
					*) _json_die "syntax: $_J_PATHNAME";;
				esac;;

			"boolean")
				case "$_J_V$_J_C" in
					"f"|"fa"|"fal"|"fals"|"t"|"tr"|"tru") _J_V="$_J_V$_J_C";;
					"false"|"true")
						_J_STATE="$_J_STATE_DEFAULT"
						echo "$_J_PATHNAME boolean $_J_V$_J_C" >&$_J_FD;;
					*) _json_die "syntax: $_J_PATHNAME boolean $_J_V$_J_C";;
				esac;;

			"object")
				case "$_J_C" in
					"\"")
						_J_FD=4
						_J_STATE="string"
						_J_STATE_DEFAULT="object-value"
						_J_V="";;
					",") ;; # TODO Should imply another key is coming.
					"}") exit;;
					"	"|""|" ") ;;
					*) _json_die "syntax: $_J_PATHNAME";;
				esac;;

			"object-exit") exit;;

			"object-value")
				case "$_J_C" in
					":")
						_J_FD=1
						(
							[ "$_J_PATHNAME" = "/" ] && _J_PATHNAME=""
							_J_PATHNAME="$_J_PATHNAME/$_J_V"
							_J_STATE="whitespace"
							_J_STATE_DEFAULT="object-exit"
							_json
						)
						_J_STATE="object";;
					"	"|""|" ") ;;
					*) _json_die "syntax: $_J_PATHNAME";;
				esac;;

			"null")
				case "$_J_V$_J_C" in
					"n"|"nu"|"nul") _J_V="$_J_V$_J_C";;
					"null")
						_J_STATE="$_J_STATE_DEFAULT"
						echo "$_J_PATHNAME null null" >&$_J_FD;;
					*) _json_die "syntax: $_J_PATHNAME null $_J_V$_J_C";;
				esac;;

			"number-float")
				case "$_J_C" in
					[0-9]) _J_V="$_J_V$_J_C";;
					"E"|"e") _J_STATE="number-sci" _J_V="$_J_V$_J_C";;
					*)
						_J_STATE="$_J_STATE_DEFAULT"
						echo "$_J_PATHNAME number $_J_V" >&$_J_FD;;
				esac;;

			"number-leading-nonzero")
				case "$_J_C" in
					".") _J_STATE="number-float" _J_V="$_J_V$_J_C";;
					[0-9]) _J_V="$_J_V$_J_C";;
					"E"|"e") _J_STATE="number-sci" _J_V="$_J_V$_J_C";;
					*)
						_J_STATE="$_J_STATE_DEFAULT"
						echo "$_J_PATHNAME number $_J_V" >&$_J_FD;;
				esac;;

			"number-leading-zero")
				case "$_J_C" in
					".") _J_STATE="number-float" _J_V="$_J_V$_J_C";;
					[0-9]) _json_die "syntax: $_J_PATHNAME number $_J_V$_J_C";;
					"E"|"e") _J_STATE="number-sci" _J_V="$_J_V$_J_C";;
					*)
						_J_STATE="$_J_STATE_DEFAULT"
						echo "$_J_PATHNAME number $_J_V" >&$_J_FD;;
				esac;;

			"number-negative")
				case "$_J_C" in
					".") _J_STATE="number-float" _J_V="$_J_V$_J_C";;
					[0-9]) _J_V="$_J_V$_J_C";;
					"E"|"e") _J_STATE="number-sci" _J_V="$_J_V$_J_C";;
					*)
						_J_STATE="$_J_STATE_DEFAULT"
						echo "$_J_PATHNAME number $_J_V" >&$_J_FD;;
				esac;;

			"number-sci")
				case "$_J_C" in
					"+") _J_STATE="number-sci-pos" _J_V="$_J_V$_J_C";;
					"-") _J_STATE="number-sci-neg" _J_V="$_J_V$_J_C";;
					[0-9]) _J_STATE="number-sci-pos" _J_V="$_J_V$_J_C";;
					*) _json_die "syntax: $_J_PATHNAME number $_J_V$_J_C";;
				esac;;

			"number-sci-neg"|"number-sci-pos")
				case "$_J_C" in
					[0-9]) _J_V="$_J_V$_J_C";;
					*)
						_J_STATE="$_J_STATE_DEFAULT"
						echo "$_J_PATHNAME number $_J_V" >&$_J_FD;;
				esac;;

			"string")
				case "$_J_PREV_C$_J_C" in
					"\\\""|"\\/"|"\\\\") _J_V="$_J_V$_J_C";;
					"\\b"|"\\f"|"\\n"|"\\r") ;; # TODO
					"\\u") ;; # TODO
					*"\"")
						_J_STATE="$_J_STATE_DEFAULT"
						echo "$_J_PATHNAME string $_J_V" >&$_J_FD;;
					*"\\") ;;
					*) _J_V="$_J_V$_J_C";;
				esac;;

		esac
		_J_PREV_C="$_J_C"
	done

}

# Print an error message and GTFO.  The message is the concatenation
# of all the arguments to this function.
_json_die() {
	echo "json.sh: $*" >&2
	exit 1
}
