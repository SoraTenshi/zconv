# zconv 
A small cli converter that converts input to binary literals

### Pretty much unfinished, but basic functionality works
- Convert Any Integer type (appropriately prefixed with e.g. `0x`, `0o` and `0b`) to in-memory bytes.
- No padding (yet)
- Will work with strings (not really working just yet!)

### Example:
```sh
❯❯ ./zconv 0x1337
\x37\x13

❯❯ ./zconv 0b001000100011
\x23\x02

❯❯ ./zconv 0o1337
\xDF\x02
```
