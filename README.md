# zconv 
A small cli converter that converts input to binary literals

### Pretty much unfinished, but basic functionality works
- Convert Any Integer type (appropriately prefixed with e.g. `0x`, `0o` and `0b`) to in-memory bytes.
- No padding (yet)
- Will work with strings

### Example:
```sh
❯❯ ./zconv 0x1337
\x37\x13

❯❯ ./zconv 0b001000100011
\x23\x02

❯❯ ./zconv 0o1337
\xDF\x02

❯❯ ./zconv 1337
\x39\x05

❯❯ ./zconv asdf
\x61\x73\x64\x66
```

### ReadMe:
| Subcommand |  Full command    | Comment |  
|---|---------------------------|---------|
|-h | --help                    | Display this help and exit.
|-v | --version                 | Output version information and exit.
|   | [\<str\>\|\<hex\>\|\<dec\>\\|\<bin\>\] | The input to be converted.

### Installation:
```sh
git clone https://github.com/SoraTenshi/zconv \
cd zconv \
git submodule init \
git submodule update --recursive \
zig build \

# And then run with
./zig-out/bin/zconv
```
