# `json.sh`, a pure-shell JSON parser.

set -e

# Most users will be happy with the default '/' separator that makes trees
# of keys look like filesystem paths but that breaks down if keys can
# contain slashes.  In that case, set `JSON_SEPARATOR` to desired character.
[ -z "$JSON_SEPARATOR" ] && _J_S="/" || _J_S="$JSON_SEPARATOR"

# File descriptor 3 is commandeered for debug output, which may end up being
# forwarded to standard error.
[ -z "$JSON_DEBUG" ] && exec 3>/dev/null || exec 3>&2

# File descriptor 4 is commandeered for use as a sink for literal and
# variable output of (inverted) sections that are not destined for standard
# output because their condition is not met.
exec 4>/dev/null

# Consume standard input one character at a time to parse JSON.
json() {

	# Initialize the file descriptor to be used to emit characters.  At
	# times this value will be 4 to send output to `/dev/null`.
	_J_FD=1

	# Initialize storage for the "pathname", the concatenation of all
	# the keys in the tree at any point in time, the current state of
	# the machine, and the state to which the machine returns after
	# completing a key or value.
	_J_PATHNAME="$_J_S" _J_STATE="whitespace" _J_STATE_DEFAULT="whitespace"

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
	sed "
		s/./&$(printf "\036")/g
		s/\\\\/\\\\\\\\/g
	" | tr "\036" "\n" | _json

	# TODO Replace the original value of IFS.  Be careful if it's unset.

}

# Consume the one-character-per-line stream from `sed` via a state machine.
# This function will be called recursively in subshell environments to
# isolate values from their containing scope.
#
# The `read` builtin consumes one line at a time but by now each line
# contains only a single character.
_json() {
	while read _J_C
	do
		_json_char
		_J_PREV_C="$_J_C"
	done
}

# Consume a single character as stored in `_J_C`.  This function is broken
# out from `_json` so it may be called to reconsume a character as is
# necessary following the end of any number since numbers do not have a
# well-known ending in the grammar.
#
# The state machine implemented here follows very naturally from the
# diagrams of the JSON grammar on <http://json.org>.
_json_char() {
	echo " _J_C: $_J_C (${#_J_C}), _J_STATE: $_J_STATE" >&3
	case "$_J_STATE" in

		# The machine starts in the "whitespace" state and learns
		# from leading characters what state to enter next.  JSON's
		# grammar doesn't contain any tokens that are ambiguous in
		# their first character so the parser's job is relatively
		# easier.
		#
		# Further whitespace characters are consumed and ignored.
		#
		# Arrays are unique in that their parsing rules are a strict
		# superset of the rules in open whitespace.  When an opening
		# bracket is encountered, the remainder of the array is
		# parsed in a subshell which goes around again when a comma
		# is encountered and exits back to the containing scope when
		# the closing bracket is encountered.
		#
		# Objects are not parsed as a superset of open whitespace but
		# they are parsed in a subshell to protect the containing scope.
		"array-0"|"array-even"|"array-odd"|"whitespace")
			case "$_J_STATE" in
				"array-0")
					case "$_J_C" in
						"]") exit;;
					esac;;
				"array-even")
					case "$_J_C" in
						",")
							_J_DIRNAME="${_J_PATHNAME%"$_J_S"*}"
							[ "$_J_DIRNAME" = "$_J_S" ] && _J_DIRNAME=""
							_J_BASENAME="${_J_PATHNAME##*"$_J_S"}"
							_J_BASENAME="$(($_J_BASENAME + 1))"
							_J_PATHNAME="$_J_DIRNAME$_J_S$_J_BASENAME"
							_J_STATE="array-odd"
							continue;;
						"]") exit;;
					esac;;
			esac
			case "$_J_C" in
				"\"") _J_STATE="string" _J_V="";;
				"-") _J_STATE="number-negative" _J_V="$_J_C";;
				0) _J_STATE="number-leading-zero" _J_V="$_J_C";;
				[1-9]) _J_STATE="number-leading-nonzero" _J_V="$_J_C";;
				"[")
					(
						[ "$_J_PATHNAME" = "/" ] && _J_PATHNAME=""
						_J_PATHNAME="$_J_PATHNAME/0"
						_J_STATE="array-0" _J_STATE_DEFAULT="array-even"
						_json
					)
					_J_STATE="$_J_STATE_DEFAULT" _J_V="";;
				"f"|"t") _J_STATE="boolean" _J_V="$_J_C";;
				"n") _J_STATE="null" _J_V="$_J_C";;
				"{")
					(
						_J_STATE="object-0" _J_STATE_DEFAULT="object-even"
						_json
					)
					_J_STATE="$_J_STATE_DEFAULT" _J_V="";;
				"	"|""|" ") ;;
				*) _json_die "syntax: $_J_PATHNAME";;
			esac;;

		# Boolean values are multicharacter literals but they're unique
		# from their first character.  This means the eventual value is
		# already known when the "boolean" state is entered so we can
		# raise syntax errors as soon as the input goes south.
		"boolean")
			case "$_J_V$_J_C" in
				"f"|"fa"|"fal"|"fals"|"t"|"tr"|"tru") _J_V="$_J_V$_J_C";;
				"false"|"true")
					_J_STATE="$_J_STATE_DEFAULT"
					echo "$_J_PATHNAME boolean $_J_V$_J_C" >&$_J_FD;;
				*) _json_die "syntax: $_J_PATHNAME boolean $_J_V$_J_C";;
			esac;;

		# Object values are relatively more complex than array values.
		# They begin in the "object-0" state, which is almost but not
		# quite a subset of the "whitespace" state for strings.  When
		# a string is encountered it is parsed as usual but the parser
		# is set to return to the "object-value" state afterward.
		#
		# As in the "whitespace" state, extra whitespace characters
		# are consumed and ignored.
		#
		# The parser will return to this "object" state later to
		# either consume a comma and go around again or exit the
		# subshell in which this object has been parsed.
		"object-0")
			case "$_J_C" in
				"\"")
					_J_FD=4
					_J_STATE="string"
					_J_STATE_DEFAULT="object-value"
					_J_V="";;
				"}") exit;;
				"	"|""|" ") ;;
				*) _json_die "syntax: $_J_PATHNAME";;
			esac;;

		# "object-even" is like "object-0" but additionally commas are
		# consumed to enforce the another key/value pair is coming.
		"object-even")
			case "$_J_C" in
				"\"")
					_J_FD=4
					_J_STATE="string"
					_J_STATE_DEFAULT="object-value"
					_J_V="";;
				",") _J_STATE="object-odd";;
				"}") exit;;
				"	"|""|" ") ;;
				*) _json_die "syntax: $_J_PATHNAME";;
			esac;;

		# Object values have to return from whence they came.  They use
		# the "object-exit" state to signal the last character consumed
		# to the containing scope.
		"object-exit") #exit;;
			case "$_J_C" in
				",") exit 101;;
				"}") exit 102;;
				*) exit 0;;
			esac;;

		# "object-even" is like "object-0" but cannot consume a closing
		# brace because it has just consumed a comma.
		"object-odd")
			case "$_J_C" in
				"\"")
					_J_FD=4
					_J_STATE="string"
					_J_STATE_DEFAULT="object-value"
					_J_V="";;
				"	"|""|" ") ;;
				*) _json_die "syntax: $_J_PATHNAME";;
			esac;;

		# After a string key has been consumed, the state machine
		# progresses here where a colon and a value are parsed.  The
		# value is parsed in a subshell so the pathname can have the
		# key appended to it before the parser continues.
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
					) || case "$?" in
						101) _J_STATE="object-even" _J_C="," _json_char;;
						102) _J_STATE="object-even" _J_C="}" _json_char;;
					esac
					_J_STATE="object-even";;
				"	"|""|" ") ;;
				*) _json_die "syntax: $_J_PATHNAME";;
			esac;;

		# Null values work exactly like boolean values.  See above.
		"null")
			case "$_J_V$_J_C" in
				"n"|"nu"|"nul") _J_V="$_J_V$_J_C";;
				"null")
					_J_STATE="$_J_STATE_DEFAULT"
					echo "$_J_PATHNAME null null" >&$_J_FD;;
				*) _json_die "syntax: $_J_PATHNAME null $_J_V$_J_C";;
			esac;;

		# Numbers that encounter a '.' become floating point and may
		# continue consuming digits forever or may become
		# scientific-notation.  Any other character sends the parser
		# back to its default state.
		"number-float")
			case "$_J_C" in
				[0-9]) _J_V="$_J_V$_J_C";;
				"E"|"e") _J_STATE="number-sci" _J_V="$_J_V$_J_C";;
				*)
					_J_STATE="$_J_STATE_DEFAULT"
					echo "$_J_PATHNAME number $_J_V" >&$_J_FD
					_json_char;;
			esac;;

		# This is an entrypoint into parsing a number, used when
		# the first digit consumed is non-zero.  From here, a number
		# may continue on a positive integer, become a floating-point
		# number by consuming a '.', or become scientific-notation by
		# consuming an 'E' or 'e'.  Any other character sends the
		# parser back to its default state.
		"number-leading-nonzero")
			case "$_J_C" in
				".") _J_STATE="number-float" _J_V="$_J_V$_J_C";;
				[0-9]) _J_V="$_J_V$_J_C";;
				"E"|"e") _J_STATE="number-sci" _J_V="$_J_V$_J_C";;
				*)
					_J_STATE="$_J_STATE_DEFAULT"
					echo "$_J_PATHNAME number $_J_V" >&$_J_FD
					_json_char;;
			esac;;

		# This is an entrypoint into parsing a number, used when
		# the first digit consumed is zero.  From here, a number
		# may remain zero, become a floating-point number by
		# consuming a '.', or become scientific-notation by consuming
		# an 'E' or 'e'.  Any other character sends the parser back
		# to its default state.
		"number-leading-zero")
			case "$_J_C" in
				".") _J_STATE="number-float" _J_V="$_J_V$_J_C";;
				[0-9]) _json_die "syntax: $_J_PATHNAME number $_J_V$_J_C";;
				"E"|"e") _J_STATE="number-sci" _J_V="$_J_V$_J_C";;
				*)
					_J_STATE="$_J_STATE_DEFAULT"
					echo "$_J_PATHNAME number $_J_V" >&$_J_FD
					_json_char;;
			esac;;

		# This is an entrypoint into parsing a number, used when
		# the first character consumed is a '-'.  From here, a number
		# may progress to the "number-leading-nonzero" or
		# "number-leading-zero" states.  Any other character sends
		# the parser back to its default state.
		"number-negative")
			case "$_J_C" in
				0) _J_STATE="number-leading-zero" _J_V="$_J_V$_J_C";;
				[1-9])
					_J_STATE="number-leading-nonzero"
					_J_V="$_J_V$_J_C";;
				*)
					_J_STATE="$_J_STATE_DEFAULT"
					echo "$_J_PATHNAME number $_J_V" >&$_J_FD
					_json_char;;
			esac;;

		# Numbers that encounter an 'E' or 'e' become
		# scientific-notation and consume digits, optionally prefixed
		# by a '+' or '-', forever.  The actual consumption is
		# delegated to the "number-sci-neg" and "number-sci-pos"
		# states.  Any other character immediately following the 'E'
		# or 'e' is a syntax error.
		"number-sci")
			case "$_J_C" in
				"+") _J_STATE="number-sci-pos" _J_V="$_J_V$_J_C";;
				"-") _J_STATE="number-sci-neg" _J_V="$_J_V$_J_C";;
				[0-9]) _J_STATE="number-sci-pos" _J_V="$_J_V$_J_C";;
				*) _json_die "syntax: $_J_PATHNAME number $_J_V$_J_C";;
			esac;;

		# Once in these states, numbers may consume digits forever.
		# Any other character sends the parser back to its default
		# state.
		"number-sci-neg"|"number-sci-pos")
			case "$_J_C" in
				[0-9]) _J_V="$_J_V$_J_C";;
				*)
					_J_STATE="$_J_STATE_DEFAULT"
					echo "$_J_PATHNAME number $_J_V" >&$_J_FD
					_json_char;;
			esac;;

		# Strings aren't as easy as they look.  JSON supports several
		# escape sequences that require the state machine to keep a
		# history of its input.  Basic backslash/newline/etc. escapes
		# are simple because they only require one character of
		# history.  Unicode codepoint escapes require more.  The
		# strategy there is to add states to the machine.
		#
		# TODO It'd be nice to decode all escape sequences, including
		# Unicode codepoints but that would definitely ruin the
		# line-oriented thing we've got goin' on.
		"string")
			case "$_J_PREV_C$_J_C" in
				"\\\""|"\\/"|"\\\\") _J_V="$_J_V$_J_C";;
				"\\b"|"\\f"|"\\n"|"\\r")  _J_V="$_J_V\\\\$_J_C";;
				"\\u") _J_V="$_J_V\\\\$_J_C";;
				*"\"")
					_J_STATE="$_J_STATE_DEFAULT"
					echo "$_J_PATHNAME string $_J_V" >&$_J_FD;;
				*"\\") ;;
				*) _J_V="$_J_V$_J_C";;
			esac;;

	esac
}

# Print an error message and GTFO.  The message is the concatenation
# of all the arguments to this function.
_json_die() {
	echo "json.sh: $*" >&2
	exit 1
}
