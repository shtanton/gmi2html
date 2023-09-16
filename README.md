# gmi2html

A tiny executable that does one job well.

## Why?

Currently, it is nice to be able to serve content on gemini on the web too. Writing everything twice is a waste of time, so just write it for gemini and then translate it to HTML.

## Usage

Input is accepted from stdin and output written to stdout.

```
$ gmi2html < input.gmi > output.html
```

## Building and Installing

To build

```
$ zig build
```

Build options:
- `-Drelease-safe` leaves safety checks so bugs lead to errors instead of undefined behaviour.
- `-Drelease-small` slightly slower but much smaller binary, especially with `-Dstrip`.
- `-Drelease-fast` fastest possible binary.

To install, you need zig 0.11.0 (other versions might work but I haven't tested them) then run

```
$ zig build --prefix /usr install
```

Use one of the build modes when installing so the debug code isn't left in.

To build and install the man pages you need `scdoc`:

```
$ scdoc < doc/gmi2html.scdoc > doc/gmi2html.1
# install doc/gmi2html.1 /usr/share/man/man1/gmi2html.1
```

It is also available on the AUR as `gmi2html`.

## Contributing

See CONTRIBUTING.md.

## Licensing

gmi2html is released under the MIT license.
