import symbol_index
import std.json

// query.pact — Query engine for the symbol index
//
// Filters the symbol index and returns JSON results.
// Supports: --layer intent|signature|contract|full, --effect, --pub --pure, --fn name.
// Output format per spec section 8.5.

// ── JSON string escaping ─────────────────────────────────────────────

fn escape_str(s: Str) -> Str {
    let mut result = ""
    let mut i = 0
    while i < s.len() {
        let c = s.char_at(i)
        if c == 34 {
            result = result.concat("\\\"")
        } else if c == 92 {
            result = result.concat("\\\\")
        } else if c == 10 {
            result = result.concat("\\n")
        } else if c == 9 {
            result = result.concat("\\t")
        } else if c == 13 {
            result = result.concat("\\r")
        } else {
            result = result.concat(s.substring(i, 1))
        }
        i = i + 1
    }
    result
}

// ── Effects string to JSON array ─────────────────────────────────────

fn effects_to_json_array(effects: Str) -> Str {
    if effects == "" {
        return "[]"
    }
    let mut result = "["
    let mut start = 0
    let mut i = 0
    let mut first = 1
    while i <= effects.len() {
        if i == effects.len() || effects.char_at(i) == 44 {
            let part = effects.substring(start, i - start)
            if first == 0 {
                result = result.concat(",")
            }
            result = result.concat("\"").concat(escape_str(part)).concat("\"")
            first = 0
            start = i + 1
        }
        i = i + 1
    }
    result = result.concat("]")
    result
}

// ── Visibility name ──────────────────────────────────────────────────

fn vis_name(vis: Int) -> Str {
    if vis == VIS_PUB {
        return "pub"
    }
    "private"
}

// ── Format a single symbol as a JSON object ──────────────────────────

fn symbol_to_json(idx: Int) -> Str {
    json_clear()
    let obj = json_new_object()
    json_set(obj, "name", json_new_str(si_sym_name.get(idx)))
    json_set(obj, "kind", json_new_str(sym_kind_name(si_sym_kind.get(idx))))
    json_set(obj, "module", json_new_str(si_sym_module.get(idx)))
    json_set(obj, "signature", json_new_str(si_sym_sig.get(idx)))
    let eff_arr = json_new_array()
    let effects = si_sym_effects.get(idx)
    if effects != "" {
        let mut start = 0
        let mut i = 0
        while i <= effects.len() {
            if i == effects.len() || effects.char_at(i) == 44 {
                let part = effects.substring(start, i - start)
                json_push(eff_arr, json_new_str(part))
                start = i + 1
            }
            i = i + 1
        }
    }
    json_set(obj, "effects", eff_arr)
    json_set(obj, "visibility", json_new_str(vis_name(si_sym_vis.get(idx))))
    let intent = si_sym_intent.get(idx)
    if intent != "" {
        json_set(obj, "intent", json_new_str(intent))
    }
    let doc = si_sym_doc.get(idx)
    if doc != "" {
        json_set(obj, "doc", json_new_str(doc))
    }
    let req = si_sym_requires.get(idx)
    if req != "" {
        json_set(obj, "requires", json_new_str(req))
    }
    let ens = si_sym_ensures.get(idx)
    if ens != "" {
        json_set(obj, "ensures", json_new_str(ens))
    }
    let el = si_sym_end_line.get(idx)
    if el > 0 {
        json_set(obj, "end_line", json_new_int(el))
    }
    json_encode(obj)
}

// ── Wrap results array in envelope ───────────────────────────────────

fn wrap_results(items: Str) -> Str {
    "\{\"results\":[".concat(items).concat("]}")
}

// ── Check if comma-separated effects string contains a given effect ──

fn effects_contain(effects: Str, target: Str) -> Int {
    if effects == "" {
        return 0
    }
    let mut start = 0
    let mut i = 0
    while i <= effects.len() {
        if i == effects.len() || effects.char_at(i) == 44 {
            let part = effects.substring(start, i - start)
            if part == target {
                return 1
            }
            start = i + 1
        }
        i = i + 1
    }
    0
}

// ── Query: list fn signatures in a module ────────────────────────────

pub fn query_by_signature(module: Str) -> Str {
    let mut items = ""
    let mut first = 1
    let mut i = 0
    while i < si_sym_count {
        if si_sym_module.get(i) == module && si_sym_kind.get(i) == SK_FN {
            if first == 0 {
                items = items.concat(",")
            }
            items = items.concat(symbol_to_json(i))
            first = 0
        }
        i = i + 1
    }
    wrap_results(items)
}

// ── Query: find fns with a matching effect ───────────────────────────

pub fn query_by_effect(effect_name: Str) -> Str {
    let mut items = ""
    let mut first = 1
    let mut i = 0
    while i < si_sym_count {
        if si_sym_kind.get(i) == SK_FN {
            if effects_contain(si_sym_effects.get(i), effect_name) == 1 {
                if first == 0 {
                    items = items.concat(",")
                }
                items = items.concat(symbol_to_json(i))
                first = 0
            }
        }
        i = i + 1
    }
    wrap_results(items)
}

// ── Query: public functions with no effects (pure) ───────────────────

pub fn query_pub_pure() -> Str {
    let mut items = ""
    let mut first = 1
    let mut i = 0
    while i < si_sym_count {
        if si_sym_kind.get(i) == SK_FN && si_sym_vis.get(i) == VIS_PUB && si_sym_effects.get(i) == "" {
            if first == 0 {
                items = items.concat(",")
            }
            items = items.concat(symbol_to_json(i))
            first = 0
        }
        i = i + 1
    }
    wrap_results(items)
}

// ── Query: lookup specific function by name ──────────────────────────

pub fn query_by_name(name: Str) -> Str {
    let idx = si_find_sym(name)
    if idx < 0 {
        return wrap_results("")
    }
    wrap_results(symbol_to_json(idx))
}

// ── Composable query: apply all filters in a single pass ─────────────

pub fn query_filtered(vis_filter: Int, module_filter: Str, effect_filter: Str, pure_only: Int, name_filter: Str) -> Str {
    let mut items = ""
    let mut first = 1
    let mut i = 0
    while i < si_sym_count {
        if si_sym_kind.get(i) != SK_FN {
            i = i + 1
            continue
        }
        if vis_filter == VIS_PUB && si_sym_vis.get(i) != VIS_PUB {
            i = i + 1
            continue
        }
        if module_filter != "" && si_sym_module.get(i) != module_filter {
            i = i + 1
            continue
        }
        if effect_filter != "" && effects_contain(si_sym_effects.get(i), effect_filter) == 0 {
            i = i + 1
            continue
        }
        if pure_only != 0 && si_sym_effects.get(i) != "" {
            i = i + 1
            continue
        }
        if name_filter != "" && si_sym_name.get(i) != name_filter {
            i = i + 1
            continue
        }
        if first == 0 {
            items = items.concat(",")
        }
        items = items.concat(symbol_to_json(i))
        first = 0
        i = i + 1
    }
    wrap_results(items)
}

// ── Layer: intent — minimal name + intent ────────────────────────────

fn symbol_to_intent_json(idx: Int) -> Str {
    json_clear()
    let obj = json_new_object()
    json_set(obj, "name", json_new_str(si_sym_name.get(idx)))
    json_set(obj, "intent", json_new_str(si_sym_intent.get(idx)))
    json_encode(obj)
}

// ── Layer: contract — signature + contracts ──────────────────────────

fn symbol_to_contract_json(idx: Int) -> Str {
    json_clear()
    let obj = json_new_object()
    json_set(obj, "name", json_new_str(si_sym_name.get(idx)))
    json_set(obj, "signature", json_new_str(si_sym_sig.get(idx)))
    let eff_arr = json_new_array()
    let effects = si_sym_effects.get(idx)
    if effects != "" {
        let mut start = 0
        let mut i = 0
        while i <= effects.len() {
            if i == effects.len() || effects.char_at(i) == 44 {
                let part = effects.substring(start, i - start)
                json_push(eff_arr, json_new_str(part))
                start = i + 1
            }
            i = i + 1
        }
    }
    json_set(obj, "effects", eff_arr)
    json_set(obj, "visibility", json_new_str(vis_name(si_sym_vis.get(idx))))
    let req = si_sym_requires.get(idx)
    if req != "" {
        json_set(obj, "requires", json_new_str(req))
    }
    let ens = si_sym_ensures.get(idx)
    if ens != "" {
        json_set(obj, "ensures", json_new_str(ens))
    }
    json_encode(obj)
}

// ── Layer: full — everything including source text ───────────────────

fn extract_lines(content: Str, start_line: Int, end_line: Int) -> Str {
    let mut line_num = 1
    let mut line_start = 0
    let mut capture_start = -1
    let mut i = 0
    while i <= content.len() {
        if i == content.len() || content.char_at(i) == 10 {
            if line_num == start_line {
                capture_start = line_start
            }
            if line_num == end_line {
                let capture_end = i
                if capture_start < 0 {
                    capture_start = line_start
                }
                return content.substring(capture_start, capture_end - capture_start)
            }
            line_num = line_num + 1
            line_start = i + 1
        }
        i = i + 1
    }
    if capture_start >= 0 {
        return content.substring(capture_start, content.len() - capture_start)
    }
    ""
}

fn symbol_to_full_json(idx: Int) -> Str {
    json_clear()
    let obj = json_new_object()
    json_set(obj, "name", json_new_str(si_sym_name.get(idx)))
    json_set(obj, "kind", json_new_str(sym_kind_name(si_sym_kind.get(idx))))
    json_set(obj, "module", json_new_str(si_sym_module.get(idx)))
    json_set(obj, "signature", json_new_str(si_sym_sig.get(idx)))
    let eff_arr = json_new_array()
    let effects = si_sym_effects.get(idx)
    if effects != "" {
        let mut start = 0
        let mut i = 0
        while i <= effects.len() {
            if i == effects.len() || effects.char_at(i) == 44 {
                let part = effects.substring(start, i - start)
                json_push(eff_arr, json_new_str(part))
                start = i + 1
            }
            i = i + 1
        }
    }
    json_set(obj, "effects", eff_arr)
    json_set(obj, "visibility", json_new_str(vis_name(si_sym_vis.get(idx))))
    let intent = si_sym_intent.get(idx)
    if intent != "" {
        json_set(obj, "intent", json_new_str(intent))
    }
    let doc = si_sym_doc.get(idx)
    if doc != "" {
        json_set(obj, "doc", json_new_str(doc))
    }
    let req = si_sym_requires.get(idx)
    if req != "" {
        json_set(obj, "requires", json_new_str(req))
    }
    let ens = si_sym_ensures.get(idx)
    if ens != "" {
        json_set(obj, "ensures", json_new_str(ens))
    }
    let line = si_sym_line.get(idx)
    json_set(obj, "line", json_new_int(line))
    let el = si_sym_end_line.get(idx)
    if el > 0 {
        json_set(obj, "end_line", json_new_int(el))
        let file_path = si_sym_file.get(idx)
        if file_path != "" {
            let file_content = read_file(file_path)
            if file_content != "" {
                let source = extract_lines(file_content, line, el)
                if source != "" {
                    json_set(obj, "source", json_new_str(source))
                }
            }
        }
    }
    json_encode(obj)
}

// ── Composable query with layer selection ─────────────────────────────

fn format_symbol_for_layer(layer: Str, idx: Int) -> Str {
    if layer == "intent" {
        return symbol_to_intent_json(idx)
    }
    if layer == "contract" {
        return symbol_to_contract_json(idx)
    }
    if layer == "full" {
        return symbol_to_full_json(idx)
    }
    symbol_to_json(idx)
}

pub fn query_filtered_layer(layer: Str, vis_filter: Int, module_filter: Str, effect_filter: Str, pure_only: Int, name_filter: Str) -> Str {
    let mut items = ""
    let mut first = 1
    let mut i = 0
    while i < si_sym_count {
        if si_sym_kind.get(i) != SK_FN {
            i = i + 1
            continue
        }
        if vis_filter == VIS_PUB && si_sym_vis.get(i) != VIS_PUB {
            i = i + 1
            continue
        }
        if module_filter != "" && si_sym_module.get(i) != module_filter {
            i = i + 1
            continue
        }
        if effect_filter != "" && effects_contain(si_sym_effects.get(i), effect_filter) == 0 {
            i = i + 1
            continue
        }
        if pure_only != 0 && si_sym_effects.get(i) != "" {
            i = i + 1
            continue
        }
        if name_filter != "" && si_sym_name.get(i) != name_filter {
            i = i + 1
            continue
        }
        if first == 0 {
            items = items.concat(",")
        }
        items = items.concat(format_symbol_for_layer(layer, i))
        first = 0
        i = i + 1
    }
    wrap_results(items)
}

// ── Minimal JSON request parser ──────────────────────────────────────
// Parses flat {"key":"value",...} objects. Only supports string values.
// Minimal JSON request parser for incoming daemon requests.

let mut qr_keys: List[Str] = []
let mut qr_vals: List[Str] = []

fn qr_skip_ws(s: Str, pos: Int) -> Int {
    let mut p = pos
    while p < s.len() {
        let c = s.char_at(p)
        if c == 32 || c == 9 || c == 10 || c == 13 {
            p = p + 1
        } else {
            return p
        }
    }
    p
}

fn qr_parse_string(s: Str, pos: Int) -> Str {
    if pos >= s.len() || s.char_at(pos) != 34 {
        return ""
    }
    let mut p = pos + 1
    let mut result = ""
    while p < s.len() {
        let c = s.char_at(p)
        if c == 34 {
            return result
        }
        if c == 92 && p + 1 < s.len() {
            let next = s.char_at(p + 1)
            if next == 34 {
                result = result.concat("\"")
                p = p + 2
            } else if next == 92 {
                result = result.concat("\\")
                p = p + 2
            } else if next == 110 {
                result = result.concat("\n")
                p = p + 2
            } else {
                result = result.concat(s.substring(p, 1))
                p = p + 1
            }
        } else {
            result = result.concat(s.substring(p, 1))
            p = p + 1
        }
    }
    result
}

fn qr_end_of_string(s: Str, pos: Int) -> Int {
    if pos >= s.len() || s.char_at(pos) != 34 {
        return pos
    }
    let mut p = pos + 1
    while p < s.len() {
        let c = s.char_at(p)
        if c == 34 {
            return p + 1
        }
        if c == 92 {
            p = p + 2
        } else {
            p = p + 1
        }
    }
    p
}

fn qr_parse_request(s: Str) -> Int {
    qr_keys = []
    qr_vals = []
    let mut p = qr_skip_ws(s, 0)
    if p >= s.len() || s.char_at(p) != 123 {
        return 0
    }
    p = p + 1
    p = qr_skip_ws(s, p)
    while p < s.len() && s.char_at(p) != 125 {
        if qr_keys.len() > 0 {
            if p < s.len() && s.char_at(p) == 44 {
                p = p + 1
                p = qr_skip_ws(s, p)
            }
        }
        let key = qr_parse_string(s, p)
        p = qr_end_of_string(s, p)
        p = qr_skip_ws(s, p)
        if p < s.len() && s.char_at(p) == 58 {
            p = p + 1
        }
        p = qr_skip_ws(s, p)
        let val = qr_parse_string(s, p)
        p = qr_end_of_string(s, p)
        p = qr_skip_ws(s, p)
        qr_keys.push(key)
        qr_vals.push(val)
    }
    1
}

fn qr_get(key: Str) -> Str {
    let mut i = 0
    while i < qr_keys.len() {
        if qr_keys.get(i) == key {
            return qr_vals.get(i)
        }
        i = i + 1
    }
    ""
}

// ── Dispatch: parse JSON request, route to filter fn ─────────────────
//
// Request format:
//   {"type":"signature","module":"main"}
//   {"type":"effect","effect":"IO"}
//   {"type":"pub_pure"}
//   {"type":"fn","name":"foo"}

pub fn query_dispatch(request: Str) -> Str {
    if qr_parse_request(request) == 0 {
        return "\{\"error\":\"invalid JSON request\"}"
    }

    let qtype = qr_get("type")
    if qtype == "" {
        return "\{\"error\":\"missing 'type' field\"}"
    }

    if qtype == "signature" {
        let module = qr_get("module")
        if module == "" {
            return "\{\"error\":\"missing 'module' field for signature query\"}"
        }
        return query_by_signature(module)
    }

    if qtype == "effect" {
        let eff_name = qr_get("effect")
        if eff_name == "" {
            return "\{\"error\":\"missing 'effect' field for effect query\"}"
        }
        return query_by_effect(eff_name)
    }

    if qtype == "pub_pure" {
        return query_pub_pure()
    }

    if qtype == "fn" {
        let name = qr_get("name")
        if name == "" {
            return "\{\"error\":\"missing 'name' field for fn query\"}"
        }
        return query_by_name(name)
    }

    "\{\"error\":\"unknown query type: {qtype}\"}"
}
