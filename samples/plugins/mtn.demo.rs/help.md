# CSV table viewer (Rust)

**F3** on a `.csv` file shows an aligned table instead of raw text. The separator (comma, semicolon or tab) is picked from the first line; quoted fields are understood.

## Use

- Put the cursor on a `.csv` file and press **F3**.
- **F4** opens the normal editor: the plugin leaves editing alone.
- Files over 4 MB and files that cannot be read open as usual.

The table is written to a text file in the temporary folder and shown in the built-in viewer.

## For authors

Source: `samples/plugins/mtn.demo.rs/src/lib.rs`. A document provider that answers with a redirect.
