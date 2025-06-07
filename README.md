
# Ruby Term

This is a *very early*, *very rough* Ruby terminal application that uses
a pure-Ruby X11 client to talk to an X server. The entire terminal is
pure Ruby.

It will change a lot when I get time...

It will currently fail to run most full-screen applications, as only a very
small subset of escape codes are handled properly (enough to run my own
personal editor, barely). Localisation is a mess. Font-handling is near
non-existent. Keymap handling is very limited.

In general: **You probably don't want to use this.**

If you insist on playing with it anyway, I do welcome thoughtful modifications,
but I have very specific ideas for the direction I want to take it, so
either talk to me first (e-mail: vidar@hokstad.com) or fork it. Or both. I
will not guarantee I'll merge in changes unless we've spoken about it first.

Some thoughts on where I want to take this:

* Decouple the interpretation of escape sequences and updates of the terminal
  buffer entirely from both the pty handling and the X11 interface, and make
  it a separate gem.
* Allow Ruby applications to instantiate a "terminal window" with an IO object
  as the interface without actually running in a terminal (I want to use it to
  run my own editor in), while being able to do **basic** other X stuff.
* Make the terminal itself complete enough to run most Linux/Unix command line
  tools - so that means a fairly complete unicode enabled xterm/vt100 terminal.
* KEEP THE CODE SMALL, but understandable. You might spot hints at golfing in
  the current code. I will value terseness, but only as long as it helps
  preserve readability.

## Done
* Moved to a pure-Ruby direct implementation of a small subset of the
  X Protocol.

## Installation and Setup

### Dependencies

This project uses `bundle install --standalone` to manage dependencies:

```bash
bundle install --standalone
```

### Running

After installing dependencies, run:

```bash
ruby termtest.rb
```

With some luck you'll get a terminal window.

## Configuration

Ruby Term can be configured using a TOML configuration file located at `~/.config/rterm/config.toml`. See `example-config.toml` for a complete example.

### Configuration Options

#### Shell Configuration

- **`shell`** (string): Path to the shell executable to use
  - Default: Uses `ENV["SHELL"]` if set, otherwise falls back to `/bin/sh`
  - Example: `shell = "/bin/bash"`

#### Font Configuration

- **`fonts`** (array of strings): List of fonts to use, in priority order
  - Supports multiple font formats and sources:
    - Direct file paths (with `~` expansion): `"~/fonts/MyFont.ttf"`
    - Files in `~/.local/share/fonts/`: `"FiraCode-Regular.ttf"`
    - System fonts via `fc-match`: `"monospace"`
    - Fonts with fc-match options: `"monospace:weight=bold"`
  - When a glyph is unavailable in the first font, subsequent fonts are tried
  - Example:
    ```toml
    fonts = [
      "FiraCode-Regular.ttf",
      "unifont-15.0.06.ttf",
      "monospace"
    ]
    ```

- **`fontsize`** (integer): Font size in points
  - Default: Platform dependent
  - Example: `fontsize = 32`

### Font Resolution

The font resolution process works as follows:

1. **Direct path**: If the font name is a valid file path, it's opened directly
2. **Local fonts**: Check `~/.local/share/fonts/[fontname]`
3. **System fonts**: Use `fc-match --format='%{file}\n' [fontname]` to find system fonts
4. **fc-match options**: Font names without extensions or with fc-match syntax are passed to fc-match

### Example Configuration

```toml
# Shell to use (optional)
shell = "/bin/zsh"

# Font configuration
fonts = [
  "FiraCode-Regular.ttf",    # Programming font with ligatures
  "unifont-15.0.06.ttf",    # Unicode fallback font
  "monospace"                # System monospace fallback
]

fontsize = 24
```

### Configuration File Location

The configuration file should be placed at:
```
~/.config/rterm/config.toml
```

If this file doesn't exist, Ruby Term will use default values for all settings.

## Resources

https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h2-Definitions
https://www.xfree86.org/current/ctlseqs.html
