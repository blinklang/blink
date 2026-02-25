import codegen_types
import parser

pub fn register_derive_annotations(types_sl: Int) {
    if types_sl == -1 { return }
    let mut i = 0
    while i < sublist_length(types_sl) {
        let td = sublist_get(types_sl, i)
        let td_anns = np_handlers.get(td)
        if td_anns != -1 {
            let mut ai = 0
            while ai < sublist_length(td_anns) {
                let ann = sublist_get(td_anns, ai)
                if np_name.get(ann) == "derive" {
                    let args_sl = np_args.get(ann)
                    if args_sl != -1 {
                        let mut di = 0
                        while di < sublist_length(args_sl) {
                            let darg = sublist_get(args_sl, di)
                            let dname = np_name.get(darg)
                            let tname = np_name.get(td)
                            if dname == "Serialize" {
                                derive_serialize_types.push(tname)
                                derive_method_entries.push(DeriveMethodEntry {
                                    type_name: tname,
                                    method_name: "to_json",
                                    ret_type: CT_STRING
                                })
                            }
                            if dname == "Deserialize" {
                                derive_deserialize_types.push(tname)
                                derive_method_entries.push(DeriveMethodEntry {
                                    type_name: tname,
                                    method_name: "from_json",
                                    ret_type: CT_VOID
                                })
                                ensure_struct_result_type(tname, "str")
                            }
                            di = di + 1
                        }
                    }
                }
                ai = ai + 1
            }
        }
        i = i + 1
    }
}

pub fn emit_derive_forward_decls() ! Codegen.Emit {
    let mut i = 0
    while i < derive_serialize_types.len() {
        let tname = derive_serialize_types.get(i)
        if is_enum_type(tname) != 0 {
            emit_line("const char* {c_type_c_name(tname)}_to_json({c_type_c_name(tname)} self);")
        } else {
            emit_line("const char* {c_type_c_name(tname)}_to_json({c_type_c_name(tname)} self);")
        }
        i = i + 1
    }
    let mut j = 0
    while j < derive_deserialize_types.len() {
        let tname = derive_deserialize_types.get(j)
        emit_line("pact_Result_{tname}_str {c_type_c_name(tname)}_from_json(const char* input);")
        j = j + 1
    }
}

pub fn emit_derive_fn_defs() ! Codegen.Emit {
    let mut i = 0
    while i < derive_serialize_types.len() {
        let tname = derive_serialize_types.get(i)
        if is_enum_type(tname) != 0 {
            emit_enum_to_json(tname)
        } else {
            emit_struct_to_json(tname)
        }
        i = i + 1
    }
    let mut j = 0
    while j < derive_deserialize_types.len() {
        let tname = derive_deserialize_types.get(j)
        if is_enum_type(tname) != 0 {
            emit_enum_from_json(tname)
        } else {
            emit_struct_from_json(tname)
        }
        j = j + 1
    }
}

fn emit_struct_to_json(type_name: Str) ! Codegen.Emit {
    emit_line("const char* {c_type_c_name(type_name)}_to_json({c_type_c_name(type_name)} self) \{")
    cg_indent = cg_indent + 1
    emit_line("const char* result = \"\{\";")
    let mut field_idx = 0
    let mut i = 0
    while i < sf_entries.len() {
        let sf = sf_entries.get(i)
        if sf.struct_name == type_name {
            if field_idx > 0 {
                emit_line("result = pact_str_concat(result, \",\");")
            }
            emit_line("result = pact_str_concat(result, \"\\\"{sf.field_name}\\\":\");")
            emit_field_serialize("self.{sf.field_name}", sf.field_type, sf.stype, type_name, sf.field_name)
            field_idx = field_idx + 1
        }
        i = i + 1
    }
    emit_line("result = pact_str_concat(result, \"}\");")
    emit_line("return result;")
    cg_indent = cg_indent - 1
    emit_line("}")
    emit_line("")
}

fn emit_field_serialize(access: Str, field_type: Int, stype: Str, struct_name: Str, field_name: Str) ! Codegen.Emit {
    if field_type == CT_STRING {
        emit_line("result = pact_str_concat(result, \"\\\"\");")
        emit_line("result = pact_str_concat(result, {c_fn_name("escape_json_str")}({access}));")
        emit_line("result = pact_str_concat(result, \"\\\"\");")
    } else if field_type == CT_INT {
        emit_line("result = pact_str_concat(result, pact_int_to_str({access}));")
    } else if field_type == CT_FLOAT {
        emit_line("result = pact_str_concat(result, pact_float_to_str({access}));")
    } else if field_type == CT_BOOL {
        emit_line("result = pact_str_concat(result, {access} ? \"true\" : \"false\");")
    } else if field_type == CT_VOID && stype != "" {
        if has_derive_method(stype, "to_json") != 0 {
            emit_line("result = pact_str_concat(result, {c_type_c_name(stype)}_to_json({access}));")
        } else {
            emit_line("result = pact_str_concat(result, \"null\");")
        }
    } else if field_type == CT_LIST {
        emit_list_serialize(access, struct_name, field_name)
    } else {
        emit_line("result = pact_str_concat(result, \"null\");")
    }
}

fn emit_list_serialize(access: Str, struct_name: Str, field_name: Str) ! Codegen.Emit {
    let elem_struct = get_struct_field_list_elem(struct_name, field_name)
    let elem_type = get_struct_field_list_elem_type(struct_name, field_name)
    emit_line("result = pact_str_concat(result, \"[\");")
    emit_line("\{")
    cg_indent = cg_indent + 1
    emit_line("int64_t _len = pact_list_len({access});")
    emit_line("for (int64_t _i = 0; _i < _len; _i++) \{")
    cg_indent = cg_indent + 1
    emit_line("if (_i > 0) result = pact_str_concat(result, \",\");")
    if elem_struct != "" {
        emit_line("{c_type_c_name(elem_struct)} _elem = *({c_type_c_name(elem_struct)}*)pact_list_get({access}, _i);")
        if has_derive_method(elem_struct, "to_json") != 0 {
            emit_line("result = pact_str_concat(result, {c_type_c_name(elem_struct)}_to_json(_elem));")
        } else {
            emit_line("result = pact_str_concat(result, \"null\");")
        }
    } else if elem_type == CT_STRING {
        emit_line("result = pact_str_concat(result, \"\\\"\");")
        emit_line("result = pact_str_concat(result, {c_fn_name("escape_json_str")}((const char*)pact_list_get({access}, _i)));")
        emit_line("result = pact_str_concat(result, \"\\\"\");")
    } else if elem_type == CT_INT {
        emit_line("result = pact_str_concat(result, pact_int_to_str((int64_t)(intptr_t)pact_list_get({access}, _i)));")
    } else if elem_type == CT_FLOAT {
        emit_line("result = pact_str_concat(result, pact_float_to_str(*(double*)pact_list_get({access}, _i)));")
    } else if elem_type == CT_BOOL {
        emit_line("result = pact_str_concat(result, (int64_t)(intptr_t)pact_list_get({access}, _i) ? \"true\" : \"false\");")
    } else {
        emit_line("result = pact_str_concat(result, \"null\");")
    }
    cg_indent = cg_indent - 1
    emit_line("}")
    cg_indent = cg_indent - 1
    emit_line("}")
    emit_line("result = pact_str_concat(result, \"]\");")
}

fn get_enum_reg_idx(name: Str) -> Int {
    let mut i = 0
    while i < enum_regs.len() {
        if enum_regs.get(i).name == name {
            return i
        }
        i = i + 1
    }
    -1
}

fn emit_enum_to_json(type_name: Str) ! Codegen.Emit {
    let eidx = get_enum_reg_idx(type_name)
    if eidx == -1 { return }
    let is_data = is_data_enum(type_name)

    if is_data == 0 {
        // Simple enum: return quoted variant name
        emit_line("const char* {c_type_c_name(type_name)}_to_json({c_type_c_name(type_name)} self) \{")
        cg_indent = cg_indent + 1
        emit_line("switch (self) \{")
        cg_indent = cg_indent + 1
        let mut i = 0
        while i < enum_variants.len() {
            let evar = enum_variants.get(i)
            if evar.enum_idx == eidx {
                emit_line("case {c_type_c_name(type_name)}_{evar.name}: return \"\\\"{evar.name}\\\"\";")
            }
            i = i + 1
        }
        emit_line("default: return \"null\";")
        cg_indent = cg_indent - 1
        emit_line("}")
        cg_indent = cg_indent - 1
        emit_line("}")
        emit_line("")
    } else {
        // Data enum: internally tagged JSON object
        emit_line("const char* {c_type_c_name(type_name)}_to_json({c_type_c_name(type_name)} self) \{")
        cg_indent = cg_indent + 1
        emit_line("const char* result = \"\";")
        emit_line("switch (self.tag) \{")
        cg_indent = cg_indent + 1
        let mut tag = 0
        let mut i = 0
        while i < enum_variants.len() {
            let evar = enum_variants.get(i)
            if evar.enum_idx == eidx {
                emit_line("case {tag}: \{")
                cg_indent = cg_indent + 1
                emit_line("result = \"\{\\\"type\\\":\\\"{evar.name}\\\"\";")
                if evar.field_count > 0 {
                    let vidx = i
                    let mut fi = 0
                    while fi < evar.field_count {
                        let fname = get_variant_field_name(vidx, fi)
                        let ftype_str = get_variant_field_type_str(vidx, fi)
                        let fct = type_from_name(ftype_str)
                        emit_line("result = pact_str_concat(result, \",\\\"{fname}\\\":\");")
                        let access = "self.data.{evar.name}.{fname}"
                        if fct == CT_STRING {
                            emit_line("result = pact_str_concat(result, \"\\\"\");")
                            emit_line("result = pact_str_concat(result, {c_fn_name("escape_json_str")}({access}));")
                            emit_line("result = pact_str_concat(result, \"\\\"\");")
                        } else if fct == CT_INT {
                            emit_line("result = pact_str_concat(result, pact_int_to_str({access}));")
                        } else if fct == CT_FLOAT {
                            emit_line("result = pact_str_concat(result, pact_float_to_str({access}));")
                        } else if fct == CT_BOOL {
                            emit_line("result = pact_str_concat(result, {access} ? \"true\" : \"false\");")
                        } else if is_struct_type(ftype_str) != 0 && has_derive_method(ftype_str, "to_json") != 0 {
                            emit_line("result = pact_str_concat(result, {c_type_c_name(ftype_str)}_to_json({access}));")
                        } else {
                            emit_line("result = pact_str_concat(result, \"null\");")
                        }
                        fi = fi + 1
                    }
                }
                emit_line("result = pact_str_concat(result, \"}\");")
                emit_line("return result;")
                cg_indent = cg_indent - 1
                emit_line("}")
                tag = tag + 1
            }
            i = i + 1
        }
        emit_line("default: return \"null\";")
        cg_indent = cg_indent - 1
        emit_line("}")
        cg_indent = cg_indent - 1
        emit_line("}")
        emit_line("")
    }
}

fn emit_json_extern_decls() ! Codegen.Emit {
    emit_line("// JSON parser extern declarations for derive(Deserialize)")
    emit_line("extern void {c_fn_name("json_clear")}(void);")
    emit_line("extern int64_t {c_fn_name("json_parse")}(const char* input);")
    emit_line("extern int64_t {c_fn_name("json_get")}(int64_t idx, const char* key);")
    emit_line("extern int64_t {c_fn_name("json_type")}(int64_t idx);")
    emit_line("extern const char* {c_fn_name("json_as_str")}(int64_t idx);")
    emit_line("extern int64_t {c_fn_name("json_as_int")}(int64_t idx);")
    emit_line("extern double {c_fn_name("json_as_float")}(int64_t idx);")
    emit_line("extern int64_t {c_fn_name("json_as_bool")}(int64_t idx);")
    emit_line("extern int64_t {c_fn_name("json_at")}(int64_t idx, int64_t i);")
    emit_line("extern int64_t {c_fn_name("json_len")}(int64_t idx);")
    emit_line("")
}

pub let mut deser_externs_emitted = 0

fn emit_struct_from_json(type_name: Str) ! Codegen.Emit {
    if deser_externs_emitted == 0 {
        emit_json_extern_decls()
        deser_externs_emitted = 1
    }
    emit_line("pact_Result_{type_name}_str {c_type_c_name(type_name)}_from_json(const char* input) \{")
    cg_indent = cg_indent + 1
    emit_line("pact_Result_{type_name}_str _r;")
    emit_line("{c_fn_name("json_clear")}();")
    emit_line("int64_t _root = {c_fn_name("json_parse")}(input);")
    emit_line("if (_root < 0) \{")
    cg_indent = cg_indent + 1
    emit_line("_r.tag = 1;")
    emit_line("_r.err = \"JSON parse error\";")
    emit_line("return _r;")
    cg_indent = cg_indent - 1
    emit_line("}")
    emit_line("{c_type_c_name(type_name)} _val;")
    // Iterate struct fields
    let mut i = 0
    while i < sf_entries.len() {
        let sf = sf_entries.get(i)
        if sf.struct_name == type_name {
            emit_line("\{")
            cg_indent = cg_indent + 1
            emit_line("int64_t _f = {c_fn_name("json_get")}(_root, \"{sf.field_name}\");")
            emit_deser_field("_val.{sf.field_name}", "_f", sf.field_type, sf.stype, type_name, sf.field_name)
            cg_indent = cg_indent - 1
            emit_line("}")
        }
        i = i + 1
    }
    emit_line("_r.tag = 0;")
    emit_line("_r.ok = _val;")
    emit_line("return _r;")
    cg_indent = cg_indent - 1
    emit_line("}")
    emit_line("")
}

fn emit_deser_field(target: Str, node_var: Str, field_type: Int, stype: Str, struct_name: Str, field_name: Str) ! Codegen.Emit {
    if field_type == CT_STRING {
        emit_line("{target} = {c_fn_name("json_as_str")}({node_var});")
    } else if field_type == CT_INT {
        emit_line("{target} = {c_fn_name("json_as_int")}({node_var});")
    } else if field_type == CT_FLOAT {
        emit_line("{target} = {c_fn_name("json_as_float")}({node_var});")
    } else if field_type == CT_BOOL {
        emit_line("{target} = {c_fn_name("json_as_bool")}({node_var});")
    } else if field_type == CT_VOID && stype != "" {
        if has_derive_method(stype, "from_json") != 0 {
            emit_line("// nested deserialize: re-serialize node to string, call from_json")
            emit_line("// For now, set to default zero-initialized value")
            emit_line("memset(&{target}, 0, sizeof({target}));")
        } else {
            emit_line("memset(&{target}, 0, sizeof({target}));")
        }
    } else if field_type == CT_LIST {
        emit_list_deserialize(target, node_var, struct_name, field_name)
    } else {
        emit_line("// unknown field type, zero-init")
        emit_line("memset(&{target}, 0, sizeof({target}));")
    }
}

fn emit_list_deserialize(target: Str, node_var: Str, struct_name: Str, field_name: Str) ! Codegen.Emit {
    let elem_struct = get_struct_field_list_elem(struct_name, field_name)
    let elem_type = get_struct_field_list_elem_type(struct_name, field_name)
    emit_line("{target} = pact_list_new();")
    emit_line("\{")
    cg_indent = cg_indent + 1
    emit_line("int64_t _arr_len = {c_fn_name("json_len")}({node_var});")
    emit_line("for (int64_t _ai = 0; _ai < _arr_len; _ai++) \{")
    cg_indent = cg_indent + 1
    emit_line("int64_t _elem_node = {c_fn_name("json_at")}({node_var}, _ai);")
    if elem_type == CT_STRING {
        emit_line("pact_list_push_str({target}, {c_fn_name("json_as_str")}(_elem_node));")
    } else if elem_type == CT_INT {
        emit_line("pact_list_push_int({target}, {c_fn_name("json_as_int")}(_elem_node));")
    } else if elem_type == CT_FLOAT {
        emit_line("pact_list_push_float({target}, {c_fn_name("json_as_float")}(_elem_node));")
    } else if elem_type == CT_BOOL {
        emit_line("pact_list_push_int({target}, {c_fn_name("json_as_bool")}(_elem_node));")
    } else {
        emit_line("// unsupported list element type")
    }
    cg_indent = cg_indent - 1
    emit_line("}")
    cg_indent = cg_indent - 1
    emit_line("}")
}

fn emit_enum_from_json(type_name: Str) ! Codegen.Emit {
    if deser_externs_emitted == 0 {
        emit_json_extern_decls()
        deser_externs_emitted = 1
    }
    let eidx = get_enum_reg_idx(type_name)
    if eidx == -1 { return }
    let is_data = is_data_enum(type_name)

    emit_line("pact_Result_{type_name}_str {c_type_c_name(type_name)}_from_json(const char* input) \{")
    cg_indent = cg_indent + 1
    emit_line("pact_Result_{type_name}_str _r;")
    emit_line("{c_fn_name("json_clear")}();")
    emit_line("int64_t _root = {c_fn_name("json_parse")}(input);")
    emit_line("if (_root < 0) \{")
    cg_indent = cg_indent + 1
    emit_line("_r.tag = 1;")
    emit_line("_r.err = \"JSON parse error\";")
    emit_line("return _r;")
    cg_indent = cg_indent - 1
    emit_line("}")

    if is_data == 0 {
        emit_line("const char* _str = {c_fn_name("json_as_str")}(_root);")
        let mut i = 0
        let mut tag = 0
        while i < enum_variants.len() {
            let evar = enum_variants.get(i)
            if evar.enum_idx == eidx {
                if tag == 0 {
                    emit_line("if (pact_str_eq(_str, \"{evar.name}\")) \{")
                } else {
                    emit_line("} else if (pact_str_eq(_str, \"{evar.name}\")) \{")
                }
                cg_indent = cg_indent + 1
                emit_line("_r.tag = 0;")
                emit_line("_r.ok = {c_type_c_name(type_name)}_{evar.name};")
                cg_indent = cg_indent - 1
                tag = tag + 1
            }
            i = i + 1
        }
        emit_line("} else \{")
        cg_indent = cg_indent + 1
        emit_line("_r.tag = 1;")
        emit_line("_r.err = \"unknown enum variant\";")
        cg_indent = cg_indent - 1
        emit_line("}")
    } else {
        emit_line("int64_t _type_node = {c_fn_name("json_get")}(_root, \"type\");")
        emit_line("if (_type_node < 0) \{")
        cg_indent = cg_indent + 1
        emit_line("_r.tag = 1;")
        emit_line("_r.err = \"missing type discriminator\";")
        emit_line("return _r;")
        cg_indent = cg_indent - 1
        emit_line("}")
        emit_line("const char* _disc = {c_fn_name("json_as_str")}(_type_node);")
        emit_line("{c_type_c_name(type_name)} _val;")
        let mut i = 0
        let mut tag = 0
        let mut first = 1
        while i < enum_variants.len() {
            let evar = enum_variants.get(i)
            if evar.enum_idx == eidx {
                if first == 1 {
                    emit_line("if (pact_str_eq(_disc, \"{evar.name}\")) \{")
                    first = 0
                } else {
                    emit_line("} else if (pact_str_eq(_disc, \"{evar.name}\")) \{")
                }
                cg_indent = cg_indent + 1
                emit_line("_val.tag = {tag};")
                if evar.field_count > 0 {
                    let vidx = i
                    let mut fi = 0
                    while fi < evar.field_count {
                        let fname = get_variant_field_name(vidx, fi)
                        let ftype_str = get_variant_field_type_str(vidx, fi)
                        let fct = type_from_name(ftype_str)
                        emit_line("\{")
                        cg_indent = cg_indent + 1
                        emit_line("int64_t _fv = {c_fn_name("json_get")}(_root, \"{fname}\");")
                        if fct == CT_STRING {
                            emit_line("_val.data.{evar.name}.{fname} = {c_fn_name("json_as_str")}(_fv);")
                        } else if fct == CT_INT {
                            emit_line("_val.data.{evar.name}.{fname} = {c_fn_name("json_as_int")}(_fv);")
                        } else if fct == CT_FLOAT {
                            emit_line("_val.data.{evar.name}.{fname} = {c_fn_name("json_as_float")}(_fv);")
                        } else if fct == CT_BOOL {
                            emit_line("_val.data.{evar.name}.{fname} = {c_fn_name("json_as_bool")}(_fv);")
                        } else {
                            emit_line("// unsupported variant field type")
                        }
                        cg_indent = cg_indent - 1
                        emit_line("}")
                        fi = fi + 1
                    }
                }
                cg_indent = cg_indent - 1
                tag = tag + 1
            }
            i = i + 1
        }
        emit_line("} else \{")
        cg_indent = cg_indent + 1
        emit_line("_r.tag = 1;")
        emit_line("_r.err = \"unknown enum variant\";")
        emit_line("return _r;")
        cg_indent = cg_indent - 1
        emit_line("}")
        emit_line("_r.tag = 0;")
        emit_line("_r.ok = _val;")
    }

    emit_line("return _r;")
    cg_indent = cg_indent - 1
    emit_line("}")
    emit_line("")
}
