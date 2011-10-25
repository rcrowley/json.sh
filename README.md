json.sh
=======

Pure-shell [JSON](http://json.org/) parser.

Installation
------------

	make && sudo make install

Usage
-----

From the command-line:

	json.sh <"tests/object-complex.json"

As a library:

	. "lib/json.sh"
	json <"tests/object-complex.json"

TODO
----

* Support for backspace, form feed, newline, and carriage return escapes.
* Support for Unicode characters specified by their codepoints; `\uXXXX`.

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

License
-------

`json.sh` is [BSD-licensed](https://github.com/rcrowley/json.sh/blob/master/LICENSE).
