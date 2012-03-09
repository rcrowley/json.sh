json.sh
=======

Pure-shell [JSON](http://json.org/) parser.

`json.sh` requires GNU `sed`(1).

Example
-------

Suppose `tests/mixed.json` contains the following (it does):

	{
		"foo": ["bar", "baz"],
		"asdf": {
			"qwerty": 47
		}
	}

Running `json.sh <"tests/mixed.json"` yields:

	/foo/0 string bar
	/foo/1 string baz
	/asdf/qwerty number 47

Installation
------------

	make && sudo make install

Usage
-----

From the command-line:

	json.sh <"tests/mixed.json"

As a library:

	. "lib/json.sh"
	json <"tests/mixed.json"

Overriding the default use of `/` as the key separator:

	JSON_SEPARATOR="^" json.sh <"tests/mixed.json"

TODO
----

* Whole-ass the half-assed escape sequence and Unicode support.

TODONE
------

* Arrays.
* Booleans.
* Objects.
* `null`.
* Numbers.
  * Floating-point.
  * Negative.
  * Scientific notation.
* Strings.
  * Backspace, form feed, newline, and carriage return escapes.
  * Unicode characters specified by their codepoints: `\uXXXX`.

License
-------

`json.sh` is [BSD-licensed](https://github.com/rcrowley/json.sh/blob/master/LICENSE).
