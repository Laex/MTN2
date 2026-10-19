//! Syntax highlighting for the viewer and the editor on top of syntect (Sublime syntaxes).
//!
//! The host asks for one line at a time together with the parser state at the start of the line
//! (0 = start of the file) and gets back the colored spans and the state at the end of the
//! line, so block comments and multi-line strings carry over. A state is a small integer that
//! names a parser snapshot kept here; the same snapshot always has the same number while the
//! table lasts, so equal states compare equal on the host side.

use std::collections::{HashMap, HashSet};

use syntect::parsing::{ParseState, Scope, ScopeStack, SyntaxSet};

#[link(wasm_import_module = "mtn_host")]
extern "C" {
    fn register_highlighter_state(
        ext_ptr: i32,
        ext_len: i32,
        export_ptr: i32,
        export_len: i32,
        lang: i32,
    ) -> i32;
}

const ABI_VERSION: i64 = 1;
const SPAN_BYTES: usize = 12;
const MAX_STATES: usize = 2048;

const COMMENT: u8 = 1;
const STRING: u8 = 2;
const NUMBER: u8 = 3;
const KEYWORD: u8 = 4;
const TYPE: u8 = 5;
const FUNCTION: u8 = 6;
const OPERATOR: u8 = 7;
const PREPROCESSOR: u8 = 8;
const CONSTANT: u8 = 9;
const KEY: u8 = 10;
const ERROR: u8 = 11;

static mut SCRATCH: [u8; 32768] = [0; 32768];

struct Entry {
    lang: usize,
    parse: ParseState,
    stack: ScopeStack,
}

struct Engine {
    set: SyntaxSet,
    fresh: Vec<Option<ParseState>>,
    states: Vec<Entry>,
    generation: u32,
    classes: HashMap<Scope, Option<u8>>,
}

static mut ENGINE: Option<Engine> = None;

fn engine() -> &'static mut Engine {
    unsafe {
        let slot = &mut *std::ptr::addr_of_mut!(ENGINE);
        slot.get_or_insert_with(|| {
            let set = SyntaxSet::load_defaults_newlines();
            let n = set.syntaxes().len();
            Engine {
                set,
                fresh: (0..n).map(|_| None).collect(),
                states: Vec::new(),
                generation: 1,
                classes: HashMap::new(),
            }
        })
    }
}

/// The class of the text a scope names, `None` when the scope says nothing about color.
fn classify(name: &str) -> Option<u8> {
    let starts = |p: &str| name.starts_with(p);
    if starts("comment") {
        return Some(COMMENT);
    }
    if starts("string") || starts("markup.raw") {
        return Some(STRING);
    }
    if starts("constant.numeric") {
        return Some(NUMBER);
    }
    if starts("constant") || starts("support.constant") {
        return Some(CONSTANT);
    }
    if starts("keyword.operator") {
        return Some(OPERATOR);
    }
    if starts("meta.preprocessor")
        || starts("keyword.control.import")
        || starts("keyword.control.directive")
        || starts("keyword.other.preprocessor")
        || starts("punctuation.definition.directive")
    {
        return Some(PREPROCESSOR);
    }
    if starts("storage.type") {
        const DECL: [&str; 13] = [
            "function", "class", "struct", "enum", "interface", "trait", "impl", "namespace",
            "module", "let", "var", "const", "def",
        ];
        return Some(if DECL.iter().any(|d| name.contains(d)) { KEYWORD } else { TYPE });
    }
    if starts("storage") || starts("keyword") {
        return Some(KEYWORD);
    }
    if starts("entity.name.function") || starts("support.function") || starts("variable.function") {
        return Some(FUNCTION);
    }
    if starts("entity.name.type")
        || starts("entity.name.class")
        || starts("entity.name.struct")
        || starts("entity.name.enum")
        || starts("entity.name.trait")
        || starts("entity.name.namespace")
        || starts("entity.other.inherited-class")
        || starts("support.type")
        || starts("support.class")
    {
        return Some(TYPE);
    }
    if starts("entity.name.tag") || starts("markup.heading") {
        return Some(KEYWORD);
    }
    if starts("entity.other.attribute-name") || starts("support.type.property-name") {
        return Some(KEY);
    }
    if starts("invalid") {
        return Some(ERROR);
    }
    None
}

/// The class of the innermost scope of the stack that has one, 0 for plain text.
fn class_of(eng: &mut Engine, stack: &ScopeStack) -> u8 {
    let scopes = stack.as_slice();
    let mut found = 0u8;
    for scope in scopes.iter().rev() {
        let cls = *eng
            .classes
            .entry(*scope)
            .or_insert_with(|| classify(&scope.build_string()));
        if let Some(c) = cls {
            found = c;
            break;
        }
    }
    // A quoted key of a mapping (JSON) is a key, not a string.
    if found == STRING {
        for scope in scopes.iter() {
            let name = scope.build_string();
            if name.starts_with("meta.mapping.key") || name.starts_with("meta.property-name") {
                return KEY;
            }
        }
    }
    found
}

fn state_id(generation: u32, index: usize) -> i32 {
    (((generation & 0x7fff) << 16) | (index as u32 + 1)) as i32
}

fn intern(eng: &mut Engine, lang: usize, parse: ParseState, stack: ScopeStack) -> i32 {
    if stack.is_empty() {
        if eng.fresh[lang].is_none() {
            eng.fresh[lang] = Some(ParseState::new(&eng.set.syntaxes()[lang]));
        }
        if eng.fresh[lang].as_ref() == Some(&parse) {
            return 0;
        }
    }
    for (i, e) in eng.states.iter().enumerate() {
        if e.lang == lang && e.parse == parse && e.stack == stack {
            return state_id(eng.generation, i);
        }
    }
    if eng.states.len() >= MAX_STATES {
        eng.states.clear();
        eng.generation += 1;
    }
    eng.states.push(Entry { lang, parse, stack });
    state_id(eng.generation, eng.states.len() - 1)
}

fn push_span(spans: &mut Vec<(usize, usize, u8)>, visible: usize, from: usize, to: usize, cls: u8) {
    let to = to.min(visible);
    if cls == 0 || to <= from {
        return;
    }
    if let Some(last) = spans.last_mut() {
        if last.2 == cls && last.0 + last.1 == from {
            last.1 += to - from;
            return;
        }
    }
    spans.push((from, to - from, cls));
}

/// Colors one line. Layout of the output buffer: the state at the end of the line (i32), then
/// up to `out_cap` spans of three i32 (start byte, byte length, class). Returns the number of
/// spans, or -1 when `state_in` is not a state this module knows (the host then starts over).
#[no_mangle]
pub extern "C" fn hl_line(
    line_ptr: i32,
    line_len: i32,
    lang: i32,
    state_in: i32,
    out_ptr: i32,
    out_cap: i32,
) -> i32 {
    let eng = engine();
    let lang = lang as usize;
    if lang >= eng.set.syntaxes().len() {
        return -1;
    }
    let (mut parse, mut stack) = if state_in == 0 {
        (ParseState::new(&eng.set.syntaxes()[lang]), ScopeStack::new())
    } else {
        let idx = (state_in as u32 & 0xffff) as usize;
        let gen = (state_in as u32 >> 16) & 0x7fff;
        if gen != (eng.generation & 0x7fff) || idx == 0 || idx > eng.states.len() {
            return -1;
        }
        let e = &eng.states[idx - 1];
        if e.lang != lang {
            return -1;
        }
        (e.parse.clone(), e.stack.clone())
    };

    let bytes =
        unsafe { std::slice::from_raw_parts(line_ptr as usize as *const u8, line_len as usize) };
    let mut text = String::from_utf8_lossy(bytes).into_owned();
    let visible = text.len();
    text.push('\n');

    let ops = match parse.parse_line(&text, &eng.set) {
        Ok(ops) => ops,
        Err(_) => return write_out(out_ptr, out_cap, state_in, &[]),
    };
    let mut spans: Vec<(usize, usize, u8)> = Vec::new();
    let mut prev = 0usize;
    for (pos, op) in ops {
        if pos > prev {
            let cls = class_of(eng, &stack);
            push_span(&mut spans, visible, prev, pos, cls);
        }
        prev = pos;
        if stack.apply(&op).is_err() {
            break;
        }
    }
    if prev < visible {
        let cls = class_of(eng, &stack);
        push_span(&mut spans, visible, prev, visible, cls);
    }

    let state_out = intern(eng, lang, parse, stack);
    write_out(out_ptr, out_cap, state_out, &spans)
}

fn write_out(out_ptr: i32, out_cap: i32, state: i32, spans: &[(usize, usize, u8)]) -> i32 {
    let n = spans.len().min(out_cap.max(0) as usize);
    let out = unsafe {
        std::slice::from_raw_parts_mut(out_ptr as usize as *mut u8, 4 + n * SPAN_BYTES)
    };
    out[0..4].copy_from_slice(&state.to_le_bytes());
    for (i, (start, len, cls)) in spans.iter().take(n).enumerate() {
        let at = 4 + i * SPAN_BYTES;
        out[at..at + 4].copy_from_slice(&(*start as i32).to_le_bytes());
        out[at + 4..at + 8].copy_from_slice(&(*len as i32).to_le_bytes());
        out[at + 8..at + 12].copy_from_slice(&(*cls as i32).to_le_bytes());
    }
    n as i32
}

#[no_mangle]
pub extern "C" fn mtn_plugin_get_abi_version() -> i64 {
    ABI_VERSION
}

#[no_mangle]
pub extern "C" fn mtn_scratch_ptr() -> i32 {
    std::ptr::addr_of_mut!(SCRATCH) as usize as i32
}

#[no_mangle]
pub extern "C" fn mtn_plugin_init() -> i32 {
    let eng = engine();
    let export = b"hl_line";
    let mut order: Vec<usize> = (0..eng.set.syntaxes().len()).collect();
    // C++ before C and Objective-C: a header (.h) is read as C++.
    order.sort_by_key(|&i| if eng.set.syntaxes()[i].name == "C++" { 0 } else { 1 });
    let mut claimed: HashSet<String> = HashSet::new();
    for idx in order {
        let syn = &eng.set.syntaxes()[idx];
        if syn.hidden || syn.name == "Plain Text" {
            continue;
        }
        let mut exts: Vec<String> = Vec::new();
        for e in &syn.file_extensions {
            if claimed.insert(e.to_lowercase()) {
                exts.push(e.clone());
            }
        }
        if exts.is_empty() {
            continue;
        }
        let joined = exts.join(";");
        unsafe {
            register_highlighter_state(
                joined.as_ptr() as usize as i32,
                joined.len() as i32,
                export.as_ptr() as usize as i32,
                export.len() as i32,
                idx as i32,
            );
        }
    }
    0
}

#[no_mangle]
pub extern "C" fn mtn_plugin_shutdown() {}
