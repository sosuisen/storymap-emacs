[README (日本語)](README.ja.md)

# story-mapping for Emacs

This Emacs package shows a Markdown outline as a user story map.
It is the Emacs version of the VS Code extension [Story Mapping](https://github.com/sosuisen/vscode-user-story-mapping).
Both use the Rust crate [storymap](https://crates.io/crates/storymap) to draw the map.

## Requirements

- Windows 11
- Emacs 31.1, as a graphical frame with PNG support
- Rust 1.99, to build the render program

## Install

Build the render program:

```sh
cargo build --release
```

The package finds the program in `target/release` next to `story-mapping.el`.
You can also put it on your `PATH` with `cargo install --path .`.

Add the package to your init file:

```elisp
(add-to-list 'load-path "/path/to/story-mapping")
(autoload 'story-mapping "story-mapping" nil t)
(autoload 'story-mapping-export-svg "story-mapping" nil t)
```

## Usage

Open a `.md` file, and run one of these commands.

| Command | What it does |
|---|---|
| `M-x story-mapping` | Opens a panel on the right that shows the map. The panel follows your edits, also before you save. |
| `M-x story-mapping-export-svg` | Saves the map as an SVG file. Press `RET` to use the default, which is the file with the same name next to the `.md` file. |

Use these keys in the panel.

| Key | What it does |
|---|---|
| `+` or `=` | Zooms in |
| `-` | Zooms out |
| `0` | Sets the zoom to 100% |
| Arrow keys, `C-n`, `C-p`, `C-f`, `C-b`, `C-v`, `M-v`, the mouse wheel | Scroll the map |
| `g` | Draws the map again |
| `q` | Closes the panel |

The outline format is the same as in the VS Code extension.
See [its README](https://github.com/sosuisen/vscode-user-story-mapping#readme).

## Options

Use `M-x customize-group RET story-mapping` to change them.

| Option | Default | Meaning |
|---|---|---|
| `story-mapping-program` | `"story-mapping-render"` | The render program |
| `story-mapping-window-width` | `0.5` | The width of the panel, as a fraction of the frame |
| `story-mapping-update-delay` | `0.3` | The seconds to wait after an edit before the update |
| `story-mapping-scale` | `1.0` | The image pixels per map pixel at 100%. Use `2.0` if the map looks small on a high resolution display |

To open the panel in another place, add a rule for `*Story Map: ...*` buffers to `display-buffer-alist`.

## Limits

- The preview is an image, so the links in the map cannot be clicked.
- The panel needs a graphical frame. It does not work in a terminal.
- The text uses the fonts of the OS. An SVG file names only the generic font `sans-serif`, so it can look different on another machine.

## Development

```sh
cargo fmt --check
cargo clippy --all-targets
cargo test
cargo build --release
emacs -Q --batch -L . -l test/story-mapping-tests.el -f ert-run-tests-batch-and-exit
```

The Emacs tests run the release build of the render program.

## Coverage and mutation testing

Install the tools once:

```sh
rustup component add llvm-tools-preview
cargo install cargo-llvm-cov --locked
cargo install cargo-mutants --locked
```

Then run them:

```sh
cargo cov            # a table per file
cargo cov --html     # a report per line in target/llvm-cov/html/index.html
cargo mutants
```

No file is left out of the measurement.

## License

MIT
