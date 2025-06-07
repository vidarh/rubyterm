# Ruby Term - Development Guide

## Build/Run Commands
- Run terminal: `ruby termtest.rb`
- Build executable (requires unreleased tool 'rubypkg'): `make build` (creates standalone executable in file `t`)
- Install to ~/bin: `make promote`
- Debug mode: `DEBUG=1 ruby termtest.rb`

## Code Organization

### Scrollback Buffer
- Primary implementation: `lib/termbuffer.rb` - handles line storage and management
- Scroll handling: `lib/window.rb` - contains viewport and scroll position logic
- User input processing: `lib/keymap.rb` - mappings for Page Up/Down and scrolling keys

## Code Style Guidelines

### Formatting & Syntax
- Use 2-space indentation
- Prefer Ruby's modern syntax: method definitions with `=` for one-liners
- Use concise, readable variable names
- Liberal use of symbols (`:symbol`) for keys and identifiers
- Use snake_case for methods and variables

### Design Patterns
- Terminal is decoupled into components (buffer, controller, window adapter)
- Use classes with clear responsibilities
- Employ thread-based event handling
- Prefer standard library over external dependencies when possible

### Error Handling
- Use exceptions for genuine errors, with rescue blocks to handle gracefully
- Debug information with `p` calls (preferable to puts for inspection)
- In production mode, trap and log exceptions where possible

### Documentation
- Document escape sequences and control codes with comments
- Include references to terminal specifications when implementing features
- Use inline documentation for complex logic
