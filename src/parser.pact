import tokens
import ast
import lexer

// parser.pact — Self-hosting recursive descent parser for Pact
//
// Port of src/pact/parser.py. Uses parallel-array node pool since
// the C backend can't store structs in List. Token input arrives as
// parallel arrays (from the lexer). AST output is a node pool: one
// set of parallel arrays indexed by node ID.

// ── Node pool (parallel arrays) ─────────────────────────────────────
// Each node is an index into these arrays. -1 means "no node".

pub let mut np_kind: List[Int] = []
pub let mut np_int_val: List[Int] = []
pub let mut np_str_val: List[Str] = []
pub let mut np_name: List[Str] = []
pub let mut np_op: List[Str] = []
pub let mut np_left: List[Int] = []
pub let mut np_right: List[Int] = []
pub let mut np_body: List[Int] = []
pub let mut np_condition: List[Int] = []
pub let mut np_then_body: List[Int] = []
pub let mut np_else_body: List[Int] = []
pub let mut np_scrutinee: List[Int] = []
pub let mut np_pattern: List[Int] = []
pub let mut np_guard: List[Int] = []
pub let mut np_value: List[Int] = []
pub let mut np_target: List[Int] = []
pub let mut np_iterable: List[Int] = []
pub let mut np_var_name: List[Str] = []
pub let mut np_is_mut: List[Int] = []
pub let mut np_is_pub: List[Int] = []
pub let mut np_inclusive: List[Int] = []
pub let mut np_start: List[Int] = []
pub let mut np_end: List[Int] = []
pub let mut np_obj: List[Int] = []
pub let mut np_method: List[Str] = []
pub let mut np_index: List[Int] = []
pub let mut np_return_type: List[Str] = []
pub let mut np_type_name: List[Str] = []
pub let mut np_trait_name: List[Str] = []

// Sublists: for lists of node references (params, args, stmts, etc.)
pub let mut sl_items: List[Int] = []
pub let mut sl_start: List[Int] = []
pub let mut sl_len: List[Int] = []
pub let mut sl_open: Int = 0

// Each node stores a sublist index for various list fields (-1 = none)
pub let mut np_params: List[Int] = []
pub let mut np_args: List[Int] = []
pub let mut np_stmts: List[Int] = []
pub let mut np_arms: List[Int] = []
pub let mut np_fields: List[Int] = []
pub let mut np_elements: List[Int] = []
pub let mut np_methods: List[Int] = []
pub let mut np_type_params: List[Int] = []
pub let mut np_effects: List[Int] = []
pub let mut np_captures: List[Int] = []
pub let mut np_type_ann: List[Int] = []
pub let mut np_handlers: List[Int] = []

pub fn new_node(kind: Int) -> Int {
    let id = np_kind.len()
    np_kind.push(kind)
    np_int_val.push(0)
    np_str_val.push("")
    np_name.push("")
    np_op.push("")
    np_left.push(-1)
    np_right.push(-1)
    np_body.push(-1)
    np_condition.push(-1)
    np_then_body.push(-1)
    np_else_body.push(-1)
    np_scrutinee.push(-1)
    np_pattern.push(-1)
    np_guard.push(-1)
    np_value.push(-1)
    np_target.push(-1)
    np_iterable.push(-1)
    np_var_name.push("")
    np_is_mut.push(0)
    np_is_pub.push(0)
    np_inclusive.push(0)
    np_start.push(-1)
    np_end.push(-1)
    np_obj.push(-1)
    np_method.push("")
    np_index.push(-1)
    np_return_type.push("")
    np_type_name.push("")
    np_trait_name.push("")
    np_params.push(-1)
    np_args.push(-1)
    np_stmts.push(-1)
    np_arms.push(-1)
    np_fields.push(-1)
    np_elements.push(-1)
    np_methods.push(-1)
    np_type_params.push(-1)
    np_effects.push(-1)
    np_captures.push(-1)
    np_type_ann.push(-1)
    np_handlers.push(-1)
    id
}

pub fn new_sublist() -> Int {
    if sl_open {
        io.println("FATAL: new_sublist() called while another sublist is open — collect items into a List first, then build the sublist after parsing completes")
    }
    sl_open = 1
    let id = sl_start.len()
    sl_start.push(sl_items.len())
    sl_len.push(0)
    id
}

pub fn sublist_push(sl: Int, node_id: Int) {
    if !sl_open {
        io.println("FATAL: sublist_push() called with no open sublist — call new_sublist() first")
    }
    sl_items.push(node_id)
}

pub fn finalize_sublist(sl: Int) {
    if !sl_open {
        io.println("FATAL: finalize_sublist() called with no open sublist — mismatched new_sublist/finalize_sublist calls")
    }
    let start = sl_start.get(sl)
    let length = sl_items.len() - start
    sl_len.set(sl, length)
    sl_open = 0
}

pub fn sublist_get(sl: Int, idx: Int) -> Int {
    sl_items.get(sl_start.get(sl) + idx)
}

pub fn sublist_length(sl: Int) -> Int {
    sl_len.get(sl)
}

// ── Token input (parallel arrays from lexer) ────────────────────────

pub let mut pos: Int = 0

// ── Token navigation ────────────────────────────────────────────────

pub fn peek_kind() -> Int {
    tok_kinds.get(pos)
}

pub fn peek_value() -> Str {
    tok_values.get(pos)
}

pub fn peek_line() -> Int {
    tok_lines.get(pos)
}

pub fn peek_col() -> Int {
    tok_cols.get(pos)
}

pub fn at(kind: Int) -> Int {
    peek_kind() == kind
}

pub fn advance() -> Int {
    let old = pos
    pos = pos + 1
    old
}

pub fn advance_value() -> Str {
    let v = tok_values.get(pos)
    pos = pos + 1
    v
}

pub fn expect(kind: Int) -> Int {
    if peek_kind() != kind {
        io.println("parse error at line {peek_line()}:{peek_col()}: expected token kind {kind}, got {peek_kind()}")
    }
    advance()
}

pub fn expect_value(kind: Int) -> Str {
    if peek_kind() != kind {
        io.println("parse error at line {peek_line()}:{peek_col()}: expected token kind {kind}, got {peek_kind()}")
    }
    advance_value()
}

pub fn skip_newlines() {
    while at(TokenKind.Newline) {
        advance()
    }
}

pub fn maybe_newline() {
    if at(TokenKind.Newline) {
        advance()
    }
}

// ── Import statements ────────────────────────────────────────────────

pub fn parse_import_stmt() -> Int {
    // 'import' already consumed
    let mut path = expect_value(TokenKind.Ident)
    while at(TokenKind.Dot) {
        advance()
        if at(TokenKind.LBrace) {
            break
        }
        path = path.concat(".").concat(expect_value(TokenKind.Ident))
    }

    let node = new_node(NodeKind.ImportStmt)
    np_str_val.pop()
    np_str_val.push(path)

    if at(TokenKind.LBrace) {
        advance()
        skip_newlines()
        let names_sl = new_sublist()
        while !at(TokenKind.RBrace) && !at(TokenKind.EOF) {
            let name_node = new_node(NodeKind.Ident)
            let item_name = expect_value(TokenKind.Ident)
            np_name.pop()
            np_name.push(item_name)
            if at(TokenKind.As) {
                advance()
                let alias = expect_value(TokenKind.Ident)
                np_str_val.pop()
                np_str_val.push(alias)
            }
            sublist_push(names_sl, name_node)
            skip_newlines()
            if at(TokenKind.Comma) {
                advance()
                skip_newlines()
            }
        }
        expect(TokenKind.RBrace)
        finalize_sublist(names_sl)
        np_args.set(node, names_sl)
    }

    node
}

// ── Top-level ───────────────────────────────────────────────────────

pub fn parse_program() -> Int {
    let mut fn_nodes: List[Int] = []
    let mut type_nodes: List[Int] = []
    let mut let_nodes: List[Int] = []
    let mut trait_nodes: List[Int] = []
    let mut impl_nodes: List[Int] = []
    let mut fn_pub: List[Int] = []
    let mut import_nodes: List[Int] = []
    let mut effect_decl_nodes: List[Int] = []
    skip_newlines()
    while !at(TokenKind.EOF) {
        skip_newlines()
        if at(TokenKind.EOF) {
            break
        }
        if at(TokenKind.Import) {
            advance()
            let imp = parse_import_stmt()
            import_nodes.push(imp)
            skip_newlines()
        } else if at(TokenKind.Type) {
            let td = parse_type_def()
            type_nodes.push(td)
        } else if at(TokenKind.Trait) {
            let tr = parse_trait_def()
            trait_nodes.push(tr)
        } else if at(TokenKind.Impl) {
            let im = parse_impl_block()
            impl_nodes.push(im)
        } else if at(TokenKind.Let) {
            let lb = parse_let_binding()
            let_nodes.push(lb)
        } else if at(TokenKind.Pub) {
            advance()
            skip_newlines()
            if at(TokenKind.Fn) {
                let f = parse_fn_def()
                np_is_pub.set(f, 1)
                fn_nodes.push(f)
            } else if at(TokenKind.Type) {
                let td = parse_type_def()
                np_is_pub.set(td, 1)
                type_nodes.push(td)
            } else if at(TokenKind.Trait) {
                let tr = parse_trait_def()
                np_is_pub.set(tr, 1)
                trait_nodes.push(tr)
            } else if at(TokenKind.Let) {
                let lb = parse_let_binding()
                np_is_pub.set(lb, 1)
                let_nodes.push(lb)
            } else if at(TokenKind.Effect) {
                let ed = parse_effect_decl()
                np_is_pub.set(ed, 1)
                effect_decl_nodes.push(ed)
            } else {
                io.println("parse error: expected fn, type, trait, or effect after pub")
                advance()
            }
        } else if at(TokenKind.Effect) {
            let ed = parse_effect_decl()
            effect_decl_nodes.push(ed)
        } else if at(TokenKind.Fn) {
            let f = parse_fn_def()
            fn_nodes.push(f)
        } else {
            io.println("parse error: unexpected token at top level: {peek_kind()}")
            advance()
        }
        skip_newlines()
    }
    // Build sublists from collected node IDs
    let fns = new_sublist()
    let mut i = 0
    while i < fn_nodes.len() {
        sublist_push(fns, fn_nodes.get(i))
        i = i + 1
    }
    finalize_sublist(fns)
    let types = new_sublist()
    i = 0
    while i < type_nodes.len() {
        sublist_push(types, type_nodes.get(i))
        i = i + 1
    }
    finalize_sublist(types)
    let lets = new_sublist()
    i = 0
    while i < let_nodes.len() {
        sublist_push(lets, let_nodes.get(i))
        i = i + 1
    }
    finalize_sublist(lets)
    let traits = new_sublist()
    i = 0
    while i < trait_nodes.len() {
        sublist_push(traits, trait_nodes.get(i))
        i = i + 1
    }
    finalize_sublist(traits)
    let impls = new_sublist()
    i = 0
    while i < impl_nodes.len() {
        sublist_push(impls, impl_nodes.get(i))
        i = i + 1
    }
    finalize_sublist(impls)
    let imports = new_sublist()
    i = 0
    while i < import_nodes.len() {
        sublist_push(imports, import_nodes.get(i))
        i = i + 1
    }
    finalize_sublist(imports)
    let mut effect_decls = -1
    if effect_decl_nodes.len() > 0 {
        effect_decls = new_sublist()
        i = 0
        while i < effect_decl_nodes.len() {
            sublist_push(effect_decls, effect_decl_nodes.get(i))
            i = i + 1
        }
        finalize_sublist(effect_decls)
    }
    let prog = new_node(NodeKind.Program)
    np_params.pop()
    np_params.push(fns)
    np_fields.pop()
    np_fields.push(types)
    np_stmts.pop()
    np_stmts.push(lets)
    np_arms.pop()
    np_arms.push(traits)
    np_methods.pop()
    np_methods.push(impls)
    np_elements.pop()
    np_elements.push(imports)
    np_args.pop()
    np_args.push(effect_decls)
    prog
}

// ── Type parameters ──────────────────────────────────────────────────

pub fn parse_type_params() -> Int {
    if !at(TokenKind.LBracket) {
        return -1
    }
    advance()
    let mut param_nodes: List[Int] = []
    let pname = expect_value(TokenKind.Ident)
    let mut bounds_sl = -1
    if at(TokenKind.Colon) {
        advance()
        let mut bound_nodes: List[Int] = []
        bound_nodes.push(parse_type_annotation())
        while at(TokenKind.Plus) {
            advance()
            skip_newlines()
            bound_nodes.push(parse_type_annotation())
        }
        bounds_sl = new_sublist()
        let mut bi = 0
        while bi < bound_nodes.len() {
            sublist_push(bounds_sl, bound_nodes.get(bi))
            bi = bi + 1
        }
        finalize_sublist(bounds_sl)
    }
    let tp = new_node(NodeKind.TypeParam)
    np_name.pop()
    np_name.push(pname)
    np_elements.pop()
    np_elements.push(bounds_sl)
    param_nodes.push(tp)
    while at(TokenKind.Comma) {
        advance()
        skip_newlines()
        let pn2 = expect_value(TokenKind.Ident)
        let mut bs2 = -1
        if at(TokenKind.Colon) {
            advance()
            let mut bn2: List[Int] = []
            bn2.push(parse_type_annotation())
            while at(TokenKind.Plus) {
                advance()
                skip_newlines()
                bn2.push(parse_type_annotation())
            }
            bs2 = new_sublist()
            let mut bi = 0
            while bi < bn2.len() {
                sublist_push(bs2, bn2.get(bi))
                bi = bi + 1
            }
            finalize_sublist(bs2)
        }
        let tp2 = new_node(NodeKind.TypeParam)
        np_name.pop()
        np_name.push(pn2)
        np_elements.pop()
        np_elements.push(bs2)
        param_nodes.push(tp2)
    }
    expect(TokenKind.RBracket)
    let sl = new_sublist()
    let mut i = 0
    while i < param_nodes.len() {
        sublist_push(sl, param_nodes.get(i))
        i = i + 1
    }
    finalize_sublist(sl)
    sl
}

// ── Type definitions ────────────────────────────────────────────────

pub fn parse_type_def() -> Int {
    expect(TokenKind.Type)
    let name = expect_value(TokenKind.Ident)
    let tparams = parse_type_params()
    skip_newlines()
    let mut flds = -1
    if at(TokenKind.LBrace) {
        expect(TokenKind.LBrace)
        skip_newlines()
        let mut field_nodes: List[Int] = []
        while !at(TokenKind.RBrace) {
            let fname = expect_value(TokenKind.Ident)
            if at(TokenKind.Colon) {
                advance()
                let type_ann = parse_type_annotation()
                let tf = new_node(NodeKind.TypeField)
                np_name.pop()
                np_name.push(fname)
                np_value.pop()
                np_value.push(type_ann)
                field_nodes.push(tf)
            } else {
                let tv = new_node(NodeKind.TypeVariant)
                np_name.pop()
                np_name.push(fname)
                field_nodes.push(tv)
            }
            if at(TokenKind.Comma) {
                advance()
            }
            skip_newlines()
        }
        expect(TokenKind.RBrace)
        flds = new_sublist()
        let mut i = 0
        while i < field_nodes.len() {
            sublist_push(flds, field_nodes.get(i))
            i = i + 1
        }
        finalize_sublist(flds)
    }
    let td = new_node(NodeKind.TypeDef)
    np_name.pop()
    np_name.push(name)
    np_fields.pop()
    np_fields.push(flds)
    np_type_params.pop()
    np_type_params.push(tparams)
    td
}

pub fn parse_type_annotation() -> Int {
    if at(TokenKind.Fn) {
        advance()
        expect(TokenKind.LParen)
        let mut type_nodes: List[Int] = []
        if !at(TokenKind.RParen) {
            type_nodes.push(parse_type_annotation())
            while at(TokenKind.Comma) {
                advance()
                skip_newlines()
                type_nodes.push(parse_type_annotation())
            }
        }
        expect(TokenKind.RParen)
        let mut ret_name = "Void"
        if at(TokenKind.Arrow) {
            advance()
            let rt = parse_type_annotation()
            ret_name = np_name.get(rt)
        }
        let mut elems = -1
        if type_nodes.len() > 0 {
            elems = new_sublist()
            let mut i = 0
            while i < type_nodes.len() {
                sublist_push(elems, type_nodes.get(i))
                i = i + 1
            }
            finalize_sublist(elems)
        }
        let ta = new_node(NodeKind.TypeAnn)
        np_name.pop()
        np_name.push("Fn")
        np_elements.pop()
        np_elements.push(elems)
        np_return_type.pop()
        np_return_type.push(ret_name)
        return ta
    }
    let name = expect_value(TokenKind.Ident)
    let mut elems = -1
    if at(TokenKind.LBracket) {
        advance()
        let mut type_nodes: List[Int] = []
        type_nodes.push(parse_type_annotation())
        while at(TokenKind.Comma) {
            advance()
            skip_newlines()
            type_nodes.push(parse_type_annotation())
        }
        expect(TokenKind.RBracket)
        elems = new_sublist()
        let mut i = 0
        while i < type_nodes.len() {
            sublist_push(elems, type_nodes.get(i))
            i = i + 1
        }
        finalize_sublist(elems)
    }
    let ta = new_node(NodeKind.TypeAnn)
    np_name.pop()
    np_name.push(name)
    np_elements.pop()
    np_elements.push(elems)
    ta
}

// ── Effect declarations ─────────────────────────────────────────────

pub fn parse_effect_decl() -> Int {
    expect(TokenKind.Effect)
    let name = expect_value(TokenKind.Ident)
    skip_newlines()
    if at(TokenKind.LBrace) {
        advance()
        skip_newlines()
        let mut children: List[Int] = []
        while !at(TokenKind.RBrace) && !at(TokenKind.EOF) {
            expect(TokenKind.Effect)
            let child_name = expect_value(TokenKind.Ident)
            let child = new_node(NodeKind.EffectDecl)
            np_name.pop()
            np_name.push(child_name)
            children.push(child)
            skip_newlines()
            if at(TokenKind.Comma) {
                advance()
            }
            skip_newlines()
        }
        expect(TokenKind.RBrace)
        let children_sl = new_sublist()
        let mut i = 0
        while i < children.len() {
            sublist_push(children_sl, children.get(i))
            i = i + 1
        }
        finalize_sublist(children_sl)
        let nd = new_node(NodeKind.EffectDecl)
        np_name.pop()
        np_name.push(name)
        np_elements.pop()
        np_elements.push(children_sl)
        return nd
    }
    let nd = new_node(NodeKind.EffectDecl)
    np_name.pop()
    np_name.push(name)
    nd
}

// ── Function definitions ────────────────────────────────────────────

pub fn parse_fn_def() -> Int {
    expect(TokenKind.Fn)
    let name = expect_value(TokenKind.Ident)
    let tparams = parse_type_params()
    expect(TokenKind.LParen)
    let mut param_nodes: List[Int] = []
    if !at(TokenKind.RParen) {
        param_nodes.push(parse_param())
        while at(TokenKind.Comma) {
            advance()
            if at(TokenKind.RParen) {
                break
            }
            param_nodes.push(parse_param())
        }
    }
    expect(TokenKind.RParen)
    let ret_type = ""
    let mut ret_str = ""
    if at(TokenKind.Arrow) {
        advance()
        let rt = parse_type_annotation()
        ret_str = np_name.get(rt)
    }
    let mut effect_nodes: List[Int] = []
    if at(TokenKind.Bang) {
        advance()
        let mut eff_name = expect_value(TokenKind.Ident)
        if at(TokenKind.Dot) {
            advance()
            eff_name = eff_name.concat(".").concat(expect_value(TokenKind.Ident))
        }
        let eff = new_node(NodeKind.Ident)
        np_name.pop()
        np_name.push(eff_name)
        effect_nodes.push(eff)
        while at(TokenKind.Comma) {
            advance()
            skip_newlines()
            let mut eff_name2 = expect_value(TokenKind.Ident)
            if at(TokenKind.Dot) {
                advance()
                eff_name2 = eff_name2.concat(".").concat(expect_value(TokenKind.Ident))
            }
            let eff2 = new_node(NodeKind.Ident)
            np_name.pop()
            np_name.push(eff_name2)
            effect_nodes.push(eff2)
        }
    }
    skip_newlines()
    let body = -1
    let mut body_id = -1
    if at(TokenKind.LBrace) {
        body_id = parse_block()
    }
    let params = new_sublist()
    let mut pi = 0
    while pi < param_nodes.len() {
        sublist_push(params, param_nodes.get(pi))
        pi = pi + 1
    }
    finalize_sublist(params)
    let mut effects_sl = -1
    if effect_nodes.len() > 0 {
        effects_sl = new_sublist()
        let mut ei = 0
        while ei < effect_nodes.len() {
            sublist_push(effects_sl, effect_nodes.get(ei))
            ei = ei + 1
        }
        finalize_sublist(effects_sl)
    }
    let nd = new_node(NodeKind.FnDef)
    np_name.pop()
    np_name.push(name)
    np_params.pop()
    np_params.push(params)
    np_body.pop()
    np_body.push(body_id)
    np_return_type.pop()
    np_return_type.push(ret_str)
    np_type_params.pop()
    np_type_params.push(tparams)
    np_effects.pop()
    np_effects.push(effects_sl)
    nd
}

pub fn parse_param() -> Int {
    let mut is_mut = 0
    if at(TokenKind.Mut) {
        is_mut = 1
        advance()
    }
    let mut name = ""
    if at(TokenKind.Self) {
        name = "self"
        advance()
    } else {
        name = expect_value(TokenKind.Ident)
    }
    let mut type_str = ""
    let mut type_ann_id = -1
    if at(TokenKind.Colon) {
        advance()
        let ta = parse_type_annotation()
        type_str = np_name.get(ta)
        type_ann_id = ta
    }
    let nd = new_node(NodeKind.Param)
    np_name.pop()
    np_name.push(name)
    np_type_name.pop()
    np_type_name.push(type_str)
    np_is_mut.pop()
    np_is_mut.push(is_mut)
    np_type_ann.set(nd, type_ann_id)
    nd
}

pub fn parse_closure() -> Int {
    expect(TokenKind.Fn)
    expect(TokenKind.LParen)
    let mut param_nodes: List[Int] = []
    if !at(TokenKind.RParen) {
        param_nodes.push(parse_param())
        while at(TokenKind.Comma) {
            advance()
            if at(TokenKind.RParen) {
                break
            }
            param_nodes.push(parse_param())
        }
    }
    expect(TokenKind.RParen)
    let mut ret_str = ""
    if at(TokenKind.Arrow) {
        advance()
        let rt = parse_type_annotation()
        ret_str = np_name.get(rt)
    }
    skip_newlines()
    let body_id = parse_block()
    let params = new_sublist()
    let mut pi = 0
    while pi < param_nodes.len() {
        sublist_push(params, param_nodes.get(pi))
        pi = pi + 1
    }
    finalize_sublist(params)
    let nd = new_node(NodeKind.Closure)
    np_params.pop()
    np_params.push(params)
    np_body.pop()
    np_body.push(body_id)
    np_return_type.pop()
    np_return_type.push(ret_str)
    nd
}

// ── Trait definitions ────────────────────────────────────────────────

pub fn parse_trait_def() -> Int {
    expect(TokenKind.Trait)
    let name = expect_value(TokenKind.Ident)
    let mut trait_type_arg_nodes: List[Int] = []
    if at(TokenKind.LBracket) {
        advance()
        trait_type_arg_nodes.push(parse_type_annotation())
        while at(TokenKind.Comma) {
            advance()
            skip_newlines()
            trait_type_arg_nodes.push(parse_type_annotation())
        }
        expect(TokenKind.RBracket)
    }
    skip_newlines()
    expect(TokenKind.LBrace)
    skip_newlines()
    let mut method_nodes: List[Int] = []
    while !at(TokenKind.RBrace) {
        if at(TokenKind.Fn) {
            method_nodes.push(parse_fn_def())
        } else {
            advance()
        }
        skip_newlines()
    }
    expect(TokenKind.RBrace)
    let mut trait_type_args = -1
    if trait_type_arg_nodes.len() > 0 {
        trait_type_args = new_sublist()
        let mut ti = 0
        while ti < trait_type_arg_nodes.len() {
            sublist_push(trait_type_args, trait_type_arg_nodes.get(ti))
            ti = ti + 1
        }
        finalize_sublist(trait_type_args)
    }
    let methods = new_sublist()
    let mut i = 0
    while i < method_nodes.len() {
        sublist_push(methods, method_nodes.get(i))
        i = i + 1
    }
    finalize_sublist(methods)
    let nd = new_node(NodeKind.TraitDef)
    np_name.pop()
    np_name.push(name)
    np_methods.pop()
    np_methods.push(methods)
    np_type_params.pop()
    np_type_params.push(trait_type_args)
    nd
}

// ── Impl blocks ─────────────────────────────────────────────────────

pub fn parse_impl_block() -> Int {
    expect(TokenKind.Impl)
    let trait_name = expect_value(TokenKind.Ident)
    let mut trait_type_arg_nodes: List[Int] = []
    if at(TokenKind.LBracket) {
        advance()
        trait_type_arg_nodes.push(parse_type_annotation())
        while at(TokenKind.Comma) {
            advance()
            skip_newlines()
            trait_type_arg_nodes.push(parse_type_annotation())
        }
        expect(TokenKind.RBracket)
    }
    skip_newlines()
    let mut type_name = ""
    if at(TokenKind.For) {
        advance()
        skip_newlines()
        type_name = expect_value(TokenKind.Ident)
    }
    skip_newlines()
    expect(TokenKind.LBrace)
    skip_newlines()
    let mut method_nodes: List[Int] = []
    while !at(TokenKind.RBrace) {
        if at(TokenKind.Fn) {
            method_nodes.push(parse_fn_def())
        } else {
            advance()
        }
        skip_newlines()
    }
    expect(TokenKind.RBrace)
    let mut trait_type_args = -1
    if trait_type_arg_nodes.len() > 0 {
        trait_type_args = new_sublist()
        let mut ti = 0
        while ti < trait_type_arg_nodes.len() {
            sublist_push(trait_type_args, trait_type_arg_nodes.get(ti))
            ti = ti + 1
        }
        finalize_sublist(trait_type_args)
    }
    let methods = new_sublist()
    let mut i = 0
    while i < method_nodes.len() {
        sublist_push(methods, method_nodes.get(i))
        i = i + 1
    }
    finalize_sublist(methods)
    let nd = new_node(NodeKind.ImplBlock)
    np_trait_name.pop()
    np_trait_name.push(trait_name)
    np_name.pop()
    np_name.push(type_name)
    np_methods.pop()
    np_methods.push(methods)
    np_type_params.pop()
    np_type_params.push(trait_type_args)
    nd
}

// ── Handler expressions ──────────────────────────────────────────────

pub fn parse_handler_expr() -> Int {
    expect(TokenKind.Handler)
    let effect_name = expect_value(TokenKind.Ident)
    let mut full_name = effect_name
    if at(TokenKind.Dot) {
        advance()
        let child = expect_value(TokenKind.Ident)
        full_name = full_name.concat(".").concat(child)
    }
    skip_newlines()
    expect(TokenKind.LBrace)
    skip_newlines()
    let mut method_nodes: List[Int] = []
    while !at(TokenKind.RBrace) && !at(TokenKind.EOF) {
        if at(TokenKind.Fn) {
            method_nodes.push(parse_fn_def())
        } else {
            advance()
        }
        skip_newlines()
    }
    expect(TokenKind.RBrace)
    let methods = new_sublist()
    let mut i = 0
    while i < method_nodes.len() {
        sublist_push(methods, method_nodes.get(i))
        i = i + 1
    }
    finalize_sublist(methods)
    let nd = new_node(NodeKind.HandlerExpr)
    np_name.pop()
    np_name.push(full_name)
    np_methods.pop()
    np_methods.push(methods)
    nd
}

// ── With blocks ─────────────────────────────────────────────────────

pub fn parse_with_block() -> Int {
    expect(TokenKind.With)
    let mut handler_nodes: List[Int] = []
    let expr0 = parse_expr()
    if at(TokenKind.As) {
        advance()
        let binding = expect_value(TokenKind.Ident)
        let wr = new_node(NodeKind.WithResource)
        np_value.set(wr, expr0)
        np_name.set(wr, binding)
        handler_nodes.push(wr)
    } else {
        handler_nodes.push(expr0)
    }
    while at(TokenKind.Comma) {
        advance()
        skip_newlines()
        let expr_n = parse_expr()
        if at(TokenKind.As) {
            advance()
            let binding_n = expect_value(TokenKind.Ident)
            let wr_n = new_node(NodeKind.WithResource)
            np_value.set(wr_n, expr_n)
            np_name.set(wr_n, binding_n)
            handler_nodes.push(wr_n)
        } else {
            handler_nodes.push(expr_n)
        }
    }
    skip_newlines()
    let body = parse_block()
    let handlers_sl = new_sublist()
    let mut i = 0
    while i < handler_nodes.len() {
        sublist_push(handlers_sl, handler_nodes.get(i))
        i = i + 1
    }
    finalize_sublist(handlers_sl)
    let nd = new_node(NodeKind.WithBlock)
    np_handlers.set(nd, handlers_sl)
    np_body.set(nd, body)
    nd
}

// ── Block ───────────────────────────────────────────────────────────

pub fn parse_block() -> Int {
    expect(TokenKind.LBrace)
    skip_newlines()
    let mut stmt_nodes: List[Int] = []
    while !at(TokenKind.RBrace) {
        stmt_nodes.push(parse_stmt())
        skip_newlines()
    }
    expect(TokenKind.RBrace)
    let stmts = new_sublist()
    let mut i = 0
    while i < stmt_nodes.len() {
        sublist_push(stmts, stmt_nodes.get(i))
        i = i + 1
    }
    finalize_sublist(stmts)
    let nd = new_node(NodeKind.Block)
    np_stmts.pop()
    np_stmts.push(stmts)
    nd
}

// ── Statements ──────────────────────────────────────────────────────

pub fn parse_stmt() -> Int {
    if at(TokenKind.While) {
        return parse_while_loop()
    }
    if at(TokenKind.Loop) {
        return parse_loop_expr()
    }
    if at(TokenKind.Break) {
        advance()
        maybe_newline()
        return new_node(NodeKind.Break)
    }
    if at(TokenKind.Continue) {
        advance()
        maybe_newline()
        return new_node(NodeKind.Continue)
    }
    if at(TokenKind.Let) {
        return parse_let_binding()
    }
    if at(TokenKind.For) {
        return parse_for_in()
    }
    if at(TokenKind.Return) {
        return parse_return_stmt()
    }
    if at(TokenKind.If) {
        let nd = parse_if_expr()
        maybe_newline()
        return nd
    }
    if at(TokenKind.With) {
        let nd = parse_with_block()
        maybe_newline()
        return nd
    }

    let expr = parse_expr()

    if at(TokenKind.Equals) {
        advance()
        skip_newlines()
        let val = parse_expr()
        maybe_newline()
        let nd = new_node(NodeKind.Assignment)
        np_target.pop()
        np_target.push(expr)
        np_value.pop()
        np_value.push(val)
        return nd
    }

    if at(TokenKind.PlusEq) || at(TokenKind.MinusEq) || at(TokenKind.StarEq) || at(TokenKind.SlashEq) {
        let op_kind = peek_kind()
        advance()
        skip_newlines()
        let val = parse_expr()
        maybe_newline()
        let mut op_str = "+"
        if op_kind == TokenKind.MinusEq {
            op_str = "-"
        } else if op_kind == TokenKind.StarEq {
            op_str = "*"
        } else if op_kind == TokenKind.SlashEq {
            op_str = "/"
        }
        let nd = new_node(NodeKind.CompoundAssign)
        np_op.pop()
        np_op.push(op_str)
        np_target.pop()
        np_target.push(expr)
        np_value.pop()
        np_value.push(val)
        return nd
    }

    maybe_newline()
    let nd = new_node(NodeKind.ExprStmt)
    np_value.pop()
    np_value.push(expr)
    nd
}

pub fn parse_let_binding() -> Int {
    expect(TokenKind.Let)
    let mut is_mut = 0
    if at(TokenKind.Mut) {
        is_mut = 1
        advance()
    }
    let name = expect_value(TokenKind.Ident)
    let mut type_ann = -1
    if at(TokenKind.Colon) {
        advance()
        type_ann = parse_type_annotation()
    }
    expect(TokenKind.Equals)
    skip_newlines()
    let val = parse_expr()
    maybe_newline()
    let nd = new_node(NodeKind.LetBinding)
    np_name.pop()
    np_name.push(name)
    np_value.pop()
    np_value.push(val)
    np_is_mut.pop()
    np_is_mut.push(is_mut)
    np_target.pop()
    np_target.push(type_ann)
    nd
}

pub fn parse_return_stmt() -> Int {
    expect(TokenKind.Return)
    if at(TokenKind.Newline) || at(TokenKind.RBrace) || at(TokenKind.EOF) {
        maybe_newline()
        let nd = new_node(NodeKind.Return)
        return nd
    }
    let val = parse_expr()
    maybe_newline()
    let nd = new_node(NodeKind.Return)
    np_value.pop()
    np_value.push(val)
    nd
}

pub fn parse_if_expr() -> Int {
    expect(TokenKind.If)
    let cond = parse_expr()
    skip_newlines()
    let then_b = parse_block()
    let mut else_b = -1
    skip_newlines()
    if at(TokenKind.Else) {
        advance()
        skip_newlines()
        if at(TokenKind.If) {
            let inner = parse_if_expr()
            let stmts = new_sublist()
            sublist_push(stmts, inner)
            finalize_sublist(stmts)
            let blk = new_node(NodeKind.Block)
            np_stmts.pop()
            np_stmts.push(stmts)
            else_b = blk
        } else {
            else_b = parse_block()
        }
    }
    let nd = new_node(NodeKind.IfExpr)
    np_condition.pop()
    np_condition.push(cond)
    np_then_body.pop()
    np_then_body.push(then_b)
    np_else_body.pop()
    np_else_body.push(else_b)
    nd
}

pub fn parse_while_loop() -> Int {
    expect(TokenKind.While)
    let cond = parse_expr()
    skip_newlines()
    let body = parse_block()
    let nd = new_node(NodeKind.WhileLoop)
    np_condition.pop()
    np_condition.push(cond)
    np_body.pop()
    np_body.push(body)
    nd
}

pub fn parse_loop_expr() -> Int {
    expect(TokenKind.Loop)
    skip_newlines()
    let body = parse_block()
    let nd = new_node(NodeKind.LoopExpr)
    np_body.pop()
    np_body.push(body)
    nd
}

pub fn parse_for_in() -> Int {
    expect(TokenKind.For)
    let mut var = ""
    let mut pat = -1
    if at(TokenKind.LParen) {
        pat = parse_pattern()
        var = "_tuple"
    } else {
        var = expect_value(TokenKind.Ident)
    }
    expect(TokenKind.In)
    let iter = parse_expr()
    skip_newlines()
    let body = parse_block()
    let nd = new_node(NodeKind.ForIn)
    np_var_name.pop()
    np_var_name.push(var)
    np_iterable.pop()
    np_iterable.push(iter)
    np_body.pop()
    np_body.push(body)
    if pat != -1 {
        np_elements.pop()
        np_elements.push(pat)
    }
    nd
}

// ── Expressions (precedence climbing) ───────────────────────────────

pub fn parse_expr() -> Int {
    parse_nullcoalesce()
}

pub fn parse_nullcoalesce() -> Int {
    let mut left = parse_or()
    while at(TokenKind.DoubleQuestion) {
        advance()
        skip_newlines()
        let right = parse_or()
        let nd = new_node(NodeKind.BinOp)
        np_op.pop()
        np_op.push("??")
        np_left.pop()
        np_left.push(left)
        np_right.pop()
        np_right.push(right)
        left = nd
    }
    left
}

pub fn parse_or() -> Int {
    let mut left = parse_and()
    while at(TokenKind.Or) {
        advance()
        skip_newlines()
        let right = parse_and()
        let nd = new_node(NodeKind.BinOp)
        np_op.pop()
        np_op.push("||")
        np_left.pop()
        np_left.push(left)
        np_right.pop()
        np_right.push(right)
        left = nd
    }
    left
}

pub fn parse_and() -> Int {
    let mut left = parse_equality()
    while at(TokenKind.And) {
        advance()
        skip_newlines()
        let right = parse_equality()
        let nd = new_node(NodeKind.BinOp)
        np_op.pop()
        np_op.push("&&")
        np_left.pop()
        np_left.push(left)
        np_right.pop()
        np_right.push(right)
        left = nd
    }
    left
}

pub fn parse_equality() -> Int {
    let mut left = parse_comparison()
    while at(TokenKind.EqEq) || at(TokenKind.NotEq) {
        let op = advance_value()
        skip_newlines()
        let right = parse_comparison()
        let nd = new_node(NodeKind.BinOp)
        np_op.pop()
        np_op.push(op)
        np_left.pop()
        np_left.push(left)
        np_right.pop()
        np_right.push(right)
        left = nd
    }
    left
}

pub fn parse_comparison() -> Int {
    let mut left = parse_additive()
    while at(TokenKind.Less) || at(TokenKind.Greater) || at(TokenKind.LessEq) || at(TokenKind.GreaterEq) {
        let op = advance_value()
        skip_newlines()
        let right = parse_additive()
        let nd = new_node(NodeKind.BinOp)
        np_op.pop()
        np_op.push(op)
        np_left.pop()
        np_left.push(left)
        np_right.pop()
        np_right.push(right)
        left = nd
    }
    left
}

pub fn parse_additive() -> Int {
    let mut left = parse_multiplicative()
    while at(TokenKind.Plus) || at(TokenKind.Minus) {
        let op = advance_value()
        skip_newlines()
        let right = parse_multiplicative()
        let nd = new_node(NodeKind.BinOp)
        np_op.pop()
        np_op.push(op)
        np_left.pop()
        np_left.push(left)
        np_right.pop()
        np_right.push(right)
        left = nd
    }
    left
}

pub fn parse_multiplicative() -> Int {
    let mut left = parse_unary()
    while at(TokenKind.Star) || at(TokenKind.Slash) || at(TokenKind.Percent) {
        let op = advance_value()
        skip_newlines()
        let right = parse_unary()
        let nd = new_node(NodeKind.BinOp)
        np_op.pop()
        np_op.push(op)
        np_left.pop()
        np_left.push(left)
        np_right.pop()
        np_right.push(right)
        left = nd
    }
    left
}

pub fn parse_unary() -> Int {
    if at(TokenKind.Minus) {
        advance()
        let operand = parse_unary()
        let nd = new_node(NodeKind.UnaryOp)
        np_op.pop()
        np_op.push("-")
        np_left.pop()
        np_left.push(operand)
        return nd
    }
    if at(TokenKind.Bang) {
        advance()
        let operand = parse_unary()
        let nd = new_node(NodeKind.UnaryOp)
        np_op.pop()
        np_op.push("!")
        np_left.pop()
        np_left.push(operand)
        return nd
    }
    parse_postfix()
}

// ── Postfix: calls, field access, index, method calls ───────────────

pub fn parse_postfix() -> Int {
    let mut node = parse_primary()
    let mut running = 1
    while running {
        if at(TokenKind.Dot) {
            advance()
            let member = expect_value(TokenKind.Ident)
            if at(TokenKind.LParen) {
                advance()
                let mut arg_nodes: List[Int] = []
                if !at(TokenKind.RParen) {
                    arg_nodes.push(parse_expr())
                    while at(TokenKind.Comma) {
                        advance()
                        skip_newlines()
                        if at(TokenKind.RParen) {
                            break
                        }
                        arg_nodes.push(parse_expr())
                    }
                    skip_newlines()
                }
                expect(TokenKind.RParen)
                let args = new_sublist()
                let mut ai = 0
                while ai < arg_nodes.len() {
                    sublist_push(args, arg_nodes.get(ai))
                    ai = ai + 1
                }
                finalize_sublist(args)
                let nd = new_node(NodeKind.MethodCall)
                np_obj.pop()
                np_obj.push(node)
                np_method.pop()
                np_method.push(member)
                np_args.pop()
                np_args.push(args)
                node = nd
            } else {
                let nd = new_node(NodeKind.FieldAccess)
                np_obj.pop()
                np_obj.push(node)
                np_name.pop()
                np_name.push(member)
                node = nd
                // Check for struct literal after field access (e.g. Foo.Bar { ... })
                if at(TokenKind.LBrace) {
                    if looks_like_struct_lit() {
                        // Reconstruct dotted name
                        let dotted = flatten_field_access(node)
                        if dotted != "" {
                            node = parse_struct_lit(dotted)
                        }
                    }
                }
            }
        } else if at(TokenKind.LParen) {
            advance()
            let mut call_arg_nodes: List[Int] = []
            if !at(TokenKind.RParen) {
                skip_newlines()
                skip_named_arg_label()
                call_arg_nodes.push(parse_expr())
                while at(TokenKind.Comma) {
                    advance()
                    skip_newlines()
                    if at(TokenKind.RParen) {
                        break
                    }
                    skip_named_arg_label()
                    call_arg_nodes.push(parse_expr())
                }
                skip_newlines()
            }
            expect(TokenKind.RParen)
            let args = new_sublist()
            let mut ci = 0
            while ci < call_arg_nodes.len() {
                sublist_push(args, call_arg_nodes.get(ci))
                ci = ci + 1
            }
            finalize_sublist(args)
            let nd = new_node(NodeKind.Call)
            np_left.pop()
            np_left.push(node)
            np_args.pop()
            np_args.push(args)
            node = nd
        } else if at(TokenKind.LBracket) {
            advance()
            skip_newlines()
            let idx = parse_expr()
            skip_newlines()
            expect(TokenKind.RBracket)
            let nd = new_node(NodeKind.IndexExpr)
            np_obj.pop()
            np_obj.push(node)
            np_index.pop()
            np_index.push(idx)
            node = nd
        } else if at(TokenKind.Question) {
            advance()
            let nd = new_node(NodeKind.UnaryOp)
            np_op.pop()
            np_op.push("?")
            np_left.pop()
            np_left.push(node)
            node = nd
        } else {
            running = 0
        }
    }
    node
}

pub fn skip_named_arg_label() {
    if at(TokenKind.Ident) {
        // Peek ahead to see if next is colon (named arg)
        let saved = pos
        advance()
        if at(TokenKind.Colon) {
            advance()
            skip_newlines()
        } else {
            pos = saved
        }
    }
}

pub fn flatten_field_access(node: Int) -> Str {
    let kind = np_kind.get(node)
    if kind == NodeKind.Ident {
        return np_name.get(node)
    }
    if kind == NodeKind.FieldAccess {
        let base = flatten_field_access(np_obj.get(node))
        if base != "" {
            return base + "." + np_name.get(node)
        }
    }
    ""
}

pub fn looks_like_struct_lit() -> Int {
    let saved = pos
    // Expect { ident :
    if !at(TokenKind.LBrace) {
        return 0
    }
    advance()
    skip_newlines()
    if at(TokenKind.RBrace) {
        pos = saved
        return 1
    }
    if !at(TokenKind.Ident) {
        pos = saved
        return 0
    }
    advance()
    let result = at(TokenKind.Colon)
    pos = saved
    result
}

// ── Primary expressions ─────────────────────────────────────────────

pub fn parse_primary() -> Int {
    if at(TokenKind.Match) {
        return parse_match_expr()
    }
    if at(TokenKind.If) {
        return parse_if_expr()
    }
    if at(TokenKind.Self) {
        advance()
        let nd = new_node(NodeKind.Ident)
        np_name.pop()
        np_name.push("self")
        return nd
    }

    if at(TokenKind.Fn) {
        return parse_closure()
    }

    if at(TokenKind.Handler) {
        return parse_handler_expr()
    }

    if at(TokenKind.Ident) {
        let name = advance_value()
        if name == "true" {
            let nd = new_node(NodeKind.BoolLit)
            np_int_val.pop()
            np_int_val.push(1)
            return nd
        }
        if name == "false" {
            let nd = new_node(NodeKind.BoolLit)
            np_int_val.pop()
            np_int_val.push(0)
            return nd
        }
        if at(TokenKind.LBrace) && looks_like_struct_lit() {
            return parse_struct_lit(name)
        }
        let nd = new_node(NodeKind.Ident)
        np_name.pop()
        np_name.push(name)
        return nd
    }

    if at(TokenKind.Int) {
        let val_str = advance_value()
        let nd = new_node(NodeKind.IntLit)
        np_str_val.pop()
        np_str_val.push(val_str)
        // Check for range
        if at(TokenKind.DotDot) {
            advance()
            let end_nd = parse_primary()
            let rng = new_node(NodeKind.RangeLit)
            np_start.pop()
            np_start.push(nd)
            np_end.pop()
            np_end.push(end_nd)
            return rng
        }
        if at(TokenKind.DotDoteq) {
            advance()
            let end_nd = parse_primary()
            let rng = new_node(NodeKind.RangeLit)
            np_start.pop()
            np_start.push(nd)
            np_end.pop()
            np_end.push(end_nd)
            np_inclusive.pop()
            np_inclusive.push(1)
            return rng
        }
        return nd
    }

    if at(TokenKind.Float) {
        let val_str = advance_value()
        let nd = new_node(NodeKind.FloatLit)
        np_str_val.pop()
        np_str_val.push(val_str)
        return nd
    }

    if at(TokenKind.LParen) {
        advance()
        skip_newlines()
        if at(TokenKind.RParen) {
            advance()
            // Unit / empty tuple — represent as int lit 0 for simplicity
            return new_node(NodeKind.IntLit)
        }
        let first = parse_expr()
        if at(TokenKind.Comma) {
            let mut elem_nodes: List[Int] = [first]
            while at(TokenKind.Comma) {
                advance()
                skip_newlines()
                if at(TokenKind.RParen) {
                    break
                }
                elem_nodes.push(parse_expr())
            }
            expect(TokenKind.RParen)
            let elems = new_sublist()
            let mut ti = 0
            while ti < elem_nodes.len() {
                sublist_push(elems, elem_nodes.get(ti))
                ti = ti + 1
            }
            finalize_sublist(elems)
            let nd = new_node(NodeKind.TupleLit)
            np_elements.pop()
            np_elements.push(elems)
            return nd
        }
        skip_newlines()
        expect(TokenKind.RParen)
        return first
    }

    if at(TokenKind.LBracket) {
        return parse_list_lit()
    }

    if at(TokenKind.StringStart) {
        return parse_interp_string()
    }

    if at(TokenKind.LBrace) {
        return parse_block()
    }

    io.println("parse error: unexpected token {peek_kind()} at line {peek_line()}:{peek_col()}")
    advance()
    new_node(NodeKind.IntLit)
}

pub fn parse_struct_lit(type_name: Str) -> Int {
    expect(TokenKind.LBrace)
    skip_newlines()
    let mut field_nodes: List[Int] = []
    while !at(TokenKind.RBrace) {
        let fname = expect_value(TokenKind.Ident)
        expect(TokenKind.Colon)
        skip_newlines()
        let fval = parse_expr()
        let sf = new_node(NodeKind.StructLitField)
        np_name.pop()
        np_name.push(fname)
        np_value.pop()
        np_value.push(fval)
        field_nodes.push(sf)
        if at(TokenKind.Comma) {
            advance()
        }
        skip_newlines()
    }
    expect(TokenKind.RBrace)
    let flds = new_sublist()
    let mut i = 0
    while i < field_nodes.len() {
        sublist_push(flds, field_nodes.get(i))
        i = i + 1
    }
    finalize_sublist(flds)
    let nd = new_node(NodeKind.StructLit)
    np_type_name.pop()
    np_type_name.push(type_name)
    np_fields.pop()
    np_fields.push(flds)
    nd
}

pub fn parse_list_lit() -> Int {
    expect(TokenKind.LBracket)
    skip_newlines()
    let mut elem_nodes: List[Int] = []
    while !at(TokenKind.RBracket) {
        elem_nodes.push(parse_expr())
        if at(TokenKind.Comma) {
            advance()
        }
        skip_newlines()
    }
    expect(TokenKind.RBracket)
    let elems = new_sublist()
    let mut i = 0
    while i < elem_nodes.len() {
        sublist_push(elems, elem_nodes.get(i))
        i = i + 1
    }
    finalize_sublist(elems)
    let nd = new_node(NodeKind.ListLit)
    np_elements.pop()
    np_elements.push(elems)
    nd
}

pub fn parse_interp_string() -> Int {
    expect(TokenKind.StringStart)
    let mut part_nodes: List[Int] = []
    while !at(TokenKind.StringEnd) {
        if at(TokenKind.StringPart) {
            let s = advance_value()
            let sn = new_node(NodeKind.Ident)
            np_str_val.pop()
            np_str_val.push(s)
            np_name.pop()
            np_name.push(s)
            part_nodes.push(sn)
        } else if at(TokenKind.InterpStart) {
            advance()
            part_nodes.push(parse_expr())
            expect(TokenKind.InterpEnd)
        } else {
            io.println("parse error: unexpected token in string: {peek_kind()}")
            advance()
        }
    }
    expect(TokenKind.StringEnd)
    let parts = new_sublist()
    let mut i = 0
    while i < part_nodes.len() {
        sublist_push(parts, part_nodes.get(i))
        i = i + 1
    }
    finalize_sublist(parts)
    let nd = new_node(NodeKind.InterpString)
    np_elements.pop()
    np_elements.push(parts)
    nd
}

// ── Match ───────────────────────────────────────────────────────────

pub fn parse_match_expr() -> Int {
    expect(TokenKind.Match)
    let scrut = parse_expr()
    skip_newlines()
    expect(TokenKind.LBrace)
    skip_newlines()
    let mut arm_nodes: List[Int] = []
    while !at(TokenKind.RBrace) {
        arm_nodes.push(parse_match_arm())
        skip_newlines()
    }
    expect(TokenKind.RBrace)
    let arms = new_sublist()
    let mut i = 0
    while i < arm_nodes.len() {
        sublist_push(arms, arm_nodes.get(i))
        i = i + 1
    }
    finalize_sublist(arms)
    let nd = new_node(NodeKind.MatchExpr)
    np_scrutinee.pop()
    np_scrutinee.push(scrut)
    np_arms.pop()
    np_arms.push(arms)
    nd
}

pub fn parse_match_arm() -> Int {
    let pat = parse_pattern()
    let mut guard = -1
    skip_newlines()
    if at(TokenKind.If) {
        advance()
        guard = parse_expr()
    }
    skip_newlines()
    expect(TokenKind.FatArrow)
    skip_newlines()
    let mut body = -1
    if at(TokenKind.LBrace) {
        body = parse_block()
    } else {
        body = parse_stmt()
    }
    let nd = new_node(NodeKind.MatchArm)
    np_pattern.pop()
    np_pattern.push(pat)
    np_body.pop()
    np_body.push(body)
    np_guard.pop()
    np_guard.push(guard)
    nd
}

pub fn parse_pattern() -> Int {
    let first = parse_single_pattern()
    if !at(TokenKind.Pipe) {
        return first
    }
    let mut alt_nodes: List[Int] = []
    alt_nodes.push(first)
    while at(TokenKind.Pipe) {
        advance()
        skip_newlines()
        alt_nodes.push(parse_single_pattern())
    }
    let alts = new_sublist()
    let mut ai = 0
    while ai < alt_nodes.len() {
        sublist_push(alts, alt_nodes.get(ai))
        ai = ai + 1
    }
    finalize_sublist(alts)
    let nd = new_node(NodeKind.OrPattern)
    np_elements.pop()
    np_elements.push(alts)
    nd
}

pub fn parse_single_pattern() -> Int {
    if at(TokenKind.LParen) {
        advance()
        skip_newlines()
        let mut elem_nodes: List[Int] = []
        elem_nodes.push(parse_pattern())
        while at(TokenKind.Comma) {
            advance()
            skip_newlines()
            elem_nodes.push(parse_pattern())
        }
        skip_newlines()
        expect(TokenKind.RParen)
        let elems = new_sublist()
        let mut ei = 0
        while ei < elem_nodes.len() {
            sublist_push(elems, elem_nodes.get(ei))
            ei = ei + 1
        }
        finalize_sublist(elems)
        let nd = new_node(NodeKind.TuplePattern)
        np_elements.pop()
        np_elements.push(elems)
        return nd
    }
    if at(TokenKind.StringStart) {
        let str_node = parse_interp_string()
        let parts_sl = np_elements.get(str_node)
        let mut str_val = ""
        if parts_sl != -1 && sublist_length(parts_sl) == 1 {
            str_val = np_str_val.get(sublist_get(parts_sl, 0))
        }
        let nd = new_node(NodeKind.StringPattern)
        np_str_val.pop()
        np_str_val.push(str_val)
        return nd
    }
    if at(TokenKind.Int) {
        let v = advance_value()
        if at(TokenKind.DotDot) {
            advance()
            let hi = advance_value()
            let nd = new_node(NodeKind.RangePattern)
            np_str_val.pop()
            np_str_val.push(v)
            np_name.pop()
            np_name.push(hi)
            np_inclusive.pop()
            np_inclusive.push(0)
            return nd
        }
        if at(TokenKind.DotDoteq) {
            advance()
            let hi = advance_value()
            let nd = new_node(NodeKind.RangePattern)
            np_str_val.pop()
            np_str_val.push(v)
            np_name.pop()
            np_name.push(hi)
            np_inclusive.pop()
            np_inclusive.push(1)
            return nd
        }
        let nd = new_node(NodeKind.IntPattern)
        np_str_val.pop()
        np_str_val.push(v)
        return nd
    }
    if at(TokenKind.Ident) {
        let name = advance_value()
        if name == "_" {
            return new_node(NodeKind.WildcardPattern)
        }
        if name == "true" {
            let nd = new_node(NodeKind.IntPattern)
            np_str_val.pop()
            np_str_val.push("1")
            return nd
        }
        if name == "false" {
            let nd = new_node(NodeKind.IntPattern)
            np_str_val.pop()
            np_str_val.push("0")
            return nd
        }
        // Qualified variant: Type.Variant or Type.Variant(fields)
        if at(TokenKind.Dot) {
            advance()
            let variant = advance_value()
            if at(TokenKind.LParen) {
                advance()
                skip_newlines()
                let mut fld_nodes: List[Int] = []
                if !at(TokenKind.RParen) {
                    fld_nodes.push(parse_pattern())
                    while at(TokenKind.Comma) {
                        advance()
                        skip_newlines()
                        fld_nodes.push(parse_pattern())
                    }
                }
                skip_newlines()
                expect(TokenKind.RParen)
                let flds = new_sublist()
                let mut fi = 0
                while fi < fld_nodes.len() {
                    sublist_push(flds, fld_nodes.get(fi))
                    fi = fi + 1
                }
                finalize_sublist(flds)
                let nd = new_node(NodeKind.EnumPattern)
                np_name.pop()
                np_name.push(name)
                np_type_name.pop()
                np_type_name.push(variant)
                np_fields.pop()
                np_fields.push(flds)
                return nd
            }
            let nd = new_node(NodeKind.EnumPattern)
            np_name.pop()
            np_name.push(name)
            np_type_name.pop()
            np_type_name.push(variant)
            np_fields.pop()
            np_fields.push(-1)
            return nd
        }
        if at(TokenKind.LParen) {
            advance()
            skip_newlines()
            let mut fld_nodes2: List[Int] = []
            if !at(TokenKind.RParen) {
                fld_nodes2.push(parse_pattern())
                while at(TokenKind.Comma) {
                    advance()
                    skip_newlines()
                    fld_nodes2.push(parse_pattern())
                }
            }
            skip_newlines()
            expect(TokenKind.RParen)
            let flds = new_sublist()
            let mut fi = 0
            while fi < fld_nodes2.len() {
                sublist_push(flds, fld_nodes2.get(fi))
                fi = fi + 1
            }
            finalize_sublist(flds)
            let nd = new_node(NodeKind.EnumPattern)
            np_name.pop()
            np_name.push(name)
            np_fields.pop()
            np_fields.push(flds)
            return nd
        }
        if at(TokenKind.LBrace) {
            advance()
            skip_newlines()
            let mut field_nodes: List[Int] = []
            let mut has_rest = 0
            while !at(TokenKind.RBrace) && !at(TokenKind.EOF) {
                if at(TokenKind.DotDot) {
                    advance()
                    has_rest = 1
                    skip_newlines()
                    if at(TokenKind.Comma) {
                        advance()
                        skip_newlines()
                    }
                    break
                }
                let fname = expect_value(TokenKind.Ident)
                if at(TokenKind.Colon) {
                    advance()
                    skip_newlines()
                    let fpat = parse_pattern()
                    let sf = new_node(NodeKind.StructLitField)
                    np_name.pop()
                    np_name.push(fname)
                    np_pattern.pop()
                    np_pattern.push(fpat)
                    field_nodes.push(sf)
                } else {
                    let sf = new_node(NodeKind.StructLitField)
                    np_name.pop()
                    np_name.push(fname)
                    field_nodes.push(sf)
                }
                if at(TokenKind.Comma) {
                    advance()
                    skip_newlines()
                }
            }
            expect(TokenKind.RBrace)
            let flds = new_sublist()
            let mut fi = 0
            while fi < field_nodes.len() {
                sublist_push(flds, field_nodes.get(fi))
                fi = fi + 1
            }
            finalize_sublist(flds)
            let nd = new_node(NodeKind.StructPattern)
            np_type_name.pop()
            np_type_name.push(name)
            np_fields.pop()
            np_fields.push(flds)
            np_inclusive.pop()
            np_inclusive.push(has_rest)
            return nd
        }
        if at(TokenKind.As) {
            advance()
            let inner = parse_pattern()
            let nd = new_node(NodeKind.AsPattern)
            np_name.pop()
            np_name.push(name)
            np_pattern.pop()
            np_pattern.push(inner)
            return nd
        }
        let nd = new_node(NodeKind.IdentPattern)
        np_name.pop()
        np_name.push(name)
        return nd
    }
    io.println("parse error: unexpected token in pattern: {peek_kind()}")
    advance()
    new_node(NodeKind.WildcardPattern)
}
