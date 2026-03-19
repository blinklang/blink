import parser
import ast

fn ast_json_escape(s: Str) -> Str {
    let mut sb = StringBuilder.new()
    let mut i = 0
    while i < s.len() {
        let c = s.char_at(i)
        if c == 34 { sb.write("\\\"") }
        else if c == 92 { sb.write("\\\\") }
        else if c == 10 { sb.write("\\n") }
        else if c == 9 { sb.write("\\t") }
        else if c == 13 { sb.write("\\r") }
        else { sb.write(s.substring(i, 1)) }
        i = i + 1
    }
    sb.to_str()
}

fn sublist_to_json(sl: Int) -> Str {
    let len = sublist_length(sl)
    let mut sb = StringBuilder.new()
    sb.write("[")
    let mut i = 0
    while i < len {
        if i > 0 { sb.write(",") }
        let child = sublist_get(sl, i)
        sb.write(ast_to_json(child))
        i = i + 1
    }
    sb.write("]")
    sb.to_str()
}

pub fn ast_to_json(id: Int) -> Str {
    if id < 0 { return "null" }
    let kind = np_kind.get(id).unwrap()
    let kind_name = node_kind_name(kind)
    let mut sb = StringBuilder.new()
    sb.write("\{\"kind\":\"")
    sb.write(ast_json_escape(kind_name))
    sb.write("\",\"id\":{id}")

    let line = np_line.get(id).unwrap()
    let col = np_col.get(id).unwrap()
    if line > 0 { sb.write(",\"line\":{line},\"col\":{col}") }

    let name = np_name.get(id).unwrap()
    if name != "" { sb.write(",\"name\":\"") sb.write(ast_json_escape(name)) sb.write("\"") }

    let str_val = np_str_val.get(id).unwrap()
    if str_val != "" { sb.write(",\"str_val\":\"") sb.write(ast_json_escape(str_val)) sb.write("\"") }

    let int_val = np_int_val.get(id).unwrap()
    if kind == NodeKind.IntLit { sb.write(",\"int_val\":{int_val}") }
    else if int_val != 0 { sb.write(",\"int_val\":{int_val}") }

    let op = np_op.get(id).unwrap()
    if op != "" { sb.write(",\"op\":\"") sb.write(ast_json_escape(op)) sb.write("\"") }

    let type_name = np_type_name.get(id).unwrap()
    if type_name != "" { sb.write(",\"type_name\":\"") sb.write(ast_json_escape(type_name)) sb.write("\"") }

    let trait_name = np_trait_name.get(id).unwrap()
    if trait_name != "" { sb.write(",\"trait_name\":\"") sb.write(ast_json_escape(trait_name)) sb.write("\"") }

    let var_name = np_var_name.get(id).unwrap()
    if var_name != "" { sb.write(",\"var_name\":\"") sb.write(ast_json_escape(var_name)) sb.write("\"") }

    let method_name = np_method.get(id).unwrap()
    if method_name != "" { sb.write(",\"method\":\"") sb.write(ast_json_escape(method_name)) sb.write("\"") }

    let return_type = np_return_type.get(id).unwrap()
    if return_type != "" { sb.write(",\"return_type\":\"") sb.write(ast_json_escape(return_type)) sb.write("\"") }

    if np_is_mut.get(id).unwrap() != 0 { sb.write(",\"is_mut\":true") }
    if np_is_pub.get(id).unwrap() != 0 { sb.write(",\"is_pub\":true") }
    if np_inclusive.get(id).unwrap() != 0 { sb.write(",\"inclusive\":true") }

    let left = np_left.get(id).unwrap()
    if left >= 0 { sb.write(",\"left\":") sb.write(ast_to_json(left)) }

    let right = np_right.get(id).unwrap()
    if right >= 0 { sb.write(",\"right\":") sb.write(ast_to_json(right)) }

    let body = np_body.get(id).unwrap()
    if body >= 0 { sb.write(",\"body\":") sb.write(ast_to_json(body)) }

    let condition = np_condition.get(id).unwrap()
    if condition >= 0 { sb.write(",\"condition\":") sb.write(ast_to_json(condition)) }

    let then_body = np_then_body.get(id).unwrap()
    if then_body >= 0 { sb.write(",\"then_body\":") sb.write(ast_to_json(then_body)) }

    let else_body = np_else_body.get(id).unwrap()
    if else_body >= 0 { sb.write(",\"else_body\":") sb.write(ast_to_json(else_body)) }

    let scrutinee = np_scrutinee.get(id).unwrap()
    if scrutinee >= 0 { sb.write(",\"scrutinee\":") sb.write(ast_to_json(scrutinee)) }

    let pattern = np_pattern.get(id).unwrap()
    if pattern >= 0 { sb.write(",\"pattern\":") sb.write(ast_to_json(pattern)) }

    let guard = np_guard.get(id).unwrap()
    if guard >= 0 { sb.write(",\"guard\":") sb.write(ast_to_json(guard)) }

    let value = np_value.get(id).unwrap()
    if value >= 0 { sb.write(",\"value\":") sb.write(ast_to_json(value)) }

    let target = np_target.get(id).unwrap()
    if target >= 0 { sb.write(",\"target\":") sb.write(ast_to_json(target)) }

    let iterable = np_iterable.get(id).unwrap()
    if iterable >= 0 { sb.write(",\"iterable\":") sb.write(ast_to_json(iterable)) }

    let start = np_start.get(id).unwrap()
    if start >= 0 { sb.write(",\"start\":") sb.write(ast_to_json(start)) }

    let end_node = np_end.get(id).unwrap()
    if end_node >= 0 { sb.write(",\"end\":") sb.write(ast_to_json(end_node)) }

    let obj = np_obj.get(id).unwrap()
    if obj >= 0 { sb.write(",\"obj\":") sb.write(ast_to_json(obj)) }

    let index = np_index.get(id).unwrap()
    if index >= 0 { sb.write(",\"index\":") sb.write(ast_to_json(index)) }

    let type_ann = np_type_ann.get(id).unwrap()
    if type_ann >= 0 { sb.write(",\"type_ann\":") sb.write(ast_to_json(type_ann)) }

    let stmts = np_stmts.get(id).unwrap()
    if stmts >= 0 { sb.write(",\"stmts\":") sb.write(sublist_to_json(stmts)) }

    let params = np_params.get(id).unwrap()
    if params >= 0 { sb.write(",\"params\":") sb.write(sublist_to_json(params)) }

    let args = np_args.get(id).unwrap()
    if args >= 0 { sb.write(",\"args\":") sb.write(sublist_to_json(args)) }

    let elements = np_elements.get(id).unwrap()
    if elements >= 0 { sb.write(",\"elements\":") sb.write(sublist_to_json(elements)) }

    let fields = np_fields.get(id).unwrap()
    if fields >= 0 { sb.write(",\"fields\":") sb.write(sublist_to_json(fields)) }

    let methods = np_methods.get(id).unwrap()
    if methods >= 0 { sb.write(",\"methods\":") sb.write(sublist_to_json(methods)) }

    let arms = np_arms.get(id).unwrap()
    if arms >= 0 { sb.write(",\"arms\":") sb.write(sublist_to_json(arms)) }

    let handlers = np_handlers.get(id).unwrap()
    if handlers >= 0 { sb.write(",\"handlers\":") sb.write(sublist_to_json(handlers)) }

    let type_params = np_type_params.get(id).unwrap()
    if type_params >= 0 { sb.write(",\"type_params\":") sb.write(sublist_to_json(type_params)) }

    let effects = np_effects.get(id).unwrap()
    if effects >= 0 { sb.write(",\"effects\":") sb.write(sublist_to_json(effects)) }

    let captures = np_captures.get(id).unwrap()
    if captures >= 0 { sb.write(",\"captures\":") sb.write(sublist_to_json(captures)) }

    let doc = np_doc_comment.get(id).unwrap()
    if doc != "" { sb.write(",\"doc_comment\":\"") sb.write(ast_json_escape(doc)) sb.write("\"") }

    let leading = np_leading_comments.get(id).unwrap()
    if leading != "" { sb.write(",\"leading_comments\":\"") sb.write(ast_json_escape(leading)) sb.write("\"") }

    sb.write("}")
    sb.to_str()
}
