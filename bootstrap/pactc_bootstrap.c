#include "runtime.h"

typedef enum { pact_TokenKind_Fn, pact_TokenKind_Let, pact_TokenKind_Mut, pact_TokenKind_Type, pact_TokenKind_Trait, pact_TokenKind_Impl, pact_TokenKind_If, pact_TokenKind_Else, pact_TokenKind_Match, pact_TokenKind_For, pact_TokenKind_In, pact_TokenKind_While, pact_TokenKind_Loop, pact_TokenKind_Break, pact_TokenKind_Continue, pact_TokenKind_Return, pact_TokenKind_Pub, pact_TokenKind_With, pact_TokenKind_Handler, pact_TokenKind_Self, pact_TokenKind_Test, pact_TokenKind_Import, pact_TokenKind_As, pact_TokenKind_Mod, pact_TokenKind_Effect, pact_TokenKind_Assert, pact_TokenKind_AssertEq, pact_TokenKind_AssertNe, pact_TokenKind_Ident, pact_TokenKind_Int, pact_TokenKind_Float, pact_TokenKind_StringStart, pact_TokenKind_StringEnd, pact_TokenKind_StringPart, pact_TokenKind_InterpStart, pact_TokenKind_InterpEnd, pact_TokenKind_LParen, pact_TokenKind_RParen, pact_TokenKind_LBrace, pact_TokenKind_RBrace, pact_TokenKind_LBracket, pact_TokenKind_RBracket, pact_TokenKind_Colon, pact_TokenKind_Comma, pact_TokenKind_Dot, pact_TokenKind_DotDot, pact_TokenKind_DotDoteq, pact_TokenKind_Arrow, pact_TokenKind_FatArrow, pact_TokenKind_At, pact_TokenKind_Plus, pact_TokenKind_Minus, pact_TokenKind_Star, pact_TokenKind_Slash, pact_TokenKind_Percent, pact_TokenKind_Equals, pact_TokenKind_EqEq, pact_TokenKind_NotEq, pact_TokenKind_Less, pact_TokenKind_Greater, pact_TokenKind_LessEq, pact_TokenKind_GreaterEq, pact_TokenKind_And, pact_TokenKind_Or, pact_TokenKind_Bang, pact_TokenKind_Question, pact_TokenKind_DoubleQuestion, pact_TokenKind_Pipe, pact_TokenKind_PipeArrow, pact_TokenKind_PlusEq, pact_TokenKind_MinusEq, pact_TokenKind_StarEq, pact_TokenKind_SlashEq, pact_TokenKind_Newline, pact_TokenKind_EOF } pact_TokenKind;

typedef struct {
    int64_t kind;
    const char* value;
    int64_t line;
    int64_t col;
} pact_Token;

typedef enum { pact_NodeKind_IntLit, pact_NodeKind_FloatLit, pact_NodeKind_Ident, pact_NodeKind_Call, pact_NodeKind_MethodCall, pact_NodeKind_BinOp, pact_NodeKind_UnaryOp, pact_NodeKind_InterpString, pact_NodeKind_BoolLit, pact_NodeKind_TupleLit, pact_NodeKind_ListLit, pact_NodeKind_StructLit, pact_NodeKind_FieldAccess, pact_NodeKind_IndexExpr, pact_NodeKind_RangeLit, pact_NodeKind_IfExpr, pact_NodeKind_MatchExpr, pact_NodeKind_Closure, pact_NodeKind_LetBinding, pact_NodeKind_ExprStmt, pact_NodeKind_Assignment, pact_NodeKind_CompoundAssign, pact_NodeKind_Return, pact_NodeKind_ForIn, pact_NodeKind_WhileLoop, pact_NodeKind_LoopExpr, pact_NodeKind_Break, pact_NodeKind_Continue, pact_NodeKind_Block, pact_NodeKind_FnDef, pact_NodeKind_Param, pact_NodeKind_Program, pact_NodeKind_TypeDef, pact_NodeKind_TypeField, pact_NodeKind_TypeVariant, pact_NodeKind_TraitDef, pact_NodeKind_ImplBlock, pact_NodeKind_TestBlock, pact_NodeKind_IntPattern, pact_NodeKind_WildcardPattern, pact_NodeKind_IdentPattern, pact_NodeKind_TuplePattern, pact_NodeKind_StringPattern, pact_NodeKind_OrPattern, pact_NodeKind_RangePattern, pact_NodeKind_StructPattern, pact_NodeKind_EnumPattern, pact_NodeKind_AsPattern, pact_NodeKind_MatchArm, pact_NodeKind_StructLitField, pact_NodeKind_WithBlock, pact_NodeKind_WithResource, pact_NodeKind_HandlerExpr, pact_NodeKind_Annotation, pact_NodeKind_ModBlock, pact_NodeKind_ImportStmt, pact_NodeKind_TypeAnn, pact_NodeKind_TypeParam, pact_NodeKind_EffectDecl } pact_NodeKind;

typedef struct {
    int64_t kind;
    int64_t int_val;
    int64_t float_val;
    const char* str_val;
    const char* name;
    const char* op;
    int64_t left;
    int64_t right;
    pact_list* params;
    int64_t body;
    const char* return_type;
    pact_list* stmts;
    int64_t condition;
    int64_t then_body;
    int64_t else_body;
    pact_list* arms;
    int64_t pattern;
    int64_t scrutinee;
    int64_t guard;
    pact_list* elements;
    pact_list* fields;
    const char* type_name;
    int64_t is_mut;
    int64_t is_pub;
    int64_t value;
    int64_t target;
    int64_t iterable;
    const char* var_name;
    int64_t inclusive;
    int64_t start;
    int64_t end;
    int64_t obj;
    const char* method;
    int64_t index;
    pact_list* args;
    const char* path;
    pact_list* names;
    pact_list* type_params;
    int64_t optional;
    pact_list* handlers;
    const char* as_binding;
    pact_list* super_traits;
    const char* trait_name;
    pact_list* methods;
    pact_list* ann_args;
    int64_t rest;
    const char* variant;
    pact_list* enum_fields;
    pact_list* alternatives;
    int64_t inner;
    pact_list* effects;
    pact_list* annotations;
} pact_Node;

static const int64_t MODE_NORMAL = 0;
static const int64_t MODE_STRING = 1;
static const int64_t CH_TAB = 9;
static const int64_t CH_NEWLINE = 10;
static const int64_t CH_SPACE = 32;
static const int64_t CH_DQUOTE = 34;
static const int64_t CH_PERCENT = 37;
static const int64_t CH_LPAREN = 40;
static const int64_t CH_RPAREN = 41;
static const int64_t CH_STAR = 42;
static const int64_t CH_PLUS = 43;
static const int64_t CH_COMMA = 44;
static const int64_t CH_MINUS = 45;
static const int64_t CH_DOT = 46;
static const int64_t CH_SLASH = 47;
static const int64_t CH_0 = 48;
static const int64_t CH_9 = 57;
static const int64_t CH_COLON = 58;
static const int64_t CH_LESS = 60;
static const int64_t CH_EQUALS = 61;
static const int64_t CH_GREATER = 62;
static const int64_t CH_QUESTION = 63;
static const int64_t CH_AT = 64;
static const int64_t CH_A = 65;
static const int64_t CH_Z = 90;
static const int64_t CH_LBRACKET = 91;
static const int64_t CH_BACKSLASH = 92;
static const int64_t CH_RBRACKET = 93;
static const int64_t CH_UNDERSCORE = 95;
static const int64_t CH_a = 97;
static const int64_t CH_n = 110;
static const int64_t CH_t = 116;
static const int64_t CH_Z_LOWER = 122;
static const int64_t CH_LBRACE = 123;
static const int64_t CH_PIPE = 124;
static const int64_t CH_RBRACE = 125;
static const int64_t CH_BANG = 33;
static const int64_t CH_AMP = 38;
static pact_list* tok_kinds;
static pact_list* tok_values;
static pact_list* tok_lines;
static pact_list* tok_cols;
static pact_list* np_kind;
static pact_list* np_int_val;
static pact_list* np_str_val;
static pact_list* np_name;
static pact_list* np_op;
static pact_list* np_left;
static pact_list* np_right;
static pact_list* np_body;
static pact_list* np_condition;
static pact_list* np_then_body;
static pact_list* np_else_body;
static pact_list* np_scrutinee;
static pact_list* np_pattern;
static pact_list* np_guard;
static pact_list* np_value;
static pact_list* np_target;
static pact_list* np_iterable;
static pact_list* np_var_name;
static pact_list* np_is_mut;
static pact_list* np_is_pub;
static pact_list* np_inclusive;
static pact_list* np_start;
static pact_list* np_end;
static pact_list* np_obj;
static pact_list* np_method;
static pact_list* np_index;
static pact_list* np_return_type;
static pact_list* np_type_name;
static pact_list* np_trait_name;
static pact_list* sl_items;
static pact_list* sl_start;
static pact_list* sl_len;
static int64_t sl_open = 0;
static pact_list* np_params;
static pact_list* np_args;
static pact_list* np_stmts;
static pact_list* np_arms;
static pact_list* np_fields;
static pact_list* np_elements;
static pact_list* np_methods;
static pact_list* np_type_params;
static pact_list* np_effects;
static pact_list* np_captures;
static pact_list* np_type_ann;
static pact_list* np_handlers;
static int64_t pos = 0;
static const int64_t CT_INT = 0;
static const int64_t CT_FLOAT = 1;
static const int64_t CT_BOOL = 2;
static const int64_t CT_STRING = 3;
static const int64_t CT_LIST = 4;
static const int64_t CT_VOID = 5;
static const int64_t CT_CLOSURE = 6;
static const int64_t CT_OPTION = 7;
static const int64_t CT_RESULT = 8;
static pact_list* cg_lines;
static int64_t cg_indent = 0;
static int64_t cg_temp_counter = 0;
static pact_list* cg_global_inits;
static pact_list* struct_reg_names;
static pact_list* enum_reg_names;
static pact_list* enum_reg_variant_names;
static pact_list* enum_reg_variant_enum_idx;
static pact_list* var_enum_names;
static pact_list* var_enum_types;
static pact_list* fn_enum_ret_names;
static pact_list* fn_enum_ret_types;
static pact_list* emitted_let_names;
static pact_list* emitted_fn_names;
static pact_list* cg_closure_defs;
static int64_t cg_closure_counter = 0;
static pact_list* closure_capture_names;
static pact_list* closure_capture_types;
static pact_list* closure_capture_muts;
static pact_list* closure_capture_starts;
static pact_list* closure_capture_counts;
static int64_t cg_closure_cap_start = (-1);
static int64_t cg_closure_cap_count = 0;
static pact_list* mut_captured_vars;
static pact_list* trait_reg_names;
static pact_list* trait_reg_method_sl;
static pact_list* impl_reg_trait;
static pact_list* impl_reg_type;
static pact_list* impl_reg_methods_sl;
static pact_list* from_reg_source;
static pact_list* from_reg_target;
static pact_list* from_reg_method_sl;
static pact_list* var_struct_names;
static pact_list* var_struct_types;
static pact_list* sf_reg_struct;
static pact_list* sf_reg_field;
static pact_list* sf_reg_type;
static pact_list* sf_reg_stype;
static pact_list* var_closure_names;
static pact_list* var_closure_sigs;
static pact_list* generic_fn_names;
static pact_list* generic_fn_nodes;
static pact_list* mono_fn_bases;
static pact_list* mono_fn_args;
static pact_list* mono_base_names;
static pact_list* mono_concrete_args;
static pact_list* mono_c_names;
static pact_list* var_option_names;
static pact_list* var_option_inner;
static pact_list* var_result_names;
static pact_list* var_result_ok;
static pact_list* var_result_err;
static pact_list* emitted_option_types;
static pact_list* emitted_result_types;
static int64_t cg_let_target_type = 0;
static pact_list* scope_names;
static pact_list* scope_types;
static pact_list* scope_muts;
static pact_list* scope_frame_starts;
static pact_list* fn_reg_names;
static pact_list* fn_reg_ret;
static pact_list* fn_reg_effect_sl;
static pact_list* effect_reg_names;
static pact_list* effect_reg_parent;
static const char* cg_current_fn_name = "";
static pact_list* var_list_elem_names;
static pact_list* var_list_elem_types;
static int64_t cg_program_node = 0;
static pact_list* match_scrut_strs;
static pact_list* match_scrut_types;
static const char* match_scrut_enum = "";
static const char* expr_result_str = "";
static int64_t expr_result_type = 0;
static const char* expr_closure_sig = "";
static int64_t expr_option_inner = (-1);
static int64_t expr_result_ok_type = (-1);
static int64_t expr_result_err_type = (-1);
static pact_list* loaded_files;
static pact_list* import_map_paths;
static pact_list* import_map_nodes;

const char* pact_token_kind_name(int64_t kind);
int64_t pact_is_keyword(int64_t kind);
int64_t pact_keyword_lookup(const char* name);
int64_t pact_is_alpha(int64_t c);
int64_t pact_is_digit(int64_t c);
int64_t pact_is_alnum(int64_t c);
int64_t pact_is_whitespace(int64_t c);
int64_t pact_peek(const char* source, int64_t pos);
int64_t pact_peek_at(const char* source, int64_t pos, int64_t offset);
void pact_lex(const char* source);
const char* pact_node_kind_name(int64_t kind);
int64_t pact_new_node(int64_t kind);
int64_t pact_new_sublist(void);
void pact_sublist_push(int64_t sl, int64_t node_id);
void pact_finalize_sublist(int64_t sl);
int64_t pact_sublist_get(int64_t sl, int64_t idx);
int64_t pact_sublist_length(int64_t sl);
int64_t pact_peek_kind(void);
const char* pact_peek_value(void);
int64_t pact_peek_line(void);
int64_t pact_peek_col(void);
int64_t pact_at(int64_t kind);
int64_t pact_advance(void);
const char* pact_advance_value(void);
int64_t pact_expect(int64_t kind);
const char* pact_expect_value(int64_t kind);
void pact_skip_newlines(void);
void pact_maybe_newline(void);
int64_t pact_parse_import_stmt(void);
int64_t pact_parse_program(void);
int64_t pact_parse_type_params(void);
int64_t pact_parse_type_def(void);
int64_t pact_parse_type_annotation(void);
int64_t pact_parse_effect_decl(void);
int64_t pact_parse_fn_def(void);
int64_t pact_parse_param(void);
int64_t pact_parse_closure(void);
int64_t pact_parse_trait_def(void);
int64_t pact_parse_impl_block(void);
int64_t pact_parse_handler_expr(void);
int64_t pact_parse_with_block(void);
int64_t pact_parse_block(void);
int64_t pact_parse_stmt(void);
int64_t pact_parse_let_binding(void);
int64_t pact_parse_return_stmt(void);
int64_t pact_parse_if_expr(void);
int64_t pact_parse_while_loop(void);
int64_t pact_parse_loop_expr(void);
int64_t pact_parse_for_in(void);
int64_t pact_parse_expr(void);
int64_t pact_parse_nullcoalesce(void);
int64_t pact_parse_or(void);
int64_t pact_parse_and(void);
int64_t pact_parse_equality(void);
int64_t pact_parse_comparison(void);
int64_t pact_parse_additive(void);
int64_t pact_parse_multiplicative(void);
int64_t pact_parse_unary(void);
int64_t pact_parse_postfix(void);
void pact_skip_named_arg_label(void);
const char* pact_flatten_field_access(int64_t node);
int64_t pact_looks_like_struct_lit(void);
int64_t pact_parse_primary(void);
int64_t pact_parse_struct_lit(const char* type_name);
int64_t pact_parse_list_lit(void);
int64_t pact_parse_interp_string(void);
int64_t pact_parse_match_expr(void);
int64_t pact_parse_match_arm(void);
int64_t pact_parse_pattern(void);
int64_t pact_parse_single_pattern(void);
void pact_push_scope(void);
void pact_pop_scope(void);
void pact_set_var(const char* name, int64_t ctype, int64_t is_mut);
int64_t pact_get_var_type(const char* name);
int64_t pact_get_var_mut(const char* name);
int64_t pact_is_mut_captured(const char* name);
int64_t pact_get_capture_index(const char* name);
const char* pact_capture_cast_expr(int64_t idx);
void pact_reg_fn(const char* name, int64_t ret);
void pact_reg_fn_with_effects(const char* name, int64_t ret, int64_t effects_sl);
int64_t pact_get_fn_effect_sl(const char* name);
int64_t pact_reg_effect(const char* name, int64_t parent);
int64_t pact_get_effect_idx(const char* name);
int64_t pact_effect_satisfies(const char* caller_effect, const char* callee_effect);
void pact_check_effect_propagation(const char* callee_name);
void pact_init_builtin_effects(void);
int64_t pact_get_fn_ret(const char* name);
void pact_set_list_elem_type(const char* name, int64_t elem_type);
int64_t pact_get_list_elem_type(const char* name);
int64_t pact_is_struct_type(const char* name);
int64_t pact_is_enum_type(const char* name);
const char* pact_resolve_variant(const char* name);
const char* pact_get_var_enum(const char* name);
const char* pact_get_fn_enum_ret(const char* name);
void pact_set_var_struct(const char* name, const char* type_name);
const char* pact_get_var_struct(const char* name);
int64_t pact_get_struct_field_type(const char* sname, const char* fname);
const char* pact_get_struct_field_stype(const char* sname, const char* fname);
void pact_set_var_closure(const char* name, const char* sig);
const char* pact_get_var_closure_sig(const char* name);
const char* pact_build_closure_sig_from_type_ann(int64_t ta);
int64_t pact_is_generic_fn(const char* name);
int64_t pact_get_generic_fn_node(const char* name);
void pact_register_mono_fn(const char* base, const char* args);
const char* pact_infer_fn_type_args_from_types(int64_t fn_node, pact_list* arg_types);
const char* pact_type_name_from_ct(int64_t ct);
const char* pact_mangle_generic_name(const char* base, const char* args);
const char* pact_register_mono_instance(const char* base, const char* args);
const char* pact_lookup_mono_instance(const char* base, const char* args);
int64_t pact_is_trait_type(const char* name);
int64_t pact_lookup_impl_method(const char* type_name, const char* method);
int64_t pact_lookup_impl_type_for_trait(const char* trait_name, const char* type_name);
int64_t pact_get_impl_method_ret(const char* type_name, const char* method);
int64_t pact_find_from_impl(const char* source, const char* target);
int64_t pact_impl_method_has_self(int64_t fn_node);
const char* pact_resolve_self_type(const char* ret_str, const char* impl_type);
int64_t pact_is_emitted_let(const char* name);
int64_t pact_is_emitted_fn(const char* name);
const char* pact_c_type_str(int64_t ct);
int64_t pact_type_from_name(const char* name);
const char* pact_option_c_type(int64_t inner);
const char* pact_result_c_type(int64_t ok_t, int64_t err_t);
const char* pact_c_type_tag(int64_t ct);
void pact_ensure_option_type(int64_t inner);
void pact_ensure_result_type(int64_t ok_t, int64_t err_t);
void pact_set_var_option(const char* name, int64_t inner);
int64_t pact_get_var_option_inner(const char* name);
void pact_set_var_result(const char* name, int64_t ok_t, int64_t err_t);
int64_t pact_get_var_result_ok(const char* name);
int64_t pact_get_var_result_err(const char* name);
void pact_emit_option_typedef(int64_t inner);
void pact_emit_result_typedef(int64_t ok_t, int64_t err_t);
void pact_emit_all_option_result_types(void);
const char* pact_fresh_temp(const char* prefix);
void pact_emit_line(const char* line);
const char* pact_join_lines(void);
void pact_emit_expr(int64_t node);
void pact_emit_binop(int64_t node);
void pact_emit_unaryop(int64_t node);
void pact_emit_call(int64_t node);
void pact_emit_method_call(int64_t node);
const char* pact_escape_c_string(const char* s);
void pact_emit_interp_string(int64_t node);
void pact_emit_list_lit(int64_t node);
const char* pact_infer_struct_type_args(const char* type_name, pact_list* field_types);
void pact_emit_struct_lit(int64_t node);
int64_t pact_list_contains_str(pact_list* lst, const char* val);
int64_t pact_is_in_scope(const char* name);
void pact_collect_free_vars(int64_t node, pact_list* params, pact_list* locals, pact_list* result);
void pact_collect_free_vars_block(int64_t block, pact_list* params, pact_list* locals, pact_list* result);
pact_list* pact_analyze_captures(int64_t body, int64_t params_sl);
void pact_emit_closure(int64_t node);
void pact_emit_if_expr(int64_t node);
void pact_emit_match_expr(int64_t node);
const char* pact_pattern_condition(int64_t pat, int64_t scrut_off, int64_t scrut_len);
void pact_bind_pattern_vars(int64_t pat, int64_t scrut_off, int64_t scrut_len);
void pact_emit_block_expr(int64_t node);
const char* pact_emit_arm_value(int64_t body);
const char* pact_emit_block_value(int64_t block);
int64_t pact_infer_block_type(int64_t block);
int64_t pact_infer_arm_type(int64_t arm);
int64_t pact_infer_expr_type(int64_t node);
void pact_emit_stmt(int64_t node);
const char* pact_infer_enum_from_node(int64_t val_node);
void pact_emit_let_binding(int64_t node);
void pact_emit_for_in(int64_t node);
void pact_emit_if_stmt(int64_t node);
void pact_emit_block(int64_t block);
void pact_emit_with_block(int64_t node);
const char* pact_format_params(int64_t fn_node);
const char* pact_format_impl_params(int64_t fn_node, const char* impl_type);
void pact_emit_impl_method_def(int64_t fn_node, const char* impl_type);
void pact_emit_fn_decl(int64_t fn_node);
void pact_emit_fn_def(int64_t fn_node);
void pact_emit_fn_body(int64_t block, int64_t ret_type);
int64_t pact_find_type_def(const char* name);
const char* pact_resolve_type_param(const char* param_name, int64_t tparams_sl, const char* concrete_args);
void pact_register_mono_field_types(const char* base_name, const char* mono_name, const char* concrete_args);
void pact_emit_mono_struct_typedef(const char* base_name, const char* concrete_args);
void pact_emit_all_mono_typedefs(void);
void pact_emit_mono_fn_def(int64_t fn_node, const char* concrete_args);
void pact_emit_all_mono_fns(void);
void pact_emit_struct_typedef(int64_t td_node);
void pact_emit_enum_typedef(int64_t td_node);
void pact_emit_top_level_let(int64_t node);
const char* pact_generate(int64_t program);
const char* pact_dots_to_slashes(const char* s);
const char* pact_find_src_root(const char* source_path);
const char* pact_resolve_module_path(const char* dotted_path, const char* src_root);
int64_t pact_should_import_item(int64_t item, int64_t import_node);
int64_t pact_merge_programs(int64_t main_prog, pact_list* imported, pact_list* import_nodes_list);
int64_t pact_is_file_loaded(const char* path);
void pact_collect_imports(int64_t program, const char* src_root, pact_list* all_programs);
void pact_main(void);

const char* pact_token_kind_name(int64_t kind) {
    const char* _match_0;
    if ((kind == pact_TokenKind_Fn)) {
        _match_0 = "fn";
    } else if ((kind == pact_TokenKind_Let)) {
        _match_0 = "let";
    } else if ((kind == pact_TokenKind_Mut)) {
        _match_0 = "mut";
    } else if ((kind == pact_TokenKind_Type)) {
        _match_0 = "type";
    } else if ((kind == pact_TokenKind_Trait)) {
        _match_0 = "trait";
    } else if ((kind == pact_TokenKind_Impl)) {
        _match_0 = "impl";
    } else if ((kind == pact_TokenKind_If)) {
        _match_0 = "if";
    } else if ((kind == pact_TokenKind_Else)) {
        _match_0 = "else";
    } else if ((kind == pact_TokenKind_Match)) {
        _match_0 = "match";
    } else if ((kind == pact_TokenKind_For)) {
        _match_0 = "for";
    } else if ((kind == pact_TokenKind_In)) {
        _match_0 = "in";
    } else if ((kind == pact_TokenKind_While)) {
        _match_0 = "while";
    } else if ((kind == pact_TokenKind_Loop)) {
        _match_0 = "loop";
    } else if ((kind == pact_TokenKind_Break)) {
        _match_0 = "break";
    } else if ((kind == pact_TokenKind_Continue)) {
        _match_0 = "continue";
    } else if ((kind == pact_TokenKind_Return)) {
        _match_0 = "return";
    } else if ((kind == pact_TokenKind_Pub)) {
        _match_0 = "pub";
    } else if ((kind == pact_TokenKind_With)) {
        _match_0 = "with";
    } else if ((kind == pact_TokenKind_Handler)) {
        _match_0 = "handler";
    } else if ((kind == pact_TokenKind_Self)) {
        _match_0 = "self";
    } else if ((kind == pact_TokenKind_Test)) {
        _match_0 = "test";
    } else if ((kind == pact_TokenKind_Import)) {
        _match_0 = "import";
    } else if ((kind == pact_TokenKind_As)) {
        _match_0 = "as";
    } else if ((kind == pact_TokenKind_Mod)) {
        _match_0 = "mod";
    } else if ((kind == pact_TokenKind_Effect)) {
        _match_0 = "effect";
    } else if ((kind == pact_TokenKind_Assert)) {
        _match_0 = "assert";
    } else if ((kind == pact_TokenKind_AssertEq)) {
        _match_0 = "assert_eq";
    } else if ((kind == pact_TokenKind_AssertNe)) {
        _match_0 = "assert_ne";
    } else if ((kind == pact_TokenKind_Ident)) {
        _match_0 = "IDENT";
    } else if ((kind == pact_TokenKind_Int)) {
        _match_0 = "INT";
    } else if ((kind == pact_TokenKind_Float)) {
        _match_0 = "FLOAT";
    } else if ((kind == pact_TokenKind_StringStart)) {
        _match_0 = "STRING_START";
    } else if ((kind == pact_TokenKind_StringEnd)) {
        _match_0 = "STRING_END";
    } else if ((kind == pact_TokenKind_StringPart)) {
        _match_0 = "STRING_PART";
    } else if ((kind == pact_TokenKind_InterpStart)) {
        _match_0 = "INTERP_START";
    } else if ((kind == pact_TokenKind_InterpEnd)) {
        _match_0 = "INTERP_END";
    } else if ((kind == pact_TokenKind_LParen)) {
        _match_0 = "(";
    } else if ((kind == pact_TokenKind_RParen)) {
        _match_0 = ")";
    } else if ((kind == pact_TokenKind_LBrace)) {
        _match_0 = "{";
    } else if ((kind == pact_TokenKind_RBrace)) {
        _match_0 = "\\";
    } else if ((kind == pact_TokenKind_LBracket)) {
        _match_0 = "[";
    } else if ((kind == pact_TokenKind_RBracket)) {
        _match_0 = "]";
    } else if ((kind == pact_TokenKind_Colon)) {
        _match_0 = ":";
    } else if ((kind == pact_TokenKind_Comma)) {
        _match_0 = ",";
    } else if ((kind == pact_TokenKind_Dot)) {
        _match_0 = ".";
    } else if ((kind == pact_TokenKind_DotDot)) {
        _match_0 = "..";
    } else if ((kind == pact_TokenKind_DotDoteq)) {
        _match_0 = "..=";
    } else if ((kind == pact_TokenKind_Arrow)) {
        _match_0 = "->";
    } else if ((kind == pact_TokenKind_FatArrow)) {
        _match_0 = "=>";
    } else if ((kind == pact_TokenKind_At)) {
        _match_0 = "@";
    } else if ((kind == pact_TokenKind_Plus)) {
        _match_0 = "+";
    } else if ((kind == pact_TokenKind_Minus)) {
        _match_0 = "-";
    } else if ((kind == pact_TokenKind_Star)) {
        _match_0 = "*";
    } else if ((kind == pact_TokenKind_Slash)) {
        _match_0 = "/";
    } else if ((kind == pact_TokenKind_Percent)) {
        _match_0 = "%";
    } else if ((kind == pact_TokenKind_Equals)) {
        _match_0 = "=";
    } else if ((kind == pact_TokenKind_EqEq)) {
        _match_0 = "==";
    } else if ((kind == pact_TokenKind_NotEq)) {
        _match_0 = "!=";
    } else if ((kind == pact_TokenKind_Less)) {
        _match_0 = "<";
    } else if ((kind == pact_TokenKind_Greater)) {
        _match_0 = ">";
    } else if ((kind == pact_TokenKind_LessEq)) {
        _match_0 = "<=";
    } else if ((kind == pact_TokenKind_GreaterEq)) {
        _match_0 = ">=";
    } else if ((kind == pact_TokenKind_And)) {
        _match_0 = "&&";
    } else if ((kind == pact_TokenKind_Or)) {
        _match_0 = "||";
    } else if ((kind == pact_TokenKind_Bang)) {
        _match_0 = "!";
    } else if ((kind == pact_TokenKind_Question)) {
        _match_0 = "?";
    } else if ((kind == pact_TokenKind_DoubleQuestion)) {
        _match_0 = "??";
    } else if ((kind == pact_TokenKind_Pipe)) {
        _match_0 = "|";
    } else if ((kind == pact_TokenKind_PipeArrow)) {
        _match_0 = "|>";
    } else if ((kind == pact_TokenKind_PlusEq)) {
        _match_0 = "+=";
    } else if ((kind == pact_TokenKind_MinusEq)) {
        _match_0 = "-=";
    } else if ((kind == pact_TokenKind_StarEq)) {
        _match_0 = "*=";
    } else if ((kind == pact_TokenKind_SlashEq)) {
        _match_0 = "/=";
    } else if ((kind == pact_TokenKind_Newline)) {
        _match_0 = "NEWLINE";
    } else if ((kind == pact_TokenKind_EOF)) {
        _match_0 = "EOF";
    } else {
        _match_0 = "UNKNOWN";
    }
    return _match_0;
}

int64_t pact_is_keyword(int64_t kind) {
    return ((kind >= pact_TokenKind_Fn) && (kind <= pact_TokenKind_Effect));
}

int64_t pact_keyword_lookup(const char* name) {
    int64_t _match_0;
    if ((pact_str_eq(name, "fn"))) {
        _match_0 = pact_TokenKind_Fn;
    } else if ((pact_str_eq(name, "let"))) {
        _match_0 = pact_TokenKind_Let;
    } else if ((pact_str_eq(name, "mut"))) {
        _match_0 = pact_TokenKind_Mut;
    } else if ((pact_str_eq(name, "type"))) {
        _match_0 = pact_TokenKind_Type;
    } else if ((pact_str_eq(name, "trait"))) {
        _match_0 = pact_TokenKind_Trait;
    } else if ((pact_str_eq(name, "impl"))) {
        _match_0 = pact_TokenKind_Impl;
    } else if ((pact_str_eq(name, "if"))) {
        _match_0 = pact_TokenKind_If;
    } else if ((pact_str_eq(name, "else"))) {
        _match_0 = pact_TokenKind_Else;
    } else if ((pact_str_eq(name, "match"))) {
        _match_0 = pact_TokenKind_Match;
    } else if ((pact_str_eq(name, "for"))) {
        _match_0 = pact_TokenKind_For;
    } else if ((pact_str_eq(name, "in"))) {
        _match_0 = pact_TokenKind_In;
    } else if ((pact_str_eq(name, "while"))) {
        _match_0 = pact_TokenKind_While;
    } else if ((pact_str_eq(name, "loop"))) {
        _match_0 = pact_TokenKind_Loop;
    } else if ((pact_str_eq(name, "break"))) {
        _match_0 = pact_TokenKind_Break;
    } else if ((pact_str_eq(name, "continue"))) {
        _match_0 = pact_TokenKind_Continue;
    } else if ((pact_str_eq(name, "return"))) {
        _match_0 = pact_TokenKind_Return;
    } else if ((pact_str_eq(name, "pub"))) {
        _match_0 = pact_TokenKind_Pub;
    } else if ((pact_str_eq(name, "with"))) {
        _match_0 = pact_TokenKind_With;
    } else if ((pact_str_eq(name, "handler"))) {
        _match_0 = pact_TokenKind_Handler;
    } else if ((pact_str_eq(name, "self"))) {
        _match_0 = pact_TokenKind_Self;
    } else if ((pact_str_eq(name, "test"))) {
        _match_0 = pact_TokenKind_Test;
    } else if ((pact_str_eq(name, "import"))) {
        _match_0 = pact_TokenKind_Import;
    } else if ((pact_str_eq(name, "as"))) {
        _match_0 = pact_TokenKind_As;
    } else if ((pact_str_eq(name, "mod"))) {
        _match_0 = pact_TokenKind_Mod;
    } else if ((pact_str_eq(name, "effect"))) {
        _match_0 = pact_TokenKind_Effect;
    } else if ((pact_str_eq(name, "assert"))) {
        _match_0 = pact_TokenKind_Assert;
    } else if ((pact_str_eq(name, "assert_eq"))) {
        _match_0 = pact_TokenKind_AssertEq;
    } else if ((pact_str_eq(name, "assert_ne"))) {
        _match_0 = pact_TokenKind_AssertNe;
    } else {
        _match_0 = pact_TokenKind_Ident;
    }
    return _match_0;
}

int64_t pact_is_alpha(int64_t c) {
    return ((((c >= CH_A) && (c <= CH_Z)) || ((c >= CH_a) && (c <= CH_Z_LOWER))) || (c == CH_UNDERSCORE));
}

int64_t pact_is_digit(int64_t c) {
    return ((c >= CH_0) && (c <= CH_9));
}

int64_t pact_is_alnum(int64_t c) {
    return (pact_is_alpha(c) || pact_is_digit(c));
}

int64_t pact_is_whitespace(int64_t c) {
    return ((c == CH_SPACE) || (c == CH_TAB));
}

int64_t pact_peek(const char* source, int64_t pos) {
    int64_t _if_0;
    if ((pos >= pact_str_len(source))) {
        _if_0 = 0;
    } else {
        _if_0 = pact_str_char_at(source, pos);
    }
    return _if_0;
}

int64_t pact_peek_at(const char* source, int64_t pos, int64_t offset) {
    return pact_peek(source, (pos + offset));
}

void pact_lex(const char* source) {
    pact_list* _l0 = pact_list_new();
    tok_kinds = _l0;
    pact_list* _l1 = pact_list_new();
    tok_values = _l1;
    pact_list* _l2 = pact_list_new();
    tok_lines = _l2;
    pact_list* _l3 = pact_list_new();
    tok_cols = _l3;
    int64_t pos = 0;
    int64_t line = 1;
    int64_t col = 1;
    pact_list* _l4 = pact_list_new();
    pact_list* mode_stack = _l4;
    pact_list* _l5 = pact_list_new();
    pact_list* brace_depth_stack = _l5;
    pact_list_push(mode_stack, (void*)(intptr_t)MODE_NORMAL);
    pact_list_push(brace_depth_stack, (void*)(intptr_t)0);
    const char* string_buf = "";
    int64_t last_kind = (-1);
    while ((pos < pact_str_len(source))) {
        const int64_t mode = (int64_t)(intptr_t)pact_list_get(mode_stack, (pact_list_len(mode_stack) - 1));
        if ((mode == MODE_NORMAL)) {
            const int64_t brace_depth = (int64_t)(intptr_t)pact_list_get(brace_depth_stack, (pact_list_len(brace_depth_stack) - 1));
            const int64_t ch = pact_peek(source, pos);
            if (pact_is_whitespace(ch)) {
                pos = (pos + 1);
                col = (col + 1);
                continue;
            }
            if (((ch == CH_SLASH) && (pact_peek_at(source, pos, 1) == CH_SLASH))) {
                pos = (pos + 2);
                col = (col + 2);
                while (((pos < pact_str_len(source)) && (pact_peek(source, pos) != CH_NEWLINE))) {
                    pos = (pos + 1);
                    col = (col + 1);
                }
                if (((pos < pact_str_len(source)) && (pact_peek(source, pos) == CH_NEWLINE))) {
                    pos = (pos + 1);
                    line = (line + 1);
                    col = 1;
                }
                continue;
            }
            if ((ch == CH_SLASH)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                if (((pos < pact_str_len(source)) && (pact_peek(source, pos) == CH_EQUALS))) {
                    pos = (pos + 1);
                    col = (col + 1);
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_SlashEq);
                    pact_list_push(tok_values, (void*)"/=");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_SlashEq;
                } else {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Slash);
                    pact_list_push(tok_values, (void*)"/");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_Slash;
                }
                continue;
            }
            if ((ch == CH_NEWLINE)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                line = (line + 1);
                col = 1;
                if ((last_kind != pact_TokenKind_Newline)) {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Newline);
                    pact_list_push(tok_values, (void*)"\\n");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_Newline;
                }
                continue;
            }
            if ((ch == CH_DQUOTE)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_StringStart);
                pact_list_push(tok_values, (void*)"\"");
                pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                last_kind = pact_TokenKind_StringStart;
                pact_list_push(mode_stack, (void*)(intptr_t)MODE_STRING);
                pact_list_push(brace_depth_stack, (void*)(intptr_t)0);
                string_buf = "";
                continue;
            }
            if ((ch == CH_LBRACE)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                if ((brace_depth > 0)) {
                    pact_list_push(brace_depth_stack, (void*)(intptr_t)(brace_depth + 1));
                    pact_list_push(mode_stack, (void*)(intptr_t)MODE_NORMAL);
                    const int64_t mlen = pact_list_len(mode_stack);
                    pact_list_pop(mode_stack);
                    pact_list_pop(brace_depth_stack);
                    pact_list_pop(brace_depth_stack);
                    pact_list_push(brace_depth_stack, (void*)(intptr_t)(brace_depth + 1));
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_LBrace);
                    pact_list_push(tok_values, (void*)"{");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_LBrace;
                } else {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_LBrace);
                    pact_list_push(tok_values, (void*)"{");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_LBrace;
                }
                continue;
            }
            if ((ch == CH_RBRACE)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                if ((brace_depth > 1)) {
                    pact_list_pop(brace_depth_stack);
                    pact_list_push(brace_depth_stack, (void*)(intptr_t)(brace_depth - 1));
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_RBrace);
                    pact_list_push(tok_values, (void*)"\\");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_RBrace;
                } else if ((brace_depth == 1)) {
                    pact_list_pop(mode_stack);
                    pact_list_pop(brace_depth_stack);
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_InterpEnd);
                    pact_list_push(tok_values, (void*)"\\");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_InterpEnd;
                } else {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_RBrace);
                    pact_list_push(tok_values, (void*)"\\");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_RBrace;
                }
                continue;
            }
            if ((ch == CH_QUESTION)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                if (((pos < pact_str_len(source)) && (pact_peek(source, pos) == CH_QUESTION))) {
                    pos = (pos + 1);
                    col = (col + 1);
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_DoubleQuestion);
                    pact_list_push(tok_values, (void*)"??");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_DoubleQuestion;
                } else {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Question);
                    pact_list_push(tok_values, (void*)"?");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_Question;
                }
                continue;
            }
            if ((ch == CH_MINUS)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                if ((pact_peek_at(source, pos, 1) == CH_GREATER)) {
                    pos = (pos + 2);
                    col = (col + 2);
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Arrow);
                    pact_list_push(tok_values, (void*)"->");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_Arrow;
                } else if ((pact_peek_at(source, pos, 1) == CH_EQUALS)) {
                    pos = (pos + 2);
                    col = (col + 2);
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_MinusEq);
                    pact_list_push(tok_values, (void*)"-=");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_MinusEq;
                } else {
                    pos = (pos + 1);
                    col = (col + 1);
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Minus);
                    pact_list_push(tok_values, (void*)"-");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_Minus;
                }
                continue;
            }
            if ((ch == CH_PLUS)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                if (((pos < pact_str_len(source)) && (pact_peek(source, pos) == CH_EQUALS))) {
                    pos = (pos + 1);
                    col = (col + 1);
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_PlusEq);
                    pact_list_push(tok_values, (void*)"+=");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_PlusEq;
                } else {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Plus);
                    pact_list_push(tok_values, (void*)"+");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_Plus;
                }
                continue;
            }
            if ((ch == CH_STAR)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                if (((pos < pact_str_len(source)) && (pact_peek(source, pos) == CH_EQUALS))) {
                    pos = (pos + 1);
                    col = (col + 1);
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_StarEq);
                    pact_list_push(tok_values, (void*)"*=");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_StarEq;
                } else {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Star);
                    pact_list_push(tok_values, (void*)"*");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_Star;
                }
                continue;
            }
            if ((ch == CH_EQUALS)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                if (((pos < pact_str_len(source)) && (pact_peek(source, pos) == CH_GREATER))) {
                    pos = (pos + 1);
                    col = (col + 1);
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_FatArrow);
                    pact_list_push(tok_values, (void*)"=>");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_FatArrow;
                } else if (((pos < pact_str_len(source)) && (pact_peek(source, pos) == CH_EQUALS))) {
                    pos = (pos + 1);
                    col = (col + 1);
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_EqEq);
                    pact_list_push(tok_values, (void*)"==");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_EqEq;
                } else {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Equals);
                    pact_list_push(tok_values, (void*)"=");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_Equals;
                }
                continue;
            }
            if (((ch == CH_DOT) && (pact_peek_at(source, pos, 1) == CH_DOT))) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 2);
                col = (col + 2);
                if (((pos < pact_str_len(source)) && (pact_peek(source, pos) == CH_EQUALS))) {
                    pos = (pos + 1);
                    col = (col + 1);
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_DotDoteq);
                    pact_list_push(tok_values, (void*)"..=");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_DotDoteq;
                } else {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_DotDot);
                    pact_list_push(tok_values, (void*)"..");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_DotDot;
                }
                continue;
            }
            if ((ch == CH_DOT)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Dot);
                pact_list_push(tok_values, (void*)".");
                pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                last_kind = pact_TokenKind_Dot;
                continue;
            }
            if ((ch == CH_BANG)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                if (((pos < pact_str_len(source)) && (pact_peek(source, pos) == CH_EQUALS))) {
                    pos = (pos + 1);
                    col = (col + 1);
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_NotEq);
                    pact_list_push(tok_values, (void*)"!=");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_NotEq;
                } else {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Bang);
                    pact_list_push(tok_values, (void*)"!");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_Bang;
                }
                continue;
            }
            if ((ch == CH_LESS)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                if (((pos < pact_str_len(source)) && (pact_peek(source, pos) == CH_EQUALS))) {
                    pos = (pos + 1);
                    col = (col + 1);
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_LessEq);
                    pact_list_push(tok_values, (void*)"<=");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_LessEq;
                } else {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Less);
                    pact_list_push(tok_values, (void*)"<");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_Less;
                }
                continue;
            }
            if ((ch == CH_GREATER)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                if (((pos < pact_str_len(source)) && (pact_peek(source, pos) == CH_EQUALS))) {
                    pos = (pos + 1);
                    col = (col + 1);
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_GreaterEq);
                    pact_list_push(tok_values, (void*)">=");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_GreaterEq;
                } else {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Greater);
                    pact_list_push(tok_values, (void*)">");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_Greater;
                }
                continue;
            }
            if (((ch == CH_AMP) && (pact_peek_at(source, pos, 1) == CH_AMP))) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 2);
                col = (col + 2);
                pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_And);
                pact_list_push(tok_values, (void*)"&&");
                pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                last_kind = pact_TokenKind_And;
                continue;
            }
            if ((ch == CH_PIPE)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                if (((pos < pact_str_len(source)) && (pact_peek(source, pos) == CH_PIPE))) {
                    pos = (pos + 1);
                    col = (col + 1);
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Or);
                    pact_list_push(tok_values, (void*)"||");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_Or;
                } else if (((pos < pact_str_len(source)) && (pact_peek(source, pos) == CH_GREATER))) {
                    pos = (pos + 1);
                    col = (col + 1);
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_PipeArrow);
                    pact_list_push(tok_values, (void*)"|>");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_PipeArrow;
                } else {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Pipe);
                    pact_list_push(tok_values, (void*)"|");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_Pipe;
                }
                continue;
            }
            if ((ch == CH_LPAREN)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_LParen);
                pact_list_push(tok_values, (void*)"(");
                pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                last_kind = pact_TokenKind_LParen;
                continue;
            }
            if ((ch == CH_RPAREN)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_RParen);
                pact_list_push(tok_values, (void*)")");
                pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                last_kind = pact_TokenKind_RParen;
                continue;
            }
            if ((ch == CH_COLON)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Colon);
                pact_list_push(tok_values, (void*)":");
                pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                last_kind = pact_TokenKind_Colon;
                continue;
            }
            if ((ch == CH_COMMA)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Comma);
                pact_list_push(tok_values, (void*)",");
                pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                last_kind = pact_TokenKind_Comma;
                continue;
            }
            if ((ch == CH_PERCENT)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Percent);
                pact_list_push(tok_values, (void*)"%");
                pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                last_kind = pact_TokenKind_Percent;
                continue;
            }
            if ((ch == CH_LBRACKET)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_LBracket);
                pact_list_push(tok_values, (void*)"[");
                pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                last_kind = pact_TokenKind_LBracket;
                continue;
            }
            if ((ch == CH_RBRACKET)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_RBracket);
                pact_list_push(tok_values, (void*)"]");
                pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                last_kind = pact_TokenKind_RBracket;
                continue;
            }
            if ((ch == CH_AT)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_At);
                pact_list_push(tok_values, (void*)"@");
                pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                last_kind = pact_TokenKind_At;
                continue;
            }
            if (pact_is_alpha(ch)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                const int64_t start = pos;
                while (((pos < pact_str_len(source)) && pact_is_alnum(pact_peek(source, pos)))) {
                    pos = (pos + 1);
                    col = (col + 1);
                }
                const char* word = pact_str_substr(source, start, (pos - start));
                const int64_t kind = pact_keyword_lookup(word);
                pact_list_push(tok_kinds, (void*)(intptr_t)kind);
                pact_list_push(tok_values, (void*)word);
                pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                last_kind = kind;
                continue;
            }
            if (pact_is_digit(ch)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                const int64_t start = pos;
                while (((pos < pact_str_len(source)) && pact_is_digit(pact_peek(source, pos)))) {
                    pos = (pos + 1);
                    col = (col + 1);
                }
                if ((((pos < pact_str_len(source)) && (pact_peek(source, pos) == CH_DOT)) && pact_is_digit(pact_peek_at(source, pos, 1)))) {
                    pos = (pos + 1);
                    col = (col + 1);
                    while (((pos < pact_str_len(source)) && pact_is_digit(pact_peek(source, pos)))) {
                        pos = (pos + 1);
                        col = (col + 1);
                    }
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Float);
                    pact_list_push(tok_values, (void*)pact_str_substr(source, start, (pos - start)));
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_Float;
                } else {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Int);
                    pact_list_push(tok_values, (void*)pact_str_substr(source, start, (pos - start)));
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_Int;
                }
                continue;
            }
            char _si_6[4096];
            snprintf(_si_6, 4096, "lexer error: unexpected character at line %lld col %lld", (long long)line, (long long)col);
            printf("%s\n", strdup(_si_6));
            pos = (pos + 1);
            col = (col + 1);
        } else {
            const int64_t ch = pact_peek(source, pos);
            if ((ch == CH_LBRACE)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_StringPart);
                pact_list_push(tok_values, (void*)string_buf);
                pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                last_kind = pact_TokenKind_StringPart;
                string_buf = "";
                pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_InterpStart);
                pact_list_push(tok_values, (void*)"{");
                pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                last_kind = pact_TokenKind_InterpStart;
                pact_list_push(mode_stack, (void*)(intptr_t)MODE_NORMAL);
                pact_list_push(brace_depth_stack, (void*)(intptr_t)1);
                continue;
            }
            if ((ch == CH_DQUOTE)) {
                const int64_t t_line = line;
                const int64_t t_col = col;
                pos = (pos + 1);
                col = (col + 1);
                pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_StringPart);
                pact_list_push(tok_values, (void*)string_buf);
                pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                last_kind = pact_TokenKind_StringPart;
                string_buf = "";
                pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_StringEnd);
                pact_list_push(tok_values, (void*)"\"");
                pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                last_kind = pact_TokenKind_StringEnd;
                pact_list_pop(mode_stack);
                pact_list_pop(brace_depth_stack);
                continue;
            }
            if ((ch == CH_BACKSLASH)) {
                pos = (pos + 1);
                col = (col + 1);
                if ((pos >= pact_str_len(source))) {
                    printf("%s\n", "lexer error: unexpected end of string after backslash");
                    continue;
                }
                const int64_t esc = pact_peek(source, pos);
                pos = (pos + 1);
                col = (col + 1);
                if ((esc == CH_n)) {
                    string_buf = pact_str_concat(string_buf, "\n");
                } else if ((esc == CH_t)) {
                    string_buf = pact_str_concat(string_buf, "\t");
                } else {
                    if ((esc == CH_BACKSLASH)) {
                        string_buf = pact_str_concat(string_buf, "\\");
                    } else if ((esc == CH_DQUOTE)) {
                        string_buf = pact_str_concat(string_buf, "\"");
                    } else {
                        if ((esc == CH_LBRACE)) {
                            string_buf = pact_str_concat(string_buf, "{");
                        } else {
                            string_buf = pact_str_concat(string_buf, "\\");
                        }
                    }
                }
                continue;
            }
            string_buf = pact_str_concat(string_buf, pact_str_substr(source, pos, 1));
            pos = (pos + 1);
            if ((ch == CH_NEWLINE)) {
                line = (line + 1);
                col = 1;
            } else {
                col = (col + 1);
            }
        }
    }
    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_EOF);
    pact_list_push(tok_values, (void*)"");
    pact_list_push(tok_lines, (void*)(intptr_t)line);
    pact_list_push(tok_cols, (void*)(intptr_t)col);
}

const char* pact_node_kind_name(int64_t kind) {
    const char* _match_0;
    if ((kind == pact_NodeKind_IntLit)) {
        _match_0 = "IntLit";
    } else if ((kind == pact_NodeKind_FloatLit)) {
        _match_0 = "FloatLit";
    } else if ((kind == pact_NodeKind_Ident)) {
        _match_0 = "Ident";
    } else if ((kind == pact_NodeKind_Call)) {
        _match_0 = "Call";
    } else if ((kind == pact_NodeKind_MethodCall)) {
        _match_0 = "MethodCall";
    } else if ((kind == pact_NodeKind_BinOp)) {
        _match_0 = "BinOp";
    } else if ((kind == pact_NodeKind_UnaryOp)) {
        _match_0 = "UnaryOp";
    } else if ((kind == pact_NodeKind_InterpString)) {
        _match_0 = "InterpString";
    } else if ((kind == pact_NodeKind_BoolLit)) {
        _match_0 = "BoolLit";
    } else if ((kind == pact_NodeKind_TupleLit)) {
        _match_0 = "TupleLit";
    } else if ((kind == pact_NodeKind_ListLit)) {
        _match_0 = "ListLit";
    } else if ((kind == pact_NodeKind_StructLit)) {
        _match_0 = "StructLit";
    } else if ((kind == pact_NodeKind_FieldAccess)) {
        _match_0 = "FieldAccess";
    } else if ((kind == pact_NodeKind_IndexExpr)) {
        _match_0 = "IndexExpr";
    } else if ((kind == pact_NodeKind_RangeLit)) {
        _match_0 = "RangeLit";
    } else if ((kind == pact_NodeKind_IfExpr)) {
        _match_0 = "IfExpr";
    } else if ((kind == pact_NodeKind_MatchExpr)) {
        _match_0 = "MatchExpr";
    } else if ((kind == pact_NodeKind_Closure)) {
        _match_0 = "Closure";
    } else if ((kind == pact_NodeKind_LetBinding)) {
        _match_0 = "LetBinding";
    } else if ((kind == pact_NodeKind_ExprStmt)) {
        _match_0 = "ExprStmt";
    } else if ((kind == pact_NodeKind_Assignment)) {
        _match_0 = "Assignment";
    } else if ((kind == pact_NodeKind_CompoundAssign)) {
        _match_0 = "CompoundAssign";
    } else if ((kind == pact_NodeKind_Return)) {
        _match_0 = "Return";
    } else if ((kind == pact_NodeKind_ForIn)) {
        _match_0 = "ForIn";
    } else if ((kind == pact_NodeKind_WhileLoop)) {
        _match_0 = "WhileLoop";
    } else if ((kind == pact_NodeKind_LoopExpr)) {
        _match_0 = "LoopExpr";
    } else if ((kind == pact_NodeKind_Break)) {
        _match_0 = "Break";
    } else if ((kind == pact_NodeKind_Continue)) {
        _match_0 = "Continue";
    } else if ((kind == pact_NodeKind_Block)) {
        _match_0 = "Block";
    } else if ((kind == pact_NodeKind_FnDef)) {
        _match_0 = "FnDef";
    } else if ((kind == pact_NodeKind_Param)) {
        _match_0 = "Param";
    } else if ((kind == pact_NodeKind_Program)) {
        _match_0 = "Program";
    } else if ((kind == pact_NodeKind_TypeDef)) {
        _match_0 = "TypeDef";
    } else if ((kind == pact_NodeKind_TypeField)) {
        _match_0 = "TypeField";
    } else if ((kind == pact_NodeKind_TypeVariant)) {
        _match_0 = "TypeVariant";
    } else if ((kind == pact_NodeKind_TraitDef)) {
        _match_0 = "TraitDef";
    } else if ((kind == pact_NodeKind_ImplBlock)) {
        _match_0 = "ImplBlock";
    } else if ((kind == pact_NodeKind_TestBlock)) {
        _match_0 = "TestBlock";
    } else if ((kind == pact_NodeKind_IntPattern)) {
        _match_0 = "IntPattern";
    } else if ((kind == pact_NodeKind_WildcardPattern)) {
        _match_0 = "WildcardPattern";
    } else if ((kind == pact_NodeKind_IdentPattern)) {
        _match_0 = "IdentPattern";
    } else if ((kind == pact_NodeKind_TuplePattern)) {
        _match_0 = "TuplePattern";
    } else if ((kind == pact_NodeKind_StringPattern)) {
        _match_0 = "StringPattern";
    } else if ((kind == pact_NodeKind_OrPattern)) {
        _match_0 = "OrPattern";
    } else if ((kind == pact_NodeKind_RangePattern)) {
        _match_0 = "RangePattern";
    } else if ((kind == pact_NodeKind_StructPattern)) {
        _match_0 = "StructPattern";
    } else if ((kind == pact_NodeKind_EnumPattern)) {
        _match_0 = "EnumPattern";
    } else if ((kind == pact_NodeKind_AsPattern)) {
        _match_0 = "AsPattern";
    } else if ((kind == pact_NodeKind_MatchArm)) {
        _match_0 = "MatchArm";
    } else if ((kind == pact_NodeKind_StructLitField)) {
        _match_0 = "StructLitField";
    } else if ((kind == pact_NodeKind_WithBlock)) {
        _match_0 = "WithBlock";
    } else if ((kind == pact_NodeKind_WithResource)) {
        _match_0 = "WithResource";
    } else if ((kind == pact_NodeKind_HandlerExpr)) {
        _match_0 = "HandlerExpr";
    } else if ((kind == pact_NodeKind_Annotation)) {
        _match_0 = "Annotation";
    } else if ((kind == pact_NodeKind_ModBlock)) {
        _match_0 = "ModBlock";
    } else if ((kind == pact_NodeKind_ImportStmt)) {
        _match_0 = "ImportStmt";
    } else if ((kind == pact_NodeKind_TypeAnn)) {
        _match_0 = "TypeAnn";
    } else if ((kind == pact_NodeKind_TypeParam)) {
        _match_0 = "TypeParam";
    } else if ((kind == pact_NodeKind_EffectDecl)) {
        _match_0 = "EffectDecl";
    } else {
        _match_0 = "Unknown";
    }
    return _match_0;
}

int64_t pact_new_node(int64_t kind) {
    const int64_t id = pact_list_len(np_kind);
    pact_list_push(np_kind, (void*)(intptr_t)kind);
    pact_list_push(np_int_val, (void*)(intptr_t)0);
    pact_list_push(np_str_val, (void*)"");
    pact_list_push(np_name, (void*)"");
    pact_list_push(np_op, (void*)"");
    pact_list_push(np_left, (void*)(intptr_t)(-1));
    pact_list_push(np_right, (void*)(intptr_t)(-1));
    pact_list_push(np_body, (void*)(intptr_t)(-1));
    pact_list_push(np_condition, (void*)(intptr_t)(-1));
    pact_list_push(np_then_body, (void*)(intptr_t)(-1));
    pact_list_push(np_else_body, (void*)(intptr_t)(-1));
    pact_list_push(np_scrutinee, (void*)(intptr_t)(-1));
    pact_list_push(np_pattern, (void*)(intptr_t)(-1));
    pact_list_push(np_guard, (void*)(intptr_t)(-1));
    pact_list_push(np_value, (void*)(intptr_t)(-1));
    pact_list_push(np_target, (void*)(intptr_t)(-1));
    pact_list_push(np_iterable, (void*)(intptr_t)(-1));
    pact_list_push(np_var_name, (void*)"");
    pact_list_push(np_is_mut, (void*)(intptr_t)0);
    pact_list_push(np_is_pub, (void*)(intptr_t)0);
    pact_list_push(np_inclusive, (void*)(intptr_t)0);
    pact_list_push(np_start, (void*)(intptr_t)(-1));
    pact_list_push(np_end, (void*)(intptr_t)(-1));
    pact_list_push(np_obj, (void*)(intptr_t)(-1));
    pact_list_push(np_method, (void*)"");
    pact_list_push(np_index, (void*)(intptr_t)(-1));
    pact_list_push(np_return_type, (void*)"");
    pact_list_push(np_type_name, (void*)"");
    pact_list_push(np_trait_name, (void*)"");
    pact_list_push(np_params, (void*)(intptr_t)(-1));
    pact_list_push(np_args, (void*)(intptr_t)(-1));
    pact_list_push(np_stmts, (void*)(intptr_t)(-1));
    pact_list_push(np_arms, (void*)(intptr_t)(-1));
    pact_list_push(np_fields, (void*)(intptr_t)(-1));
    pact_list_push(np_elements, (void*)(intptr_t)(-1));
    pact_list_push(np_methods, (void*)(intptr_t)(-1));
    pact_list_push(np_type_params, (void*)(intptr_t)(-1));
    pact_list_push(np_effects, (void*)(intptr_t)(-1));
    pact_list_push(np_captures, (void*)(intptr_t)(-1));
    pact_list_push(np_type_ann, (void*)(intptr_t)(-1));
    pact_list_push(np_handlers, (void*)(intptr_t)(-1));
    return id;
}

int64_t pact_new_sublist(void) {
    if (sl_open) {
        printf("%s\n", "FATAL: new_sublist() called while another sublist is open — collect items into a List first, then build the sublist after parsing completes");
    }
    sl_open = 1;
    const int64_t id = pact_list_len(sl_start);
    pact_list_push(sl_start, (void*)(intptr_t)pact_list_len(sl_items));
    pact_list_push(sl_len, (void*)(intptr_t)0);
    return id;
}

void pact_sublist_push(int64_t sl, int64_t node_id) {
    if ((!sl_open)) {
        printf("%s\n", "FATAL: sublist_push() called with no open sublist — call new_sublist() first");
    }
    pact_list_push(sl_items, (void*)(intptr_t)node_id);
}

void pact_finalize_sublist(int64_t sl) {
    if ((!sl_open)) {
        printf("%s\n", "FATAL: finalize_sublist() called with no open sublist — mismatched new_sublist/finalize_sublist calls");
    }
    const int64_t start = (int64_t)(intptr_t)pact_list_get(sl_start, sl);
    const int64_t length = (pact_list_len(sl_items) - start);
    pact_list_set(sl_len, sl, (void*)(intptr_t)length);
    sl_open = 0;
}

int64_t pact_sublist_get(int64_t sl, int64_t idx) {
    return (int64_t)(intptr_t)pact_list_get(sl_items, ((int64_t)(intptr_t)pact_list_get(sl_start, sl) + idx));
}

int64_t pact_sublist_length(int64_t sl) {
    return (int64_t)(intptr_t)pact_list_get(sl_len, sl);
}

int64_t pact_peek_kind(void) {
    return (int64_t)(intptr_t)pact_list_get(tok_kinds, pos);
}

const char* pact_peek_value(void) {
    return (const char*)pact_list_get(tok_values, pos);
}

int64_t pact_peek_line(void) {
    return (int64_t)(intptr_t)pact_list_get(tok_lines, pos);
}

int64_t pact_peek_col(void) {
    return (int64_t)(intptr_t)pact_list_get(tok_cols, pos);
}

int64_t pact_at(int64_t kind) {
    return (pact_peek_kind() == kind);
}

int64_t pact_advance(void) {
    const int64_t old = pos;
    pos = (pos + 1);
    return old;
}

const char* pact_advance_value(void) {
    const char* v = (const char*)pact_list_get(tok_values, pos);
    pos = (pos + 1);
    return v;
}

int64_t pact_expect(int64_t kind) {
    if ((pact_peek_kind() != kind)) {
        char _si_0[4096];
        snprintf(_si_0, 4096, "parse error at line %lld:%lld: expected token kind %lld, got %lld", (long long)pact_peek_line(), (long long)pact_peek_col(), (long long)kind, (long long)pact_peek_kind());
        printf("%s\n", strdup(_si_0));
    }
    return pact_advance();
}

const char* pact_expect_value(int64_t kind) {
    if ((pact_peek_kind() != kind)) {
        char _si_0[4096];
        snprintf(_si_0, 4096, "parse error at line %lld:%lld: expected token kind %lld, got %lld", (long long)pact_peek_line(), (long long)pact_peek_col(), (long long)kind, (long long)pact_peek_kind());
        printf("%s\n", strdup(_si_0));
    }
    return pact_advance_value();
}

void pact_skip_newlines(void) {
    while (pact_at(pact_TokenKind_Newline)) {
        pact_advance();
    }
}

void pact_maybe_newline(void) {
    if (pact_at(pact_TokenKind_Newline)) {
        pact_advance();
    }
}

int64_t pact_parse_import_stmt(void) {
    const char* path = pact_expect_value(pact_TokenKind_Ident);
    while (pact_at(pact_TokenKind_Dot)) {
        pact_advance();
        if (pact_at(pact_TokenKind_LBrace)) {
            break;
        }
        path = pact_str_concat(pact_str_concat(path, "."), pact_expect_value(pact_TokenKind_Ident));
    }
    const int64_t node = pact_new_node(pact_NodeKind_ImportStmt);
    pact_list_pop(np_str_val);
    pact_list_push(np_str_val, (void*)path);
    if (pact_at(pact_TokenKind_LBrace)) {
        pact_advance();
        pact_skip_newlines();
        const int64_t names_sl = pact_new_sublist();
        while (((!pact_at(pact_TokenKind_RBrace)) && (!pact_at(pact_TokenKind_EOF)))) {
            const int64_t name_node = pact_new_node(pact_NodeKind_Ident);
            const char* item_name = pact_expect_value(pact_TokenKind_Ident);
            pact_list_pop(np_name);
            pact_list_push(np_name, (void*)item_name);
            if (pact_at(pact_TokenKind_As)) {
                pact_advance();
                const char* alias = pact_expect_value(pact_TokenKind_Ident);
                pact_list_pop(np_str_val);
                pact_list_push(np_str_val, (void*)alias);
            }
            pact_sublist_push(names_sl, name_node);
            pact_skip_newlines();
            if (pact_at(pact_TokenKind_Comma)) {
                pact_advance();
                pact_skip_newlines();
            }
        }
        pact_expect(pact_TokenKind_RBrace);
        pact_finalize_sublist(names_sl);
        pact_list_set(np_args, node, (void*)(intptr_t)names_sl);
    }
    return node;
}

int64_t pact_parse_program(void) {
    pact_list* _l0 = pact_list_new();
    pact_list* fn_nodes = _l0;
    pact_list* _l1 = pact_list_new();
    pact_list* type_nodes = _l1;
    pact_list* _l2 = pact_list_new();
    pact_list* let_nodes = _l2;
    pact_list* _l3 = pact_list_new();
    pact_list* trait_nodes = _l3;
    pact_list* _l4 = pact_list_new();
    pact_list* impl_nodes = _l4;
    pact_list* _l5 = pact_list_new();
    pact_list* fn_pub = _l5;
    pact_list* _l6 = pact_list_new();
    pact_list* import_nodes = _l6;
    pact_list* _l7 = pact_list_new();
    pact_list* effect_decl_nodes = _l7;
    pact_skip_newlines();
    while ((!pact_at(pact_TokenKind_EOF))) {
        pact_skip_newlines();
        if (pact_at(pact_TokenKind_EOF)) {
            break;
        }
        if (pact_at(pact_TokenKind_Import)) {
            pact_advance();
            const int64_t imp = pact_parse_import_stmt();
            pact_list_push(import_nodes, (void*)(intptr_t)imp);
            pact_skip_newlines();
        } else if (pact_at(pact_TokenKind_Type)) {
            const int64_t td = pact_parse_type_def();
            pact_list_push(type_nodes, (void*)(intptr_t)td);
        } else {
            if (pact_at(pact_TokenKind_Trait)) {
                const int64_t tr = pact_parse_trait_def();
                pact_list_push(trait_nodes, (void*)(intptr_t)tr);
            } else if (pact_at(pact_TokenKind_Impl)) {
                const int64_t im = pact_parse_impl_block();
                pact_list_push(impl_nodes, (void*)(intptr_t)im);
            } else {
                if (pact_at(pact_TokenKind_Let)) {
                    const int64_t lb = pact_parse_let_binding();
                    pact_list_push(let_nodes, (void*)(intptr_t)lb);
                } else if (pact_at(pact_TokenKind_Pub)) {
                    pact_advance();
                    pact_skip_newlines();
                    if (pact_at(pact_TokenKind_Fn)) {
                        const int64_t f = pact_parse_fn_def();
                        pact_list_set(np_is_pub, f, (void*)(intptr_t)1);
                        pact_list_push(fn_nodes, (void*)(intptr_t)f);
                    } else if (pact_at(pact_TokenKind_Type)) {
                        const int64_t td = pact_parse_type_def();
                        pact_list_set(np_is_pub, td, (void*)(intptr_t)1);
                        pact_list_push(type_nodes, (void*)(intptr_t)td);
                    } else {
                        if (pact_at(pact_TokenKind_Trait)) {
                            const int64_t tr = pact_parse_trait_def();
                            pact_list_set(np_is_pub, tr, (void*)(intptr_t)1);
                            pact_list_push(trait_nodes, (void*)(intptr_t)tr);
                        } else if (pact_at(pact_TokenKind_Let)) {
                            const int64_t lb = pact_parse_let_binding();
                            pact_list_set(np_is_pub, lb, (void*)(intptr_t)1);
                            pact_list_push(let_nodes, (void*)(intptr_t)lb);
                        } else {
                            if (pact_at(pact_TokenKind_Effect)) {
                                const int64_t ed = pact_parse_effect_decl();
                                pact_list_set(np_is_pub, ed, (void*)(intptr_t)1);
                                pact_list_push(effect_decl_nodes, (void*)(intptr_t)ed);
                            } else {
                                printf("%s\n", "parse error: expected fn, type, trait, or effect after pub");
                                pact_advance();
                            }
                        }
                    }
                } else {
                    if (pact_at(pact_TokenKind_Effect)) {
                        const int64_t ed = pact_parse_effect_decl();
                        pact_list_push(effect_decl_nodes, (void*)(intptr_t)ed);
                    } else if (pact_at(pact_TokenKind_Fn)) {
                        const int64_t f = pact_parse_fn_def();
                        pact_list_push(fn_nodes, (void*)(intptr_t)f);
                    } else {
                        char _si_8[4096];
                        snprintf(_si_8, 4096, "parse error: unexpected token at top level: %lld", (long long)pact_peek_kind());
                        printf("%s\n", strdup(_si_8));
                        pact_advance();
                    }
                }
            }
        }
        pact_skip_newlines();
    }
    const int64_t fns = pact_new_sublist();
    int64_t i = 0;
    while ((i < pact_list_len(fn_nodes))) {
        pact_sublist_push(fns, (int64_t)(intptr_t)pact_list_get(fn_nodes, i));
        i = (i + 1);
    }
    pact_finalize_sublist(fns);
    const int64_t types = pact_new_sublist();
    i = 0;
    while ((i < pact_list_len(type_nodes))) {
        pact_sublist_push(types, (int64_t)(intptr_t)pact_list_get(type_nodes, i));
        i = (i + 1);
    }
    pact_finalize_sublist(types);
    const int64_t lets = pact_new_sublist();
    i = 0;
    while ((i < pact_list_len(let_nodes))) {
        pact_sublist_push(lets, (int64_t)(intptr_t)pact_list_get(let_nodes, i));
        i = (i + 1);
    }
    pact_finalize_sublist(lets);
    const int64_t traits = pact_new_sublist();
    i = 0;
    while ((i < pact_list_len(trait_nodes))) {
        pact_sublist_push(traits, (int64_t)(intptr_t)pact_list_get(trait_nodes, i));
        i = (i + 1);
    }
    pact_finalize_sublist(traits);
    const int64_t impls = pact_new_sublist();
    i = 0;
    while ((i < pact_list_len(impl_nodes))) {
        pact_sublist_push(impls, (int64_t)(intptr_t)pact_list_get(impl_nodes, i));
        i = (i + 1);
    }
    pact_finalize_sublist(impls);
    const int64_t imports = pact_new_sublist();
    i = 0;
    while ((i < pact_list_len(import_nodes))) {
        pact_sublist_push(imports, (int64_t)(intptr_t)pact_list_get(import_nodes, i));
        i = (i + 1);
    }
    pact_finalize_sublist(imports);
    int64_t effect_decls = (-1);
    if ((pact_list_len(effect_decl_nodes) > 0)) {
        effect_decls = pact_new_sublist();
        i = 0;
        while ((i < pact_list_len(effect_decl_nodes))) {
            pact_sublist_push(effect_decls, (int64_t)(intptr_t)pact_list_get(effect_decl_nodes, i));
            i = (i + 1);
        }
        pact_finalize_sublist(effect_decls);
    }
    const int64_t prog = pact_new_node(pact_NodeKind_Program);
    pact_list_pop(np_params);
    pact_list_push(np_params, (void*)(intptr_t)fns);
    pact_list_pop(np_fields);
    pact_list_push(np_fields, (void*)(intptr_t)types);
    pact_list_pop(np_stmts);
    pact_list_push(np_stmts, (void*)(intptr_t)lets);
    pact_list_pop(np_arms);
    pact_list_push(np_arms, (void*)(intptr_t)traits);
    pact_list_pop(np_methods);
    pact_list_push(np_methods, (void*)(intptr_t)impls);
    pact_list_pop(np_elements);
    pact_list_push(np_elements, (void*)(intptr_t)imports);
    pact_list_pop(np_args);
    pact_list_push(np_args, (void*)(intptr_t)effect_decls);
    return prog;
}

int64_t pact_parse_type_params(void) {
    if ((!pact_at(pact_TokenKind_LBracket))) {
        return (-1);
    }
    pact_advance();
    pact_list* _l0 = pact_list_new();
    pact_list* param_nodes = _l0;
    const char* pname = pact_expect_value(pact_TokenKind_Ident);
    int64_t bounds_sl = (-1);
    if (pact_at(pact_TokenKind_Colon)) {
        pact_advance();
        pact_list* _l1 = pact_list_new();
        pact_list* bound_nodes = _l1;
        pact_list_push(bound_nodes, (void*)(intptr_t)pact_parse_type_annotation());
        while (pact_at(pact_TokenKind_Plus)) {
            pact_advance();
            pact_skip_newlines();
            pact_list_push(bound_nodes, (void*)(intptr_t)pact_parse_type_annotation());
        }
        bounds_sl = pact_new_sublist();
        int64_t bi = 0;
        while ((bi < pact_list_len(bound_nodes))) {
            pact_sublist_push(bounds_sl, (int64_t)(intptr_t)pact_list_get(bound_nodes, bi));
            bi = (bi + 1);
        }
        pact_finalize_sublist(bounds_sl);
    }
    const int64_t tp = pact_new_node(pact_NodeKind_TypeParam);
    pact_list_pop(np_name);
    pact_list_push(np_name, (void*)pname);
    pact_list_pop(np_elements);
    pact_list_push(np_elements, (void*)(intptr_t)bounds_sl);
    pact_list_push(param_nodes, (void*)(intptr_t)tp);
    while (pact_at(pact_TokenKind_Comma)) {
        pact_advance();
        pact_skip_newlines();
        const char* pn2 = pact_expect_value(pact_TokenKind_Ident);
        int64_t bs2 = (-1);
        if (pact_at(pact_TokenKind_Colon)) {
            pact_advance();
            pact_list* _l2 = pact_list_new();
            pact_list* bn2 = _l2;
            pact_list_push(bn2, (void*)(intptr_t)pact_parse_type_annotation());
            while (pact_at(pact_TokenKind_Plus)) {
                pact_advance();
                pact_skip_newlines();
                pact_list_push(bn2, (void*)(intptr_t)pact_parse_type_annotation());
            }
            bs2 = pact_new_sublist();
            int64_t bi = 0;
            while ((bi < pact_list_len(bn2))) {
                pact_sublist_push(bs2, (int64_t)(intptr_t)pact_list_get(bn2, bi));
                bi = (bi + 1);
            }
            pact_finalize_sublist(bs2);
        }
        const int64_t tp2 = pact_new_node(pact_NodeKind_TypeParam);
        pact_list_pop(np_name);
        pact_list_push(np_name, (void*)pn2);
        pact_list_pop(np_elements);
        pact_list_push(np_elements, (void*)(intptr_t)bs2);
        pact_list_push(param_nodes, (void*)(intptr_t)tp2);
    }
    pact_expect(pact_TokenKind_RBracket);
    const int64_t sl = pact_new_sublist();
    int64_t i = 0;
    while ((i < pact_list_len(param_nodes))) {
        pact_sublist_push(sl, (int64_t)(intptr_t)pact_list_get(param_nodes, i));
        i = (i + 1);
    }
    pact_finalize_sublist(sl);
    return sl;
}

int64_t pact_parse_type_def(void) {
    pact_expect(pact_TokenKind_Type);
    const char* name = pact_expect_value(pact_TokenKind_Ident);
    const int64_t tparams = pact_parse_type_params();
    pact_skip_newlines();
    int64_t flds = (-1);
    if (pact_at(pact_TokenKind_LBrace)) {
        pact_expect(pact_TokenKind_LBrace);
        pact_skip_newlines();
        pact_list* _l0 = pact_list_new();
        pact_list* field_nodes = _l0;
        while ((!pact_at(pact_TokenKind_RBrace))) {
            const char* fname = pact_expect_value(pact_TokenKind_Ident);
            if (pact_at(pact_TokenKind_Colon)) {
                pact_advance();
                const int64_t type_ann = pact_parse_type_annotation();
                const int64_t tf = pact_new_node(pact_NodeKind_TypeField);
                pact_list_pop(np_name);
                pact_list_push(np_name, (void*)fname);
                pact_list_pop(np_value);
                pact_list_push(np_value, (void*)(intptr_t)type_ann);
                pact_list_push(field_nodes, (void*)(intptr_t)tf);
            } else {
                const int64_t tv = pact_new_node(pact_NodeKind_TypeVariant);
                pact_list_pop(np_name);
                pact_list_push(np_name, (void*)fname);
                pact_list_push(field_nodes, (void*)(intptr_t)tv);
            }
            if (pact_at(pact_TokenKind_Comma)) {
                pact_advance();
            }
            pact_skip_newlines();
        }
        pact_expect(pact_TokenKind_RBrace);
        flds = pact_new_sublist();
        int64_t i = 0;
        while ((i < pact_list_len(field_nodes))) {
            pact_sublist_push(flds, (int64_t)(intptr_t)pact_list_get(field_nodes, i));
            i = (i + 1);
        }
        pact_finalize_sublist(flds);
    }
    const int64_t td = pact_new_node(pact_NodeKind_TypeDef);
    pact_list_pop(np_name);
    pact_list_push(np_name, (void*)name);
    pact_list_pop(np_fields);
    pact_list_push(np_fields, (void*)(intptr_t)flds);
    pact_list_pop(np_type_params);
    pact_list_push(np_type_params, (void*)(intptr_t)tparams);
    return td;
}

int64_t pact_parse_type_annotation(void) {
    if (pact_at(pact_TokenKind_Fn)) {
        pact_advance();
        pact_expect(pact_TokenKind_LParen);
        pact_list* _l0 = pact_list_new();
        pact_list* type_nodes = _l0;
        if ((!pact_at(pact_TokenKind_RParen))) {
            pact_list_push(type_nodes, (void*)(intptr_t)pact_parse_type_annotation());
            while (pact_at(pact_TokenKind_Comma)) {
                pact_advance();
                pact_skip_newlines();
                pact_list_push(type_nodes, (void*)(intptr_t)pact_parse_type_annotation());
            }
        }
        pact_expect(pact_TokenKind_RParen);
        const char* ret_name = "Void";
        if (pact_at(pact_TokenKind_Arrow)) {
            pact_advance();
            const int64_t rt = pact_parse_type_annotation();
            ret_name = (const char*)pact_list_get(np_name, rt);
        }
        int64_t elems = (-1);
        if ((pact_list_len(type_nodes) > 0)) {
            elems = pact_new_sublist();
            int64_t i = 0;
            while ((i < pact_list_len(type_nodes))) {
                pact_sublist_push(elems, (int64_t)(intptr_t)pact_list_get(type_nodes, i));
                i = (i + 1);
            }
            pact_finalize_sublist(elems);
        }
        const int64_t ta = pact_new_node(pact_NodeKind_TypeAnn);
        pact_list_pop(np_name);
        pact_list_push(np_name, (void*)"Fn");
        pact_list_pop(np_elements);
        pact_list_push(np_elements, (void*)(intptr_t)elems);
        pact_list_pop(np_return_type);
        pact_list_push(np_return_type, (void*)ret_name);
        return ta;
    }
    const char* name = pact_expect_value(pact_TokenKind_Ident);
    int64_t elems = (-1);
    if (pact_at(pact_TokenKind_LBracket)) {
        pact_advance();
        pact_list* _l1 = pact_list_new();
        pact_list* type_nodes = _l1;
        pact_list_push(type_nodes, (void*)(intptr_t)pact_parse_type_annotation());
        while (pact_at(pact_TokenKind_Comma)) {
            pact_advance();
            pact_skip_newlines();
            pact_list_push(type_nodes, (void*)(intptr_t)pact_parse_type_annotation());
        }
        pact_expect(pact_TokenKind_RBracket);
        elems = pact_new_sublist();
        int64_t i = 0;
        while ((i < pact_list_len(type_nodes))) {
            pact_sublist_push(elems, (int64_t)(intptr_t)pact_list_get(type_nodes, i));
            i = (i + 1);
        }
        pact_finalize_sublist(elems);
    }
    const int64_t ta = pact_new_node(pact_NodeKind_TypeAnn);
    pact_list_pop(np_name);
    pact_list_push(np_name, (void*)name);
    pact_list_pop(np_elements);
    pact_list_push(np_elements, (void*)(intptr_t)elems);
    return ta;
}

int64_t pact_parse_effect_decl(void) {
    pact_expect(pact_TokenKind_Effect);
    const char* name = pact_expect_value(pact_TokenKind_Ident);
    pact_skip_newlines();
    if (pact_at(pact_TokenKind_LBrace)) {
        pact_advance();
        pact_skip_newlines();
        pact_list* _l0 = pact_list_new();
        pact_list* children = _l0;
        while (((!pact_at(pact_TokenKind_RBrace)) && (!pact_at(pact_TokenKind_EOF)))) {
            pact_expect(pact_TokenKind_Effect);
            const char* child_name = pact_expect_value(pact_TokenKind_Ident);
            const int64_t child = pact_new_node(pact_NodeKind_EffectDecl);
            pact_list_pop(np_name);
            pact_list_push(np_name, (void*)child_name);
            pact_list_push(children, (void*)(intptr_t)child);
            pact_skip_newlines();
            if (pact_at(pact_TokenKind_Comma)) {
                pact_advance();
            }
            pact_skip_newlines();
        }
        pact_expect(pact_TokenKind_RBrace);
        const int64_t children_sl = pact_new_sublist();
        int64_t i = 0;
        while ((i < pact_list_len(children))) {
            pact_sublist_push(children_sl, (int64_t)(intptr_t)pact_list_get(children, i));
            i = (i + 1);
        }
        pact_finalize_sublist(children_sl);
        const int64_t nd = pact_new_node(pact_NodeKind_EffectDecl);
        pact_list_pop(np_name);
        pact_list_push(np_name, (void*)name);
        pact_list_pop(np_elements);
        pact_list_push(np_elements, (void*)(intptr_t)children_sl);
        return nd;
    }
    const int64_t nd = pact_new_node(pact_NodeKind_EffectDecl);
    pact_list_pop(np_name);
    pact_list_push(np_name, (void*)name);
    return nd;
}

int64_t pact_parse_fn_def(void) {
    pact_expect(pact_TokenKind_Fn);
    const char* name = pact_expect_value(pact_TokenKind_Ident);
    const int64_t tparams = pact_parse_type_params();
    pact_expect(pact_TokenKind_LParen);
    pact_list* _l0 = pact_list_new();
    pact_list* param_nodes = _l0;
    if ((!pact_at(pact_TokenKind_RParen))) {
        pact_list_push(param_nodes, (void*)(intptr_t)pact_parse_param());
        while (pact_at(pact_TokenKind_Comma)) {
            pact_advance();
            if (pact_at(pact_TokenKind_RParen)) {
                break;
            }
            pact_list_push(param_nodes, (void*)(intptr_t)pact_parse_param());
        }
    }
    pact_expect(pact_TokenKind_RParen);
    const char* ret_type = "";
    const char* ret_str = "";
    if (pact_at(pact_TokenKind_Arrow)) {
        pact_advance();
        const int64_t rt = pact_parse_type_annotation();
        ret_str = (const char*)pact_list_get(np_name, rt);
    }
    pact_list* _l1 = pact_list_new();
    pact_list* effect_nodes = _l1;
    if (pact_at(pact_TokenKind_Bang)) {
        pact_advance();
        const char* eff_name = pact_expect_value(pact_TokenKind_Ident);
        if (pact_at(pact_TokenKind_Dot)) {
            pact_advance();
            eff_name = pact_str_concat(pact_str_concat(eff_name, "."), pact_expect_value(pact_TokenKind_Ident));
        }
        const int64_t eff = pact_new_node(pact_NodeKind_Ident);
        pact_list_pop(np_name);
        pact_list_push(np_name, (void*)eff_name);
        pact_list_push(effect_nodes, (void*)(intptr_t)eff);
        while (pact_at(pact_TokenKind_Comma)) {
            pact_advance();
            pact_skip_newlines();
            const char* eff_name2 = pact_expect_value(pact_TokenKind_Ident);
            if (pact_at(pact_TokenKind_Dot)) {
                pact_advance();
                eff_name2 = pact_str_concat(pact_str_concat(eff_name2, "."), pact_expect_value(pact_TokenKind_Ident));
            }
            const int64_t eff2 = pact_new_node(pact_NodeKind_Ident);
            pact_list_pop(np_name);
            pact_list_push(np_name, (void*)eff_name2);
            pact_list_push(effect_nodes, (void*)(intptr_t)eff2);
        }
    }
    pact_skip_newlines();
    const int64_t body = (-1);
    int64_t body_id = (-1);
    if (pact_at(pact_TokenKind_LBrace)) {
        body_id = pact_parse_block();
    }
    const int64_t params = pact_new_sublist();
    int64_t pi = 0;
    while ((pi < pact_list_len(param_nodes))) {
        pact_sublist_push(params, (int64_t)(intptr_t)pact_list_get(param_nodes, pi));
        pi = (pi + 1);
    }
    pact_finalize_sublist(params);
    int64_t effects_sl = (-1);
    if ((pact_list_len(effect_nodes) > 0)) {
        effects_sl = pact_new_sublist();
        int64_t ei = 0;
        while ((ei < pact_list_len(effect_nodes))) {
            pact_sublist_push(effects_sl, (int64_t)(intptr_t)pact_list_get(effect_nodes, ei));
            ei = (ei + 1);
        }
        pact_finalize_sublist(effects_sl);
    }
    const int64_t nd = pact_new_node(pact_NodeKind_FnDef);
    pact_list_pop(np_name);
    pact_list_push(np_name, (void*)name);
    pact_list_pop(np_params);
    pact_list_push(np_params, (void*)(intptr_t)params);
    pact_list_pop(np_body);
    pact_list_push(np_body, (void*)(intptr_t)body_id);
    pact_list_pop(np_return_type);
    pact_list_push(np_return_type, (void*)ret_str);
    pact_list_pop(np_type_params);
    pact_list_push(np_type_params, (void*)(intptr_t)tparams);
    pact_list_pop(np_effects);
    pact_list_push(np_effects, (void*)(intptr_t)effects_sl);
    return nd;
}

int64_t pact_parse_param(void) {
    int64_t is_mut = 0;
    if (pact_at(pact_TokenKind_Mut)) {
        is_mut = 1;
        pact_advance();
    }
    const char* name = "";
    if (pact_at(pact_TokenKind_Self)) {
        name = "self";
        pact_advance();
    } else {
        name = pact_expect_value(pact_TokenKind_Ident);
    }
    const char* type_str = "";
    int64_t type_ann_id = (-1);
    if (pact_at(pact_TokenKind_Colon)) {
        pact_advance();
        const int64_t ta = pact_parse_type_annotation();
        type_str = (const char*)pact_list_get(np_name, ta);
        type_ann_id = ta;
    }
    const int64_t nd = pact_new_node(pact_NodeKind_Param);
    pact_list_pop(np_name);
    pact_list_push(np_name, (void*)name);
    pact_list_pop(np_type_name);
    pact_list_push(np_type_name, (void*)type_str);
    pact_list_pop(np_is_mut);
    pact_list_push(np_is_mut, (void*)(intptr_t)is_mut);
    pact_list_set(np_type_ann, nd, (void*)(intptr_t)type_ann_id);
    return nd;
}

int64_t pact_parse_closure(void) {
    pact_expect(pact_TokenKind_Fn);
    pact_expect(pact_TokenKind_LParen);
    pact_list* _l0 = pact_list_new();
    pact_list* param_nodes = _l0;
    if ((!pact_at(pact_TokenKind_RParen))) {
        pact_list_push(param_nodes, (void*)(intptr_t)pact_parse_param());
        while (pact_at(pact_TokenKind_Comma)) {
            pact_advance();
            if (pact_at(pact_TokenKind_RParen)) {
                break;
            }
            pact_list_push(param_nodes, (void*)(intptr_t)pact_parse_param());
        }
    }
    pact_expect(pact_TokenKind_RParen);
    const char* ret_str = "";
    if (pact_at(pact_TokenKind_Arrow)) {
        pact_advance();
        const int64_t rt = pact_parse_type_annotation();
        ret_str = (const char*)pact_list_get(np_name, rt);
    }
    pact_skip_newlines();
    const int64_t body_id = pact_parse_block();
    const int64_t params = pact_new_sublist();
    int64_t pi = 0;
    while ((pi < pact_list_len(param_nodes))) {
        pact_sublist_push(params, (int64_t)(intptr_t)pact_list_get(param_nodes, pi));
        pi = (pi + 1);
    }
    pact_finalize_sublist(params);
    const int64_t nd = pact_new_node(pact_NodeKind_Closure);
    pact_list_pop(np_params);
    pact_list_push(np_params, (void*)(intptr_t)params);
    pact_list_pop(np_body);
    pact_list_push(np_body, (void*)(intptr_t)body_id);
    pact_list_pop(np_return_type);
    pact_list_push(np_return_type, (void*)ret_str);
    return nd;
}

int64_t pact_parse_trait_def(void) {
    pact_expect(pact_TokenKind_Trait);
    const char* name = pact_expect_value(pact_TokenKind_Ident);
    pact_list* _l0 = pact_list_new();
    pact_list* trait_type_arg_nodes = _l0;
    if (pact_at(pact_TokenKind_LBracket)) {
        pact_advance();
        pact_list_push(trait_type_arg_nodes, (void*)(intptr_t)pact_parse_type_annotation());
        while (pact_at(pact_TokenKind_Comma)) {
            pact_advance();
            pact_skip_newlines();
            pact_list_push(trait_type_arg_nodes, (void*)(intptr_t)pact_parse_type_annotation());
        }
        pact_expect(pact_TokenKind_RBracket);
    }
    pact_skip_newlines();
    pact_expect(pact_TokenKind_LBrace);
    pact_skip_newlines();
    pact_list* _l1 = pact_list_new();
    pact_list* method_nodes = _l1;
    while ((!pact_at(pact_TokenKind_RBrace))) {
        if (pact_at(pact_TokenKind_Fn)) {
            pact_list_push(method_nodes, (void*)(intptr_t)pact_parse_fn_def());
        } else {
            pact_advance();
        }
        pact_skip_newlines();
    }
    pact_expect(pact_TokenKind_RBrace);
    int64_t trait_type_args = (-1);
    if ((pact_list_len(trait_type_arg_nodes) > 0)) {
        trait_type_args = pact_new_sublist();
        int64_t ti = 0;
        while ((ti < pact_list_len(trait_type_arg_nodes))) {
            pact_sublist_push(trait_type_args, (int64_t)(intptr_t)pact_list_get(trait_type_arg_nodes, ti));
            ti = (ti + 1);
        }
        pact_finalize_sublist(trait_type_args);
    }
    const int64_t methods = pact_new_sublist();
    int64_t i = 0;
    while ((i < pact_list_len(method_nodes))) {
        pact_sublist_push(methods, (int64_t)(intptr_t)pact_list_get(method_nodes, i));
        i = (i + 1);
    }
    pact_finalize_sublist(methods);
    const int64_t nd = pact_new_node(pact_NodeKind_TraitDef);
    pact_list_pop(np_name);
    pact_list_push(np_name, (void*)name);
    pact_list_pop(np_methods);
    pact_list_push(np_methods, (void*)(intptr_t)methods);
    pact_list_pop(np_type_params);
    pact_list_push(np_type_params, (void*)(intptr_t)trait_type_args);
    return nd;
}

int64_t pact_parse_impl_block(void) {
    pact_expect(pact_TokenKind_Impl);
    const char* trait_name = pact_expect_value(pact_TokenKind_Ident);
    pact_list* _l0 = pact_list_new();
    pact_list* trait_type_arg_nodes = _l0;
    if (pact_at(pact_TokenKind_LBracket)) {
        pact_advance();
        pact_list_push(trait_type_arg_nodes, (void*)(intptr_t)pact_parse_type_annotation());
        while (pact_at(pact_TokenKind_Comma)) {
            pact_advance();
            pact_skip_newlines();
            pact_list_push(trait_type_arg_nodes, (void*)(intptr_t)pact_parse_type_annotation());
        }
        pact_expect(pact_TokenKind_RBracket);
    }
    pact_skip_newlines();
    const char* type_name = "";
    if (pact_at(pact_TokenKind_For)) {
        pact_advance();
        pact_skip_newlines();
        type_name = pact_expect_value(pact_TokenKind_Ident);
    }
    pact_skip_newlines();
    pact_expect(pact_TokenKind_LBrace);
    pact_skip_newlines();
    pact_list* _l1 = pact_list_new();
    pact_list* method_nodes = _l1;
    while ((!pact_at(pact_TokenKind_RBrace))) {
        if (pact_at(pact_TokenKind_Fn)) {
            pact_list_push(method_nodes, (void*)(intptr_t)pact_parse_fn_def());
        } else {
            pact_advance();
        }
        pact_skip_newlines();
    }
    pact_expect(pact_TokenKind_RBrace);
    int64_t trait_type_args = (-1);
    if ((pact_list_len(trait_type_arg_nodes) > 0)) {
        trait_type_args = pact_new_sublist();
        int64_t ti = 0;
        while ((ti < pact_list_len(trait_type_arg_nodes))) {
            pact_sublist_push(trait_type_args, (int64_t)(intptr_t)pact_list_get(trait_type_arg_nodes, ti));
            ti = (ti + 1);
        }
        pact_finalize_sublist(trait_type_args);
    }
    const int64_t methods = pact_new_sublist();
    int64_t i = 0;
    while ((i < pact_list_len(method_nodes))) {
        pact_sublist_push(methods, (int64_t)(intptr_t)pact_list_get(method_nodes, i));
        i = (i + 1);
    }
    pact_finalize_sublist(methods);
    const int64_t nd = pact_new_node(pact_NodeKind_ImplBlock);
    pact_list_pop(np_trait_name);
    pact_list_push(np_trait_name, (void*)trait_name);
    pact_list_pop(np_name);
    pact_list_push(np_name, (void*)type_name);
    pact_list_pop(np_methods);
    pact_list_push(np_methods, (void*)(intptr_t)methods);
    pact_list_pop(np_type_params);
    pact_list_push(np_type_params, (void*)(intptr_t)trait_type_args);
    return nd;
}

int64_t pact_parse_handler_expr(void) {
    pact_expect(pact_TokenKind_Handler);
    const char* effect_name = pact_expect_value(pact_TokenKind_Ident);
    const char* full_name = effect_name;
    if (pact_at(pact_TokenKind_Dot)) {
        pact_advance();
        const char* child = pact_expect_value(pact_TokenKind_Ident);
        full_name = pact_str_concat(pact_str_concat(full_name, "."), child);
    }
    pact_skip_newlines();
    pact_expect(pact_TokenKind_LBrace);
    pact_skip_newlines();
    pact_list* _l0 = pact_list_new();
    pact_list* method_nodes = _l0;
    while (((!pact_at(pact_TokenKind_RBrace)) && (!pact_at(pact_TokenKind_EOF)))) {
        if (pact_at(pact_TokenKind_Fn)) {
            pact_list_push(method_nodes, (void*)(intptr_t)pact_parse_fn_def());
        } else {
            pact_advance();
        }
        pact_skip_newlines();
    }
    pact_expect(pact_TokenKind_RBrace);
    const int64_t methods = pact_new_sublist();
    int64_t i = 0;
    while ((i < pact_list_len(method_nodes))) {
        pact_sublist_push(methods, (int64_t)(intptr_t)pact_list_get(method_nodes, i));
        i = (i + 1);
    }
    pact_finalize_sublist(methods);
    const int64_t nd = pact_new_node(pact_NodeKind_HandlerExpr);
    pact_list_pop(np_name);
    pact_list_push(np_name, (void*)full_name);
    pact_list_pop(np_methods);
    pact_list_push(np_methods, (void*)(intptr_t)methods);
    return nd;
}

int64_t pact_parse_with_block(void) {
    pact_expect(pact_TokenKind_With);
    pact_list* _l0 = pact_list_new();
    pact_list* handler_nodes = _l0;
    const int64_t expr0 = pact_parse_expr();
    if (pact_at(pact_TokenKind_As)) {
        pact_advance();
        const char* binding = pact_expect_value(pact_TokenKind_Ident);
        const int64_t wr = pact_new_node(pact_NodeKind_WithResource);
        pact_list_set(np_value, wr, (void*)(intptr_t)expr0);
        pact_list_set(np_name, wr, (void*)binding);
        pact_list_push(handler_nodes, (void*)(intptr_t)wr);
    } else {
        pact_list_push(handler_nodes, (void*)(intptr_t)expr0);
    }
    while (pact_at(pact_TokenKind_Comma)) {
        pact_advance();
        pact_skip_newlines();
        const int64_t expr_n = pact_parse_expr();
        if (pact_at(pact_TokenKind_As)) {
            pact_advance();
            const char* binding_n = pact_expect_value(pact_TokenKind_Ident);
            const int64_t wr_n = pact_new_node(pact_NodeKind_WithResource);
            pact_list_set(np_value, wr_n, (void*)(intptr_t)expr_n);
            pact_list_set(np_name, wr_n, (void*)binding_n);
            pact_list_push(handler_nodes, (void*)(intptr_t)wr_n);
        } else {
            pact_list_push(handler_nodes, (void*)(intptr_t)expr_n);
        }
    }
    pact_skip_newlines();
    const int64_t body = pact_parse_block();
    const int64_t handlers_sl = pact_new_sublist();
    int64_t i = 0;
    while ((i < pact_list_len(handler_nodes))) {
        pact_sublist_push(handlers_sl, (int64_t)(intptr_t)pact_list_get(handler_nodes, i));
        i = (i + 1);
    }
    pact_finalize_sublist(handlers_sl);
    const int64_t nd = pact_new_node(pact_NodeKind_WithBlock);
    pact_list_set(np_handlers, nd, (void*)(intptr_t)handlers_sl);
    pact_list_set(np_body, nd, (void*)(intptr_t)body);
    return nd;
}

int64_t pact_parse_block(void) {
    pact_expect(pact_TokenKind_LBrace);
    pact_skip_newlines();
    pact_list* _l0 = pact_list_new();
    pact_list* stmt_nodes = _l0;
    while ((!pact_at(pact_TokenKind_RBrace))) {
        pact_list_push(stmt_nodes, (void*)(intptr_t)pact_parse_stmt());
        pact_skip_newlines();
    }
    pact_expect(pact_TokenKind_RBrace);
    const int64_t stmts = pact_new_sublist();
    int64_t i = 0;
    while ((i < pact_list_len(stmt_nodes))) {
        pact_sublist_push(stmts, (int64_t)(intptr_t)pact_list_get(stmt_nodes, i));
        i = (i + 1);
    }
    pact_finalize_sublist(stmts);
    const int64_t nd = pact_new_node(pact_NodeKind_Block);
    pact_list_pop(np_stmts);
    pact_list_push(np_stmts, (void*)(intptr_t)stmts);
    return nd;
}

int64_t pact_parse_stmt(void) {
    if (pact_at(pact_TokenKind_While)) {
        return pact_parse_while_loop();
    }
    if (pact_at(pact_TokenKind_Loop)) {
        return pact_parse_loop_expr();
    }
    if (pact_at(pact_TokenKind_Break)) {
        pact_advance();
        pact_maybe_newline();
        return pact_new_node(pact_NodeKind_Break);
    }
    if (pact_at(pact_TokenKind_Continue)) {
        pact_advance();
        pact_maybe_newline();
        return pact_new_node(pact_NodeKind_Continue);
    }
    if (pact_at(pact_TokenKind_Let)) {
        return pact_parse_let_binding();
    }
    if (pact_at(pact_TokenKind_For)) {
        return pact_parse_for_in();
    }
    if (pact_at(pact_TokenKind_Return)) {
        return pact_parse_return_stmt();
    }
    if (pact_at(pact_TokenKind_If)) {
        const int64_t nd = pact_parse_if_expr();
        pact_maybe_newline();
        return nd;
    }
    if (pact_at(pact_TokenKind_With)) {
        const int64_t nd = pact_parse_with_block();
        pact_maybe_newline();
        return nd;
    }
    const int64_t expr = pact_parse_expr();
    if (pact_at(pact_TokenKind_Equals)) {
        pact_advance();
        pact_skip_newlines();
        const int64_t val = pact_parse_expr();
        pact_maybe_newline();
        const int64_t nd = pact_new_node(pact_NodeKind_Assignment);
        pact_list_pop(np_target);
        pact_list_push(np_target, (void*)(intptr_t)expr);
        pact_list_pop(np_value);
        pact_list_push(np_value, (void*)(intptr_t)val);
        return nd;
    }
    if ((((pact_at(pact_TokenKind_PlusEq) || pact_at(pact_TokenKind_MinusEq)) || pact_at(pact_TokenKind_StarEq)) || pact_at(pact_TokenKind_SlashEq))) {
        const int64_t op_kind = pact_peek_kind();
        pact_advance();
        pact_skip_newlines();
        const int64_t val = pact_parse_expr();
        pact_maybe_newline();
        const char* op_str = "+";
        if ((op_kind == pact_TokenKind_MinusEq)) {
            op_str = "-";
        } else if ((op_kind == pact_TokenKind_StarEq)) {
            op_str = "*";
        } else {
            if ((op_kind == pact_TokenKind_SlashEq)) {
                op_str = "/";
            }
        }
        const int64_t nd = pact_new_node(pact_NodeKind_CompoundAssign);
        pact_list_pop(np_op);
        pact_list_push(np_op, (void*)op_str);
        pact_list_pop(np_target);
        pact_list_push(np_target, (void*)(intptr_t)expr);
        pact_list_pop(np_value);
        pact_list_push(np_value, (void*)(intptr_t)val);
        return nd;
    }
    pact_maybe_newline();
    const int64_t nd = pact_new_node(pact_NodeKind_ExprStmt);
    pact_list_pop(np_value);
    pact_list_push(np_value, (void*)(intptr_t)expr);
    return nd;
}

int64_t pact_parse_let_binding(void) {
    pact_expect(pact_TokenKind_Let);
    int64_t is_mut = 0;
    if (pact_at(pact_TokenKind_Mut)) {
        is_mut = 1;
        pact_advance();
    }
    const char* name = pact_expect_value(pact_TokenKind_Ident);
    int64_t type_ann = (-1);
    if (pact_at(pact_TokenKind_Colon)) {
        pact_advance();
        type_ann = pact_parse_type_annotation();
    }
    pact_expect(pact_TokenKind_Equals);
    pact_skip_newlines();
    const int64_t val = pact_parse_expr();
    pact_maybe_newline();
    const int64_t nd = pact_new_node(pact_NodeKind_LetBinding);
    pact_list_pop(np_name);
    pact_list_push(np_name, (void*)name);
    pact_list_pop(np_value);
    pact_list_push(np_value, (void*)(intptr_t)val);
    pact_list_pop(np_is_mut);
    pact_list_push(np_is_mut, (void*)(intptr_t)is_mut);
    pact_list_pop(np_target);
    pact_list_push(np_target, (void*)(intptr_t)type_ann);
    return nd;
}

int64_t pact_parse_return_stmt(void) {
    pact_expect(pact_TokenKind_Return);
    if (((pact_at(pact_TokenKind_Newline) || pact_at(pact_TokenKind_RBrace)) || pact_at(pact_TokenKind_EOF))) {
        pact_maybe_newline();
        const int64_t nd = pact_new_node(pact_NodeKind_Return);
        return nd;
    }
    const int64_t val = pact_parse_expr();
    pact_maybe_newline();
    const int64_t nd = pact_new_node(pact_NodeKind_Return);
    pact_list_pop(np_value);
    pact_list_push(np_value, (void*)(intptr_t)val);
    return nd;
}

int64_t pact_parse_if_expr(void) {
    pact_expect(pact_TokenKind_If);
    const int64_t cond = pact_parse_expr();
    pact_skip_newlines();
    const int64_t then_b = pact_parse_block();
    int64_t else_b = (-1);
    pact_skip_newlines();
    if (pact_at(pact_TokenKind_Else)) {
        pact_advance();
        pact_skip_newlines();
        if (pact_at(pact_TokenKind_If)) {
            const int64_t inner = pact_parse_if_expr();
            const int64_t stmts = pact_new_sublist();
            pact_sublist_push(stmts, inner);
            pact_finalize_sublist(stmts);
            const int64_t blk = pact_new_node(pact_NodeKind_Block);
            pact_list_pop(np_stmts);
            pact_list_push(np_stmts, (void*)(intptr_t)stmts);
            else_b = blk;
        } else {
            else_b = pact_parse_block();
        }
    }
    const int64_t nd = pact_new_node(pact_NodeKind_IfExpr);
    pact_list_pop(np_condition);
    pact_list_push(np_condition, (void*)(intptr_t)cond);
    pact_list_pop(np_then_body);
    pact_list_push(np_then_body, (void*)(intptr_t)then_b);
    pact_list_pop(np_else_body);
    pact_list_push(np_else_body, (void*)(intptr_t)else_b);
    return nd;
}

int64_t pact_parse_while_loop(void) {
    pact_expect(pact_TokenKind_While);
    const int64_t cond = pact_parse_expr();
    pact_skip_newlines();
    const int64_t body = pact_parse_block();
    const int64_t nd = pact_new_node(pact_NodeKind_WhileLoop);
    pact_list_pop(np_condition);
    pact_list_push(np_condition, (void*)(intptr_t)cond);
    pact_list_pop(np_body);
    pact_list_push(np_body, (void*)(intptr_t)body);
    return nd;
}

int64_t pact_parse_loop_expr(void) {
    pact_expect(pact_TokenKind_Loop);
    pact_skip_newlines();
    const int64_t body = pact_parse_block();
    const int64_t nd = pact_new_node(pact_NodeKind_LoopExpr);
    pact_list_pop(np_body);
    pact_list_push(np_body, (void*)(intptr_t)body);
    return nd;
}

int64_t pact_parse_for_in(void) {
    pact_expect(pact_TokenKind_For);
    const char* var = "";
    int64_t pat = (-1);
    if (pact_at(pact_TokenKind_LParen)) {
        pat = pact_parse_pattern();
        var = "_tuple";
    } else {
        var = pact_expect_value(pact_TokenKind_Ident);
    }
    pact_expect(pact_TokenKind_In);
    const int64_t iter = pact_parse_expr();
    pact_skip_newlines();
    const int64_t body = pact_parse_block();
    const int64_t nd = pact_new_node(pact_NodeKind_ForIn);
    pact_list_pop(np_var_name);
    pact_list_push(np_var_name, (void*)var);
    pact_list_pop(np_iterable);
    pact_list_push(np_iterable, (void*)(intptr_t)iter);
    pact_list_pop(np_body);
    pact_list_push(np_body, (void*)(intptr_t)body);
    if ((pat != (-1))) {
        pact_list_pop(np_elements);
        pact_list_push(np_elements, (void*)(intptr_t)pat);
    }
    return nd;
}

int64_t pact_parse_expr(void) {
    return pact_parse_nullcoalesce();
}

int64_t pact_parse_nullcoalesce(void) {
    int64_t left = pact_parse_or();
    while (pact_at(pact_TokenKind_DoubleQuestion)) {
        pact_advance();
        pact_skip_newlines();
        const int64_t right = pact_parse_or();
        const int64_t nd = pact_new_node(pact_NodeKind_BinOp);
        pact_list_pop(np_op);
        pact_list_push(np_op, (void*)"??");
        pact_list_pop(np_left);
        pact_list_push(np_left, (void*)(intptr_t)left);
        pact_list_pop(np_right);
        pact_list_push(np_right, (void*)(intptr_t)right);
        left = nd;
    }
    return left;
}

int64_t pact_parse_or(void) {
    int64_t left = pact_parse_and();
    while (pact_at(pact_TokenKind_Or)) {
        pact_advance();
        pact_skip_newlines();
        const int64_t right = pact_parse_and();
        const int64_t nd = pact_new_node(pact_NodeKind_BinOp);
        pact_list_pop(np_op);
        pact_list_push(np_op, (void*)"||");
        pact_list_pop(np_left);
        pact_list_push(np_left, (void*)(intptr_t)left);
        pact_list_pop(np_right);
        pact_list_push(np_right, (void*)(intptr_t)right);
        left = nd;
    }
    return left;
}

int64_t pact_parse_and(void) {
    int64_t left = pact_parse_equality();
    while (pact_at(pact_TokenKind_And)) {
        pact_advance();
        pact_skip_newlines();
        const int64_t right = pact_parse_equality();
        const int64_t nd = pact_new_node(pact_NodeKind_BinOp);
        pact_list_pop(np_op);
        pact_list_push(np_op, (void*)"&&");
        pact_list_pop(np_left);
        pact_list_push(np_left, (void*)(intptr_t)left);
        pact_list_pop(np_right);
        pact_list_push(np_right, (void*)(intptr_t)right);
        left = nd;
    }
    return left;
}

int64_t pact_parse_equality(void) {
    int64_t left = pact_parse_comparison();
    while ((pact_at(pact_TokenKind_EqEq) || pact_at(pact_TokenKind_NotEq))) {
        const char* op = pact_advance_value();
        pact_skip_newlines();
        const int64_t right = pact_parse_comparison();
        const int64_t nd = pact_new_node(pact_NodeKind_BinOp);
        pact_list_pop(np_op);
        pact_list_push(np_op, (void*)op);
        pact_list_pop(np_left);
        pact_list_push(np_left, (void*)(intptr_t)left);
        pact_list_pop(np_right);
        pact_list_push(np_right, (void*)(intptr_t)right);
        left = nd;
    }
    return left;
}

int64_t pact_parse_comparison(void) {
    int64_t left = pact_parse_additive();
    while ((((pact_at(pact_TokenKind_Less) || pact_at(pact_TokenKind_Greater)) || pact_at(pact_TokenKind_LessEq)) || pact_at(pact_TokenKind_GreaterEq))) {
        const char* op = pact_advance_value();
        pact_skip_newlines();
        const int64_t right = pact_parse_additive();
        const int64_t nd = pact_new_node(pact_NodeKind_BinOp);
        pact_list_pop(np_op);
        pact_list_push(np_op, (void*)op);
        pact_list_pop(np_left);
        pact_list_push(np_left, (void*)(intptr_t)left);
        pact_list_pop(np_right);
        pact_list_push(np_right, (void*)(intptr_t)right);
        left = nd;
    }
    return left;
}

int64_t pact_parse_additive(void) {
    int64_t left = pact_parse_multiplicative();
    while ((pact_at(pact_TokenKind_Plus) || pact_at(pact_TokenKind_Minus))) {
        const char* op = pact_advance_value();
        pact_skip_newlines();
        const int64_t right = pact_parse_multiplicative();
        const int64_t nd = pact_new_node(pact_NodeKind_BinOp);
        pact_list_pop(np_op);
        pact_list_push(np_op, (void*)op);
        pact_list_pop(np_left);
        pact_list_push(np_left, (void*)(intptr_t)left);
        pact_list_pop(np_right);
        pact_list_push(np_right, (void*)(intptr_t)right);
        left = nd;
    }
    return left;
}

int64_t pact_parse_multiplicative(void) {
    int64_t left = pact_parse_unary();
    while (((pact_at(pact_TokenKind_Star) || pact_at(pact_TokenKind_Slash)) || pact_at(pact_TokenKind_Percent))) {
        const char* op = pact_advance_value();
        pact_skip_newlines();
        const int64_t right = pact_parse_unary();
        const int64_t nd = pact_new_node(pact_NodeKind_BinOp);
        pact_list_pop(np_op);
        pact_list_push(np_op, (void*)op);
        pact_list_pop(np_left);
        pact_list_push(np_left, (void*)(intptr_t)left);
        pact_list_pop(np_right);
        pact_list_push(np_right, (void*)(intptr_t)right);
        left = nd;
    }
    return left;
}

int64_t pact_parse_unary(void) {
    if (pact_at(pact_TokenKind_Minus)) {
        pact_advance();
        const int64_t operand = pact_parse_unary();
        const int64_t nd = pact_new_node(pact_NodeKind_UnaryOp);
        pact_list_pop(np_op);
        pact_list_push(np_op, (void*)"-");
        pact_list_pop(np_left);
        pact_list_push(np_left, (void*)(intptr_t)operand);
        return nd;
    }
    if (pact_at(pact_TokenKind_Bang)) {
        pact_advance();
        const int64_t operand = pact_parse_unary();
        const int64_t nd = pact_new_node(pact_NodeKind_UnaryOp);
        pact_list_pop(np_op);
        pact_list_push(np_op, (void*)"!");
        pact_list_pop(np_left);
        pact_list_push(np_left, (void*)(intptr_t)operand);
        return nd;
    }
    return pact_parse_postfix();
}

int64_t pact_parse_postfix(void) {
    int64_t node = pact_parse_primary();
    int64_t running = 1;
    while (running) {
        if (pact_at(pact_TokenKind_Dot)) {
            pact_advance();
            const char* member = pact_expect_value(pact_TokenKind_Ident);
            if (pact_at(pact_TokenKind_LParen)) {
                pact_advance();
                pact_list* _l0 = pact_list_new();
                pact_list* arg_nodes = _l0;
                if ((!pact_at(pact_TokenKind_RParen))) {
                    pact_list_push(arg_nodes, (void*)(intptr_t)pact_parse_expr());
                    while (pact_at(pact_TokenKind_Comma)) {
                        pact_advance();
                        pact_skip_newlines();
                        if (pact_at(pact_TokenKind_RParen)) {
                            break;
                        }
                        pact_list_push(arg_nodes, (void*)(intptr_t)pact_parse_expr());
                    }
                    pact_skip_newlines();
                }
                pact_expect(pact_TokenKind_RParen);
                const int64_t args = pact_new_sublist();
                int64_t ai = 0;
                while ((ai < pact_list_len(arg_nodes))) {
                    pact_sublist_push(args, (int64_t)(intptr_t)pact_list_get(arg_nodes, ai));
                    ai = (ai + 1);
                }
                pact_finalize_sublist(args);
                const int64_t nd = pact_new_node(pact_NodeKind_MethodCall);
                pact_list_pop(np_obj);
                pact_list_push(np_obj, (void*)(intptr_t)node);
                pact_list_pop(np_method);
                pact_list_push(np_method, (void*)member);
                pact_list_pop(np_args);
                pact_list_push(np_args, (void*)(intptr_t)args);
                node = nd;
            } else {
                const int64_t nd = pact_new_node(pact_NodeKind_FieldAccess);
                pact_list_pop(np_obj);
                pact_list_push(np_obj, (void*)(intptr_t)node);
                pact_list_pop(np_name);
                pact_list_push(np_name, (void*)member);
                node = nd;
                if (pact_at(pact_TokenKind_LBrace)) {
                    if (pact_looks_like_struct_lit()) {
                        const char* dotted = pact_flatten_field_access(node);
                        if ((!pact_str_eq(dotted, ""))) {
                            node = pact_parse_struct_lit(dotted);
                        }
                    }
                }
            }
        } else if (pact_at(pact_TokenKind_LParen)) {
            pact_advance();
            pact_list* _l1 = pact_list_new();
            pact_list* call_arg_nodes = _l1;
            if ((!pact_at(pact_TokenKind_RParen))) {
                pact_skip_newlines();
                pact_skip_named_arg_label();
                pact_list_push(call_arg_nodes, (void*)(intptr_t)pact_parse_expr());
                while (pact_at(pact_TokenKind_Comma)) {
                    pact_advance();
                    pact_skip_newlines();
                    if (pact_at(pact_TokenKind_RParen)) {
                        break;
                    }
                    pact_skip_named_arg_label();
                    pact_list_push(call_arg_nodes, (void*)(intptr_t)pact_parse_expr());
                }
                pact_skip_newlines();
            }
            pact_expect(pact_TokenKind_RParen);
            const int64_t args = pact_new_sublist();
            int64_t ci = 0;
            while ((ci < pact_list_len(call_arg_nodes))) {
                pact_sublist_push(args, (int64_t)(intptr_t)pact_list_get(call_arg_nodes, ci));
                ci = (ci + 1);
            }
            pact_finalize_sublist(args);
            const int64_t nd = pact_new_node(pact_NodeKind_Call);
            pact_list_pop(np_left);
            pact_list_push(np_left, (void*)(intptr_t)node);
            pact_list_pop(np_args);
            pact_list_push(np_args, (void*)(intptr_t)args);
            node = nd;
        } else {
            if (pact_at(pact_TokenKind_LBracket)) {
                pact_advance();
                pact_skip_newlines();
                const int64_t idx = pact_parse_expr();
                pact_skip_newlines();
                pact_expect(pact_TokenKind_RBracket);
                const int64_t nd = pact_new_node(pact_NodeKind_IndexExpr);
                pact_list_pop(np_obj);
                pact_list_push(np_obj, (void*)(intptr_t)node);
                pact_list_pop(np_index);
                pact_list_push(np_index, (void*)(intptr_t)idx);
                node = nd;
            } else if (pact_at(pact_TokenKind_Question)) {
                pact_advance();
                const int64_t nd = pact_new_node(pact_NodeKind_UnaryOp);
                pact_list_pop(np_op);
                pact_list_push(np_op, (void*)"?");
                pact_list_pop(np_left);
                pact_list_push(np_left, (void*)(intptr_t)node);
                node = nd;
            } else {
                running = 0;
            }
        }
    }
    return node;
}

void pact_skip_named_arg_label(void) {
    if (pact_at(pact_TokenKind_Ident)) {
        const int64_t saved = pos;
        pact_advance();
        if (pact_at(pact_TokenKind_Colon)) {
            pact_advance();
            pact_skip_newlines();
        } else {
            pos = saved;
        }
    }
}

const char* pact_flatten_field_access(int64_t node) {
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_Ident)) {
        return (const char*)pact_list_get(np_name, node);
    }
    if ((kind == pact_NodeKind_FieldAccess)) {
        const char* base = pact_flatten_field_access((int64_t)(intptr_t)pact_list_get(np_obj, node));
        if ((!pact_str_eq(base, ""))) {
            return pact_str_concat(pact_str_concat(base, "."), (const char*)pact_list_get(np_name, node));
        }
    }
    return "";
}

int64_t pact_looks_like_struct_lit(void) {
    const int64_t saved = pos;
    if ((!pact_at(pact_TokenKind_LBrace))) {
        return 0;
    }
    pact_advance();
    pact_skip_newlines();
    if (pact_at(pact_TokenKind_RBrace)) {
        pos = saved;
        return 1;
    }
    if ((!pact_at(pact_TokenKind_Ident))) {
        pos = saved;
        return 0;
    }
    pact_advance();
    const int64_t result = pact_at(pact_TokenKind_Colon);
    pos = saved;
    return result;
}

int64_t pact_parse_primary(void) {
    if (pact_at(pact_TokenKind_Match)) {
        return pact_parse_match_expr();
    }
    if (pact_at(pact_TokenKind_If)) {
        return pact_parse_if_expr();
    }
    if (pact_at(pact_TokenKind_Self)) {
        pact_advance();
        const int64_t nd = pact_new_node(pact_NodeKind_Ident);
        pact_list_pop(np_name);
        pact_list_push(np_name, (void*)"self");
        return nd;
    }
    if (pact_at(pact_TokenKind_Fn)) {
        return pact_parse_closure();
    }
    if (pact_at(pact_TokenKind_Handler)) {
        return pact_parse_handler_expr();
    }
    if (pact_at(pact_TokenKind_Ident)) {
        const char* name = pact_advance_value();
        if (pact_str_eq(name, "true")) {
            const int64_t nd = pact_new_node(pact_NodeKind_BoolLit);
            pact_list_pop(np_int_val);
            pact_list_push(np_int_val, (void*)(intptr_t)1);
            return nd;
        }
        if (pact_str_eq(name, "false")) {
            const int64_t nd = pact_new_node(pact_NodeKind_BoolLit);
            pact_list_pop(np_int_val);
            pact_list_push(np_int_val, (void*)(intptr_t)0);
            return nd;
        }
        if ((pact_at(pact_TokenKind_LBrace) && pact_looks_like_struct_lit())) {
            return pact_parse_struct_lit(name);
        }
        const int64_t nd = pact_new_node(pact_NodeKind_Ident);
        pact_list_pop(np_name);
        pact_list_push(np_name, (void*)name);
        return nd;
    }
    if (pact_at(pact_TokenKind_Int)) {
        const char* val_str = pact_advance_value();
        const int64_t nd = pact_new_node(pact_NodeKind_IntLit);
        pact_list_pop(np_str_val);
        pact_list_push(np_str_val, (void*)val_str);
        if (pact_at(pact_TokenKind_DotDot)) {
            pact_advance();
            const int64_t end_nd = pact_parse_primary();
            const int64_t rng = pact_new_node(pact_NodeKind_RangeLit);
            pact_list_pop(np_start);
            pact_list_push(np_start, (void*)(intptr_t)nd);
            pact_list_pop(np_end);
            pact_list_push(np_end, (void*)(intptr_t)end_nd);
            return rng;
        }
        if (pact_at(pact_TokenKind_DotDoteq)) {
            pact_advance();
            const int64_t end_nd = pact_parse_primary();
            const int64_t rng = pact_new_node(pact_NodeKind_RangeLit);
            pact_list_pop(np_start);
            pact_list_push(np_start, (void*)(intptr_t)nd);
            pact_list_pop(np_end);
            pact_list_push(np_end, (void*)(intptr_t)end_nd);
            pact_list_pop(np_inclusive);
            pact_list_push(np_inclusive, (void*)(intptr_t)1);
            return rng;
        }
        return nd;
    }
    if (pact_at(pact_TokenKind_Float)) {
        const char* val_str = pact_advance_value();
        const int64_t nd = pact_new_node(pact_NodeKind_FloatLit);
        pact_list_pop(np_str_val);
        pact_list_push(np_str_val, (void*)val_str);
        return nd;
    }
    if (pact_at(pact_TokenKind_LParen)) {
        pact_advance();
        pact_skip_newlines();
        if (pact_at(pact_TokenKind_RParen)) {
            pact_advance();
            return pact_new_node(pact_NodeKind_IntLit);
        }
        const int64_t first = pact_parse_expr();
        if (pact_at(pact_TokenKind_Comma)) {
            pact_list* _l0 = pact_list_new();
            pact_list_push(_l0, (void*)(intptr_t)first);
            pact_list* elem_nodes = _l0;
            while (pact_at(pact_TokenKind_Comma)) {
                pact_advance();
                pact_skip_newlines();
                if (pact_at(pact_TokenKind_RParen)) {
                    break;
                }
                pact_list_push(elem_nodes, (void*)(intptr_t)pact_parse_expr());
            }
            pact_expect(pact_TokenKind_RParen);
            const int64_t elems = pact_new_sublist();
            int64_t ti = 0;
            while ((ti < pact_list_len(elem_nodes))) {
                pact_sublist_push(elems, (int64_t)(intptr_t)pact_list_get(elem_nodes, ti));
                ti = (ti + 1);
            }
            pact_finalize_sublist(elems);
            const int64_t nd = pact_new_node(pact_NodeKind_TupleLit);
            pact_list_pop(np_elements);
            pact_list_push(np_elements, (void*)(intptr_t)elems);
            return nd;
        }
        pact_skip_newlines();
        pact_expect(pact_TokenKind_RParen);
        return first;
    }
    if (pact_at(pact_TokenKind_LBracket)) {
        return pact_parse_list_lit();
    }
    if (pact_at(pact_TokenKind_StringStart)) {
        return pact_parse_interp_string();
    }
    if (pact_at(pact_TokenKind_LBrace)) {
        return pact_parse_block();
    }
    char _si_1[4096];
    snprintf(_si_1, 4096, "parse error: unexpected token %lld at line %lld:%lld", (long long)pact_peek_kind(), (long long)pact_peek_line(), (long long)pact_peek_col());
    printf("%s\n", strdup(_si_1));
    pact_advance();
    return pact_new_node(pact_NodeKind_IntLit);
}

int64_t pact_parse_struct_lit(const char* type_name) {
    pact_expect(pact_TokenKind_LBrace);
    pact_skip_newlines();
    pact_list* _l0 = pact_list_new();
    pact_list* field_nodes = _l0;
    while ((!pact_at(pact_TokenKind_RBrace))) {
        const char* fname = pact_expect_value(pact_TokenKind_Ident);
        pact_expect(pact_TokenKind_Colon);
        pact_skip_newlines();
        const int64_t fval = pact_parse_expr();
        const int64_t sf = pact_new_node(pact_NodeKind_StructLitField);
        pact_list_pop(np_name);
        pact_list_push(np_name, (void*)fname);
        pact_list_pop(np_value);
        pact_list_push(np_value, (void*)(intptr_t)fval);
        pact_list_push(field_nodes, (void*)(intptr_t)sf);
        if (pact_at(pact_TokenKind_Comma)) {
            pact_advance();
        }
        pact_skip_newlines();
    }
    pact_expect(pact_TokenKind_RBrace);
    const int64_t flds = pact_new_sublist();
    int64_t i = 0;
    while ((i < pact_list_len(field_nodes))) {
        pact_sublist_push(flds, (int64_t)(intptr_t)pact_list_get(field_nodes, i));
        i = (i + 1);
    }
    pact_finalize_sublist(flds);
    const int64_t nd = pact_new_node(pact_NodeKind_StructLit);
    pact_list_pop(np_type_name);
    pact_list_push(np_type_name, (void*)type_name);
    pact_list_pop(np_fields);
    pact_list_push(np_fields, (void*)(intptr_t)flds);
    return nd;
}

int64_t pact_parse_list_lit(void) {
    pact_expect(pact_TokenKind_LBracket);
    pact_skip_newlines();
    pact_list* _l0 = pact_list_new();
    pact_list* elem_nodes = _l0;
    while ((!pact_at(pact_TokenKind_RBracket))) {
        pact_list_push(elem_nodes, (void*)(intptr_t)pact_parse_expr());
        if (pact_at(pact_TokenKind_Comma)) {
            pact_advance();
        }
        pact_skip_newlines();
    }
    pact_expect(pact_TokenKind_RBracket);
    const int64_t elems = pact_new_sublist();
    int64_t i = 0;
    while ((i < pact_list_len(elem_nodes))) {
        pact_sublist_push(elems, (int64_t)(intptr_t)pact_list_get(elem_nodes, i));
        i = (i + 1);
    }
    pact_finalize_sublist(elems);
    const int64_t nd = pact_new_node(pact_NodeKind_ListLit);
    pact_list_pop(np_elements);
    pact_list_push(np_elements, (void*)(intptr_t)elems);
    return nd;
}

int64_t pact_parse_interp_string(void) {
    pact_expect(pact_TokenKind_StringStart);
    pact_list* _l0 = pact_list_new();
    pact_list* part_nodes = _l0;
    while ((!pact_at(pact_TokenKind_StringEnd))) {
        if (pact_at(pact_TokenKind_StringPart)) {
            const char* s = pact_advance_value();
            const int64_t sn = pact_new_node(pact_NodeKind_Ident);
            pact_list_pop(np_str_val);
            pact_list_push(np_str_val, (void*)s);
            pact_list_pop(np_name);
            pact_list_push(np_name, (void*)s);
            pact_list_push(part_nodes, (void*)(intptr_t)sn);
        } else if (pact_at(pact_TokenKind_InterpStart)) {
            pact_advance();
            pact_list_push(part_nodes, (void*)(intptr_t)pact_parse_expr());
            pact_expect(pact_TokenKind_InterpEnd);
        } else {
            char _si_1[4096];
            snprintf(_si_1, 4096, "parse error: unexpected token in string: %lld", (long long)pact_peek_kind());
            printf("%s\n", strdup(_si_1));
            pact_advance();
        }
    }
    pact_expect(pact_TokenKind_StringEnd);
    const int64_t parts = pact_new_sublist();
    int64_t i = 0;
    while ((i < pact_list_len(part_nodes))) {
        pact_sublist_push(parts, (int64_t)(intptr_t)pact_list_get(part_nodes, i));
        i = (i + 1);
    }
    pact_finalize_sublist(parts);
    const int64_t nd = pact_new_node(pact_NodeKind_InterpString);
    pact_list_pop(np_elements);
    pact_list_push(np_elements, (void*)(intptr_t)parts);
    return nd;
}

int64_t pact_parse_match_expr(void) {
    pact_expect(pact_TokenKind_Match);
    const int64_t scrut = pact_parse_expr();
    pact_skip_newlines();
    pact_expect(pact_TokenKind_LBrace);
    pact_skip_newlines();
    pact_list* _l0 = pact_list_new();
    pact_list* arm_nodes = _l0;
    while ((!pact_at(pact_TokenKind_RBrace))) {
        pact_list_push(arm_nodes, (void*)(intptr_t)pact_parse_match_arm());
        pact_skip_newlines();
    }
    pact_expect(pact_TokenKind_RBrace);
    const int64_t arms = pact_new_sublist();
    int64_t i = 0;
    while ((i < pact_list_len(arm_nodes))) {
        pact_sublist_push(arms, (int64_t)(intptr_t)pact_list_get(arm_nodes, i));
        i = (i + 1);
    }
    pact_finalize_sublist(arms);
    const int64_t nd = pact_new_node(pact_NodeKind_MatchExpr);
    pact_list_pop(np_scrutinee);
    pact_list_push(np_scrutinee, (void*)(intptr_t)scrut);
    pact_list_pop(np_arms);
    pact_list_push(np_arms, (void*)(intptr_t)arms);
    return nd;
}

int64_t pact_parse_match_arm(void) {
    const int64_t pat = pact_parse_pattern();
    int64_t guard = (-1);
    pact_skip_newlines();
    if (pact_at(pact_TokenKind_If)) {
        pact_advance();
        guard = pact_parse_expr();
    }
    pact_skip_newlines();
    pact_expect(pact_TokenKind_FatArrow);
    pact_skip_newlines();
    int64_t body = (-1);
    if (pact_at(pact_TokenKind_LBrace)) {
        body = pact_parse_block();
    } else {
        body = pact_parse_stmt();
    }
    const int64_t nd = pact_new_node(pact_NodeKind_MatchArm);
    pact_list_pop(np_pattern);
    pact_list_push(np_pattern, (void*)(intptr_t)pat);
    pact_list_pop(np_body);
    pact_list_push(np_body, (void*)(intptr_t)body);
    pact_list_pop(np_guard);
    pact_list_push(np_guard, (void*)(intptr_t)guard);
    return nd;
}

int64_t pact_parse_pattern(void) {
    const int64_t first = pact_parse_single_pattern();
    if ((!pact_at(pact_TokenKind_Pipe))) {
        return first;
    }
    pact_list* _l0 = pact_list_new();
    pact_list* alt_nodes = _l0;
    pact_list_push(alt_nodes, (void*)(intptr_t)first);
    while (pact_at(pact_TokenKind_Pipe)) {
        pact_advance();
        pact_skip_newlines();
        pact_list_push(alt_nodes, (void*)(intptr_t)pact_parse_single_pattern());
    }
    const int64_t alts = pact_new_sublist();
    int64_t ai = 0;
    while ((ai < pact_list_len(alt_nodes))) {
        pact_sublist_push(alts, (int64_t)(intptr_t)pact_list_get(alt_nodes, ai));
        ai = (ai + 1);
    }
    pact_finalize_sublist(alts);
    const int64_t nd = pact_new_node(pact_NodeKind_OrPattern);
    pact_list_pop(np_elements);
    pact_list_push(np_elements, (void*)(intptr_t)alts);
    return nd;
}

int64_t pact_parse_single_pattern(void) {
    if (pact_at(pact_TokenKind_LParen)) {
        pact_advance();
        pact_skip_newlines();
        pact_list* _l0 = pact_list_new();
        pact_list* elem_nodes = _l0;
        pact_list_push(elem_nodes, (void*)(intptr_t)pact_parse_pattern());
        while (pact_at(pact_TokenKind_Comma)) {
            pact_advance();
            pact_skip_newlines();
            pact_list_push(elem_nodes, (void*)(intptr_t)pact_parse_pattern());
        }
        pact_skip_newlines();
        pact_expect(pact_TokenKind_RParen);
        const int64_t elems = pact_new_sublist();
        int64_t ei = 0;
        while ((ei < pact_list_len(elem_nodes))) {
            pact_sublist_push(elems, (int64_t)(intptr_t)pact_list_get(elem_nodes, ei));
            ei = (ei + 1);
        }
        pact_finalize_sublist(elems);
        const int64_t nd = pact_new_node(pact_NodeKind_TuplePattern);
        pact_list_pop(np_elements);
        pact_list_push(np_elements, (void*)(intptr_t)elems);
        return nd;
    }
    if (pact_at(pact_TokenKind_StringStart)) {
        const int64_t str_node = pact_parse_interp_string();
        const int64_t parts_sl = (int64_t)(intptr_t)pact_list_get(np_elements, str_node);
        const char* str_val = "";
        if (((parts_sl != (-1)) && (pact_sublist_length(parts_sl) == 1))) {
            str_val = (const char*)pact_list_get(np_str_val, pact_sublist_get(parts_sl, 0));
        }
        const int64_t nd = pact_new_node(pact_NodeKind_StringPattern);
        pact_list_pop(np_str_val);
        pact_list_push(np_str_val, (void*)str_val);
        return nd;
    }
    if (pact_at(pact_TokenKind_Int)) {
        const char* v = pact_advance_value();
        if (pact_at(pact_TokenKind_DotDot)) {
            pact_advance();
            const char* hi = pact_advance_value();
            const int64_t nd = pact_new_node(pact_NodeKind_RangePattern);
            pact_list_pop(np_str_val);
            pact_list_push(np_str_val, (void*)v);
            pact_list_pop(np_name);
            pact_list_push(np_name, (void*)hi);
            pact_list_pop(np_inclusive);
            pact_list_push(np_inclusive, (void*)(intptr_t)0);
            return nd;
        }
        if (pact_at(pact_TokenKind_DotDoteq)) {
            pact_advance();
            const char* hi = pact_advance_value();
            const int64_t nd = pact_new_node(pact_NodeKind_RangePattern);
            pact_list_pop(np_str_val);
            pact_list_push(np_str_val, (void*)v);
            pact_list_pop(np_name);
            pact_list_push(np_name, (void*)hi);
            pact_list_pop(np_inclusive);
            pact_list_push(np_inclusive, (void*)(intptr_t)1);
            return nd;
        }
        const int64_t nd = pact_new_node(pact_NodeKind_IntPattern);
        pact_list_pop(np_str_val);
        pact_list_push(np_str_val, (void*)v);
        return nd;
    }
    if (pact_at(pact_TokenKind_Ident)) {
        const char* name = pact_advance_value();
        if (pact_str_eq(name, "_")) {
            return pact_new_node(pact_NodeKind_WildcardPattern);
        }
        if (pact_str_eq(name, "true")) {
            const int64_t nd = pact_new_node(pact_NodeKind_IntPattern);
            pact_list_pop(np_str_val);
            pact_list_push(np_str_val, (void*)"1");
            return nd;
        }
        if (pact_str_eq(name, "false")) {
            const int64_t nd = pact_new_node(pact_NodeKind_IntPattern);
            pact_list_pop(np_str_val);
            pact_list_push(np_str_val, (void*)"0");
            return nd;
        }
        if (pact_at(pact_TokenKind_Dot)) {
            pact_advance();
            const char* variant = pact_advance_value();
            if (pact_at(pact_TokenKind_LParen)) {
                pact_advance();
                pact_skip_newlines();
                pact_list* _l1 = pact_list_new();
                pact_list* fld_nodes = _l1;
                if ((!pact_at(pact_TokenKind_RParen))) {
                    pact_list_push(fld_nodes, (void*)(intptr_t)pact_parse_pattern());
                    while (pact_at(pact_TokenKind_Comma)) {
                        pact_advance();
                        pact_skip_newlines();
                        pact_list_push(fld_nodes, (void*)(intptr_t)pact_parse_pattern());
                    }
                }
                pact_skip_newlines();
                pact_expect(pact_TokenKind_RParen);
                const int64_t flds = pact_new_sublist();
                int64_t fi = 0;
                while ((fi < pact_list_len(fld_nodes))) {
                    pact_sublist_push(flds, (int64_t)(intptr_t)pact_list_get(fld_nodes, fi));
                    fi = (fi + 1);
                }
                pact_finalize_sublist(flds);
                const int64_t nd = pact_new_node(pact_NodeKind_EnumPattern);
                pact_list_pop(np_name);
                pact_list_push(np_name, (void*)name);
                pact_list_pop(np_type_name);
                pact_list_push(np_type_name, (void*)variant);
                pact_list_pop(np_fields);
                pact_list_push(np_fields, (void*)(intptr_t)flds);
                return nd;
            }
            const int64_t nd = pact_new_node(pact_NodeKind_EnumPattern);
            pact_list_pop(np_name);
            pact_list_push(np_name, (void*)name);
            pact_list_pop(np_type_name);
            pact_list_push(np_type_name, (void*)variant);
            pact_list_pop(np_fields);
            pact_list_push(np_fields, (void*)(intptr_t)(-1));
            return nd;
        }
        if (pact_at(pact_TokenKind_LParen)) {
            pact_advance();
            pact_skip_newlines();
            pact_list* _l2 = pact_list_new();
            pact_list* fld_nodes2 = _l2;
            if ((!pact_at(pact_TokenKind_RParen))) {
                pact_list_push(fld_nodes2, (void*)(intptr_t)pact_parse_pattern());
                while (pact_at(pact_TokenKind_Comma)) {
                    pact_advance();
                    pact_skip_newlines();
                    pact_list_push(fld_nodes2, (void*)(intptr_t)pact_parse_pattern());
                }
            }
            pact_skip_newlines();
            pact_expect(pact_TokenKind_RParen);
            const int64_t flds = pact_new_sublist();
            int64_t fi = 0;
            while ((fi < pact_list_len(fld_nodes2))) {
                pact_sublist_push(flds, (int64_t)(intptr_t)pact_list_get(fld_nodes2, fi));
                fi = (fi + 1);
            }
            pact_finalize_sublist(flds);
            const int64_t nd = pact_new_node(pact_NodeKind_EnumPattern);
            pact_list_pop(np_name);
            pact_list_push(np_name, (void*)name);
            pact_list_pop(np_fields);
            pact_list_push(np_fields, (void*)(intptr_t)flds);
            return nd;
        }
        if (pact_at(pact_TokenKind_LBrace)) {
            pact_advance();
            pact_skip_newlines();
            pact_list* _l3 = pact_list_new();
            pact_list* field_nodes = _l3;
            int64_t has_rest = 0;
            while (((!pact_at(pact_TokenKind_RBrace)) && (!pact_at(pact_TokenKind_EOF)))) {
                if (pact_at(pact_TokenKind_DotDot)) {
                    pact_advance();
                    has_rest = 1;
                    pact_skip_newlines();
                    if (pact_at(pact_TokenKind_Comma)) {
                        pact_advance();
                        pact_skip_newlines();
                    }
                    break;
                }
                const char* fname = pact_expect_value(pact_TokenKind_Ident);
                if (pact_at(pact_TokenKind_Colon)) {
                    pact_advance();
                    pact_skip_newlines();
                    const int64_t fpat = pact_parse_pattern();
                    const int64_t sf = pact_new_node(pact_NodeKind_StructLitField);
                    pact_list_pop(np_name);
                    pact_list_push(np_name, (void*)fname);
                    pact_list_pop(np_pattern);
                    pact_list_push(np_pattern, (void*)(intptr_t)fpat);
                    pact_list_push(field_nodes, (void*)(intptr_t)sf);
                } else {
                    const int64_t sf = pact_new_node(pact_NodeKind_StructLitField);
                    pact_list_pop(np_name);
                    pact_list_push(np_name, (void*)fname);
                    pact_list_push(field_nodes, (void*)(intptr_t)sf);
                }
                if (pact_at(pact_TokenKind_Comma)) {
                    pact_advance();
                    pact_skip_newlines();
                }
            }
            pact_expect(pact_TokenKind_RBrace);
            const int64_t flds = pact_new_sublist();
            int64_t fi = 0;
            while ((fi < pact_list_len(field_nodes))) {
                pact_sublist_push(flds, (int64_t)(intptr_t)pact_list_get(field_nodes, fi));
                fi = (fi + 1);
            }
            pact_finalize_sublist(flds);
            const int64_t nd = pact_new_node(pact_NodeKind_StructPattern);
            pact_list_pop(np_type_name);
            pact_list_push(np_type_name, (void*)name);
            pact_list_pop(np_fields);
            pact_list_push(np_fields, (void*)(intptr_t)flds);
            pact_list_pop(np_inclusive);
            pact_list_push(np_inclusive, (void*)(intptr_t)has_rest);
            return nd;
        }
        if (pact_at(pact_TokenKind_As)) {
            pact_advance();
            const int64_t inner = pact_parse_pattern();
            const int64_t nd = pact_new_node(pact_NodeKind_AsPattern);
            pact_list_pop(np_name);
            pact_list_push(np_name, (void*)name);
            pact_list_pop(np_pattern);
            pact_list_push(np_pattern, (void*)(intptr_t)inner);
            return nd;
        }
        const int64_t nd = pact_new_node(pact_NodeKind_IdentPattern);
        pact_list_pop(np_name);
        pact_list_push(np_name, (void*)name);
        return nd;
    }
    char _si_4[4096];
    snprintf(_si_4, 4096, "parse error: unexpected token in pattern: %lld", (long long)pact_peek_kind());
    printf("%s\n", strdup(_si_4));
    pact_advance();
    return pact_new_node(pact_NodeKind_WildcardPattern);
}

void pact_push_scope(void) {
    pact_list_push(scope_frame_starts, (void*)(intptr_t)pact_list_len(scope_names));
}

void pact_pop_scope(void) {
    const int64_t start = (int64_t)(intptr_t)pact_list_get(scope_frame_starts, (pact_list_len(scope_frame_starts) - 1));
    pact_list_pop(scope_frame_starts);
    while ((pact_list_len(scope_names) > start)) {
        pact_list_pop(scope_names);
        pact_list_pop(scope_types);
        pact_list_pop(scope_muts);
    }
}

void pact_set_var(const char* name, int64_t ctype, int64_t is_mut) {
    pact_list_push(scope_names, (void*)name);
    pact_list_push(scope_types, (void*)(intptr_t)ctype);
    pact_list_push(scope_muts, (void*)(intptr_t)is_mut);
}

int64_t pact_get_var_type(const char* name) {
    int64_t i = (pact_list_len(scope_names) - 1);
    while ((i >= 0)) {
        if (pact_str_eq((const char*)pact_list_get(scope_names, i), name)) {
            return (int64_t)(intptr_t)pact_list_get(scope_types, i);
        }
        i = (i - 1);
    }
    return CT_INT;
}

int64_t pact_get_var_mut(const char* name) {
    int64_t i = (pact_list_len(scope_names) - 1);
    while ((i >= 0)) {
        if (pact_str_eq((const char*)pact_list_get(scope_names, i), name)) {
            return (int64_t)(intptr_t)pact_list_get(scope_muts, i);
        }
        i = (i - 1);
    }
    return 0;
}

int64_t pact_is_mut_captured(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(mut_captured_vars))) {
        if (pact_str_eq((const char*)pact_list_get(mut_captured_vars, i), name)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_get_capture_index(const char* name) {
    if ((cg_closure_cap_start < 0)) {
        return (-1);
    }
    int64_t i = 0;
    while ((i < cg_closure_cap_count)) {
        if (pact_str_eq((const char*)pact_list_get(closure_capture_names, (cg_closure_cap_start + i)), name)) {
            return i;
        }
        i = (i + 1);
    }
    return (-1);
}

const char* pact_capture_cast_expr(int64_t idx) {
    const int64_t ct = (int64_t)(intptr_t)pact_list_get(closure_capture_types, (cg_closure_cap_start + idx));
    const char* _if_0;
    if ((ct == CT_INT)) {
        char _si_1[4096];
        snprintf(_si_1, 4096, "(int64_t)(intptr_t)pact_closure_get_capture(__self, %lld)", (long long)idx);
        _if_0 = strdup(_si_1);
    } else {
        const char* _if_2;
        if ((ct == CT_FLOAT)) {
            char _si_3[4096];
            snprintf(_si_3, 4096, "*(double*)pact_closure_get_capture(__self, %lld)", (long long)idx);
            _if_2 = strdup(_si_3);
        } else {
            const char* _if_4;
            if ((ct == CT_STRING)) {
                char _si_5[4096];
                snprintf(_si_5, 4096, "(const char*)pact_closure_get_capture(__self, %lld)", (long long)idx);
                _if_4 = strdup(_si_5);
            } else {
                const char* _if_6;
                if ((ct == CT_BOOL)) {
                    char _si_7[4096];
                    snprintf(_si_7, 4096, "(int)(intptr_t)pact_closure_get_capture(__self, %lld)", (long long)idx);
                    _if_6 = strdup(_si_7);
                } else {
                    const char* _if_8;
                    if ((ct == CT_LIST)) {
                        char _si_9[4096];
                        snprintf(_si_9, 4096, "(pact_list*)pact_closure_get_capture(__self, %lld)", (long long)idx);
                        _if_8 = strdup(_si_9);
                    } else {
                        const char* _if_10;
                        if ((ct == CT_CLOSURE)) {
                            char _si_11[4096];
                            snprintf(_si_11, 4096, "(pact_closure*)pact_closure_get_capture(__self, %lld)", (long long)idx);
                            _if_10 = strdup(_si_11);
                        } else {
                            char _si_12[4096];
                            snprintf(_si_12, 4096, "pact_closure_get_capture(__self, %lld)", (long long)idx);
                            _if_10 = strdup(_si_12);
                        }
                        _if_8 = _if_10;
                    }
                    _if_6 = _if_8;
                }
                _if_4 = _if_6;
            }
            _if_2 = _if_4;
        }
        _if_0 = _if_2;
    }
    return _if_0;
}

void pact_reg_fn(const char* name, int64_t ret) {
    pact_list_push(fn_reg_names, (void*)name);
    pact_list_push(fn_reg_ret, (void*)(intptr_t)ret);
    pact_list_push(fn_reg_effect_sl, (void*)(intptr_t)(-1));
}

void pact_reg_fn_with_effects(const char* name, int64_t ret, int64_t effects_sl) {
    pact_list_push(fn_reg_names, (void*)name);
    pact_list_push(fn_reg_ret, (void*)(intptr_t)ret);
    pact_list_push(fn_reg_effect_sl, (void*)(intptr_t)effects_sl);
}

int64_t pact_get_fn_effect_sl(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(fn_reg_names))) {
        if (pact_str_eq((const char*)pact_list_get(fn_reg_names, i), name)) {
            return (int64_t)(intptr_t)pact_list_get(fn_reg_effect_sl, i);
        }
        i = (i + 1);
    }
    return (-1);
}

int64_t pact_reg_effect(const char* name, int64_t parent) {
    const int64_t idx = pact_list_len(effect_reg_names);
    pact_list_push(effect_reg_names, (void*)name);
    pact_list_push(effect_reg_parent, (void*)(intptr_t)parent);
    return idx;
}

int64_t pact_get_effect_idx(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(effect_reg_names))) {
        if (pact_str_eq((const char*)pact_list_get(effect_reg_names, i), name)) {
            return i;
        }
        i = (i + 1);
    }
    return (-1);
}

int64_t pact_effect_satisfies(const char* caller_effect, const char* callee_effect) {
    if (pact_str_eq(caller_effect, callee_effect)) {
        return 1;
    }
    const int64_t callee_idx = pact_get_effect_idx(callee_effect);
    if ((callee_idx == (-1))) {
        return 0;
    }
    const int64_t parent_idx = (int64_t)(intptr_t)pact_list_get(effect_reg_parent, callee_idx);
    if ((parent_idx == (-1))) {
        return 0;
    }
    const char* parent_name = (const char*)pact_list_get(effect_reg_names, parent_idx);
    if (pact_str_eq(parent_name, caller_effect)) {
        return 1;
    }
    return 0;
}

void pact_check_effect_propagation(const char* callee_name) {
    if (pact_str_eq(cg_current_fn_name, "main")) {
        return;
    }
    const int64_t callee_sl = pact_get_fn_effect_sl(callee_name);
    if ((callee_sl == (-1))) {
        return;
    }
    const int64_t callee_count = pact_sublist_length(callee_sl);
    if ((callee_count == 0)) {
        return;
    }
    const int64_t caller_sl = pact_get_fn_effect_sl(cg_current_fn_name);
    int64_t ci = 0;
    while ((ci < callee_count)) {
        const int64_t callee_eff_node = pact_sublist_get(callee_sl, ci);
        const char* callee_eff = (const char*)pact_list_get(np_name, callee_eff_node);
        int64_t satisfied = 0;
        if ((caller_sl != (-1))) {
            const int64_t caller_count = pact_sublist_length(caller_sl);
            int64_t ki = 0;
            while ((ki < caller_count)) {
                const int64_t caller_eff_node = pact_sublist_get(caller_sl, ki);
                const char* caller_eff = (const char*)pact_list_get(np_name, caller_eff_node);
                if ((pact_effect_satisfies(caller_eff, callee_eff) != 0)) {
                    satisfied = 1;
                }
                ki = (ki + 1);
            }
        }
        if ((satisfied == 0)) {
            char _si_0[4096];
            snprintf(_si_0, 4096, "error E0500: function '%s' requires effect '%s' but caller '%s' does not declare it", callee_name, callee_eff, cg_current_fn_name);
            printf("%s\n", strdup(_si_0));
        }
        ci = (ci + 1);
    }
}

void pact_init_builtin_effects(void) {
    const int64_t io_idx = pact_reg_effect("IO", (-1));
    pact_reg_effect("IO.Print", io_idx);
    pact_reg_effect("IO.Log", io_idx);
    const int64_t fs_idx = pact_reg_effect("FS", (-1));
    pact_reg_effect("FS.Read", fs_idx);
    pact_reg_effect("FS.Write", fs_idx);
    pact_reg_effect("FS.Delete", fs_idx);
    pact_reg_effect("FS.Watch", fs_idx);
    const int64_t net_idx = pact_reg_effect("Net", (-1));
    pact_reg_effect("Net.Connect", net_idx);
    pact_reg_effect("Net.Listen", net_idx);
    pact_reg_effect("Net.DNS", net_idx);
    const int64_t db_idx = pact_reg_effect("DB", (-1));
    pact_reg_effect("DB.Read", db_idx);
    pact_reg_effect("DB.Write", db_idx);
    pact_reg_effect("DB.Admin", db_idx);
    const int64_t env_idx = pact_reg_effect("Env", (-1));
    pact_reg_effect("Env.Read", env_idx);
    pact_reg_effect("Env.Write", env_idx);
    const int64_t time_idx = pact_reg_effect("Time", (-1));
    pact_reg_effect("Time.Read", time_idx);
    pact_reg_effect("Time.Sleep", time_idx);
    pact_reg_effect("Rand", (-1));
    const int64_t crypto_idx = pact_reg_effect("Crypto", (-1));
    pact_reg_effect("Crypto.Hash", crypto_idx);
    pact_reg_effect("Crypto.Sign", crypto_idx);
    pact_reg_effect("Crypto.Encrypt", crypto_idx);
    pact_reg_effect("Crypto.Decrypt", crypto_idx);
    const int64_t proc_idx = pact_reg_effect("Process", (-1));
    pact_reg_effect("Process.Spawn", proc_idx);
    pact_reg_effect("Process.Signal", proc_idx);
}

int64_t pact_get_fn_ret(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(fn_reg_names))) {
        if (pact_str_eq((const char*)pact_list_get(fn_reg_names, i), name)) {
            return (int64_t)(intptr_t)pact_list_get(fn_reg_ret, i);
        }
        i = (i + 1);
    }
    return CT_VOID;
}

void pact_set_list_elem_type(const char* name, int64_t elem_type) {
    pact_list_push(var_list_elem_names, (void*)name);
    pact_list_push(var_list_elem_types, (void*)(intptr_t)elem_type);
}

int64_t pact_get_list_elem_type(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(var_list_elem_names))) {
        if (pact_str_eq((const char*)pact_list_get(var_list_elem_names, i), name)) {
            return (int64_t)(intptr_t)pact_list_get(var_list_elem_types, i);
        }
        i = (i + 1);
    }
    return CT_INT;
}

int64_t pact_is_struct_type(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(struct_reg_names))) {
        if (pact_str_eq((const char*)pact_list_get(struct_reg_names, i), name)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_is_enum_type(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(enum_reg_names))) {
        if (pact_str_eq((const char*)pact_list_get(enum_reg_names, i), name)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

const char* pact_resolve_variant(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(enum_reg_variant_names))) {
        if (pact_str_eq((const char*)pact_list_get(enum_reg_variant_names, i), name)) {
            return (const char*)pact_list_get(enum_reg_names, (int64_t)(intptr_t)pact_list_get(enum_reg_variant_enum_idx, i));
        }
        i = (i + 1);
    }
    return "";
}

const char* pact_get_var_enum(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(var_enum_names))) {
        if (pact_str_eq((const char*)pact_list_get(var_enum_names, i), name)) {
            return (const char*)pact_list_get(var_enum_types, i);
        }
        i = (i + 1);
    }
    return "";
}

const char* pact_get_fn_enum_ret(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(fn_enum_ret_names))) {
        if (pact_str_eq((const char*)pact_list_get(fn_enum_ret_names, i), name)) {
            return (const char*)pact_list_get(fn_enum_ret_types, i);
        }
        i = (i + 1);
    }
    return "";
}

void pact_set_var_struct(const char* name, const char* type_name) {
    pact_list_push(var_struct_names, (void*)name);
    pact_list_push(var_struct_types, (void*)type_name);
}

const char* pact_get_var_struct(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(var_struct_names))) {
        if (pact_str_eq((const char*)pact_list_get(var_struct_names, i), name)) {
            return (const char*)pact_list_get(var_struct_types, i);
        }
        i = (i + 1);
    }
    return "";
}

int64_t pact_get_struct_field_type(const char* sname, const char* fname) {
    int64_t i = 0;
    while ((i < pact_list_len(sf_reg_struct))) {
        if ((pact_str_eq((const char*)pact_list_get(sf_reg_struct, i), sname) && pact_str_eq((const char*)pact_list_get(sf_reg_field, i), fname))) {
            return (int64_t)(intptr_t)pact_list_get(sf_reg_type, i);
        }
        i = (i + 1);
    }
    return CT_VOID;
}

const char* pact_get_struct_field_stype(const char* sname, const char* fname) {
    int64_t i = 0;
    while ((i < pact_list_len(sf_reg_struct))) {
        if ((pact_str_eq((const char*)pact_list_get(sf_reg_struct, i), sname) && pact_str_eq((const char*)pact_list_get(sf_reg_field, i), fname))) {
            return (const char*)pact_list_get(sf_reg_stype, i);
        }
        i = (i + 1);
    }
    return "";
}

void pact_set_var_closure(const char* name, const char* sig) {
    pact_list_push(var_closure_names, (void*)name);
    pact_list_push(var_closure_sigs, (void*)sig);
}

const char* pact_get_var_closure_sig(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(var_closure_names))) {
        if (pact_str_eq((const char*)pact_list_get(var_closure_names, i), name)) {
            return (const char*)pact_list_get(var_closure_sigs, i);
        }
        i = (i + 1);
    }
    return "";
}

const char* pact_build_closure_sig_from_type_ann(int64_t ta) {
    const char* ret_name = (const char*)pact_list_get(np_return_type, ta);
    const int64_t ret_type = pact_type_from_name(ret_name);
    const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, ta);
    const char* sig_params = "pact_closure*";
    if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) > 0))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(elems_sl))) {
            const int64_t elem = pact_sublist_get(elems_sl, i);
            const char* ename = (const char*)pact_list_get(np_name, elem);
            sig_params = pact_str_concat(sig_params, ", ");
            if ((pact_is_enum_type(ename) != 0)) {
                char _si_0[4096];
                snprintf(_si_0, 4096, "pact_%s", ename);
                sig_params = pact_str_concat(sig_params, strdup(_si_0));
            } else if ((pact_is_struct_type(ename) != 0)) {
                char _si_1[4096];
                snprintf(_si_1, 4096, "pact_%s", ename);
                sig_params = pact_str_concat(sig_params, strdup(_si_1));
            } else {
                sig_params = pact_str_concat(sig_params, pact_c_type_str(pact_type_from_name(ename)));
            }
            i = (i + 1);
        }
    }
    char _si_2[4096];
    snprintf(_si_2, 4096, "%s(*)(%s)", pact_c_type_str(ret_type), sig_params);
    return strdup(_si_2);
}

int64_t pact_is_generic_fn(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(generic_fn_names))) {
        if (pact_str_eq((const char*)pact_list_get(generic_fn_names, i), name)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_get_generic_fn_node(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(generic_fn_names))) {
        if (pact_str_eq((const char*)pact_list_get(generic_fn_names, i), name)) {
            return (int64_t)(intptr_t)pact_list_get(generic_fn_nodes, i);
        }
        i = (i + 1);
    }
    return (-1);
}

void pact_register_mono_fn(const char* base, const char* args) {
    int64_t i = 0;
    while ((i < pact_list_len(mono_fn_bases))) {
        if ((pact_str_eq((const char*)pact_list_get(mono_fn_bases, i), base) && pact_str_eq((const char*)pact_list_get(mono_fn_args, i), args))) {
            return;
        }
        i = (i + 1);
    }
    pact_list_push(mono_fn_bases, (void*)base);
    pact_list_push(mono_fn_args, (void*)args);
}

const char* pact_infer_fn_type_args_from_types(int64_t fn_node, pact_list* arg_types) {
    const int64_t tparams_sl = (int64_t)(intptr_t)pact_list_get(np_type_params, fn_node);
    if ((tparams_sl == (-1))) {
        return "";
    }
    const int64_t num_params = pact_sublist_length(tparams_sl);
    if ((num_params == 0)) {
        return "";
    }
    const int64_t fn_params_sl = (int64_t)(intptr_t)pact_list_get(np_params, fn_node);
    if ((fn_params_sl == (-1))) {
        return "";
    }
    const char* args = "";
    int64_t pi = 0;
    while ((pi < num_params)) {
        const char* param_name = (const char*)pact_list_get(np_name, pact_sublist_get(tparams_sl, pi));
        const char* resolved = "Void";
        int64_t fi = 0;
        while (((fi < pact_sublist_length(fn_params_sl)) && (fi < pact_list_len(arg_types)))) {
            const int64_t p = pact_sublist_get(fn_params_sl, fi);
            const char* ptype = (const char*)pact_list_get(np_type_name, p);
            if (pact_str_eq(ptype, param_name)) {
                resolved = pact_type_name_from_ct((int64_t)(intptr_t)pact_list_get(arg_types, fi));
            }
            fi = (fi + 1);
        }
        if ((pi > 0)) {
            args = pact_str_concat(args, ",");
        }
        args = pact_str_concat(args, resolved);
        pi = (pi + 1);
    }
    return args;
}

const char* pact_type_name_from_ct(int64_t ct) {
    const char* _if_0;
    if ((ct == CT_INT)) {
        _if_0 = "Int";
    } else {
        const char* _if_1;
        if ((ct == CT_FLOAT)) {
            _if_1 = "Float";
        } else {
            const char* _if_2;
            if ((ct == CT_BOOL)) {
                _if_2 = "Bool";
            } else {
                const char* _if_3;
                if ((ct == CT_STRING)) {
                    _if_3 = "Str";
                } else {
                    const char* _if_4;
                    if ((ct == CT_LIST)) {
                        _if_4 = "List";
                    } else {
                        _if_4 = "Void";
                    }
                    _if_3 = _if_4;
                }
                _if_2 = _if_3;
            }
            _if_1 = _if_2;
        }
        _if_0 = _if_1;
    }
    return _if_0;
}

const char* pact_mangle_generic_name(const char* base, const char* args) {
    const char* result = base;
    int64_t i = 0;
    int64_t seg_start = 0;
    while ((i <= pact_str_len(args))) {
        if (((i == pact_str_len(args)) || (pact_str_char_at(args, i) == 44))) {
            const char* seg = pact_str_substr(args, seg_start, (i - seg_start));
            result = pact_str_concat(pact_str_concat(result, "_"), seg);
            seg_start = (i + 1);
        }
        i = (i + 1);
    }
    return result;
}

const char* pact_register_mono_instance(const char* base, const char* args) {
    const char* existing = pact_lookup_mono_instance(base, args);
    if ((!pact_str_eq(existing, ""))) {
        return existing;
    }
    const char* c_name = pact_mangle_generic_name(base, args);
    pact_list_push(mono_base_names, (void*)base);
    pact_list_push(mono_concrete_args, (void*)args);
    pact_list_push(mono_c_names, (void*)c_name);
    return c_name;
}

const char* pact_lookup_mono_instance(const char* base, const char* args) {
    int64_t i = 0;
    while ((i < pact_list_len(mono_base_names))) {
        if ((pact_str_eq((const char*)pact_list_get(mono_base_names, i), base) && pact_str_eq((const char*)pact_list_get(mono_concrete_args, i), args))) {
            return (const char*)pact_list_get(mono_c_names, i);
        }
        i = (i + 1);
    }
    return "";
}

int64_t pact_is_trait_type(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(trait_reg_names))) {
        if (pact_str_eq((const char*)pact_list_get(trait_reg_names, i), name)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_lookup_impl_method(const char* type_name, const char* method) {
    int64_t i = 0;
    while ((i < pact_list_len(impl_reg_type))) {
        if (pact_str_eq((const char*)pact_list_get(impl_reg_type, i), type_name)) {
            const int64_t methods_sl = (int64_t)(intptr_t)pact_list_get(impl_reg_methods_sl, i);
            int64_t j = 0;
            while ((j < pact_sublist_length(methods_sl))) {
                const int64_t m = pact_sublist_get(methods_sl, j);
                if (pact_str_eq((const char*)pact_list_get(np_name, m), method)) {
                    return 1;
                }
                j = (j + 1);
            }
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_lookup_impl_type_for_trait(const char* trait_name, const char* type_name) {
    int64_t i = 0;
    while ((i < pact_list_len(impl_reg_trait))) {
        if ((pact_str_eq((const char*)pact_list_get(impl_reg_trait, i), trait_name) && pact_str_eq((const char*)pact_list_get(impl_reg_type, i), type_name))) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_get_impl_method_ret(const char* type_name, const char* method) {
    int64_t i = 0;
    while ((i < pact_list_len(impl_reg_type))) {
        if (pact_str_eq((const char*)pact_list_get(impl_reg_type, i), type_name)) {
            const int64_t methods_sl = (int64_t)(intptr_t)pact_list_get(impl_reg_methods_sl, i);
            int64_t j = 0;
            while ((j < pact_sublist_length(methods_sl))) {
                const int64_t m = pact_sublist_get(methods_sl, j);
                if (pact_str_eq((const char*)pact_list_get(np_name, m), method)) {
                    const char* ret_str = (const char*)pact_list_get(np_return_type, m);
                    return pact_type_from_name(ret_str);
                }
                j = (j + 1);
            }
        }
        i = (i + 1);
    }
    return CT_VOID;
}

int64_t pact_find_from_impl(const char* source, const char* target) {
    int64_t i = 0;
    while ((i < pact_list_len(from_reg_source))) {
        if ((pact_str_eq((const char*)pact_list_get(from_reg_source, i), source) && pact_str_eq((const char*)pact_list_get(from_reg_target, i), target))) {
            return (int64_t)(intptr_t)pact_list_get(from_reg_method_sl, i);
        }
        i = (i + 1);
    }
    return (-1);
}

int64_t pact_impl_method_has_self(int64_t fn_node) {
    const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, fn_node);
    if ((params_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(params_sl))) {
            const int64_t p = pact_sublist_get(params_sl, i);
            if (pact_str_eq((const char*)pact_list_get(np_name, p), "self")) {
                return 1;
            }
            i = (i + 1);
        }
    }
    return 0;
}

const char* pact_resolve_self_type(const char* ret_str, const char* impl_type) {
    if (pact_str_eq(ret_str, "Self")) {
        return impl_type;
    }
    return ret_str;
}

int64_t pact_is_emitted_let(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(emitted_let_names))) {
        if (pact_str_eq((const char*)pact_list_get(emitted_let_names, i), name)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_is_emitted_fn(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(emitted_fn_names))) {
        if (pact_str_eq((const char*)pact_list_get(emitted_fn_names, i), name)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

const char* pact_c_type_str(int64_t ct) {
    const char* _if_0;
    if ((ct == CT_INT)) {
        _if_0 = "int64_t";
    } else {
        const char* _if_1;
        if ((ct == CT_FLOAT)) {
            _if_1 = "double";
        } else {
            const char* _if_2;
            if ((ct == CT_BOOL)) {
                _if_2 = "int";
            } else {
                const char* _if_3;
                if ((ct == CT_STRING)) {
                    _if_3 = "const char*";
                } else {
                    const char* _if_4;
                    if ((ct == CT_LIST)) {
                        _if_4 = "pact_list*";
                    } else {
                        const char* _if_5;
                        if ((ct == CT_CLOSURE)) {
                            _if_5 = "pact_closure*";
                        } else {
                            _if_5 = "void";
                        }
                        _if_4 = _if_5;
                    }
                    _if_3 = _if_4;
                }
                _if_2 = _if_3;
            }
            _if_1 = _if_2;
        }
        _if_0 = _if_1;
    }
    return _if_0;
}

int64_t pact_type_from_name(const char* name) {
    int64_t _match_0;
    if ((pact_str_eq(name, "Int"))) {
        _match_0 = CT_INT;
    } else if ((pact_str_eq(name, "Str"))) {
        _match_0 = CT_STRING;
    } else if ((pact_str_eq(name, "Float"))) {
        _match_0 = CT_FLOAT;
    } else if ((pact_str_eq(name, "Bool"))) {
        _match_0 = CT_BOOL;
    } else if ((pact_str_eq(name, "List"))) {
        _match_0 = CT_LIST;
    } else if ((pact_str_eq(name, "Option"))) {
        _match_0 = CT_OPTION;
    } else if ((pact_str_eq(name, "Result"))) {
        _match_0 = CT_RESULT;
    } else {
        _match_0 = CT_VOID;
    }
    return _match_0;
}

const char* pact_option_c_type(int64_t inner) {
    char _si_0[4096];
    snprintf(_si_0, 4096, "pact_Option_%s", pact_c_type_tag(inner));
    return strdup(_si_0);
}

const char* pact_result_c_type(int64_t ok_t, int64_t err_t) {
    char _si_0[4096];
    snprintf(_si_0, 4096, "pact_Result_%s_%s", pact_c_type_tag(ok_t), pact_c_type_tag(err_t));
    return strdup(_si_0);
}

const char* pact_c_type_tag(int64_t ct) {
    const char* _if_0;
    if ((ct == CT_INT)) {
        _if_0 = "int";
    } else {
        const char* _if_1;
        if ((ct == CT_FLOAT)) {
            _if_1 = "double";
        } else {
            const char* _if_2;
            if ((ct == CT_BOOL)) {
                _if_2 = "bool";
            } else {
                const char* _if_3;
                if ((ct == CT_STRING)) {
                    _if_3 = "str";
                } else {
                    const char* _if_4;
                    if ((ct == CT_LIST)) {
                        _if_4 = "list";
                    } else {
                        _if_4 = "void";
                    }
                    _if_3 = _if_4;
                }
                _if_2 = _if_3;
            }
            _if_1 = _if_2;
        }
        _if_0 = _if_1;
    }
    return _if_0;
}

void pact_ensure_option_type(int64_t inner) {
    int64_t i = 0;
    while ((i < pact_list_len(emitted_option_types))) {
        if (((int64_t)(intptr_t)pact_list_get(emitted_option_types, i) == inner)) {
            return;
        }
        i = (i + 1);
    }
    pact_list_push(emitted_option_types, (void*)(intptr_t)inner);
}

void pact_ensure_result_type(int64_t ok_t, int64_t err_t) {
    char _si_0[4096];
    snprintf(_si_0, 4096, "%lld_%lld", (long long)ok_t, (long long)err_t);
    const char* key = strdup(_si_0);
    int64_t i = 0;
    while ((i < pact_list_len(emitted_result_types))) {
        if (pact_str_eq((const char*)pact_list_get(emitted_result_types, i), key)) {
            return;
        }
        i = (i + 1);
    }
    pact_list_push(emitted_result_types, (void*)key);
}

void pact_set_var_option(const char* name, int64_t inner) {
    pact_list_push(var_option_names, (void*)name);
    pact_list_push(var_option_inner, (void*)(intptr_t)inner);
}

int64_t pact_get_var_option_inner(const char* name) {
    int64_t i = (pact_list_len(var_option_names) - 1);
    while ((i >= 0)) {
        if (pact_str_eq((const char*)pact_list_get(var_option_names, i), name)) {
            return (int64_t)(intptr_t)pact_list_get(var_option_inner, i);
        }
        i = (i - 1);
    }
    return (-1);
}

void pact_set_var_result(const char* name, int64_t ok_t, int64_t err_t) {
    pact_list_push(var_result_names, (void*)name);
    pact_list_push(var_result_ok, (void*)(intptr_t)ok_t);
    pact_list_push(var_result_err, (void*)(intptr_t)err_t);
}

int64_t pact_get_var_result_ok(const char* name) {
    int64_t i = (pact_list_len(var_result_names) - 1);
    while ((i >= 0)) {
        if (pact_str_eq((const char*)pact_list_get(var_result_names, i), name)) {
            return (int64_t)(intptr_t)pact_list_get(var_result_ok, i);
        }
        i = (i - 1);
    }
    return (-1);
}

int64_t pact_get_var_result_err(const char* name) {
    int64_t i = (pact_list_len(var_result_names) - 1);
    while ((i >= 0)) {
        if (pact_str_eq((const char*)pact_list_get(var_result_names, i), name)) {
            return (int64_t)(intptr_t)pact_list_get(var_result_err, i);
        }
        i = (i - 1);
    }
    return (-1);
}

void pact_emit_option_typedef(int64_t inner) {
    const char* tag = pact_c_type_tag(inner);
    char _si_0[4096];
    snprintf(_si_0, 4096, "pact_Option_%s", tag);
    const char* tname = strdup(_si_0);
    const char* c_inner = pact_c_type_str(inner);
    char _si_1[4096];
    snprintf(_si_1, 4096, "typedef struct { int tag; %s value; } %s;", c_inner, tname);
    pact_emit_line(strdup(_si_1));
    pact_emit_line("");
}

void pact_emit_result_typedef(int64_t ok_t, int64_t err_t) {
    const char* ok_tag = pact_c_type_tag(ok_t);
    const char* err_tag = pact_c_type_tag(err_t);
    char _si_0[4096];
    snprintf(_si_0, 4096, "pact_Result_%s_%s", ok_tag, err_tag);
    const char* tname = strdup(_si_0);
    const char* c_ok = pact_c_type_str(ok_t);
    const char* c_err = pact_c_type_str(err_t);
    char _si_1[4096];
    snprintf(_si_1, 4096, "typedef struct { int tag; union { %s ok; %s err; }; } %s;", c_ok, c_err, tname);
    pact_emit_line(strdup(_si_1));
    pact_emit_line("");
}

void pact_emit_all_option_result_types(void) {
    int64_t i = 0;
    while ((i < pact_list_len(emitted_option_types))) {
        pact_emit_option_typedef((int64_t)(intptr_t)pact_list_get(emitted_option_types, i));
        i = (i + 1);
    }
    i = 0;
    while ((i < pact_list_len(emitted_result_types))) {
        const char* key = (const char*)pact_list_get(emitted_result_types, i);
        int64_t sep = 0;
        int64_t j = 0;
        while ((j < pact_str_len(key))) {
            if ((pact_str_char_at(key, j) == 95)) {
                sep = j;
            }
            j = (j + 1);
        }
        const char* ok_str = pact_str_substr(key, 0, sep);
        const char* err_str = pact_str_substr(key, (sep + 1), ((pact_str_len(key) - sep) - 1));
        int64_t ok_t = CT_INT;
        int64_t err_t = CT_INT;
        if (pact_str_eq(ok_str, "0")) {
            ok_t = CT_INT;
        } else if (pact_str_eq(ok_str, "1")) {
            ok_t = CT_FLOAT;
        } else {
            if (pact_str_eq(ok_str, "2")) {
                ok_t = CT_BOOL;
            } else if (pact_str_eq(ok_str, "3")) {
                ok_t = CT_STRING;
            } else {
                if (pact_str_eq(ok_str, "4")) {
                    ok_t = CT_LIST;
                }
            }
        }
        if (pact_str_eq(err_str, "0")) {
            err_t = CT_INT;
        } else if (pact_str_eq(err_str, "1")) {
            err_t = CT_FLOAT;
        } else {
            if (pact_str_eq(err_str, "2")) {
                err_t = CT_BOOL;
            } else if (pact_str_eq(err_str, "3")) {
                err_t = CT_STRING;
            } else {
                if (pact_str_eq(err_str, "4")) {
                    err_t = CT_LIST;
                }
            }
        }
        pact_emit_result_typedef(ok_t, err_t);
        i = (i + 1);
    }
}

const char* pact_fresh_temp(const char* prefix) {
    const int64_t n = cg_temp_counter;
    cg_temp_counter = (cg_temp_counter + 1);
    char _si_0[4096];
    snprintf(_si_0, 4096, "%s%lld", prefix, (long long)n);
    return strdup(_si_0);
}

void pact_emit_line(const char* line) {
    if (pact_str_eq(line, "")) {
        pact_list_push(cg_lines, (void*)"");
    } else {
        const char* pad = "";
        int64_t i = 0;
        while ((i < cg_indent)) {
            pad = pact_str_concat(pad, "    ");
            i = (i + 1);
        }
        pact_list_push(cg_lines, (void*)pact_str_concat(pad, line));
    }
}

const char* pact_join_lines(void) {
    const char* result = "";
    int64_t i = 0;
    while ((i < pact_list_len(cg_lines))) {
        if ((i > 0)) {
            result = pact_str_concat(result, "\n");
        }
        result = pact_str_concat(result, (const char*)pact_list_get(cg_lines, i));
        i = (i + 1);
    }
    return result;
}

void pact_emit_expr(int64_t node) {
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_IntLit)) {
        const char* s = (const char*)pact_list_get(np_str_val, node);
        if (pact_str_eq(s, "")) {
            char _si_0[4096];
            snprintf(_si_0, 4096, "%lld", (long long)(int64_t)(intptr_t)pact_list_get(np_int_val, node));
            expr_result_str = strdup(_si_0);
        } else {
            expr_result_str = s;
        }
        expr_result_type = CT_INT;
        return;
    }
    if ((kind == pact_NodeKind_FloatLit)) {
        expr_result_str = (const char*)pact_list_get(np_str_val, node);
        expr_result_type = CT_FLOAT;
        return;
    }
    if ((kind == pact_NodeKind_BoolLit)) {
        if (((int64_t)(intptr_t)pact_list_get(np_int_val, node) != 0)) {
            expr_result_str = "1";
        } else {
            expr_result_str = "0";
        }
        expr_result_type = CT_BOOL;
        return;
    }
    if ((kind == pact_NodeKind_Ident)) {
        const char* name = (const char*)pact_list_get(np_name, node);
        if (pact_str_eq(name, "None")) {
            pact_ensure_option_type(CT_INT);
            const char* opt_type = pact_option_c_type(CT_INT);
            char _si_1[4096];
            snprintf(_si_1, 4096, "(%s){.tag = 0}", opt_type);
            expr_result_str = strdup(_si_1);
            expr_result_type = CT_OPTION;
            expr_option_inner = CT_INT;
            return;
        }
        const char* variant_enum = pact_resolve_variant(name);
        if ((!pact_str_eq(variant_enum, ""))) {
            char _si_2[4096];
            snprintf(_si_2, 4096, "pact_%s_%s", variant_enum, name);
            expr_result_str = strdup(_si_2);
            expr_result_type = CT_INT;
            return;
        }
        const int64_t cap_idx = pact_get_capture_index(name);
        if ((cap_idx >= 0)) {
            expr_result_str = pact_capture_cast_expr(cap_idx);
            expr_result_type = (int64_t)(intptr_t)pact_list_get(closure_capture_types, (cg_closure_cap_start + cap_idx));
            return;
        }
        if ((pact_is_mut_captured(name) != 0)) {
            char _si_3[4096];
            snprintf(_si_3, 4096, "(*%s_cell)", name);
            expr_result_str = strdup(_si_3);
            expr_result_type = pact_get_var_type(name);
            return;
        }
        expr_result_str = name;
        expr_result_type = pact_get_var_type(name);
        if ((expr_result_type == CT_OPTION)) {
            expr_option_inner = pact_get_var_option_inner(name);
        }
        if ((expr_result_type == CT_RESULT)) {
            expr_result_ok_type = pact_get_var_result_ok(name);
            expr_result_err_type = pact_get_var_result_err(name);
        }
        return;
    }
    if ((kind == pact_NodeKind_BinOp)) {
        pact_emit_binop(node);
        return;
    }
    if ((kind == pact_NodeKind_UnaryOp)) {
        pact_emit_unaryop(node);
        return;
    }
    if ((kind == pact_NodeKind_Call)) {
        pact_emit_call(node);
        return;
    }
    if ((kind == pact_NodeKind_MethodCall)) {
        pact_emit_method_call(node);
        return;
    }
    if ((kind == pact_NodeKind_InterpString)) {
        pact_emit_interp_string(node);
        return;
    }
    if ((kind == pact_NodeKind_IfExpr)) {
        pact_emit_if_expr(node);
        return;
    }
    if ((kind == pact_NodeKind_FieldAccess)) {
        const int64_t fa_obj = (int64_t)(intptr_t)pact_list_get(np_obj, node);
        const char* fa_field = (const char*)pact_list_get(np_name, node);
        if (((int64_t)(intptr_t)pact_list_get(np_kind, fa_obj) == pact_NodeKind_Ident)) {
            const char* obj_name = (const char*)pact_list_get(np_name, fa_obj);
            if ((pact_is_enum_type(obj_name) != 0)) {
                char _si_4[4096];
                snprintf(_si_4, 4096, "pact_%s_%s", obj_name, fa_field);
                expr_result_str = strdup(_si_4);
                expr_result_type = CT_INT;
                return;
            }
        }
        pact_emit_expr(fa_obj);
        const char* obj_str = expr_result_str;
        char _si_5[4096];
        snprintf(_si_5, 4096, "%s.%s", obj_str, fa_field);
        expr_result_str = strdup(_si_5);
        int64_t fa_type = CT_VOID;
        const char* struct_type = pact_get_var_struct(obj_str);
        if ((!pact_str_eq(struct_type, ""))) {
            fa_type = pact_get_struct_field_type(struct_type, fa_field);
            const char* fa_stype = pact_get_struct_field_stype(struct_type, fa_field);
            if ((!pact_str_eq(fa_stype, ""))) {
                pact_set_var_struct(expr_result_str, fa_stype);
            }
        }
        expr_result_type = fa_type;
        return;
    }
    if ((kind == pact_NodeKind_IndexExpr)) {
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_obj, node));
        const char* obj_str = expr_result_str;
        const int64_t obj_type = expr_result_type;
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_index, node));
        const char* idx_str = expr_result_str;
        if ((obj_type == CT_STRING)) {
            char _si_6[4096];
            snprintf(_si_6, 4096, "pact_str_char_at(%s, %s)", obj_str, idx_str);
            expr_result_str = strdup(_si_6);
            expr_result_type = CT_INT;
        } else {
            char _si_7[4096];
            snprintf(_si_7, 4096, "%s[%s]", obj_str, idx_str);
            expr_result_str = strdup(_si_7);
            expr_result_type = CT_INT;
        }
        return;
    }
    if ((kind == pact_NodeKind_ListLit)) {
        pact_emit_list_lit(node);
        return;
    }
    if ((kind == pact_NodeKind_RangeLit)) {
        expr_result_str = "0";
        expr_result_type = CT_VOID;
        return;
    }
    if ((kind == pact_NodeKind_MatchExpr)) {
        pact_emit_match_expr(node);
        return;
    }
    if ((kind == pact_NodeKind_Block)) {
        pact_emit_block_expr(node);
        return;
    }
    if ((kind == pact_NodeKind_Return)) {
        if (((int64_t)(intptr_t)pact_list_get(np_value, node) != (-1))) {
            pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_value, node));
            const char* val_str = expr_result_str;
            char _si_8[4096];
            snprintf(_si_8, 4096, "return %s;", val_str);
            pact_emit_line(strdup(_si_8));
        } else {
            pact_emit_line("return;");
        }
        expr_result_str = "0";
        expr_result_type = CT_VOID;
        return;
    }
    if ((kind == pact_NodeKind_StructLit)) {
        pact_emit_struct_lit(node);
        return;
    }
    if ((kind == pact_NodeKind_Closure)) {
        pact_emit_closure(node);
        return;
    }
    expr_result_str = "0";
    expr_result_type = CT_VOID;
}

void pact_emit_binop(int64_t node) {
    const char* op = (const char*)pact_list_get(np_op, node);
    if (pact_str_eq(op, "??")) {
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_left, node));
        const char* left_str = expr_result_str;
        const int64_t left_type = expr_result_type;
        const int64_t opt_inner = expr_option_inner;
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_right, node));
        const char* right_str = expr_result_str;
        const int64_t right_type = expr_result_type;
        const char* tmp = pact_fresh_temp("__opt");
        if ((opt_inner >= 0)) {
            const char* opt_c = pact_option_c_type(opt_inner);
            char _si_0[4096];
            snprintf(_si_0, 4096, "%s %s = %s;", opt_c, tmp, left_str);
            pact_emit_line(strdup(_si_0));
        } else {
            char _si_1[4096];
            snprintf(_si_1, 4096, "const int64_t %s = (int64_t)%s;", tmp, left_str);
            pact_emit_line(strdup(_si_1));
        }
        char _si_2[4096];
        snprintf(_si_2, 4096, "(%s.tag == 1 ? %s.value : %s)", tmp, tmp, right_str);
        expr_result_str = strdup(_si_2);
        expr_result_type = right_type;
        return;
    }
    pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_left, node));
    const char* left_str = expr_result_str;
    const int64_t left_type = expr_result_type;
    pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_right, node));
    const char* right_str = expr_result_str;
    const int64_t right_type = expr_result_type;
    if (((pact_str_eq(op, "==") && (left_type == CT_STRING)) && (right_type == CT_STRING))) {
        char _si_3[4096];
        snprintf(_si_3, 4096, "pact_str_eq(%s, %s)", left_str, right_str);
        expr_result_str = strdup(_si_3);
        expr_result_type = CT_BOOL;
        return;
    }
    if (((pact_str_eq(op, "!=") && (left_type == CT_STRING)) && (right_type == CT_STRING))) {
        char _si_4[4096];
        snprintf(_si_4, 4096, "(!pact_str_eq(%s, %s))", left_str, right_str);
        expr_result_str = strdup(_si_4);
        expr_result_type = CT_BOOL;
        return;
    }
    if ((pact_str_eq(op, "+") && ((left_type == CT_STRING) || (right_type == CT_STRING)))) {
        char _si_5[4096];
        snprintf(_si_5, 4096, "pact_str_concat(%s, %s)", left_str, right_str);
        expr_result_str = strdup(_si_5);
        expr_result_type = CT_STRING;
        return;
    }
    char _si_6[4096];
    snprintf(_si_6, 4096, "(%s %s %s)", left_str, op, right_str);
    expr_result_str = strdup(_si_6);
    if ((((((((pact_str_eq(op, "==") || pact_str_eq(op, "!=")) || pact_str_eq(op, "<")) || pact_str_eq(op, ">")) || pact_str_eq(op, "<=")) || pact_str_eq(op, ">=")) || pact_str_eq(op, "&&")) || pact_str_eq(op, "||"))) {
        expr_result_type = CT_BOOL;
    } else {
        expr_result_type = left_type;
    }
}

void pact_emit_unaryop(int64_t node) {
    pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_left, node));
    const char* operand_str = expr_result_str;
    const int64_t operand_type = expr_result_type;
    const char* op = (const char*)pact_list_get(np_op, node);
    if (pact_str_eq(op, "-")) {
        char _si_0[4096];
        snprintf(_si_0, 4096, "(-%s)", operand_str);
        expr_result_str = strdup(_si_0);
        expr_result_type = operand_type;
    } else if (pact_str_eq(op, "!")) {
        char _si_1[4096];
        snprintf(_si_1, 4096, "(!%s)", operand_str);
        expr_result_str = strdup(_si_1);
        expr_result_type = CT_BOOL;
    } else {
        if (pact_str_eq(op, "?")) {
            const char* tmp = pact_fresh_temp("__res");
            if ((operand_type == CT_RESULT)) {
                const int64_t rok = expr_result_ok_type;
                const int64_t rerr = expr_result_err_type;
                const char* res_c = pact_result_c_type(rok, rerr);
                char _si_2[4096];
                snprintf(_si_2, 4096, "%s %s = %s;", res_c, tmp, operand_str);
                pact_emit_line(strdup(_si_2));
                char _si_3[4096];
                snprintf(_si_3, 4096, "if (%s.tag == 1) return (%s){.tag = 1, .err = %s.err};", tmp, res_c, tmp);
                pact_emit_line(strdup(_si_3));
                char _si_4[4096];
                snprintf(_si_4, 4096, "%s.ok", tmp);
                expr_result_str = strdup(_si_4);
                expr_result_type = rok;
            } else {
                char _si_5[4096];
                snprintf(_si_5, 4096, "int64_t %s = (int64_t)%s;", tmp, operand_str);
                pact_emit_line(strdup(_si_5));
                char _si_6[4096];
                snprintf(_si_6, 4096, "%s", tmp);
                expr_result_str = strdup(_si_6);
                expr_result_type = operand_type;
            }
        } else {
            char _si_7[4096];
            snprintf(_si_7, 4096, "(%s%s)", op, operand_str);
            expr_result_str = strdup(_si_7);
            expr_result_type = operand_type;
        }
    }
}

void pact_emit_call(int64_t node) {
    const int64_t func_node = (int64_t)(intptr_t)pact_list_get(np_left, node);
    const int64_t func_kind = (int64_t)(intptr_t)pact_list_get(np_kind, func_node);
    if ((func_kind == pact_NodeKind_Ident)) {
        const char* fn_name = (const char*)pact_list_get(np_name, func_node);
        if (pact_str_eq(fn_name, "Some")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
                pact_emit_expr(pact_sublist_get(args_sl, 0));
                const char* inner_str = expr_result_str;
                const int64_t inner_type = expr_result_type;
                pact_ensure_option_type(inner_type);
                const char* opt_type = pact_option_c_type(inner_type);
                char _si_0[4096];
                snprintf(_si_0, 4096, "(%s){.tag = 1, .value = %s}", opt_type, inner_str);
                expr_result_str = strdup(_si_0);
                expr_result_type = CT_OPTION;
                expr_option_inner = inner_type;
                return;
            }
        }
        if (pact_str_eq(fn_name, "Ok")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
                pact_emit_expr(pact_sublist_get(args_sl, 0));
                const char* ok_str = expr_result_str;
                const int64_t ok_type = expr_result_type;
                const int64_t err_type = CT_STRING;
                pact_ensure_result_type(ok_type, err_type);
                const char* res_type = pact_result_c_type(ok_type, err_type);
                char _si_1[4096];
                snprintf(_si_1, 4096, "(%s){.tag = 0, .ok = %s}", res_type, ok_str);
                expr_result_str = strdup(_si_1);
                expr_result_type = CT_RESULT;
                expr_result_ok_type = ok_type;
                expr_result_err_type = err_type;
                return;
            }
        }
        if (pact_str_eq(fn_name, "Err")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
                pact_emit_expr(pact_sublist_get(args_sl, 0));
                const char* err_str = expr_result_str;
                const int64_t err_type = expr_result_type;
                const int64_t ok_type = CT_INT;
                pact_ensure_result_type(ok_type, err_type);
                const char* res_type = pact_result_c_type(ok_type, err_type);
                char _si_2[4096];
                snprintf(_si_2, 4096, "(%s){.tag = 1, .err = %s}", res_type, err_str);
                expr_result_str = strdup(_si_2);
                expr_result_type = CT_RESULT;
                expr_result_ok_type = ok_type;
                expr_result_err_type = err_type;
                return;
            }
        }
        const char* closure_sig = pact_get_var_closure_sig(fn_name);
        if ((!pact_str_eq(closure_sig, ""))) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            const char* args_str = fn_name;
            if ((args_sl != (-1))) {
                int64_t i = 0;
                while ((i < pact_sublist_length(args_sl))) {
                    args_str = pact_str_concat(args_str, ", ");
                    pact_emit_expr(pact_sublist_get(args_sl, i));
                    args_str = pact_str_concat(args_str, expr_result_str);
                    i = (i + 1);
                }
            }
            char _si_3[4096];
            snprintf(_si_3, 4096, "((%s)%s->fn_ptr)(%s)", closure_sig, fn_name, args_str);
            expr_result_str = strdup(_si_3);
            int64_t ret_end = 0;
            while (((ret_end < pact_str_len(closure_sig)) && (pact_str_char_at(closure_sig, ret_end) != 40))) {
                ret_end = (ret_end + 1);
            }
            const char* ret_part = pact_str_substr(closure_sig, 0, ret_end);
            if (pact_str_eq(ret_part, "int64_t")) {
                expr_result_type = CT_INT;
            } else if (pact_str_eq(ret_part, "double")) {
                expr_result_type = CT_FLOAT;
            } else {
                if (pact_str_eq(ret_part, "const char*")) {
                    expr_result_type = CT_STRING;
                } else if (pact_str_eq(ret_part, "int")) {
                    expr_result_type = CT_BOOL;
                } else {
                    expr_result_type = CT_VOID;
                }
            }
            return;
        }
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        const char* args_str = "";
        pact_list* _l4 = pact_list_new();
        pact_list* arg_types = _l4;
        if ((args_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(args_sl))) {
                if ((i > 0)) {
                    args_str = pact_str_concat(args_str, ", ");
                }
                pact_emit_expr(pact_sublist_get(args_sl, i));
                args_str = pact_str_concat(args_str, expr_result_str);
                pact_list_push(arg_types, (void*)(intptr_t)expr_result_type);
                i = (i + 1);
            }
        }
        pact_check_effect_propagation(fn_name);
        if ((pact_is_generic_fn(fn_name) != 0)) {
            const int64_t gfn_node = pact_get_generic_fn_node(fn_name);
            const char* type_args = pact_infer_fn_type_args_from_types(gfn_node, arg_types);
            if ((!pact_str_eq(type_args, ""))) {
                const char* mangled = pact_mangle_generic_name(fn_name, type_args);
                pact_register_mono_fn(fn_name, type_args);
                pact_register_mono_instance(fn_name, type_args);
                const char* ret_str = (const char*)pact_list_get(np_return_type, gfn_node);
                const int64_t tparams_sl = (int64_t)(intptr_t)pact_list_get(np_type_params, gfn_node);
                const char* resolved_ret = pact_resolve_type_param(ret_str, tparams_sl, type_args);
                const int64_t ret_type = pact_type_from_name(resolved_ret);
                pact_reg_fn(mangled, ret_type);
                char _si_5[4096];
                snprintf(_si_5, 4096, "pact_%s(%s)", mangled, args_str);
                expr_result_str = strdup(_si_5);
                expr_result_type = ret_type;
                return;
            }
        }
        char _si_6[4096];
        snprintf(_si_6, 4096, "pact_%s(%s)", fn_name, args_str);
        expr_result_str = strdup(_si_6);
        expr_result_type = pact_get_fn_ret(fn_name);
        return;
    }
    if ((func_kind == pact_NodeKind_FieldAccess)) {
        const int64_t trait_obj = (int64_t)(intptr_t)pact_list_get(np_obj, func_node);
        if (((int64_t)(intptr_t)pact_list_get(np_kind, trait_obj) == pact_NodeKind_Ident)) {
            const char* trait_name = (const char*)pact_list_get(np_name, trait_obj);
            if ((pact_is_trait_type(trait_name) != 0)) {
                const char* method = (const char*)pact_list_get(np_name, func_node);
                const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
                if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
                    pact_emit_expr(pact_sublist_get(args_sl, 0));
                    const char* first_str = expr_result_str;
                    const char* type_name = pact_get_var_struct(first_str);
                    if ((!pact_str_eq(type_name, ""))) {
                        char _si_7[4096];
                        snprintf(_si_7, 4096, "%s_%s", type_name, method);
                        const char* mangled = strdup(_si_7);
                        const char* args_str = first_str;
                        int64_t i = 1;
                        while ((i < pact_sublist_length(args_sl))) {
                            args_str = pact_str_concat(args_str, ", ");
                            pact_emit_expr(pact_sublist_get(args_sl, i));
                            args_str = pact_str_concat(args_str, expr_result_str);
                            i = (i + 1);
                        }
                        char _si_8[4096];
                        snprintf(_si_8, 4096, "pact_%s(%s)", mangled, args_str);
                        expr_result_str = strdup(_si_8);
                        expr_result_type = pact_get_impl_method_ret(type_name, method);
                        return;
                    }
                }
            }
        }
    }
    pact_emit_expr(func_node);
    const char* func_str = expr_result_str;
    const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
    const char* args_str = "";
    if ((args_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(args_sl))) {
            if ((i > 0)) {
                args_str = pact_str_concat(args_str, ", ");
            }
            pact_emit_expr(pact_sublist_get(args_sl, i));
            args_str = pact_str_concat(args_str, expr_result_str);
            i = (i + 1);
        }
    }
    char _si_9[4096];
    snprintf(_si_9, 4096, "%s(%s)", func_str, args_str);
    expr_result_str = strdup(_si_9);
    expr_result_type = CT_VOID;
}

void pact_emit_method_call(int64_t node) {
    const int64_t obj_node = (int64_t)(intptr_t)pact_list_get(np_obj, node);
    const char* method = (const char*)pact_list_get(np_method, node);
    if (((((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident) && pact_str_eq((const char*)pact_list_get(np_name, obj_node), "io")) && pact_str_eq(method, "println"))) {
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* arg_str = expr_result_str;
            const int64_t arg_type = expr_result_type;
            if ((arg_type == CT_INT)) {
                char _si_0[4096];
                snprintf(_si_0, 4096, "printf(\"%%lld\\n\", (long long)%s);", arg_str);
                pact_emit_line(strdup(_si_0));
            } else if ((arg_type == CT_FLOAT)) {
                char _si_1[4096];
                snprintf(_si_1, 4096, "printf(\"%%g\\n\", %s);", arg_str);
                pact_emit_line(strdup(_si_1));
            } else {
                if ((arg_type == CT_BOOL)) {
                    char _si_2[4096];
                    snprintf(_si_2, 4096, "printf(\"%%s\\n\", %s ? \"true\" : \"false\");", arg_str);
                    pact_emit_line(strdup(_si_2));
                } else {
                    char _si_3[4096];
                    snprintf(_si_3, 4096, "printf(\"%%s\\n\", %s);", arg_str);
                    pact_emit_line(strdup(_si_3));
                }
            }
        } else {
            pact_emit_line("printf(\"\\n\");");
        }
        expr_result_str = "0";
        expr_result_type = CT_VOID;
        return;
    }
    if (((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident)) {
        const char* trait_name = (const char*)pact_list_get(np_name, obj_node);
        if ((pact_is_trait_type(trait_name) != 0)) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
                pact_emit_expr(pact_sublist_get(args_sl, 0));
                const char* first_str = expr_result_str;
                const char* type_name = pact_get_var_struct(first_str);
                if ((!pact_str_eq(type_name, ""))) {
                    char _si_4[4096];
                    snprintf(_si_4, 4096, "%s_%s", type_name, method);
                    const char* mangled = strdup(_si_4);
                    const char* args_str = first_str;
                    int64_t i = 1;
                    while ((i < pact_sublist_length(args_sl))) {
                        args_str = pact_str_concat(args_str, ", ");
                        pact_emit_expr(pact_sublist_get(args_sl, i));
                        args_str = pact_str_concat(args_str, expr_result_str);
                        i = (i + 1);
                    }
                    char _si_5[4096];
                    snprintf(_si_5, 4096, "pact_%s(%s)", mangled, args_str);
                    expr_result_str = strdup(_si_5);
                    expr_result_type = pact_get_impl_method_ret(type_name, method);
                    return;
                }
            }
        }
    }
    if (((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident)) {
        const char* target_type = (const char*)pact_list_get(np_name, obj_node);
        if ((pact_str_eq(method, "from") && ((pact_is_struct_type(target_type) != 0) || (pact_is_enum_type(target_type) != 0)))) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
                pact_emit_expr(pact_sublist_get(args_sl, 0));
                const char* arg_str = expr_result_str;
                const int64_t arg_type = expr_result_type;
                const char* source_type = pact_type_name_from_ct(arg_type);
                const char* arg_struct = pact_get_var_struct(arg_str);
                const char* src = source_type;
                if ((!pact_str_eq(arg_struct, ""))) {
                    src = arg_struct;
                }
                const int64_t from_methods = pact_find_from_impl(src, target_type);
                if (((from_methods != (-1)) && (pact_sublist_length(from_methods) > 0))) {
                    const int64_t from_fn = pact_sublist_get(from_methods, 0);
                    const char* from_name = (const char*)pact_list_get(np_name, from_fn);
                    char _si_6[4096];
                    snprintf(_si_6, 4096, "%s_%s", target_type, from_name);
                    const char* mangled = strdup(_si_6);
                    char _si_7[4096];
                    snprintf(_si_7, 4096, "pact_%s(%s)", mangled, arg_str);
                    expr_result_str = strdup(_si_7);
                    expr_result_type = pact_get_fn_ret(mangled);
                    if ((expr_result_type == CT_VOID)) {
                        pact_set_var_struct(expr_result_str, target_type);
                    }
                    return;
                }
            }
        }
    }
    pact_emit_expr(obj_node);
    const char* obj_str = expr_result_str;
    const int64_t obj_type = expr_result_type;
    if (pact_str_eq(method, "into")) {
        const int64_t target = cg_let_target_type;
        if (((target == CT_FLOAT) && (obj_type == CT_INT))) {
            char _si_8[4096];
            snprintf(_si_8, 4096, "(double)%s", obj_str);
            expr_result_str = strdup(_si_8);
            expr_result_type = CT_FLOAT;
            return;
        }
        if (((target == CT_INT) && (obj_type == CT_FLOAT))) {
            char _si_9[4096];
            snprintf(_si_9, 4096, "(int64_t)%s", obj_str);
            expr_result_str = strdup(_si_9);
            expr_result_type = CT_INT;
            return;
        }
        if (((target == CT_STRING) && (obj_type == CT_INT))) {
            char _si_10[4096];
            snprintf(_si_10, 4096, "pact_int_to_str(%s)", obj_str);
            expr_result_str = strdup(_si_10);
            expr_result_type = CT_STRING;
            return;
        }
        if (((target == CT_STRING) && (obj_type == CT_FLOAT))) {
            char _si_11[4096];
            snprintf(_si_11, 4096, "pact_float_to_str(%s)", obj_str);
            expr_result_str = strdup(_si_11);
            expr_result_type = CT_STRING;
            return;
        }
        const char* src_name = pact_type_name_from_ct(obj_type);
        const char* src_struct = pact_get_var_struct(obj_str);
        if ((!pact_str_eq(src_struct, ""))) {
            src_name = src_struct;
        }
        const char* tgt_name = pact_type_name_from_ct(target);
        const int64_t from_methods = pact_find_from_impl(src_name, tgt_name);
        if (((from_methods != (-1)) && (pact_sublist_length(from_methods) > 0))) {
            const int64_t from_fn = pact_sublist_get(from_methods, 0);
            const char* from_name = (const char*)pact_list_get(np_name, from_fn);
            char _si_12[4096];
            snprintf(_si_12, 4096, "%s_%s", tgt_name, from_name);
            const char* mangled = strdup(_si_12);
            char _si_13[4096];
            snprintf(_si_13, 4096, "pact_%s(%s)", mangled, obj_str);
            expr_result_str = strdup(_si_13);
            expr_result_type = target;
            return;
        }
        pact_emit_line("/* into() conversion not found */");
        expr_result_str = obj_str;
        expr_result_type = obj_type;
        return;
    }
    if ((obj_type == CT_STRING)) {
        if (pact_str_eq(method, "len")) {
            char _si_14[4096];
            snprintf(_si_14, 4096, "pact_str_len(%s)", obj_str);
            expr_result_str = strdup(_si_14);
            expr_result_type = CT_INT;
            return;
        }
        if ((pact_str_eq(method, "char_at") || pact_str_eq(method, "charAt"))) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* idx_str = expr_result_str;
            char _si_15[4096];
            snprintf(_si_15, 4096, "pact_str_char_at(%s, %s)", obj_str, idx_str);
            expr_result_str = strdup(_si_15);
            expr_result_type = CT_INT;
            return;
        }
        if ((pact_str_eq(method, "substring") || pact_str_eq(method, "substr"))) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* start_str = expr_result_str;
            pact_emit_expr(pact_sublist_get(args_sl, 1));
            const char* len_str = expr_result_str;
            char _si_16[4096];
            snprintf(_si_16, 4096, "pact_str_substr(%s, %s, %s)", obj_str, start_str, len_str);
            expr_result_str = strdup(_si_16);
            expr_result_type = CT_STRING;
            return;
        }
        if (pact_str_eq(method, "contains")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* needle_str = expr_result_str;
            char _si_17[4096];
            snprintf(_si_17, 4096, "pact_str_contains(%s, %s)", obj_str, needle_str);
            expr_result_str = strdup(_si_17);
            expr_result_type = CT_BOOL;
            return;
        }
        if (pact_str_eq(method, "starts_with")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* pfx_str = expr_result_str;
            char _si_18[4096];
            snprintf(_si_18, 4096, "pact_str_starts_with(%s, %s)", obj_str, pfx_str);
            expr_result_str = strdup(_si_18);
            expr_result_type = CT_BOOL;
            return;
        }
        if (pact_str_eq(method, "concat")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* other_str = expr_result_str;
            char _si_19[4096];
            snprintf(_si_19, 4096, "pact_str_concat(%s, %s)", obj_str, other_str);
            expr_result_str = strdup(_si_19);
            expr_result_type = CT_STRING;
            return;
        }
    }
    if ((obj_type == CT_LIST)) {
        if (pact_str_eq(method, "push")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* val_str = expr_result_str;
            const int64_t val_type = expr_result_type;
            if ((val_type == CT_INT)) {
                char _si_20[4096];
                snprintf(_si_20, 4096, "pact_list_push(%s, (void*)(intptr_t)%s);", obj_str, val_str);
                pact_emit_line(strdup(_si_20));
            } else {
                char _si_21[4096];
                snprintf(_si_21, 4096, "pact_list_push(%s, (void*)%s);", obj_str, val_str);
                pact_emit_line(strdup(_si_21));
            }
            expr_result_str = "0";
            expr_result_type = CT_VOID;
            return;
        }
        if (pact_str_eq(method, "pop")) {
            char _si_22[4096];
            snprintf(_si_22, 4096, "pact_list_pop(%s);", obj_str);
            pact_emit_line(strdup(_si_22));
            expr_result_str = "0";
            expr_result_type = CT_VOID;
            return;
        }
        if (pact_str_eq(method, "len")) {
            char _si_23[4096];
            snprintf(_si_23, 4096, "pact_list_len(%s)", obj_str);
            expr_result_str = strdup(_si_23);
            expr_result_type = CT_INT;
            return;
        }
        if (pact_str_eq(method, "get")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* idx_str = expr_result_str;
            const int64_t elem_type = pact_get_list_elem_type(obj_str);
            if ((elem_type == CT_STRING)) {
                char _si_24[4096];
                snprintf(_si_24, 4096, "(const char*)pact_list_get(%s, %s)", obj_str, idx_str);
                expr_result_str = strdup(_si_24);
                expr_result_type = CT_STRING;
            } else {
                char _si_25[4096];
                snprintf(_si_25, 4096, "(int64_t)(intptr_t)pact_list_get(%s, %s)", obj_str, idx_str);
                expr_result_str = strdup(_si_25);
                expr_result_type = CT_INT;
            }
            return;
        }
        if (pact_str_eq(method, "set")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* idx_str = expr_result_str;
            pact_emit_expr(pact_sublist_get(args_sl, 1));
            const char* val_str2 = expr_result_str;
            const int64_t val_type2 = expr_result_type;
            if ((val_type2 == CT_INT)) {
                char _si_26[4096];
                snprintf(_si_26, 4096, "pact_list_set(%s, %s, (void*)(intptr_t)%s);", obj_str, idx_str, val_str2);
                pact_emit_line(strdup(_si_26));
            } else {
                char _si_27[4096];
                snprintf(_si_27, 4096, "pact_list_set(%s, %s, (void*)%s);", obj_str, idx_str, val_str2);
                pact_emit_line(strdup(_si_27));
            }
            expr_result_str = "0";
            expr_result_type = CT_VOID;
            return;
        }
    }
    const char* struct_type = pact_get_var_struct(obj_str);
    if (((!pact_str_eq(struct_type, "")) && (pact_lookup_impl_method(struct_type, method) != 0))) {
        char _si_28[4096];
        snprintf(_si_28, 4096, "%s_%s", struct_type, method);
        const char* mangled = strdup(_si_28);
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        const char* args_str = obj_str;
        if ((args_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(args_sl))) {
                args_str = pact_str_concat(args_str, ", ");
                pact_emit_expr(pact_sublist_get(args_sl, i));
                args_str = pact_str_concat(args_str, expr_result_str);
                i = (i + 1);
            }
        }
        char _si_29[4096];
        snprintf(_si_29, 4096, "pact_%s(%s)", mangled, args_str);
        expr_result_str = strdup(_si_29);
        expr_result_type = pact_get_impl_method_ret(struct_type, method);
        return;
    }
    const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
    const char* args_str = "";
    if ((args_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(args_sl))) {
            if ((i > 0)) {
                args_str = pact_str_concat(args_str, ", ");
            }
            pact_emit_expr(pact_sublist_get(args_sl, i));
            args_str = pact_str_concat(args_str, expr_result_str);
            i = (i + 1);
        }
    }
    char _si_30[4096];
    snprintf(_si_30, 4096, "%s_%s(%s)", obj_str, method, args_str);
    expr_result_str = strdup(_si_30);
    expr_result_type = CT_VOID;
}

const char* pact_escape_c_string(const char* s) {
    const char* result = "";
    int64_t i = 0;
    while ((i < pact_str_len(s))) {
        const int64_t ch = pact_str_char_at(s, i);
        if ((ch == 92)) {
            result = pact_str_concat(result, "\\\\");
        } else if ((ch == 34)) {
            result = pact_str_concat(result, "\\\"");
        } else {
            if ((ch == 10)) {
                result = pact_str_concat(result, "\\n");
            } else if ((ch == 9)) {
                result = pact_str_concat(result, "\\t");
            } else {
                result = pact_str_concat(result, pact_str_substr(s, i, 1));
            }
        }
        i = (i + 1);
    }
    return result;
}

void pact_emit_interp_string(int64_t node) {
    const int64_t parts_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
    if ((parts_sl == (-1))) {
        expr_result_str = "\"\"";
        expr_result_type = CT_STRING;
        return;
    }
    int64_t all_literal = 1;
    int64_t ai = 0;
    while ((ai < pact_sublist_length(parts_sl))) {
        const int64_t part = pact_sublist_get(parts_sl, ai);
        const int64_t pk = (int64_t)(intptr_t)pact_list_get(np_kind, part);
        if ((!((pk == pact_NodeKind_Ident) && pact_str_eq((const char*)pact_list_get(np_str_val, part), (const char*)pact_list_get(np_name, part))))) {
            all_literal = 0;
        }
        ai = (ai + 1);
    }
    if ((all_literal != 0)) {
        const char* concat_str = "";
        int64_t ci = 0;
        while ((ci < pact_sublist_length(parts_sl))) {
            const int64_t part = pact_sublist_get(parts_sl, ci);
            concat_str = pact_str_concat(concat_str, pact_escape_c_string((const char*)pact_list_get(np_str_val, part)));
            ci = (ci + 1);
        }
        expr_result_str = pact_str_concat(pact_str_concat("\"", concat_str), "\"");
        expr_result_type = CT_STRING;
        return;
    }
    const char* buf_name = pact_fresh_temp("_si_");
    char _si_0[4096];
    snprintf(_si_0, 4096, "char %s[4096];", buf_name);
    pact_emit_line(strdup(_si_0));
    const char* fmt = "";
    const char* args = "";
    int64_t has_args = 0;
    int64_t i = 0;
    while ((i < pact_sublist_length(parts_sl))) {
        const int64_t part = pact_sublist_get(parts_sl, i);
        const int64_t pk = (int64_t)(intptr_t)pact_list_get(np_kind, part);
        if (((pk == pact_NodeKind_Ident) && pact_str_eq((const char*)pact_list_get(np_str_val, part), (const char*)pact_list_get(np_name, part)))) {
            fmt = pact_str_concat(fmt, pact_escape_c_string((const char*)pact_list_get(np_str_val, part)));
        } else {
            pact_emit_expr(part);
            const char* e_str = expr_result_str;
            const int64_t e_type = expr_result_type;
            if ((e_type == CT_INT)) {
                fmt = pact_str_concat(fmt, "%lld");
                if (has_args) {
                    args = pact_str_concat(args, ", ");
                }
                args = pact_str_concat(args, "(long long)");
                args = pact_str_concat(args, e_str);
                has_args = 1;
            } else if ((e_type == CT_FLOAT)) {
                fmt = pact_str_concat(fmt, "%g");
                if (has_args) {
                    args = pact_str_concat(args, ", ");
                }
                args = pact_str_concat(args, e_str);
                has_args = 1;
            } else {
                if ((e_type == CT_BOOL)) {
                    fmt = pact_str_concat(fmt, "%s");
                    if (has_args) {
                        args = pact_str_concat(args, ", ");
                    }
                    args = pact_str_concat(args, e_str);
                    args = pact_str_concat(args, " ? \"true\" : \"false\"");
                    has_args = 1;
                } else {
                    fmt = pact_str_concat(fmt, "%s");
                    if (has_args) {
                        args = pact_str_concat(args, ", ");
                    }
                    args = pact_str_concat(args, e_str);
                    has_args = 1;
                }
            }
        }
        i = (i + 1);
    }
    if (has_args) {
        const char* line = pact_str_concat(pact_str_concat(pact_str_concat(pact_str_concat(pact_str_concat(pact_str_concat("snprintf(", buf_name), ", 4096, \""), fmt), "\", "), args), ");");
        pact_emit_line(line);
    } else {
        const char* line = pact_str_concat(pact_str_concat(pact_str_concat(pact_str_concat("snprintf(", buf_name), ", 4096, \""), fmt), "\");");
        pact_emit_line(line);
    }
    expr_result_str = pact_str_concat(pact_str_concat("strdup(", buf_name), ")");
    expr_result_type = CT_STRING;
}

void pact_emit_list_lit(int64_t node) {
    const char* tmp = pact_fresh_temp("_l");
    char _si_0[4096];
    snprintf(_si_0, 4096, "pact_list* %s = pact_list_new();", tmp);
    pact_emit_line(strdup(_si_0));
    const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
    if ((elems_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(elems_sl))) {
            pact_emit_expr(pact_sublist_get(elems_sl, i));
            const char* e_str = expr_result_str;
            const int64_t e_type = expr_result_type;
            if ((e_type == CT_INT)) {
                char _si_1[4096];
                snprintf(_si_1, 4096, "pact_list_push(%s, (void*)(intptr_t)%s);", tmp, e_str);
                pact_emit_line(strdup(_si_1));
            } else {
                char _si_2[4096];
                snprintf(_si_2, 4096, "pact_list_push(%s, (void*)%s);", tmp, e_str);
                pact_emit_line(strdup(_si_2));
            }
            i = (i + 1);
        }
    }
    expr_result_str = tmp;
    expr_result_type = CT_LIST;
}

const char* pact_infer_struct_type_args(const char* type_name, pact_list* field_types) {
    const int64_t types_sl = (int64_t)(intptr_t)pact_list_get(np_fields, cg_program_node);
    if ((types_sl == (-1))) {
        return "";
    }
    int64_t td = (-1);
    int64_t ti = 0;
    while ((ti < pact_sublist_length(types_sl))) {
        const int64_t candidate = pact_sublist_get(types_sl, ti);
        if (pact_str_eq((const char*)pact_list_get(np_name, candidate), type_name)) {
            td = candidate;
        }
        ti = (ti + 1);
    }
    if ((td == (-1))) {
        return "";
    }
    const int64_t tparams_sl = (int64_t)(intptr_t)pact_list_get(np_type_params, td);
    if ((tparams_sl == (-1))) {
        return "";
    }
    const int64_t num_params = pact_sublist_length(tparams_sl);
    if ((num_params == 0)) {
        return "";
    }
    const int64_t td_flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, td);
    if ((td_flds_sl == (-1))) {
        return "";
    }
    const char* args = "";
    int64_t pi = 0;
    while ((pi < num_params)) {
        const char* param_name = (const char*)pact_list_get(np_name, pact_sublist_get(tparams_sl, pi));
        const char* resolved = "Void";
        int64_t fi = 0;
        while (((fi < pact_sublist_length(td_flds_sl)) && (fi < pact_list_len(field_types)))) {
            const int64_t f = pact_sublist_get(td_flds_sl, fi);
            const int64_t type_ann_node = (int64_t)(intptr_t)pact_list_get(np_value, f);
            if ((type_ann_node != (-1))) {
                if (pact_str_eq((const char*)pact_list_get(np_name, type_ann_node), param_name)) {
                    resolved = pact_type_name_from_ct((int64_t)(intptr_t)pact_list_get(field_types, fi));
                }
            }
            fi = (fi + 1);
        }
        if ((pi > 0)) {
            args = pact_str_concat(args, ",");
        }
        args = pact_str_concat(args, resolved);
        pi = (pi + 1);
    }
    return args;
}

void pact_emit_struct_lit(int64_t node) {
    const char* sname = (const char*)pact_list_get(np_type_name, node);
    char _si_0[4096];
    snprintf(_si_0, 4096, "pact_%s", sname);
    const char* c_type = strdup(_si_0);
    const char* tmp = pact_fresh_temp("_s");
    const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, node);
    const char* inits = "";
    pact_list* _l1 = pact_list_new();
    pact_list* field_types = _l1;
    if ((flds_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(flds_sl))) {
            const int64_t sf = pact_sublist_get(flds_sl, i);
            const char* fname = (const char*)pact_list_get(np_name, sf);
            pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_value, sf));
            const char* val_str = expr_result_str;
            pact_list_push(field_types, (void*)(intptr_t)expr_result_type);
            if ((i > 0)) {
                inits = pact_str_concat(inits, ", ");
            }
            char _si_2[4096];
            snprintf(_si_2, 4096, ".%s = %s", fname, val_str);
            inits = pact_str_concat(inits, strdup(_si_2));
            i = (i + 1);
        }
    }
    const char* type_args = pact_infer_struct_type_args(sname, field_types);
    const char* struct_key = sname;
    if ((!pact_str_eq(type_args, ""))) {
        const char* mono_name = pact_register_mono_instance(sname, type_args);
        char _si_3[4096];
        snprintf(_si_3, 4096, "pact_%s", mono_name);
        c_type = strdup(_si_3);
        struct_key = mono_name;
        pact_register_mono_field_types(sname, mono_name, type_args);
    }
    char _si_4[4096];
    snprintf(_si_4, 4096, "%s %s = { %s };", c_type, tmp, inits);
    pact_emit_line(strdup(_si_4));
    pact_set_var_struct(tmp, struct_key);
    expr_result_str = tmp;
    expr_result_type = CT_VOID;
}

int64_t pact_list_contains_str(pact_list* lst, const char* val) {
    int64_t i = 0;
    while ((i < pact_list_len(lst))) {
        if (((int64_t)(intptr_t)pact_list_get(lst, i) == val)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_is_in_scope(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(scope_names))) {
        if (pact_str_eq((const char*)pact_list_get(scope_names, i), name)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

void pact_collect_free_vars(int64_t node, pact_list* params, pact_list* locals, pact_list* result) {
    if ((node == (-1))) {
        return;
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_Ident)) {
        const char* name = (const char*)pact_list_get(np_name, node);
        if (pact_list_contains_str(params, name)) {
            return;
        }
        if (pact_list_contains_str(locals, name)) {
            return;
        }
        if (pact_list_contains_str(result, name)) {
            return;
        }
        if (pact_is_emitted_fn(name)) {
            return;
        }
        if ((!pact_str_eq(pact_resolve_variant(name), ""))) {
            return;
        }
        if ((pact_is_enum_type(name) != 0)) {
            return;
        }
        if ((pact_is_struct_type(name) != 0)) {
            return;
        }
        int64_t fi = 0;
        int64_t is_fn_reg = 0;
        while ((fi < pact_list_len(fn_reg_names))) {
            if (pact_str_eq((const char*)pact_list_get(fn_reg_names, fi), name)) {
                is_fn_reg = 1;
            }
            fi = (fi + 1);
        }
        if (is_fn_reg) {
            return;
        }
        if (pact_is_in_scope(name)) {
            pact_list_push(result, (void*)name);
        }
        return;
    }
    if ((kind == pact_NodeKind_BinOp)) {
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_left, node), params, locals, result);
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_right, node), params, locals, result);
        return;
    }
    if ((kind == pact_NodeKind_UnaryOp)) {
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_left, node), params, locals, result);
        return;
    }
    if ((kind == pact_NodeKind_Call)) {
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_left, node), params, locals, result);
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if ((args_sl != (-1))) {
            int64_t ai = 0;
            while ((ai < pact_sublist_length(args_sl))) {
                pact_collect_free_vars(pact_sublist_get(args_sl, ai), params, locals, result);
                ai = (ai + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_MethodCall)) {
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_obj, node), params, locals, result);
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if ((args_sl != (-1))) {
            int64_t ai = 0;
            while ((ai < pact_sublist_length(args_sl))) {
                pact_collect_free_vars(pact_sublist_get(args_sl, ai), params, locals, result);
                ai = (ai + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_IfExpr)) {
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_condition, node), params, locals, result);
        pact_collect_free_vars_block((int64_t)(intptr_t)pact_list_get(np_then_body, node), params, locals, result);
        pact_collect_free_vars_block((int64_t)(intptr_t)pact_list_get(np_else_body, node), params, locals, result);
        return;
    }
    if ((kind == pact_NodeKind_Block)) {
        pact_collect_free_vars_block(node, params, locals, result);
        return;
    }
    if ((kind == pact_NodeKind_LetBinding)) {
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_value, node), params, locals, result);
        const char* bound_name = (const char*)pact_list_get(np_name, node);
        if ((!pact_list_contains_str(locals, bound_name))) {
            pact_list_push(locals, (void*)bound_name);
        }
        return;
    }
    if ((kind == pact_NodeKind_ForIn)) {
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_iterable, node), params, locals, result);
        const char* vn = (const char*)pact_list_get(np_var_name, node);
        pact_list* _l0 = pact_list_new();
        pact_list* inner_locals = _l0;
        int64_t li = 0;
        while ((li < pact_list_len(locals))) {
            pact_list_push(inner_locals, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(locals, li));
            li = (li + 1);
        }
        pact_list_push(inner_locals, (void*)vn);
        pact_collect_free_vars_block((int64_t)(intptr_t)pact_list_get(np_body, node), params, inner_locals, result);
        return;
    }
    if ((kind == pact_NodeKind_WhileLoop)) {
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_condition, node), params, locals, result);
        pact_collect_free_vars_block((int64_t)(intptr_t)pact_list_get(np_body, node), params, locals, result);
        return;
    }
    if ((kind == pact_NodeKind_LoopExpr)) {
        pact_collect_free_vars_block((int64_t)(intptr_t)pact_list_get(np_body, node), params, locals, result);
        return;
    }
    if ((kind == pact_NodeKind_Return)) {
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_value, node), params, locals, result);
        return;
    }
    if ((kind == pact_NodeKind_ExprStmt)) {
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_value, node), params, locals, result);
        return;
    }
    if ((kind == pact_NodeKind_Assignment)) {
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_target, node), params, locals, result);
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_value, node), params, locals, result);
        return;
    }
    if ((kind == pact_NodeKind_CompoundAssign)) {
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_target, node), params, locals, result);
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_value, node), params, locals, result);
        return;
    }
    if ((kind == pact_NodeKind_MatchExpr)) {
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_scrutinee, node), params, locals, result);
        const int64_t arms_sl = (int64_t)(intptr_t)pact_list_get(np_arms, node);
        if ((arms_sl != (-1))) {
            int64_t ai = 0;
            while ((ai < pact_sublist_length(arms_sl))) {
                const int64_t arm = pact_sublist_get(arms_sl, ai);
                pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_guard, arm), params, locals, result);
                pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_body, arm), params, locals, result);
                ai = (ai + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_FieldAccess)) {
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_obj, node), params, locals, result);
        return;
    }
    if ((kind == pact_NodeKind_IndexExpr)) {
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_obj, node), params, locals, result);
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_index, node), params, locals, result);
        return;
    }
    if ((kind == pact_NodeKind_InterpString)) {
        const int64_t parts_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        if ((parts_sl != (-1))) {
            int64_t pi = 0;
            while ((pi < pact_sublist_length(parts_sl))) {
                const int64_t part = pact_sublist_get(parts_sl, pi);
                if ((((int64_t)(intptr_t)pact_list_get(np_kind, part) != pact_NodeKind_Ident) || pact_str_eq((const char*)pact_list_get(np_str_val, part), ""))) {
                    pact_collect_free_vars(part, params, locals, result);
                }
                pi = (pi + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_Closure)) {
        return;
    }
    if ((kind == pact_NodeKind_ListLit)) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        if ((elems_sl != (-1))) {
            int64_t ei = 0;
            while ((ei < pact_sublist_length(elems_sl))) {
                pact_collect_free_vars(pact_sublist_get(elems_sl, ei), params, locals, result);
                ei = (ei + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_StructLit)) {
        const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, node);
        if ((flds_sl != (-1))) {
            int64_t fi = 0;
            while ((fi < pact_sublist_length(flds_sl))) {
                const int64_t sf = pact_sublist_get(flds_sl, fi);
                pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_value, sf), params, locals, result);
                fi = (fi + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_TupleLit)) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        if ((elems_sl != (-1))) {
            int64_t ei = 0;
            while ((ei < pact_sublist_length(elems_sl))) {
                pact_collect_free_vars(pact_sublist_get(elems_sl, ei), params, locals, result);
                ei = (ei + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_RangeLit)) {
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_start, node), params, locals, result);
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_end, node), params, locals, result);
        return;
    }
    if ((kind == pact_NodeKind_WithBlock)) {
        const int64_t wh_sl = (int64_t)(intptr_t)pact_list_get(np_handlers, node);
        if ((wh_sl != (-1))) {
            int64_t hi = 0;
            while ((hi < pact_sublist_length(wh_sl))) {
                const int64_t hitem = pact_sublist_get(wh_sl, hi);
                if (((int64_t)(intptr_t)pact_list_get(np_kind, hitem) == pact_NodeKind_WithResource)) {
                    pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_value, hitem), params, locals, result);
                } else {
                    pact_collect_free_vars(hitem, params, locals, result);
                }
                hi = (hi + 1);
            }
        }
        pact_collect_free_vars_block((int64_t)(intptr_t)pact_list_get(np_body, node), params, locals, result);
        return;
    }
    if ((kind == pact_NodeKind_WithResource)) {
        pact_collect_free_vars((int64_t)(intptr_t)pact_list_get(np_value, node), params, locals, result);
        return;
    }
}

void pact_collect_free_vars_block(int64_t block, pact_list* params, pact_list* locals, pact_list* result) {
    if ((block == (-1))) {
        return;
    }
    const int64_t stmts_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, block);
    if ((stmts_sl == (-1))) {
        return;
    }
    pact_list* _l0 = pact_list_new();
    pact_list* block_locals = _l0;
    int64_t li = 0;
    while ((li < pact_list_len(locals))) {
        pact_list_push(block_locals, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(locals, li));
        li = (li + 1);
    }
    int64_t si = 0;
    while ((si < pact_sublist_length(stmts_sl))) {
        pact_collect_free_vars(pact_sublist_get(stmts_sl, si), params, block_locals, result);
        si = (si + 1);
    }
}

pact_list* pact_analyze_captures(int64_t body, int64_t params_sl) {
    pact_list* _l0 = pact_list_new();
    pact_list* param_names = _l0;
    if ((params_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(params_sl))) {
            const int64_t p = pact_sublist_get(params_sl, i);
            pact_list_push(param_names, (void*)(const char*)pact_list_get(np_name, p));
            i = (i + 1);
        }
    }
    pact_list* _l1 = pact_list_new();
    pact_list* locals = _l1;
    pact_list* _l2 = pact_list_new();
    pact_list* result = _l2;
    pact_collect_free_vars_block(body, param_names, locals, result);
    return result;
}

void pact_emit_closure(int64_t node) {
    const int64_t closure_idx = cg_closure_counter;
    char _si_0[4096];
    snprintf(_si_0, 4096, "__closure_%lld", (long long)closure_idx);
    const char* cname = strdup(_si_0);
    cg_closure_counter = (cg_closure_counter + 1);
    const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, node);
    const char* ret_str = (const char*)pact_list_get(np_return_type, node);
    const int64_t ret_type = pact_type_from_name(ret_str);
    const pact_list* captures = pact_analyze_captures((int64_t)(intptr_t)pact_list_get(np_body, node), params_sl);
    const int64_t cap_start = pact_list_len(closure_capture_names);
    int64_t cap_i = 0;
    while ((cap_i < pact_list_len(captures))) {
        pact_list_push(closure_capture_names, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(captures, cap_i));
        cap_i = (cap_i + 1);
    }
    cap_i = 0;
    while ((cap_i < pact_list_len(captures))) {
        const char* cname_lookup = (const char*)pact_list_get(closure_capture_names, (cap_start + cap_i));
        const int64_t cap_ct = pact_get_var_type(cname_lookup);
        pact_list_push(closure_capture_types, (void*)(intptr_t)cap_ct);
        cap_i = (cap_i + 1);
    }
    pact_list_push(closure_capture_starts, (void*)(intptr_t)cap_start);
    pact_list_push(closure_capture_counts, (void*)(intptr_t)pact_list_len(captures));
    const int has_caps = (pact_list_len(captures) > 0);
    const char* params_c = "pact_closure* __self";
    if (((params_sl != (-1)) && (pact_sublist_length(params_sl) > 0))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(params_sl))) {
            const int64_t p = pact_sublist_get(params_sl, i);
            const char* pname = (const char*)pact_list_get(np_name, p);
            const char* ptype = (const char*)pact_list_get(np_type_name, p);
            params_c = pact_str_concat(params_c, ", ");
            if (pact_str_eq(ptype, "Fn")) {
                char _si_1[4096];
                snprintf(_si_1, 4096, "pact_closure* %s", pname);
                params_c = pact_str_concat(params_c, strdup(_si_1));
            } else if ((pact_is_enum_type(ptype) != 0)) {
                char _si_2[4096];
                snprintf(_si_2, 4096, "pact_%s %s", ptype, pname);
                params_c = pact_str_concat(params_c, strdup(_si_2));
            } else {
                if ((pact_is_struct_type(ptype) != 0)) {
                    char _si_3[4096];
                    snprintf(_si_3, 4096, "pact_%s %s", ptype, pname);
                    params_c = pact_str_concat(params_c, strdup(_si_3));
                } else {
                    const int64_t ct = pact_type_from_name(ptype);
                    char _si_4[4096];
                    snprintf(_si_4, 4096, "%s %s", pact_c_type_str(ct), pname);
                    params_c = pact_str_concat(params_c, strdup(_si_4));
                }
            }
            i = (i + 1);
        }
    }
    const pact_list* saved_lines = cg_lines;
    const int64_t saved_indent = cg_indent;
    const int64_t saved_temp = cg_temp_counter;
    const int64_t saved_cap_start = cg_closure_cap_start;
    const int64_t saved_cap_count = cg_closure_cap_count;
    pact_list* _l5 = pact_list_new();
    cg_lines = _l5;
    cg_indent = 0;
    cg_temp_counter = 0;
    cg_closure_cap_start = cap_start;
    cg_closure_cap_count = pact_list_len(captures);
    pact_push_scope();
    if ((params_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(params_sl))) {
            const int64_t p = pact_sublist_get(params_sl, i);
            const char* pname = (const char*)pact_list_get(np_name, p);
            const char* ptype = (const char*)pact_list_get(np_type_name, p);
            if (pact_str_eq(ptype, "Fn")) {
                pact_set_var(pname, CT_CLOSURE, 1);
                const int64_t ta = (int64_t)(intptr_t)pact_list_get(np_type_ann, p);
                if ((ta != (-1))) {
                    const char* sig_str = pact_build_closure_sig_from_type_ann(ta);
                    pact_set_var_closure(pname, sig_str);
                }
            } else {
                pact_set_var(pname, pact_type_from_name(ptype), 1);
                if ((pact_is_struct_type(ptype) != 0)) {
                    pact_set_var_struct(pname, ptype);
                }
                if ((pact_is_enum_type(ptype) != 0)) {
                    pact_list_push(var_enum_names, (void*)pname);
                    pact_list_push(var_enum_types, (void*)ptype);
                }
            }
            i = (i + 1);
        }
    }
    char _si_6[4096];
    snprintf(_si_6, 4096, "static %s %s(%s) {", pact_c_type_str(ret_type), cname, params_c);
    pact_emit_line(strdup(_si_6));
    cg_indent = (cg_indent + 1);
    pact_emit_fn_body((int64_t)(intptr_t)pact_list_get(np_body, node), ret_type);
    cg_indent = (cg_indent - 1);
    pact_emit_line("}");
    pact_emit_line("");
    pact_pop_scope();
    const pact_list* closure_lines = cg_lines;
    cg_lines = saved_lines;
    cg_indent = saved_indent;
    cg_temp_counter = saved_temp;
    cg_closure_cap_start = saved_cap_start;
    cg_closure_cap_count = saved_cap_count;
    int64_t ci = 0;
    while ((ci < pact_list_len(closure_lines))) {
        pact_list_push(cg_closure_defs, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(closure_lines, ci));
        ci = (ci + 1);
    }
    const char* sig_params = "pact_closure*";
    if (((params_sl != (-1)) && (pact_sublist_length(params_sl) > 0))) {
        int64_t si = 0;
        while ((si < pact_sublist_length(params_sl))) {
            const int64_t sp = pact_sublist_get(params_sl, si);
            const char* sptype = (const char*)pact_list_get(np_type_name, sp);
            sig_params = pact_str_concat(sig_params, ", ");
            if (pact_str_eq(sptype, "Fn")) {
                sig_params = pact_str_concat(sig_params, "pact_closure*");
            } else if ((pact_is_enum_type(sptype) != 0)) {
                char _si_7[4096];
                snprintf(_si_7, 4096, "pact_%s", sptype);
                sig_params = pact_str_concat(sig_params, strdup(_si_7));
            } else {
                if ((pact_is_struct_type(sptype) != 0)) {
                    char _si_8[4096];
                    snprintf(_si_8, 4096, "pact_%s", sptype);
                    sig_params = pact_str_concat(sig_params, strdup(_si_8));
                } else {
                    sig_params = pact_str_concat(sig_params, pact_c_type_str(pact_type_from_name(sptype)));
                }
            }
            si = (si + 1);
        }
    }
    char _si_9[4096];
    snprintf(_si_9, 4096, "%s(*)(%s)", pact_c_type_str(ret_type), sig_params);
    expr_closure_sig = strdup(_si_9);
    if ((pact_list_len(captures) > 0)) {
        char _si_10[4096];
        snprintf(_si_10, 4096, "__caps_%lld", (long long)closure_idx);
        const char* caps_var = strdup(_si_10);
        char _si_11[4096];
        snprintf(_si_11, 4096, "void** %s = (void**)pact_alloc(sizeof(void*) * %lld);", caps_var, (long long)pact_list_len(captures));
        pact_emit_line(strdup(_si_11));
        int64_t ci2 = 0;
        while ((ci2 < pact_list_len(captures))) {
            const char* cap_name = (const char*)pact_list_get(closure_capture_names, (cap_start + ci2));
            const int64_t cap_type = (int64_t)(intptr_t)pact_list_get(closure_capture_types, (cap_start + ci2));
            if ((cap_type == CT_INT)) {
                char _si_12[4096];
                snprintf(_si_12, 4096, "%s[%lld] = (void*)(intptr_t)%s;", caps_var, (long long)ci2, cap_name);
                pact_emit_line(strdup(_si_12));
            } else if ((cap_type == CT_FLOAT)) {
                char _si_13[4096];
                snprintf(_si_13, 4096, "{double* __fp_%lld_%lld = (double*)pact_alloc(sizeof(double)); *__fp_%lld_%lld = %s; %s[%lld] = (void*)__fp_%lld_%lld;}", (long long)closure_idx, (long long)ci2, (long long)closure_idx, (long long)ci2, cap_name, caps_var, (long long)ci2, (long long)closure_idx, (long long)ci2);
                pact_emit_line(strdup(_si_13));
            } else {
                if ((cap_type == CT_BOOL)) {
                    char _si_14[4096];
                    snprintf(_si_14, 4096, "%s[%lld] = (void*)(intptr_t)%s;", caps_var, (long long)ci2, cap_name);
                    pact_emit_line(strdup(_si_14));
                } else {
                    char _si_15[4096];
                    snprintf(_si_15, 4096, "%s[%lld] = (void*)%s;", caps_var, (long long)ci2, cap_name);
                    pact_emit_line(strdup(_si_15));
                }
            }
            ci2 = (ci2 + 1);
        }
        char _si_16[4096];
        snprintf(_si_16, 4096, "pact_closure_new((void*)%s, %s, %lld)", cname, caps_var, (long long)pact_list_len(captures));
        expr_result_str = strdup(_si_16);
    } else {
        char _si_17[4096];
        snprintf(_si_17, 4096, "pact_closure_new((void*)%s, NULL, 0)", cname);
        expr_result_str = strdup(_si_17);
    }
    expr_result_type = CT_CLOSURE;
}

void pact_emit_if_expr(int64_t node) {
    const char* tmp = pact_fresh_temp("_if_");
    const int64_t then_type = pact_infer_block_type((int64_t)(intptr_t)pact_list_get(np_then_body, node));
    char _si_0[4096];
    snprintf(_si_0, 4096, "%s %s;", pact_c_type_str(then_type), tmp);
    pact_emit_line(strdup(_si_0));
    pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_condition, node));
    const char* cond_str = expr_result_str;
    char _si_1[4096];
    snprintf(_si_1, 4096, "if (%s) {", cond_str);
    pact_emit_line(strdup(_si_1));
    cg_indent = (cg_indent + 1);
    const char* then_val = pact_emit_block_value((int64_t)(intptr_t)pact_list_get(np_then_body, node));
    char _si_2[4096];
    snprintf(_si_2, 4096, "%s = %s;", tmp, then_val);
    pact_emit_line(strdup(_si_2));
    cg_indent = (cg_indent - 1);
    if (((int64_t)(intptr_t)pact_list_get(np_else_body, node) != (-1))) {
        pact_emit_line("} else {");
        cg_indent = (cg_indent + 1);
        const char* else_val = pact_emit_block_value((int64_t)(intptr_t)pact_list_get(np_else_body, node));
        char _si_3[4096];
        snprintf(_si_3, 4096, "%s = %s;", tmp, else_val);
        pact_emit_line(strdup(_si_3));
        cg_indent = (cg_indent - 1);
    }
    pact_emit_line("}");
    pact_set_var(tmp, then_type, 1);
    expr_result_str = tmp;
    expr_result_type = then_type;
}

void pact_emit_match_expr(int64_t node) {
    const int64_t scrut = (int64_t)(intptr_t)pact_list_get(np_scrutinee, node);
    pact_list* _l0 = pact_list_new();
    match_scrut_strs = _l0;
    pact_list* _l1 = pact_list_new();
    match_scrut_types = _l1;
    match_scrut_enum = "";
    if (((int64_t)(intptr_t)pact_list_get(np_kind, scrut) == pact_NodeKind_TupleLit)) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, scrut);
        if ((elems_sl != (-1))) {
            int64_t ei = 0;
            while ((ei < pact_sublist_length(elems_sl))) {
                pact_emit_expr(pact_sublist_get(elems_sl, ei));
                const char* tmp = pact_fresh_temp("_tup_");
                char _si_2[4096];
                snprintf(_si_2, 4096, "%s %s = %s;", pact_c_type_str(expr_result_type), tmp, expr_result_str);
                pact_emit_line(strdup(_si_2));
                pact_set_var(tmp, expr_result_type, 1);
                pact_list_push(match_scrut_strs, (void*)tmp);
                pact_list_push(match_scrut_types, (void*)(intptr_t)expr_result_type);
                ei = (ei + 1);
            }
        }
    } else {
        if (((int64_t)(intptr_t)pact_list_get(np_kind, scrut) == pact_NodeKind_Ident)) {
            match_scrut_enum = pact_get_var_enum((const char*)pact_list_get(np_name, scrut));
        } else if (((int64_t)(intptr_t)pact_list_get(np_kind, scrut) == pact_NodeKind_FieldAccess)) {
            match_scrut_enum = pact_infer_enum_from_node(scrut);
        }
        pact_emit_expr(scrut);
        pact_list_push(match_scrut_strs, (void*)expr_result_str);
        pact_list_push(match_scrut_types, (void*)(intptr_t)expr_result_type);
    }
    const int64_t arms_sl = (int64_t)(intptr_t)pact_list_get(np_arms, node);
    if ((arms_sl == (-1))) {
        expr_result_str = "0";
        expr_result_type = CT_VOID;
        return;
    }
    const int64_t first_arm = pact_sublist_get(arms_sl, 0);
    const int64_t result_type = pact_infer_arm_type(first_arm);
    const char* result_var = pact_fresh_temp("_match_");
    char _si_3[4096];
    snprintf(_si_3, 4096, "%s %s;", pact_c_type_str(result_type), result_var);
    pact_emit_line(strdup(_si_3));
    int64_t has_guards = 0;
    int64_t gi = 0;
    while ((gi < pact_sublist_length(arms_sl))) {
        if (((int64_t)(intptr_t)pact_list_get(np_guard, pact_sublist_get(arms_sl, gi)) != (-1))) {
            has_guards = 1;
        }
        gi = (gi + 1);
    }
    if (has_guards) {
        pact_emit_line("int _mg_ = 0;");
    }
    int64_t first = 1;
    int64_t i = 0;
    while ((i < pact_sublist_length(arms_sl))) {
        const int64_t arm = pact_sublist_get(arms_sl, i);
        const int64_t pat = (int64_t)(intptr_t)pact_list_get(np_pattern, arm);
        const char* pat_cond = pact_pattern_condition(pat, 0, pact_list_len(match_scrut_strs));
        const int64_t guard_node = (int64_t)(intptr_t)pact_list_get(np_guard, arm);
        const int is_wildcard = (pact_str_eq(pat_cond, "") && (guard_node == (-1)));
        if (has_guards) {
            if (pact_str_eq(pat_cond, "")) {
                if (first) {
                    pact_emit_line("if (!_mg_) {");
                } else {
                    pact_emit_line("} if (!_mg_) {");
                }
            } else if (first) {
                char _si_4[4096];
                snprintf(_si_4, 4096, "if (!_mg_ && %s) {", pat_cond);
                pact_emit_line(strdup(_si_4));
            } else {
                char _si_5[4096];
                snprintf(_si_5, 4096, "} if (!_mg_ && %s) {", pat_cond);
                pact_emit_line(strdup(_si_5));
            }
            cg_indent = (cg_indent + 1);
            pact_bind_pattern_vars(pat, 0, pact_list_len(match_scrut_strs));
            if ((guard_node != (-1))) {
                pact_emit_expr(guard_node);
                const char* guard_str = expr_result_str;
                char _si_6[4096];
                snprintf(_si_6, 4096, "if (%s) {", guard_str);
                pact_emit_line(strdup(_si_6));
                cg_indent = (cg_indent + 1);
                const char* arm_val = pact_emit_arm_value((int64_t)(intptr_t)pact_list_get(np_body, arm));
                char _si_7[4096];
                snprintf(_si_7, 4096, "%s = %s;", result_var, arm_val);
                pact_emit_line(strdup(_si_7));
                pact_emit_line("_mg_ = 1;");
                cg_indent = (cg_indent - 1);
                pact_emit_line("}");
            } else {
                const char* arm_val = pact_emit_arm_value((int64_t)(intptr_t)pact_list_get(np_body, arm));
                char _si_8[4096];
                snprintf(_si_8, 4096, "%s = %s;", result_var, arm_val);
                pact_emit_line(strdup(_si_8));
                pact_emit_line("_mg_ = 1;");
            }
            cg_indent = (cg_indent - 1);
        } else {
            if (is_wildcard) {
                if (first) {
                    pact_emit_line("{");
                } else {
                    pact_emit_line("} else {");
                }
            } else if (first) {
                char _si_9[4096];
                snprintf(_si_9, 4096, "if (%s) {", pat_cond);
                pact_emit_line(strdup(_si_9));
            } else {
                char _si_10[4096];
                snprintf(_si_10, 4096, "} else if (%s) {", pat_cond);
                pact_emit_line(strdup(_si_10));
            }
            cg_indent = (cg_indent + 1);
            pact_bind_pattern_vars(pat, 0, pact_list_len(match_scrut_strs));
            const char* arm_val = pact_emit_arm_value((int64_t)(intptr_t)pact_list_get(np_body, arm));
            char _si_11[4096];
            snprintf(_si_11, 4096, "%s = %s;", result_var, arm_val);
            pact_emit_line(strdup(_si_11));
            cg_indent = (cg_indent - 1);
        }
        first = 0;
        i = (i + 1);
    }
    pact_emit_line("}");
    pact_set_var(result_var, result_type, 1);
    expr_result_str = result_var;
    expr_result_type = result_type;
}

const char* pact_pattern_condition(int64_t pat, int64_t scrut_off, int64_t scrut_len) {
    const int64_t pk = (int64_t)(intptr_t)pact_list_get(np_kind, pat);
    if ((pk == pact_NodeKind_WildcardPattern)) {
        return "";
    }
    if ((pk == pact_NodeKind_IdentPattern)) {
        const char* pat_name = (const char*)pact_list_get(np_name, pat);
        const char* enum_name = match_scrut_enum;
        if (pact_str_eq(enum_name, "")) {
            enum_name = pact_resolve_variant(pat_name);
        }
        if ((!pact_str_eq(enum_name, ""))) {
            char _si_0[4096];
            snprintf(_si_0, 4096, "(%s == pact_%s_%s)", (const char*)pact_list_get(match_scrut_strs, scrut_off), enum_name, pat_name);
            return strdup(_si_0);
        }
        return "";
    }
    if ((pk == pact_NodeKind_IntPattern)) {
        const char* pat_val = (const char*)pact_list_get(np_str_val, pat);
        char _si_1[4096];
        snprintf(_si_1, 4096, "(%s == %s)", (const char*)pact_list_get(match_scrut_strs, scrut_off), pat_val);
        return strdup(_si_1);
    }
    if ((pk == pact_NodeKind_StringPattern)) {
        const char* pat_val = (const char*)pact_list_get(np_str_val, pat);
        char _si_2[4096];
        snprintf(_si_2, 4096, "(pact_str_eq(%s, \"%s\"))", (const char*)pact_list_get(match_scrut_strs, scrut_off), pat_val);
        return strdup(_si_2);
    }
    if ((pk == pact_NodeKind_RangePattern)) {
        const char* lo = (const char*)pact_list_get(np_str_val, pat);
        const char* hi = (const char*)pact_list_get(np_name, pat);
        const char* scrut = (const char*)pact_list_get(match_scrut_strs, scrut_off);
        if (((int64_t)(intptr_t)pact_list_get(np_inclusive, pat) != 0)) {
            char _si_3[4096];
            snprintf(_si_3, 4096, "(%s >= %s && %s <= %s)", scrut, lo, scrut, hi);
            return strdup(_si_3);
        }
        char _si_4[4096];
        snprintf(_si_4, 4096, "(%s >= %s && %s < %s)", scrut, lo, scrut, hi);
        return strdup(_si_4);
    }
    if ((pk == pact_NodeKind_EnumPattern)) {
        const char* enum_name = (const char*)pact_list_get(np_name, pat);
        const char* variant_name = (const char*)pact_list_get(np_type_name, pat);
        if ((!pact_str_eq(variant_name, ""))) {
            char _si_5[4096];
            snprintf(_si_5, 4096, "(%s == pact_%s_%s)", (const char*)pact_list_get(match_scrut_strs, scrut_off), enum_name, variant_name);
            return strdup(_si_5);
        }
        return "";
    }
    if ((pk == pact_NodeKind_StructPattern)) {
        const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, pat);
        if ((flds_sl == (-1))) {
            return "";
        }
        const char* parts = "";
        int64_t parts_n = 0;
        const char* scrut = (const char*)pact_list_get(match_scrut_strs, scrut_off);
        int64_t j = 0;
        while ((j < pact_sublist_length(flds_sl))) {
            const int64_t sf = pact_sublist_get(flds_sl, j);
            const char* fname = (const char*)pact_list_get(np_name, sf);
            const int64_t fpat = (int64_t)(intptr_t)pact_list_get(np_pattern, sf);
            if ((fpat != (-1))) {
                const pact_list* saved_strs = match_scrut_strs;
                const pact_list* saved_types = match_scrut_types;
                pact_list* _l6 = pact_list_new();
                char _si_7[4096];
                snprintf(_si_7, 4096, "%s.%s", scrut, fname);
                pact_list_push(_l6, (void*)strdup(_si_7));
                match_scrut_strs = _l6;
                pact_list* _l8 = pact_list_new();
                pact_list_push(_l8, (void*)(intptr_t)CT_VOID);
                match_scrut_types = _l8;
                const char* sub_cond = pact_pattern_condition(fpat, 0, 1);
                match_scrut_strs = saved_strs;
                match_scrut_types = saved_types;
                if ((!pact_str_eq(sub_cond, ""))) {
                    if ((parts_n > 0)) {
                        parts = pact_str_concat(parts, " && ");
                    }
                    parts = pact_str_concat(parts, sub_cond);
                    parts_n = (parts_n + 1);
                }
            }
            j = (j + 1);
        }
        return parts;
    }
    if ((pk == pact_NodeKind_OrPattern)) {
        const int64_t alts_sl = (int64_t)(intptr_t)pact_list_get(np_elements, pat);
        if ((alts_sl == (-1))) {
            return "";
        }
        const char* parts = "";
        int64_t parts_n = 0;
        int64_t j = 0;
        while ((j < pact_sublist_length(alts_sl))) {
            const int64_t sub_pat = pact_sublist_get(alts_sl, j);
            const char* sub_cond = pact_pattern_condition(sub_pat, scrut_off, scrut_len);
            if ((!pact_str_eq(sub_cond, ""))) {
                if ((parts_n > 0)) {
                    parts = pact_str_concat(parts, " || ");
                }
                parts = pact_str_concat(parts, sub_cond);
                parts_n = (parts_n + 1);
            }
            j = (j + 1);
        }
        return parts;
    }
    if ((pk == pact_NodeKind_AsPattern)) {
        const int64_t inner = (int64_t)(intptr_t)pact_list_get(np_pattern, pat);
        return pact_pattern_condition(inner, scrut_off, scrut_len);
    }
    if ((pk == pact_NodeKind_TuplePattern)) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, pat);
        if ((elems_sl == (-1))) {
            return "";
        }
        const char* parts = "";
        int64_t parts_n = 0;
        int64_t j = 0;
        while ((j < pact_sublist_length(elems_sl))) {
            const int64_t sub_pat = pact_sublist_get(elems_sl, j);
            const char* sub_cond = pact_pattern_condition(sub_pat, (scrut_off + j), 1);
            if ((!pact_str_eq(sub_cond, ""))) {
                if ((parts_n > 0)) {
                    parts = pact_str_concat(parts, " && ");
                }
                parts = pact_str_concat(parts, sub_cond);
                parts_n = (parts_n + 1);
            }
            j = (j + 1);
        }
        return parts;
    }
    return "";
}

void pact_bind_pattern_vars(int64_t pat, int64_t scrut_off, int64_t scrut_len) {
    const int64_t pk = (int64_t)(intptr_t)pact_list_get(np_kind, pat);
    if ((pk == pact_NodeKind_EnumPattern)) {
        return;
    }
    if ((pk == pact_NodeKind_StringPattern)) {
        return;
    }
    if ((pk == pact_NodeKind_RangePattern)) {
        return;
    }
    if ((pk == pact_NodeKind_IntPattern)) {
        return;
    }
    if ((pk == pact_NodeKind_OrPattern)) {
        const int64_t alts_sl = (int64_t)(intptr_t)pact_list_get(np_elements, pat);
        if (((alts_sl != (-1)) && (pact_sublist_length(alts_sl) > 0))) {
            pact_bind_pattern_vars(pact_sublist_get(alts_sl, 0), scrut_off, scrut_len);
        }
        return;
    }
    if ((pk == pact_NodeKind_StructPattern)) {
        const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, pat);
        if ((flds_sl == (-1))) {
            return;
        }
        const char* scrut = (const char*)pact_list_get(match_scrut_strs, scrut_off);
        const char* stype_name = (const char*)pact_list_get(np_type_name, pat);
        int64_t j = 0;
        while ((j < pact_sublist_length(flds_sl))) {
            const int64_t sf = pact_sublist_get(flds_sl, j);
            const char* fname = (const char*)pact_list_get(np_name, sf);
            const int64_t fpat = (int64_t)(intptr_t)pact_list_get(np_pattern, sf);
            if ((fpat != (-1))) {
                const pact_list* saved_strs = match_scrut_strs;
                const pact_list* saved_types = match_scrut_types;
                pact_list* _l0 = pact_list_new();
                char _si_1[4096];
                snprintf(_si_1, 4096, "%s.%s", scrut, fname);
                pact_list_push(_l0, (void*)strdup(_si_1));
                match_scrut_strs = _l0;
                pact_list* _l2 = pact_list_new();
                pact_list_push(_l2, (void*)(intptr_t)CT_VOID);
                match_scrut_types = _l2;
                pact_bind_pattern_vars(fpat, 0, 1);
                match_scrut_strs = saved_strs;
                match_scrut_types = saved_types;
            } else {
                char _si_3[4096];
                snprintf(_si_3, 4096, "__typeof__(%s.%s) %s = %s.%s;", scrut, fname, fname, scrut, fname);
                pact_emit_line(strdup(_si_3));
                const int64_t ftype = pact_get_struct_field_type(stype_name, fname);
                const char* fstype = pact_get_struct_field_stype(stype_name, fname);
                pact_set_var(fname, ftype, 0);
                if ((!pact_str_eq(fstype, ""))) {
                    pact_set_var_struct(fname, fstype);
                }
            }
            j = (j + 1);
        }
        return;
    }
    if ((pk == pact_NodeKind_AsPattern)) {
        const char* bind_name = (const char*)pact_list_get(np_name, pat);
        const int64_t st = (int64_t)(intptr_t)pact_list_get(match_scrut_types, scrut_off);
        const char* scrut_str = (const char*)pact_list_get(match_scrut_strs, scrut_off);
        if ((!pact_str_eq(match_scrut_enum, ""))) {
            char _si_4[4096];
            snprintf(_si_4, 4096, "pact_%s %s = %s;", match_scrut_enum, bind_name, scrut_str);
            pact_emit_line(strdup(_si_4));
            pact_set_var(bind_name, CT_INT, 1);
            pact_list_push(var_enum_names, (void*)bind_name);
            pact_list_push(var_enum_types, (void*)match_scrut_enum);
        } else {
            char _si_5[4096];
            snprintf(_si_5, 4096, "%s %s = %s;", pact_c_type_str(st), bind_name, scrut_str);
            pact_emit_line(strdup(_si_5));
            pact_set_var(bind_name, st, 1);
        }
        pact_bind_pattern_vars((int64_t)(intptr_t)pact_list_get(np_pattern, pat), scrut_off, scrut_len);
        return;
    }
    if ((pk == pact_NodeKind_IdentPattern)) {
        const char* bind_name = (const char*)pact_list_get(np_name, pat);
        const char* enum_name = match_scrut_enum;
        if (pact_str_eq(enum_name, "")) {
            enum_name = pact_resolve_variant(bind_name);
        }
        if ((!pact_str_eq(enum_name, ""))) {
            return;
        }
        if ((scrut_len == 1)) {
            const int64_t st = (int64_t)(intptr_t)pact_list_get(match_scrut_types, scrut_off);
            char _si_6[4096];
            snprintf(_si_6, 4096, "%s %s = %s;", pact_c_type_str(st), bind_name, (const char*)pact_list_get(match_scrut_strs, scrut_off));
            pact_emit_line(strdup(_si_6));
            pact_set_var(bind_name, st, 1);
        }
        return;
    }
    if ((pk == pact_NodeKind_TuplePattern)) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, pat);
        if ((elems_sl != (-1))) {
            int64_t j = 0;
            while ((j < pact_sublist_length(elems_sl))) {
                const int64_t sub_pat = pact_sublist_get(elems_sl, j);
                pact_bind_pattern_vars(sub_pat, (scrut_off + j), 1);
                j = (j + 1);
            }
        }
        return;
    }
}

void pact_emit_block_expr(int64_t node) {
    const int64_t stmts_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, node);
    if ((stmts_sl == (-1))) {
        expr_result_str = "0";
        expr_result_type = CT_VOID;
        return;
    }
    const int64_t count = pact_sublist_length(stmts_sl);
    int64_t i = 0;
    while ((i < (count - 1))) {
        pact_emit_stmt(pact_sublist_get(stmts_sl, i));
        i = (i + 1);
    }
    if ((count > 0)) {
        const int64_t last = pact_sublist_get(stmts_sl, (count - 1));
        const int64_t last_kind = (int64_t)(intptr_t)pact_list_get(np_kind, last);
        if ((last_kind == pact_NodeKind_ExprStmt)) {
            pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_value, last));
            return;
        }
        pact_emit_stmt(last);
    }
    expr_result_str = "0";
    expr_result_type = CT_VOID;
}

const char* pact_emit_arm_value(int64_t body) {
    if ((body == (-1))) {
        return "0";
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, body);
    if ((kind == pact_NodeKind_Block)) {
        return pact_emit_block_value(body);
    }
    if ((kind == pact_NodeKind_ExprStmt)) {
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_value, body));
        return expr_result_str;
    }
    pact_emit_expr(body);
    return expr_result_str;
}

const char* pact_emit_block_value(int64_t block) {
    if ((block == (-1))) {
        return "0";
    }
    const int64_t stmts_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, block);
    if ((stmts_sl == (-1))) {
        return "0";
    }
    const int64_t count = pact_sublist_length(stmts_sl);
    if ((count == 0)) {
        return "0";
    }
    int64_t i = 0;
    while ((i < (count - 1))) {
        pact_emit_stmt(pact_sublist_get(stmts_sl, i));
        i = (i + 1);
    }
    const int64_t last = pact_sublist_get(stmts_sl, (count - 1));
    const int64_t last_kind = (int64_t)(intptr_t)pact_list_get(np_kind, last);
    if ((last_kind == pact_NodeKind_ExprStmt)) {
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_value, last));
        return expr_result_str;
    }
    if ((last_kind == pact_NodeKind_IfExpr)) {
        pact_emit_if_expr(last);
        return expr_result_str;
    }
    if ((last_kind == pact_NodeKind_Return)) {
        if (((int64_t)(intptr_t)pact_list_get(np_value, last) != (-1))) {
            pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_value, last));
            const char* val_s = expr_result_str;
            char _si_0[4096];
            snprintf(_si_0, 4096, "return %s;", val_s);
            pact_emit_line(strdup(_si_0));
        } else {
            pact_emit_line("return;");
        }
        return "0";
    }
    pact_emit_stmt(last);
    return "0";
}

int64_t pact_infer_block_type(int64_t block) {
    if ((block == (-1))) {
        return CT_VOID;
    }
    const int64_t stmts_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, block);
    if ((stmts_sl == (-1))) {
        return CT_VOID;
    }
    const int64_t count = pact_sublist_length(stmts_sl);
    if ((count == 0)) {
        return CT_VOID;
    }
    const int64_t last = pact_sublist_get(stmts_sl, (count - 1));
    const int64_t last_kind = (int64_t)(intptr_t)pact_list_get(np_kind, last);
    if ((last_kind == pact_NodeKind_ExprStmt)) {
        return pact_infer_expr_type((int64_t)(intptr_t)pact_list_get(np_value, last));
    }
    return CT_VOID;
}

int64_t pact_infer_arm_type(int64_t arm) {
    const int64_t body = (int64_t)(intptr_t)pact_list_get(np_body, arm);
    if ((body == (-1))) {
        return CT_VOID;
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, body);
    if ((kind == pact_NodeKind_Block)) {
        return pact_infer_block_type(body);
    }
    if ((kind == pact_NodeKind_ExprStmt)) {
        return pact_infer_expr_type((int64_t)(intptr_t)pact_list_get(np_value, body));
    }
    return pact_infer_expr_type(body);
}

int64_t pact_infer_expr_type(int64_t node) {
    if ((node == (-1))) {
        return CT_VOID;
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_IntLit)) {
        return CT_INT;
    }
    if ((kind == pact_NodeKind_FloatLit)) {
        return CT_FLOAT;
    }
    if ((kind == pact_NodeKind_BoolLit)) {
        return CT_BOOL;
    }
    if ((kind == pact_NodeKind_InterpString)) {
        return CT_STRING;
    }
    if ((kind == pact_NodeKind_ListLit)) {
        return CT_LIST;
    }
    if ((kind == pact_NodeKind_Ident)) {
        const char* iname = (const char*)pact_list_get(np_name, node);
        if ((!pact_str_eq(pact_resolve_variant(iname), ""))) {
            return CT_INT;
        }
        return pact_get_var_type(iname);
    }
    if ((kind == pact_NodeKind_FieldAccess)) {
        const int64_t fa_obj = (int64_t)(intptr_t)pact_list_get(np_obj, node);
        const char* fa_field = (const char*)pact_list_get(np_name, node);
        if (((int64_t)(intptr_t)pact_list_get(np_kind, fa_obj) == pact_NodeKind_Ident)) {
            const char* obj_name = (const char*)pact_list_get(np_name, fa_obj);
            if ((pact_is_enum_type(obj_name) != 0)) {
                return CT_INT;
            }
            const char* stype = pact_get_var_struct(obj_name);
            if ((!pact_str_eq(stype, ""))) {
                return pact_get_struct_field_type(stype, fa_field);
            }
        }
        return CT_VOID;
    }
    if ((kind == pact_NodeKind_IfExpr)) {
        return pact_infer_block_type((int64_t)(intptr_t)pact_list_get(np_then_body, node));
    }
    if ((kind == pact_NodeKind_Call)) {
        const int64_t func_node = (int64_t)(intptr_t)pact_list_get(np_left, node);
        if (((int64_t)(intptr_t)pact_list_get(np_kind, func_node) == pact_NodeKind_Ident)) {
            return pact_get_fn_ret((const char*)pact_list_get(np_name, func_node));
        }
    }
    if ((kind == pact_NodeKind_BinOp)) {
        const char* op = (const char*)pact_list_get(np_op, node);
        if ((((((((pact_str_eq(op, "==") || pact_str_eq(op, "!=")) || pact_str_eq(op, "<")) || pact_str_eq(op, ">")) || pact_str_eq(op, "<=")) || pact_str_eq(op, ">=")) || pact_str_eq(op, "&&")) || pact_str_eq(op, "||"))) {
            return CT_BOOL;
        }
        return pact_infer_expr_type((int64_t)(intptr_t)pact_list_get(np_left, node));
    }
    return CT_VOID;
}

void pact_emit_stmt(int64_t node) {
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_ExprStmt)) {
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_value, node));
        const char* s = expr_result_str;
        if (((!pact_str_eq(s, "")) && (!pact_str_eq(s, "0")))) {
            char _si_0[4096];
            snprintf(_si_0, 4096, "%s;", s);
            pact_emit_line(strdup(_si_0));
        }
        return;
    }
    if ((kind == pact_NodeKind_LetBinding)) {
        pact_emit_let_binding(node);
        return;
    }
    if ((kind == pact_NodeKind_Assignment)) {
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_target, node));
        const char* target_str = expr_result_str;
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_value, node));
        const char* val_str = expr_result_str;
        char _si_1[4096];
        snprintf(_si_1, 4096, "%s = %s;", target_str, val_str);
        pact_emit_line(strdup(_si_1));
        return;
    }
    if ((kind == pact_NodeKind_CompoundAssign)) {
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_target, node));
        const char* target_str = expr_result_str;
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_value, node));
        const char* val_str = expr_result_str;
        const char* op = (const char*)pact_list_get(np_op, node);
        char _si_2[4096];
        snprintf(_si_2, 4096, "%s %s= %s;", target_str, op, val_str);
        pact_emit_line(strdup(_si_2));
        return;
    }
    if ((kind == pact_NodeKind_Return)) {
        if (((int64_t)(intptr_t)pact_list_get(np_value, node) != (-1))) {
            pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_value, node));
            const char* val_str = expr_result_str;
            char _si_3[4096];
            snprintf(_si_3, 4096, "return %s;", val_str);
            pact_emit_line(strdup(_si_3));
        } else {
            pact_emit_line("return;");
        }
        return;
    }
    if ((kind == pact_NodeKind_ForIn)) {
        pact_emit_for_in(node);
        return;
    }
    if ((kind == pact_NodeKind_WhileLoop)) {
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_condition, node));
        const char* cond_str = expr_result_str;
        char _si_4[4096];
        snprintf(_si_4, 4096, "while (%s) {", cond_str);
        pact_emit_line(strdup(_si_4));
        cg_indent = (cg_indent + 1);
        pact_emit_block((int64_t)(intptr_t)pact_list_get(np_body, node));
        cg_indent = (cg_indent - 1);
        pact_emit_line("}");
        return;
    }
    if ((kind == pact_NodeKind_LoopExpr)) {
        pact_emit_line("while (1) {");
        cg_indent = (cg_indent + 1);
        pact_emit_block((int64_t)(intptr_t)pact_list_get(np_body, node));
        cg_indent = (cg_indent - 1);
        pact_emit_line("}");
        return;
    }
    if ((kind == pact_NodeKind_Break)) {
        pact_emit_line("break;");
        return;
    }
    if ((kind == pact_NodeKind_Continue)) {
        pact_emit_line("continue;");
        return;
    }
    if ((kind == pact_NodeKind_IfExpr)) {
        pact_emit_if_stmt(node);
        return;
    }
    if ((kind == pact_NodeKind_MatchExpr)) {
        pact_emit_match_expr(node);
        return;
    }
    if ((kind == pact_NodeKind_WithBlock)) {
        pact_emit_with_block(node);
        return;
    }
    pact_emit_expr(node);
    const char* s = expr_result_str;
    if ((!pact_str_eq(s, ""))) {
        char _si_5[4096];
        snprintf(_si_5, 4096, "%s;", s);
        pact_emit_line(strdup(_si_5));
    }
}

const char* pact_infer_enum_from_node(int64_t val_node) {
    const int64_t vk = (int64_t)(intptr_t)pact_list_get(np_kind, val_node);
    if ((vk == pact_NodeKind_FieldAccess)) {
        const int64_t obj = (int64_t)(intptr_t)pact_list_get(np_obj, val_node);
        if (((int64_t)(intptr_t)pact_list_get(np_kind, obj) == pact_NodeKind_Ident)) {
            const char* obj_name = (const char*)pact_list_get(np_name, obj);
            if ((pact_is_enum_type(obj_name) != 0)) {
                return obj_name;
            }
        }
    }
    if ((vk == pact_NodeKind_Ident)) {
        return pact_resolve_variant((const char*)pact_list_get(np_name, val_node));
    }
    return "";
}

void pact_emit_let_binding(int64_t node) {
    const int64_t val_node = (int64_t)(intptr_t)pact_list_get(np_value, node);
    const char* enum_type = pact_infer_enum_from_node(val_node);
    const int64_t type_ann = (int64_t)(intptr_t)pact_list_get(np_target, node);
    if ((pact_str_eq(enum_type, "") && (type_ann != (-1)))) {
        const char* ann_name = (const char*)pact_list_get(np_name, type_ann);
        if ((pact_is_enum_type(ann_name) != 0)) {
            enum_type = ann_name;
        }
    }
    const int64_t saved_let_target = cg_let_target_type;
    if ((type_ann != (-1))) {
        cg_let_target_type = pact_type_from_name((const char*)pact_list_get(np_name, type_ann));
    } else {
        cg_let_target_type = 0;
    }
    pact_emit_expr(val_node);
    cg_let_target_type = saved_let_target;
    const char* val_str = expr_result_str;
    const int64_t val_type = expr_result_type;
    const char* name = (const char*)pact_list_get(np_name, node);
    const int64_t is_mut = (int64_t)(intptr_t)pact_list_get(np_is_mut, node);
    pact_set_var(name, val_type, is_mut);
    if ((!pact_str_eq(enum_type, ""))) {
        pact_list_push(var_enum_names, (void*)name);
        pact_list_push(var_enum_types, (void*)enum_type);
    }
    if ((val_type == CT_CLOSURE)) {
        pact_set_var_closure(name, expr_closure_sig);
    }
    if ((val_type == CT_OPTION)) {
        pact_set_var_option(name, expr_option_inner);
    }
    if ((val_type == CT_RESULT)) {
        pact_set_var_result(name, expr_result_ok_type, expr_result_err_type);
    }
    if (((int64_t)(intptr_t)pact_list_get(np_kind, val_node) == pact_NodeKind_StructLit)) {
        const char* expr_struct = pact_get_var_struct(val_str);
        if ((!pact_str_eq(expr_struct, ""))) {
            pact_set_var_struct(name, expr_struct);
        } else {
            const char* sname = (const char*)pact_list_get(np_type_name, val_node);
            if ((pact_is_struct_type(sname) != 0)) {
                pact_set_var_struct(name, sname);
            }
        }
    } else if ((type_ann != (-1))) {
        const char* ann_name = (const char*)pact_list_get(np_name, type_ann);
        if ((pact_is_struct_type(ann_name) != 0)) {
            pact_set_var_struct(name, ann_name);
        }
    } else {
        const char* expr_struct = pact_get_var_struct(val_str);
        if ((!pact_str_eq(expr_struct, ""))) {
            pact_set_var_struct(name, expr_struct);
        }
    }
    if (((val_type == CT_LIST) && (type_ann != (-1)))) {
        const char* ann_name = (const char*)pact_list_get(np_name, type_ann);
        if (pact_str_eq(ann_name, "List")) {
            const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, type_ann);
            if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) > 0))) {
                const int64_t elem_ann = pact_sublist_get(elems_sl, 0);
                const char* elem_name = (const char*)pact_list_get(np_name, elem_ann);
                pact_set_list_elem_type(name, pact_type_from_name(elem_name));
            }
        }
    }
    const char* struct_type = pact_get_var_struct(name);
    if ((val_type == CT_OPTION)) {
        const int64_t opt_inner = pact_get_var_option_inner(name);
        const char* opt_c = pact_option_c_type(opt_inner);
        if ((is_mut != 0)) {
            char _si_0[4096];
            snprintf(_si_0, 4096, "%s %s = %s;", opt_c, name, val_str);
            pact_emit_line(strdup(_si_0));
        } else {
            char _si_1[4096];
            snprintf(_si_1, 4096, "const %s %s = %s;", opt_c, name, val_str);
            pact_emit_line(strdup(_si_1));
        }
    } else if ((val_type == CT_RESULT)) {
        const int64_t rok = pact_get_var_result_ok(name);
        const int64_t rerr = pact_get_var_result_err(name);
        const char* res_c = pact_result_c_type(rok, rerr);
        if ((is_mut != 0)) {
            char _si_2[4096];
            snprintf(_si_2, 4096, "%s %s = %s;", res_c, name, val_str);
            pact_emit_line(strdup(_si_2));
        } else {
            char _si_3[4096];
            snprintf(_si_3, 4096, "const %s %s = %s;", res_c, name, val_str);
            pact_emit_line(strdup(_si_3));
        }
    } else {
        if ((!pact_str_eq(enum_type, ""))) {
            if ((is_mut != 0)) {
                char _si_4[4096];
                snprintf(_si_4, 4096, "pact_%s %s = %s;", enum_type, name, val_str);
                pact_emit_line(strdup(_si_4));
            } else {
                char _si_5[4096];
                snprintf(_si_5, 4096, "const pact_%s %s = %s;", enum_type, name, val_str);
                pact_emit_line(strdup(_si_5));
            }
        } else if ((!pact_str_eq(struct_type, ""))) {
            if ((is_mut != 0)) {
                char _si_6[4096];
                snprintf(_si_6, 4096, "pact_%s %s = %s;", struct_type, name, val_str);
                pact_emit_line(strdup(_si_6));
            } else {
                char _si_7[4096];
                snprintf(_si_7, 4096, "const pact_%s %s = %s;", struct_type, name, val_str);
                pact_emit_line(strdup(_si_7));
            }
        } else {
            const char* ts = pact_c_type_str(val_type);
            if (((is_mut != 0) || (val_type == CT_STRING))) {
                char _si_8[4096];
                snprintf(_si_8, 4096, "%s %s = %s;", ts, name, val_str);
                pact_emit_line(strdup(_si_8));
            } else {
                char _si_9[4096];
                snprintf(_si_9, 4096, "const %s %s = %s;", ts, name, val_str);
                pact_emit_line(strdup(_si_9));
            }
        }
    }
}

void pact_emit_for_in(int64_t node) {
    const char* var_name = (const char*)pact_list_get(np_var_name, node);
    const int64_t iter_node = (int64_t)(intptr_t)pact_list_get(np_iterable, node);
    const int64_t iter_kind = (int64_t)(intptr_t)pact_list_get(np_kind, iter_node);
    if ((iter_kind == pact_NodeKind_RangeLit)) {
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_start, iter_node));
        const char* start_str = expr_result_str;
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_end, iter_node));
        const char* end_str = expr_result_str;
        const char* op = "<";
        if (((int64_t)(intptr_t)pact_list_get(np_inclusive, iter_node) != 0)) {
            op = "<=";
        }
        char _si_0[4096];
        snprintf(_si_0, 4096, "for (int64_t %s = %s; %s %s %s; %s++) {", var_name, start_str, var_name, op, end_str, var_name);
        pact_emit_line(strdup(_si_0));
        pact_push_scope();
        pact_set_var(var_name, CT_INT, 1);
        cg_indent = (cg_indent + 1);
        pact_emit_block((int64_t)(intptr_t)pact_list_get(np_body, node));
        cg_indent = (cg_indent - 1);
        pact_pop_scope();
        pact_emit_line("}");
    } else {
        pact_emit_expr(iter_node);
        const char* iter_str = expr_result_str;
        const int64_t iter_type = expr_result_type;
        if ((iter_type == CT_LIST)) {
            const char* idx = pact_fresh_temp("_i");
            char _si_1[4096];
            snprintf(_si_1, 4096, "for (int64_t %s = 0; %s < pact_list_len(%s); %s++) {", idx, idx, iter_str, idx);
            pact_emit_line(strdup(_si_1));
            pact_push_scope();
            char _si_2[4096];
            snprintf(_si_2, 4096, "    int64_t %s = (int64_t)(intptr_t)pact_list_get(%s, %s);", var_name, iter_str, idx);
            pact_emit_line(strdup(_si_2));
            pact_set_var(var_name, CT_INT, 0);
            cg_indent = (cg_indent + 1);
            pact_emit_block((int64_t)(intptr_t)pact_list_get(np_body, node));
            cg_indent = (cg_indent - 1);
            pact_pop_scope();
            pact_emit_line("}");
        } else {
            pact_emit_line("/* unsupported iterable */");
        }
    }
}

void pact_emit_if_stmt(int64_t node) {
    pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_condition, node));
    const char* cond_str = expr_result_str;
    char _si_0[4096];
    snprintf(_si_0, 4096, "if (%s) {", cond_str);
    pact_emit_line(strdup(_si_0));
    cg_indent = (cg_indent + 1);
    pact_emit_block((int64_t)(intptr_t)pact_list_get(np_then_body, node));
    cg_indent = (cg_indent - 1);
    if (((int64_t)(intptr_t)pact_list_get(np_else_body, node) != (-1))) {
        const int64_t else_b = (int64_t)(intptr_t)pact_list_get(np_else_body, node);
        const int64_t else_stmts = (int64_t)(intptr_t)pact_list_get(np_stmts, else_b);
        if (((else_stmts != (-1)) && (pact_sublist_length(else_stmts) == 1))) {
            const int64_t inner = pact_sublist_get(else_stmts, 0);
            if (((int64_t)(intptr_t)pact_list_get(np_kind, inner) == pact_NodeKind_IfExpr)) {
                const pact_list* saved_lines2 = cg_lines;
                pact_list* _l1 = pact_list_new();
                cg_lines = _l1;
                pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_condition, inner));
                const pact_list* hoisted_lines = cg_lines;
                cg_lines = saved_lines2;
                if ((pact_list_len(hoisted_lines) > 0)) {
                    pact_emit_line("} else {");
                    cg_indent = (cg_indent + 1);
                    pact_emit_if_stmt(inner);
                    cg_indent = (cg_indent - 1);
                } else {
                    const char* inner_cond = expr_result_str;
                    char _si_2[4096];
                    snprintf(_si_2, 4096, "} else if (%s) {", inner_cond);
                    pact_emit_line(strdup(_si_2));
                    cg_indent = (cg_indent + 1);
                    pact_emit_block((int64_t)(intptr_t)pact_list_get(np_then_body, inner));
                    cg_indent = (cg_indent - 1);
                    if (((int64_t)(intptr_t)pact_list_get(np_else_body, inner) != (-1))) {
                        pact_emit_line("} else {");
                        cg_indent = (cg_indent + 1);
                        pact_emit_block((int64_t)(intptr_t)pact_list_get(np_else_body, inner));
                        cg_indent = (cg_indent - 1);
                    }
                }
                pact_emit_line("}");
                return;
            }
        }
        pact_emit_line("} else {");
        cg_indent = (cg_indent + 1);
        pact_emit_block(else_b);
        cg_indent = (cg_indent - 1);
    }
    pact_emit_line("}");
}

void pact_emit_block(int64_t block) {
    if ((block == (-1))) {
        return;
    }
    const int64_t stmts_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, block);
    if ((stmts_sl == (-1))) {
        return;
    }
    int64_t i = 0;
    while ((i < pact_sublist_length(stmts_sl))) {
        pact_emit_stmt(pact_sublist_get(stmts_sl, i));
        i = (i + 1);
    }
}

void pact_emit_with_block(int64_t node) {
    const int64_t handlers_sl = (int64_t)(intptr_t)pact_list_get(np_handlers, node);
    const int64_t body = (int64_t)(intptr_t)pact_list_get(np_body, node);
    if ((handlers_sl == (-1))) {
        pact_emit_block(body);
        return;
    }
    const int64_t count = pact_sublist_length(handlers_sl);
    pact_list* _l0 = pact_list_new();
    pact_list* resource_names = _l0;
    pact_list* _l1 = pact_list_new();
    pact_list* resource_vars = _l1;
    pact_emit_line("{");
    cg_indent = (cg_indent + 1);
    int64_t i = 0;
    while ((i < count)) {
        const int64_t item = pact_sublist_get(handlers_sl, i);
        const int64_t item_kind = (int64_t)(intptr_t)pact_list_get(np_kind, item);
        if ((item_kind == pact_NodeKind_WithResource)) {
            const char* binding = (const char*)pact_list_get(np_name, item);
            const int64_t res_expr = (int64_t)(intptr_t)pact_list_get(np_value, item);
            pact_emit_expr(res_expr);
            const char* res_str = expr_result_str;
            const char* tmp = pact_fresh_temp("_wr_");
            char _si_2[4096];
            snprintf(_si_2, 4096, "int64_t %s = %s;", tmp, res_str);
            pact_emit_line(strdup(_si_2));
            pact_list_push(emitted_let_names, (void*)binding);
            char _si_3[4096];
            snprintf(_si_3, 4096, "int64_t %s = %s;", binding, tmp);
            pact_emit_line(strdup(_si_3));
            pact_list_push(resource_names, (void*)binding);
            pact_list_push(resource_vars, (void*)tmp);
        } else {
            pact_emit_expr(item);
            const char* handler_str = expr_result_str;
            if ((!pact_str_eq(handler_str, ""))) {
                char _si_4[4096];
                snprintf(_si_4, 4096, "%s;", handler_str);
                pact_emit_line(strdup(_si_4));
            }
        }
        i = (i + 1);
    }
    pact_emit_block(body);
    int64_t ri = (pact_list_len(resource_names) - 1);
    while ((ri >= 0)) {
        const char* rname = (const char*)pact_list_get(resource_names, ri);
        char _si_5[4096];
        snprintf(_si_5, 4096, "// close resource: %s", rname);
        pact_emit_line(strdup(_si_5));
        char _si_6[4096];
        snprintf(_si_6, 4096, "/* %s.close() -- Closeable trait call */", rname);
        pact_emit_line(strdup(_si_6));
        ri = (ri - 1);
    }
    cg_indent = (cg_indent - 1);
    pact_emit_line("}");
}

const char* pact_format_params(int64_t fn_node) {
    const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, fn_node);
    if ((params_sl == (-1))) {
        return "void";
    }
    const int64_t count = pact_sublist_length(params_sl);
    if ((count == 0)) {
        return "void";
    }
    const char* result = "";
    int64_t i = 0;
    while ((i < count)) {
        const int64_t p = pact_sublist_get(params_sl, i);
        const char* pname = (const char*)pact_list_get(np_name, p);
        const char* ptype = (const char*)pact_list_get(np_type_name, p);
        if ((i > 0)) {
            result = pact_str_concat(result, ", ");
        }
        if (pact_str_eq(ptype, "Fn")) {
            char _si_0[4096];
            snprintf(_si_0, 4096, "pact_closure* %s", pname);
            result = pact_str_concat(result, strdup(_si_0));
        } else if ((pact_is_enum_type(ptype) != 0)) {
            char _si_1[4096];
            snprintf(_si_1, 4096, "pact_%s %s", ptype, pname);
            result = pact_str_concat(result, strdup(_si_1));
        } else {
            if ((pact_is_struct_type(ptype) != 0)) {
                char _si_2[4096];
                snprintf(_si_2, 4096, "pact_%s %s", ptype, pname);
                result = pact_str_concat(result, strdup(_si_2));
            } else {
                const int64_t ct = pact_type_from_name(ptype);
                char _si_3[4096];
                snprintf(_si_3, 4096, "%s %s", pact_c_type_str(ct), pname);
                result = pact_str_concat(result, strdup(_si_3));
            }
        }
        i = (i + 1);
    }
    return result;
}

const char* pact_format_impl_params(int64_t fn_node, const char* impl_type) {
    const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, fn_node);
    const int64_t has_self = pact_impl_method_has_self(fn_node);
    const char* result = "";
    if ((has_self != 0)) {
        char _si_0[4096];
        snprintf(_si_0, 4096, "pact_%s self", impl_type);
        result = strdup(_si_0);
    }
    int64_t first = 1;
    if ((has_self != 0)) {
        first = 0;
    }
    if ((params_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(params_sl))) {
            const int64_t p = pact_sublist_get(params_sl, i);
            const char* pname = (const char*)pact_list_get(np_name, p);
            if ((!pact_str_eq(pname, "self"))) {
                const char* ptype_raw = (const char*)pact_list_get(np_type_name, p);
                const char* ptype = pact_resolve_self_type(ptype_raw, impl_type);
                if ((first == 0)) {
                    result = pact_str_concat(result, ", ");
                }
                first = 0;
                if (pact_str_eq(ptype, "Fn")) {
                    char _si_1[4096];
                    snprintf(_si_1, 4096, "pact_closure* %s", pname);
                    result = pact_str_concat(result, strdup(_si_1));
                } else if ((pact_is_struct_type(ptype) != 0)) {
                    char _si_2[4096];
                    snprintf(_si_2, 4096, "pact_%s %s", ptype, pname);
                    result = pact_str_concat(result, strdup(_si_2));
                } else {
                    if ((pact_is_enum_type(ptype) != 0)) {
                        char _si_3[4096];
                        snprintf(_si_3, 4096, "pact_%s %s", ptype, pname);
                        result = pact_str_concat(result, strdup(_si_3));
                    } else {
                        const int64_t ct = pact_type_from_name(ptype);
                        char _si_4[4096];
                        snprintf(_si_4, 4096, "%s %s", pact_c_type_str(ct), pname);
                        result = pact_str_concat(result, strdup(_si_4));
                    }
                }
            }
            i = (i + 1);
        }
    }
    if (pact_str_eq(result, "")) {
        result = "void";
    }
    return result;
}

void pact_emit_impl_method_def(int64_t fn_node, const char* impl_type) {
    pact_push_scope();
    cg_temp_counter = 0;
    const char* mname = (const char*)pact_list_get(np_name, fn_node);
    char _si_0[4096];
    snprintf(_si_0, 4096, "%s_%s", impl_type, mname);
    const char* mangled = strdup(_si_0);
    cg_current_fn_name = mangled;
    const char* ret_str_raw = (const char*)pact_list_get(np_return_type, fn_node);
    const char* ret_str = pact_resolve_self_type(ret_str_raw, impl_type);
    const int64_t ret_type = pact_type_from_name(ret_str);
    const char* params = pact_format_impl_params(fn_node, impl_type);
    const char* enum_ret = pact_get_fn_enum_ret(mangled);
    const char* sig = "";
    if ((!pact_str_eq(enum_ret, ""))) {
        char _si_1[4096];
        snprintf(_si_1, 4096, "pact_%s pact_%s(%s)", enum_ret, mangled, params);
        sig = strdup(_si_1);
    } else if ((pact_is_struct_type(ret_str) != 0)) {
        char _si_2[4096];
        snprintf(_si_2, 4096, "pact_%s pact_%s(%s)", ret_str, mangled, params);
        sig = strdup(_si_2);
    } else {
        char _si_3[4096];
        snprintf(_si_3, 4096, "%s pact_%s(%s)", pact_c_type_str(ret_type), mangled, params);
        sig = strdup(_si_3);
    }
    const int64_t has_self = pact_impl_method_has_self(fn_node);
    if ((has_self != 0)) {
        pact_set_var("self", CT_VOID, 0);
        pact_set_var_struct("self", impl_type);
    }
    const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, fn_node);
    if ((params_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(params_sl))) {
            const int64_t p = pact_sublist_get(params_sl, i);
            const char* pname = (const char*)pact_list_get(np_name, p);
            if ((!pact_str_eq(pname, "self"))) {
                const char* ptype_raw = (const char*)pact_list_get(np_type_name, p);
                const char* ptype = pact_resolve_self_type(ptype_raw, impl_type);
                if (pact_str_eq(ptype, "Fn")) {
                    pact_set_var(pname, CT_CLOSURE, 1);
                    const int64_t ta = (int64_t)(intptr_t)pact_list_get(np_type_ann, p);
                    if ((ta != (-1))) {
                        const char* sig_str = pact_build_closure_sig_from_type_ann(ta);
                        pact_set_var_closure(pname, sig_str);
                    }
                } else {
                    pact_set_var(pname, pact_type_from_name(ptype), 1);
                    if ((pact_is_struct_type(ptype) != 0)) {
                        pact_set_var_struct(pname, ptype);
                    }
                    if ((pact_is_enum_type(ptype) != 0)) {
                        pact_list_push(var_enum_names, (void*)pname);
                        pact_list_push(var_enum_types, (void*)ptype);
                    }
                }
            }
            i = (i + 1);
        }
    }
    int64_t body_ret = ret_type;
    if (((pact_is_struct_type(ret_str) != 0) || (pact_is_enum_type(ret_str) != 0))) {
        body_ret = CT_INT;
    }
    char _si_4[4096];
    snprintf(_si_4, 4096, "%s {", sig);
    pact_emit_line(strdup(_si_4));
    cg_indent = (cg_indent + 1);
    pact_emit_fn_body((int64_t)(intptr_t)pact_list_get(np_body, fn_node), body_ret);
    cg_indent = (cg_indent - 1);
    pact_emit_line("}");
    pact_pop_scope();
}

void pact_emit_fn_decl(int64_t fn_node) {
    const char* name = (const char*)pact_list_get(np_name, fn_node);
    if (pact_str_eq(name, "main")) {
        pact_emit_line("void pact_main(void);");
        return;
    }
    const char* params = pact_format_params(fn_node);
    const char* enum_ret = pact_get_fn_enum_ret(name);
    if ((!pact_str_eq(enum_ret, ""))) {
        char _si_0[4096];
        snprintf(_si_0, 4096, "pact_%s pact_%s(%s);", enum_ret, name, params);
        pact_emit_line(strdup(_si_0));
    } else {
        const char* ret_str = (const char*)pact_list_get(np_return_type, fn_node);
        const int64_t ret_type = pact_type_from_name(ret_str);
        char _si_1[4096];
        snprintf(_si_1, 4096, "%s pact_%s(%s);", pact_c_type_str(ret_type), name, params);
        pact_emit_line(strdup(_si_1));
    }
}

void pact_emit_fn_def(int64_t fn_node) {
    pact_push_scope();
    cg_temp_counter = 0;
    const char* name = (const char*)pact_list_get(np_name, fn_node);
    cg_current_fn_name = name;
    const char* ret_str = (const char*)pact_list_get(np_return_type, fn_node);
    const int64_t ret_type = pact_type_from_name(ret_str);
    const char* sig = "";
    if (pact_str_eq(name, "main")) {
        sig = "void pact_main(void)";
    } else {
        const char* params = pact_format_params(fn_node);
        const char* enum_ret = pact_get_fn_enum_ret(name);
        if ((!pact_str_eq(enum_ret, ""))) {
            char _si_0[4096];
            snprintf(_si_0, 4096, "pact_%s pact_%s(%s)", enum_ret, name, params);
            sig = strdup(_si_0);
        } else {
            char _si_1[4096];
            snprintf(_si_1, 4096, "%s pact_%s(%s)", pact_c_type_str(ret_type), name, params);
            sig = strdup(_si_1);
        }
    }
    const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, fn_node);
    if ((params_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(params_sl))) {
            const int64_t p = pact_sublist_get(params_sl, i);
            const char* pname = (const char*)pact_list_get(np_name, p);
            const char* ptype = (const char*)pact_list_get(np_type_name, p);
            if (pact_str_eq(ptype, "Fn")) {
                pact_set_var(pname, CT_CLOSURE, 1);
                const int64_t ta = (int64_t)(intptr_t)pact_list_get(np_type_ann, p);
                if ((ta != (-1))) {
                    const char* sig_str = pact_build_closure_sig_from_type_ann(ta);
                    pact_set_var_closure(pname, sig_str);
                }
            } else {
                pact_set_var(pname, pact_type_from_name(ptype), 1);
                if ((pact_is_struct_type(ptype) != 0)) {
                    pact_set_var_struct(pname, ptype);
                }
                if ((pact_is_enum_type(ptype) != 0)) {
                    pact_list_push(var_enum_names, (void*)pname);
                    pact_list_push(var_enum_types, (void*)ptype);
                }
            }
            i = (i + 1);
        }
    }
    char _si_2[4096];
    snprintf(_si_2, 4096, "%s {", sig);
    pact_emit_line(strdup(_si_2));
    cg_indent = (cg_indent + 1);
    pact_emit_fn_body((int64_t)(intptr_t)pact_list_get(np_body, fn_node), ret_type);
    cg_indent = (cg_indent - 1);
    pact_emit_line("}");
    pact_pop_scope();
}

void pact_emit_fn_body(int64_t block, int64_t ret_type) {
    if ((block == (-1))) {
        return;
    }
    const int64_t stmts_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, block);
    if ((stmts_sl == (-1))) {
        return;
    }
    const int64_t count = pact_sublist_length(stmts_sl);
    if ((count == 0)) {
        return;
    }
    int64_t i = 0;
    while ((i < (count - 1))) {
        pact_emit_stmt(pact_sublist_get(stmts_sl, i));
        i = (i + 1);
    }
    const int64_t last = pact_sublist_get(stmts_sl, (count - 1));
    const int64_t last_kind = (int64_t)(intptr_t)pact_list_get(np_kind, last);
    if (((ret_type != CT_VOID) && (last_kind == pact_NodeKind_ExprStmt))) {
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_value, last));
        const char* val_str = expr_result_str;
        char _si_0[4096];
        snprintf(_si_0, 4096, "return %s;", val_str);
        pact_emit_line(strdup(_si_0));
    } else if (((ret_type != CT_VOID) && (last_kind == pact_NodeKind_IfExpr))) {
        pact_emit_if_expr(last);
        const char* val_str = expr_result_str;
        char _si_1[4096];
        snprintf(_si_1, 4096, "return %s;", val_str);
        pact_emit_line(strdup(_si_1));
    } else {
        pact_emit_stmt(last);
    }
}

int64_t pact_find_type_def(const char* name) {
    const int64_t types_sl = (int64_t)(intptr_t)pact_list_get(np_fields, cg_program_node);
    if ((types_sl == (-1))) {
        return (-1);
    }
    int64_t i = 0;
    while ((i < pact_sublist_length(types_sl))) {
        const int64_t td = pact_sublist_get(types_sl, i);
        if (pact_str_eq((const char*)pact_list_get(np_name, td), name)) {
            return td;
        }
        i = (i + 1);
    }
    return (-1);
}

const char* pact_resolve_type_param(const char* param_name, int64_t tparams_sl, const char* concrete_args) {
    int64_t pi = 0;
    int64_t arg_idx = 0;
    while ((pi < pact_sublist_length(tparams_sl))) {
        const int64_t tp = pact_sublist_get(tparams_sl, pi);
        if (pact_str_eq((const char*)pact_list_get(np_name, tp), param_name)) {
            int64_t seg_start = 0;
            int64_t seg_idx = 0;
            int64_t ci = 0;
            while ((ci <= pact_str_len(concrete_args))) {
                if (((ci == pact_str_len(concrete_args)) || (pact_str_char_at(concrete_args, ci) == 44))) {
                    if ((seg_idx == arg_idx)) {
                        return pact_str_substr(concrete_args, seg_start, (ci - seg_start));
                    }
                    seg_idx = (seg_idx + 1);
                    seg_start = (ci + 1);
                }
                ci = (ci + 1);
            }
        }
        pi = (pi + 1);
        arg_idx = (arg_idx + 1);
    }
    return param_name;
}

void pact_register_mono_field_types(const char* base_name, const char* mono_name, const char* concrete_args) {
    int64_t check = 0;
    while ((check < pact_list_len(sf_reg_struct))) {
        if (pact_str_eq((const char*)pact_list_get(sf_reg_struct, check), mono_name)) {
            return;
        }
        check = (check + 1);
    }
    const int64_t td = pact_find_type_def(base_name);
    if ((td == (-1))) {
        return;
    }
    const int64_t tparams_sl = (int64_t)(intptr_t)pact_list_get(np_type_params, td);
    if ((tparams_sl == (-1))) {
        return;
    }
    const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, td);
    if ((flds_sl == (-1))) {
        return;
    }
    int64_t i = 0;
    while ((i < pact_sublist_length(flds_sl))) {
        const int64_t f = pact_sublist_get(flds_sl, i);
        const char* fname = (const char*)pact_list_get(np_name, f);
        const int64_t type_ann_node = (int64_t)(intptr_t)pact_list_get(np_value, f);
        if ((type_ann_node != (-1))) {
            const char* type_name = (const char*)pact_list_get(np_name, type_ann_node);
            const char* resolved = pact_resolve_type_param(type_name, tparams_sl, concrete_args);
            if ((pact_is_struct_type(resolved) != 0)) {
                pact_list_push(sf_reg_struct, (void*)mono_name);
                pact_list_push(sf_reg_field, (void*)fname);
                pact_list_push(sf_reg_type, (void*)(intptr_t)CT_VOID);
                pact_list_push(sf_reg_stype, (void*)resolved);
            } else {
                const int64_t ct = pact_type_from_name(resolved);
                pact_list_push(sf_reg_struct, (void*)mono_name);
                pact_list_push(sf_reg_field, (void*)fname);
                pact_list_push(sf_reg_type, (void*)(intptr_t)ct);
                pact_list_push(sf_reg_stype, (void*)"");
            }
        } else {
            pact_list_push(sf_reg_struct, (void*)mono_name);
            pact_list_push(sf_reg_field, (void*)fname);
            pact_list_push(sf_reg_type, (void*)(intptr_t)CT_INT);
            pact_list_push(sf_reg_stype, (void*)"");
        }
        i = (i + 1);
    }
}

void pact_emit_mono_struct_typedef(const char* base_name, const char* concrete_args) {
    const int64_t td = pact_find_type_def(base_name);
    if ((td == (-1))) {
        return;
    }
    const int64_t tparams_sl = (int64_t)(intptr_t)pact_list_get(np_type_params, td);
    if ((tparams_sl == (-1))) {
        return;
    }
    const char* c_name = pact_mangle_generic_name(base_name, concrete_args);
    const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, td);
    if ((flds_sl == (-1))) {
        return;
    }
    pact_list_push(struct_reg_names, (void*)c_name);
    pact_emit_line("typedef struct {");
    cg_indent = (cg_indent + 1);
    int64_t i = 0;
    while ((i < pact_sublist_length(flds_sl))) {
        const int64_t f = pact_sublist_get(flds_sl, i);
        const char* fname = (const char*)pact_list_get(np_name, f);
        const int64_t type_ann_node = (int64_t)(intptr_t)pact_list_get(np_value, f);
        if ((type_ann_node != (-1))) {
            const char* type_name = (const char*)pact_list_get(np_name, type_ann_node);
            const char* resolved = pact_resolve_type_param(type_name, tparams_sl, concrete_args);
            if ((pact_is_struct_type(resolved) != 0)) {
                char _si_0[4096];
                snprintf(_si_0, 4096, "pact_%s %s;", resolved, fname);
                pact_emit_line(strdup(_si_0));
                pact_list_push(sf_reg_struct, (void*)c_name);
                pact_list_push(sf_reg_field, (void*)fname);
                pact_list_push(sf_reg_type, (void*)(intptr_t)CT_VOID);
                pact_list_push(sf_reg_stype, (void*)resolved);
            } else {
                const int64_t ct = pact_type_from_name(resolved);
                char _si_1[4096];
                snprintf(_si_1, 4096, "%s %s;", pact_c_type_str(ct), fname);
                pact_emit_line(strdup(_si_1));
                pact_list_push(sf_reg_struct, (void*)c_name);
                pact_list_push(sf_reg_field, (void*)fname);
                pact_list_push(sf_reg_type, (void*)(intptr_t)ct);
                pact_list_push(sf_reg_stype, (void*)"");
            }
        } else {
            char _si_2[4096];
            snprintf(_si_2, 4096, "int64_t %s;", fname);
            pact_emit_line(strdup(_si_2));
            pact_list_push(sf_reg_struct, (void*)c_name);
            pact_list_push(sf_reg_field, (void*)fname);
            pact_list_push(sf_reg_type, (void*)(intptr_t)CT_INT);
            pact_list_push(sf_reg_stype, (void*)"");
        }
        i = (i + 1);
    }
    cg_indent = (cg_indent - 1);
    char _si_3[4096];
    snprintf(_si_3, 4096, "} pact_%s;", c_name);
    pact_emit_line(strdup(_si_3));
    pact_emit_line("");
}

void pact_emit_all_mono_typedefs(void) {
    int64_t i = 0;
    while ((i < pact_list_len(mono_base_names))) {
        const char* base = (const char*)pact_list_get(mono_base_names, i);
        const char* args = (const char*)pact_list_get(mono_concrete_args, i);
        const int64_t td = pact_find_type_def(base);
        if ((td != (-1))) {
            const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, td);
            if (((flds_sl != (-1)) && (pact_sublist_length(flds_sl) > 0))) {
                if (((int64_t)(intptr_t)pact_list_get(np_kind, pact_sublist_get(flds_sl, 0)) != pact_NodeKind_TypeVariant)) {
                    pact_emit_mono_struct_typedef(base, args);
                }
            }
        }
        i = (i + 1);
    }
}

void pact_emit_mono_fn_def(int64_t fn_node, const char* concrete_args) {
    const char* base_name = (const char*)pact_list_get(np_name, fn_node);
    const char* mangled = pact_mangle_generic_name(base_name, concrete_args);
    const int64_t tparams_sl = (int64_t)(intptr_t)pact_list_get(np_type_params, fn_node);
    const char* ret_str = (const char*)pact_list_get(np_return_type, fn_node);
    const char* resolved_ret = pact_resolve_type_param(ret_str, tparams_sl, concrete_args);
    const int64_t ret_type = pact_type_from_name(resolved_ret);
    const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, fn_node);
    const char* params_c = "void";
    if (((params_sl != (-1)) && (pact_sublist_length(params_sl) > 0))) {
        params_c = "";
        int64_t i = 0;
        while ((i < pact_sublist_length(params_sl))) {
            const int64_t p = pact_sublist_get(params_sl, i);
            const char* pname = (const char*)pact_list_get(np_name, p);
            const char* ptype = (const char*)pact_list_get(np_type_name, p);
            const char* resolved_ptype = pact_resolve_type_param(ptype, tparams_sl, concrete_args);
            if ((i > 0)) {
                params_c = pact_str_concat(params_c, ", ");
            }
            if ((pact_is_struct_type(resolved_ptype) != 0)) {
                char _si_0[4096];
                snprintf(_si_0, 4096, "pact_%s %s", resolved_ptype, pname);
                params_c = pact_str_concat(params_c, strdup(_si_0));
            } else if ((pact_is_enum_type(resolved_ptype) != 0)) {
                char _si_1[4096];
                snprintf(_si_1, 4096, "pact_%s %s", resolved_ptype, pname);
                params_c = pact_str_concat(params_c, strdup(_si_1));
            } else {
                const int64_t ct = pact_type_from_name(resolved_ptype);
                char _si_2[4096];
                snprintf(_si_2, 4096, "%s %s", pact_c_type_str(ct), pname);
                params_c = pact_str_concat(params_c, strdup(_si_2));
            }
            i = (i + 1);
        }
    }
    char _si_3[4096];
    snprintf(_si_3, 4096, "%s pact_%s(%s);", pact_c_type_str(ret_type), mangled, params_c);
    pact_emit_line(strdup(_si_3));
    pact_push_scope();
    cg_temp_counter = 0;
    if ((params_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(params_sl))) {
            const int64_t p = pact_sublist_get(params_sl, i);
            const char* pname = (const char*)pact_list_get(np_name, p);
            const char* ptype = (const char*)pact_list_get(np_type_name, p);
            const char* resolved_ptype = pact_resolve_type_param(ptype, tparams_sl, concrete_args);
            pact_set_var(pname, pact_type_from_name(resolved_ptype), 1);
            if ((pact_is_struct_type(resolved_ptype) != 0)) {
                pact_set_var_struct(pname, resolved_ptype);
            }
            if ((pact_is_enum_type(resolved_ptype) != 0)) {
                pact_list_push(var_enum_names, (void*)pname);
                pact_list_push(var_enum_types, (void*)resolved_ptype);
            }
            i = (i + 1);
        }
    }
    char _si_4[4096];
    snprintf(_si_4, 4096, "%s pact_%s(%s) {", pact_c_type_str(ret_type), mangled, params_c);
    pact_emit_line(strdup(_si_4));
    cg_indent = (cg_indent + 1);
    pact_emit_fn_body((int64_t)(intptr_t)pact_list_get(np_body, fn_node), ret_type);
    cg_indent = (cg_indent - 1);
    pact_emit_line("}");
    pact_emit_line("");
    pact_pop_scope();
}

void pact_emit_all_mono_fns(void) {
    int64_t i = 0;
    while ((i < pact_list_len(mono_fn_bases))) {
        const char* base = (const char*)pact_list_get(mono_fn_bases, i);
        const char* args = (const char*)pact_list_get(mono_fn_args, i);
        const int64_t fn_node = pact_get_generic_fn_node(base);
        if ((fn_node != (-1))) {
            pact_emit_mono_fn_def(fn_node, args);
        }
        i = (i + 1);
    }
}

void pact_emit_struct_typedef(int64_t td_node) {
    const char* name = (const char*)pact_list_get(np_name, td_node);
    const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, td_node);
    if ((flds_sl == (-1))) {
        return;
    }
    if ((pact_sublist_length(flds_sl) > 0)) {
        const int64_t first = pact_sublist_get(flds_sl, 0);
        if (((int64_t)(intptr_t)pact_list_get(np_kind, first) == pact_NodeKind_TypeVariant)) {
            return;
        }
    }
    const int64_t tparams_sl = (int64_t)(intptr_t)pact_list_get(np_type_params, td_node);
    if (((tparams_sl != (-1)) && (pact_sublist_length(tparams_sl) > 0))) {
        return;
    }
    pact_emit_line("typedef struct {");
    cg_indent = (cg_indent + 1);
    int64_t i = 0;
    while ((i < pact_sublist_length(flds_sl))) {
        const int64_t f = pact_sublist_get(flds_sl, i);
        const char* fname = (const char*)pact_list_get(np_name, f);
        const int64_t type_ann_node = (int64_t)(intptr_t)pact_list_get(np_value, f);
        if ((type_ann_node != (-1))) {
            const char* type_name = (const char*)pact_list_get(np_name, type_ann_node);
            if (pact_str_eq(type_name, name)) {
                char _si_0[4096];
                snprintf(_si_0, 4096, "int64_t %s;", fname);
                pact_emit_line(strdup(_si_0));
                pact_list_push(sf_reg_struct, (void*)name);
                pact_list_push(sf_reg_field, (void*)fname);
                pact_list_push(sf_reg_type, (void*)(intptr_t)CT_INT);
                pact_list_push(sf_reg_stype, (void*)"");
            } else if ((pact_is_struct_type(type_name) != 0)) {
                char _si_1[4096];
                snprintf(_si_1, 4096, "pact_%s %s;", type_name, fname);
                pact_emit_line(strdup(_si_1));
                pact_list_push(sf_reg_struct, (void*)name);
                pact_list_push(sf_reg_field, (void*)fname);
                pact_list_push(sf_reg_type, (void*)(intptr_t)CT_VOID);
                pact_list_push(sf_reg_stype, (void*)type_name);
            } else {
                const int64_t ct = pact_type_from_name(type_name);
                char _si_2[4096];
                snprintf(_si_2, 4096, "%s %s;", pact_c_type_str(ct), fname);
                pact_emit_line(strdup(_si_2));
                pact_list_push(sf_reg_struct, (void*)name);
                pact_list_push(sf_reg_field, (void*)fname);
                pact_list_push(sf_reg_type, (void*)(intptr_t)ct);
                pact_list_push(sf_reg_stype, (void*)"");
            }
        } else {
            char _si_3[4096];
            snprintf(_si_3, 4096, "int64_t %s;", fname);
            pact_emit_line(strdup(_si_3));
            pact_list_push(sf_reg_struct, (void*)name);
            pact_list_push(sf_reg_field, (void*)fname);
            pact_list_push(sf_reg_type, (void*)(intptr_t)CT_INT);
            pact_list_push(sf_reg_stype, (void*)"");
        }
        i = (i + 1);
    }
    cg_indent = (cg_indent - 1);
    char _si_4[4096];
    snprintf(_si_4, 4096, "} pact_%s;", name);
    pact_emit_line(strdup(_si_4));
    pact_emit_line("");
}

void pact_emit_enum_typedef(int64_t td_node) {
    const char* name = (const char*)pact_list_get(np_name, td_node);
    const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, td_node);
    if ((flds_sl == (-1))) {
        return;
    }
    const int64_t enum_idx = pact_list_len(enum_reg_names);
    pact_list_push(enum_reg_names, (void*)name);
    const char* variants_str = "";
    int64_t i = 0;
    while ((i < pact_sublist_length(flds_sl))) {
        const int64_t v = pact_sublist_get(flds_sl, i);
        const char* vname = (const char*)pact_list_get(np_name, v);
        pact_list_push(enum_reg_variant_names, (void*)vname);
        pact_list_push(enum_reg_variant_enum_idx, (void*)(intptr_t)enum_idx);
        if ((i > 0)) {
            variants_str = pact_str_concat(variants_str, ", ");
        }
        char _si_0[4096];
        snprintf(_si_0, 4096, "pact_%s_%s", name, vname);
        variants_str = pact_str_concat(variants_str, strdup(_si_0));
        i = (i + 1);
    }
    char _si_1[4096];
    snprintf(_si_1, 4096, "typedef enum { %s } pact_%s;", variants_str, name);
    pact_emit_line(strdup(_si_1));
    pact_emit_line("");
}

void pact_emit_top_level_let(int64_t node) {
    const pact_list* saved_lines = cg_lines;
    pact_list* _l0 = pact_list_new();
    cg_lines = _l0;
    pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_value, node));
    const char* val_str = expr_result_str;
    const int64_t val_type = expr_result_type;
    const pact_list* helper_lines = cg_lines;
    cg_lines = saved_lines;
    const char* name = (const char*)pact_list_get(np_name, node);
    const int64_t is_mut = (int64_t)(intptr_t)pact_list_get(np_is_mut, node);
    pact_set_var(name, val_type, is_mut);
    const int64_t type_ann = (int64_t)(intptr_t)pact_list_get(np_target, node);
    if (((val_type == CT_LIST) && (type_ann != (-1)))) {
        const char* ann_name = (const char*)pact_list_get(np_name, type_ann);
        if (pact_str_eq(ann_name, "List")) {
            const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, type_ann);
            if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) > 0))) {
                const int64_t elem_ann = pact_sublist_get(elems_sl, 0);
                const char* elem_name = (const char*)pact_list_get(np_name, elem_ann);
                pact_set_list_elem_type(name, pact_type_from_name(elem_name));
            }
        }
    }
    const char* ts = pact_c_type_str(val_type);
    const int needs_init = ((pact_list_len(helper_lines) > 0) || (val_type == CT_LIST));
    if (needs_init) {
        char _si_1[4096];
        snprintf(_si_1, 4096, "static %s %s;", ts, name);
        pact_emit_line(strdup(_si_1));
        int64_t hi = 0;
        while ((hi < pact_list_len(helper_lines))) {
            pact_list_push(cg_global_inits, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(helper_lines, hi));
            hi = (hi + 1);
        }
        char _si_2[4096];
        snprintf(_si_2, 4096, "    %s = %s;", name, val_str);
        pact_list_push(cg_global_inits, (void*)strdup(_si_2));
    } else if ((is_mut != 0)) {
        char _si_3[4096];
        snprintf(_si_3, 4096, "static %s %s = %s;", ts, name, val_str);
        pact_emit_line(strdup(_si_3));
    } else {
        char _si_4[4096];
        snprintf(_si_4, 4096, "static const %s %s = %s;", ts, name, val_str);
        pact_emit_line(strdup(_si_4));
    }
}

const char* pact_generate(int64_t program) {
    cg_program_node = program;
    pact_list* _l0 = pact_list_new();
    cg_lines = _l0;
    cg_indent = 0;
    cg_temp_counter = 0;
    pact_list* _l1 = pact_list_new();
    scope_names = _l1;
    pact_list* _l2 = pact_list_new();
    scope_types = _l2;
    pact_list* _l3 = pact_list_new();
    scope_muts = _l3;
    pact_list* _l4 = pact_list_new();
    scope_frame_starts = _l4;
    pact_list* _l5 = pact_list_new();
    fn_reg_names = _l5;
    pact_list* _l6 = pact_list_new();
    fn_reg_ret = _l6;
    pact_list* _l7 = pact_list_new();
    fn_reg_effect_sl = _l7;
    pact_list* _l8 = pact_list_new();
    effect_reg_names = _l8;
    pact_list* _l9 = pact_list_new();
    effect_reg_parent = _l9;
    cg_current_fn_name = "";
    pact_list* _l10 = pact_list_new();
    cg_global_inits = _l10;
    pact_list* _l11 = pact_list_new();
    var_list_elem_names = _l11;
    pact_list* _l12 = pact_list_new();
    var_list_elem_types = _l12;
    pact_list* _l13 = pact_list_new();
    struct_reg_names = _l13;
    pact_list* _l14 = pact_list_new();
    enum_reg_names = _l14;
    pact_list* _l15 = pact_list_new();
    enum_reg_variant_names = _l15;
    pact_list* _l16 = pact_list_new();
    enum_reg_variant_enum_idx = _l16;
    pact_list* _l17 = pact_list_new();
    var_enum_names = _l17;
    pact_list* _l18 = pact_list_new();
    var_enum_types = _l18;
    pact_list* _l19 = pact_list_new();
    fn_enum_ret_names = _l19;
    pact_list* _l20 = pact_list_new();
    fn_enum_ret_types = _l20;
    pact_list* _l21 = pact_list_new();
    emitted_let_names = _l21;
    pact_list* _l22 = pact_list_new();
    emitted_fn_names = _l22;
    pact_list* _l23 = pact_list_new();
    trait_reg_names = _l23;
    pact_list* _l24 = pact_list_new();
    trait_reg_method_sl = _l24;
    pact_list* _l25 = pact_list_new();
    impl_reg_trait = _l25;
    pact_list* _l26 = pact_list_new();
    impl_reg_type = _l26;
    pact_list* _l27 = pact_list_new();
    impl_reg_methods_sl = _l27;
    pact_list* _l28 = pact_list_new();
    from_reg_source = _l28;
    pact_list* _l29 = pact_list_new();
    from_reg_target = _l29;
    pact_list* _l30 = pact_list_new();
    from_reg_method_sl = _l30;
    pact_list* _l31 = pact_list_new();
    var_struct_names = _l31;
    pact_list* _l32 = pact_list_new();
    var_struct_types = _l32;
    pact_list* _l33 = pact_list_new();
    sf_reg_struct = _l33;
    pact_list* _l34 = pact_list_new();
    sf_reg_field = _l34;
    pact_list* _l35 = pact_list_new();
    sf_reg_type = _l35;
    pact_list* _l36 = pact_list_new();
    sf_reg_stype = _l36;
    pact_list* _l37 = pact_list_new();
    mono_base_names = _l37;
    pact_list* _l38 = pact_list_new();
    mono_concrete_args = _l38;
    pact_list* _l39 = pact_list_new();
    mono_c_names = _l39;
    pact_list* _l40 = pact_list_new();
    cg_closure_defs = _l40;
    cg_closure_counter = 0;
    pact_list* _l41 = pact_list_new();
    var_closure_names = _l41;
    pact_list* _l42 = pact_list_new();
    var_closure_sigs = _l42;
    pact_list* _l43 = pact_list_new();
    generic_fn_names = _l43;
    pact_list* _l44 = pact_list_new();
    generic_fn_nodes = _l44;
    pact_list* _l45 = pact_list_new();
    mono_fn_bases = _l45;
    pact_list* _l46 = pact_list_new();
    mono_fn_args = _l46;
    pact_list* _l47 = pact_list_new();
    var_option_names = _l47;
    pact_list* _l48 = pact_list_new();
    var_option_inner = _l48;
    pact_list* _l49 = pact_list_new();
    var_result_names = _l49;
    pact_list* _l50 = pact_list_new();
    var_result_ok = _l50;
    pact_list* _l51 = pact_list_new();
    var_result_err = _l51;
    pact_list* _l52 = pact_list_new();
    emitted_option_types = _l52;
    pact_list* _l53 = pact_list_new();
    emitted_result_types = _l53;
    cg_let_target_type = 0;
    pact_push_scope();
    pact_reg_fn("arg_count", CT_INT);
    pact_reg_fn("get_arg", CT_STRING);
    pact_reg_fn("read_file", CT_STRING);
    pact_reg_fn("write_file", CT_VOID);
    pact_reg_fn("file_exists", CT_INT);
    pact_reg_fn("path_join", CT_STRING);
    pact_reg_fn("path_dirname", CT_STRING);
    pact_list_push(struct_reg_names, (void*)"ConversionError");
    pact_list_push(sf_reg_struct, (void*)"ConversionError");
    pact_list_push(sf_reg_field, (void*)"message");
    pact_list_push(sf_reg_type, (void*)(intptr_t)CT_STRING);
    pact_list_push(sf_reg_stype, (void*)"");
    pact_list_push(sf_reg_struct, (void*)"ConversionError");
    pact_list_push(sf_reg_field, (void*)"source_type");
    pact_list_push(sf_reg_type, (void*)(intptr_t)CT_STRING);
    pact_list_push(sf_reg_stype, (void*)"");
    pact_list_push(sf_reg_struct, (void*)"ConversionError");
    pact_list_push(sf_reg_field, (void*)"target_type");
    pact_list_push(sf_reg_type, (void*)(intptr_t)CT_STRING);
    pact_list_push(sf_reg_stype, (void*)"");
    pact_init_builtin_effects();
    const int64_t effects_decl_sl = (int64_t)(intptr_t)pact_list_get(np_args, program);
    if ((effects_decl_sl != (-1))) {
        int64_t ei = 0;
        while ((ei < pact_sublist_length(effects_decl_sl))) {
            const int64_t ed = pact_sublist_get(effects_decl_sl, ei);
            const char* eff_name = (const char*)pact_list_get(np_name, ed);
            const int64_t parent_idx = pact_reg_effect(eff_name, (-1));
            const int64_t children_sl = (int64_t)(intptr_t)pact_list_get(np_elements, ed);
            if ((children_sl != (-1))) {
                int64_t ci = 0;
                while ((ci < pact_sublist_length(children_sl))) {
                    const int64_t child = pact_sublist_get(children_sl, ci);
                    const char* child_name = (const char*)pact_list_get(np_name, child);
                    char _si_54[4096];
                    snprintf(_si_54, 4096, "%s.%s", eff_name, child_name);
                    pact_reg_effect(strdup(_si_54), parent_idx);
                    ci = (ci + 1);
                }
            }
            ei = (ei + 1);
        }
    }
    pact_list_push(cg_lines, (void*)"#include \"runtime.h\"");
    pact_list_push(cg_lines, (void*)"");
    const int64_t types_sl = (int64_t)(intptr_t)pact_list_get(np_fields, program);
    if ((types_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(types_sl))) {
            const int64_t td = pact_sublist_get(types_sl, i);
            const int64_t td_flds = (int64_t)(intptr_t)pact_list_get(np_fields, td);
            int64_t is_enum = 0;
            if (((td_flds != (-1)) && (pact_sublist_length(td_flds) > 0))) {
                if (((int64_t)(intptr_t)pact_list_get(np_kind, pact_sublist_get(td_flds, 0)) == pact_NodeKind_TypeVariant)) {
                    is_enum = 1;
                }
            }
            if ((is_enum == 0)) {
                pact_list_push(struct_reg_names, (void*)(const char*)pact_list_get(np_name, td));
            }
            i = (i + 1);
        }
    }
    if ((types_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(types_sl))) {
            const int64_t td = pact_sublist_get(types_sl, i);
            const int64_t td_flds = (int64_t)(intptr_t)pact_list_get(np_fields, td);
            int64_t is_enum = 0;
            if (((td_flds != (-1)) && (pact_sublist_length(td_flds) > 0))) {
                if (((int64_t)(intptr_t)pact_list_get(np_kind, pact_sublist_get(td_flds, 0)) == pact_NodeKind_TypeVariant)) {
                    is_enum = 1;
                }
            }
            if ((is_enum != 0)) {
                pact_emit_enum_typedef(td);
            } else {
                pact_emit_struct_typedef(td);
            }
            i = (i + 1);
        }
    }
    const int64_t lets_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, program);
    if ((lets_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(lets_sl))) {
            const int64_t let_node = pact_sublist_get(lets_sl, i);
            const char* let_name = (const char*)pact_list_get(np_name, let_node);
            if ((pact_is_emitted_let(let_name) == 0)) {
                pact_emit_top_level_let(let_node);
                pact_list_push(emitted_let_names, (void*)let_name);
            }
            i = (i + 1);
        }
        pact_emit_line("");
    }
    const int64_t fns_sl = (int64_t)(intptr_t)pact_list_get(np_params, program);
    if ((fns_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(fns_sl))) {
            const int64_t fn_node = pact_sublist_get(fns_sl, i);
            const char* fn_name = (const char*)pact_list_get(np_name, fn_node);
            const int64_t fn_tparams = (int64_t)(intptr_t)pact_list_get(np_type_params, fn_node);
            if (((fn_tparams != (-1)) && (pact_sublist_length(fn_tparams) > 0))) {
                pact_list_push(generic_fn_names, (void*)fn_name);
                pact_list_push(generic_fn_nodes, (void*)(intptr_t)fn_node);
            } else if ((pact_is_emitted_fn(fn_name) == 0)) {
                const char* ret_str = (const char*)pact_list_get(np_return_type, fn_node);
                const int64_t fn_eff_sl = (int64_t)(intptr_t)pact_list_get(np_effects, fn_node);
                if ((pact_is_enum_type(ret_str) != 0)) {
                    pact_list_push(fn_enum_ret_names, (void*)fn_name);
                    pact_list_push(fn_enum_ret_types, (void*)ret_str);
                    pact_reg_fn_with_effects(fn_name, CT_INT, fn_eff_sl);
                } else {
                    pact_reg_fn_with_effects(fn_name, pact_type_from_name(ret_str), fn_eff_sl);
                }
                pact_list_push(emitted_fn_names, (void*)fn_name);
            }
            i = (i + 1);
        }
    }
    const int64_t traits_sl = (int64_t)(intptr_t)pact_list_get(np_arms, program);
    if ((traits_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(traits_sl))) {
            const int64_t tr = pact_sublist_get(traits_sl, i);
            pact_list_push(trait_reg_names, (void*)(const char*)pact_list_get(np_name, tr));
            pact_list_push(trait_reg_method_sl, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(np_methods, tr));
            i = (i + 1);
        }
    }
    const int64_t impls_sl = (int64_t)(intptr_t)pact_list_get(np_methods, program);
    if ((impls_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(impls_sl))) {
            const int64_t im = pact_sublist_get(impls_sl, i);
            const char* impl_trait = (const char*)pact_list_get(np_trait_name, im);
            const char* impl_type = (const char*)pact_list_get(np_name, im);
            pact_list_push(impl_reg_trait, (void*)impl_trait);
            pact_list_push(impl_reg_type, (void*)impl_type);
            pact_list_push(impl_reg_methods_sl, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(np_methods, im));
            if (pact_str_eq(impl_trait, "From")) {
                const int64_t trait_tparams = (int64_t)(intptr_t)pact_list_get(np_type_params, im);
                if (((trait_tparams != (-1)) && (pact_sublist_length(trait_tparams) > 0))) {
                    const int64_t src_node = pact_sublist_get(trait_tparams, 0);
                    const char* src_type = (const char*)pact_list_get(np_name, src_node);
                    pact_list_push(from_reg_source, (void*)src_type);
                    pact_list_push(from_reg_target, (void*)impl_type);
                    pact_list_push(from_reg_method_sl, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(np_methods, im));
                }
            }
            const int64_t methods_sl = (int64_t)(intptr_t)pact_list_get(np_methods, im);
            if ((methods_sl != (-1))) {
                int64_t j = 0;
                while ((j < pact_sublist_length(methods_sl))) {
                    const int64_t m = pact_sublist_get(methods_sl, j);
                    const char* mname = (const char*)pact_list_get(np_name, m);
                    char _si_55[4096];
                    snprintf(_si_55, 4096, "%s_%s", impl_type, mname);
                    const char* mangled = strdup(_si_55);
                    const char* ret_str_raw = (const char*)pact_list_get(np_return_type, m);
                    const char* ret_str = pact_resolve_self_type(ret_str_raw, impl_type);
                    if ((pact_is_enum_type(ret_str) != 0)) {
                        pact_list_push(fn_enum_ret_names, (void*)mangled);
                        pact_list_push(fn_enum_ret_types, (void*)ret_str);
                        pact_reg_fn(mangled, CT_INT);
                    } else if ((pact_is_struct_type(ret_str) != 0)) {
                        pact_reg_fn(mangled, CT_VOID);
                    } else {
                        pact_reg_fn(mangled, pact_type_from_name(ret_str));
                    }
                    j = (j + 1);
                }
            }
            i = (i + 1);
        }
    }
    int64_t into_i = 0;
    while ((into_i < pact_list_len(from_reg_source))) {
        const char* src = (const char*)pact_list_get(from_reg_source, into_i);
        const char* tgt = (const char*)pact_list_get(from_reg_target, into_i);
        pact_list_push(impl_reg_trait, (void*)"Into");
        pact_list_push(impl_reg_type, (void*)src);
        pact_list_push(impl_reg_methods_sl, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(from_reg_method_sl, into_i));
        into_i = (into_i + 1);
    }
    pact_list* _l56 = pact_list_new();
    emitted_fn_names = _l56;
    if ((fns_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(fns_sl))) {
            const int64_t fn_node = pact_sublist_get(fns_sl, i);
            const char* fn_name = (const char*)pact_list_get(np_name, fn_node);
            if (((pact_is_emitted_fn(fn_name) == 0) && (pact_is_generic_fn(fn_name) == 0))) {
                pact_emit_fn_decl(fn_node);
                pact_list_push(emitted_fn_names, (void*)fn_name);
            }
            i = (i + 1);
        }
    }
    if ((impls_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(impls_sl))) {
            const int64_t im = pact_sublist_get(impls_sl, i);
            const char* impl_type = (const char*)pact_list_get(np_name, im);
            const int64_t methods_sl = (int64_t)(intptr_t)pact_list_get(np_methods, im);
            if ((methods_sl != (-1))) {
                int64_t j = 0;
                while ((j < pact_sublist_length(methods_sl))) {
                    const int64_t m = pact_sublist_get(methods_sl, j);
                    const char* mname = (const char*)pact_list_get(np_name, m);
                    char _si_57[4096];
                    snprintf(_si_57, 4096, "%s_%s", impl_type, mname);
                    const char* mangled = strdup(_si_57);
                    const char* params = pact_format_impl_params(m, impl_type);
                    const char* enum_ret = pact_get_fn_enum_ret(mangled);
                    if ((!pact_str_eq(enum_ret, ""))) {
                        char _si_58[4096];
                        snprintf(_si_58, 4096, "pact_%s pact_%s(%s);", enum_ret, mangled, params);
                        pact_emit_line(strdup(_si_58));
                    } else {
                        const char* ret_str_raw = (const char*)pact_list_get(np_return_type, m);
                        const char* ret_str = pact_resolve_self_type(ret_str_raw, impl_type);
                        if ((pact_is_struct_type(ret_str) != 0)) {
                            char _si_59[4096];
                            snprintf(_si_59, 4096, "pact_%s pact_%s(%s);", ret_str, mangled, params);
                            pact_emit_line(strdup(_si_59));
                        } else {
                            const int64_t ret_type = pact_type_from_name(ret_str);
                            char _si_60[4096];
                            snprintf(_si_60, 4096, "%s pact_%s(%s);", pact_c_type_str(ret_type), mangled, params);
                            pact_emit_line(strdup(_si_60));
                        }
                    }
                    j = (j + 1);
                }
            }
            i = (i + 1);
        }
    }
    pact_emit_line("");
    const pact_list* pre_fn_lines = cg_lines;
    pact_list* _l61 = pact_list_new();
    cg_lines = _l61;
    pact_list* _l62 = pact_list_new();
    emitted_fn_names = _l62;
    if ((fns_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(fns_sl))) {
            const int64_t fn_node = pact_sublist_get(fns_sl, i);
            const char* fn_name = (const char*)pact_list_get(np_name, fn_node);
            if (((pact_is_emitted_fn(fn_name) == 0) && (pact_is_generic_fn(fn_name) == 0))) {
                pact_emit_fn_def(fn_node);
                pact_emit_line("");
                pact_list_push(emitted_fn_names, (void*)fn_name);
            }
            i = (i + 1);
        }
    }
    if ((impls_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(impls_sl))) {
            const int64_t im = pact_sublist_get(impls_sl, i);
            const char* impl_type = (const char*)pact_list_get(np_name, im);
            const int64_t methods_sl = (int64_t)(intptr_t)pact_list_get(np_methods, im);
            if ((methods_sl != (-1))) {
                int64_t j = 0;
                while ((j < pact_sublist_length(methods_sl))) {
                    const int64_t m = pact_sublist_get(methods_sl, j);
                    pact_emit_impl_method_def(m, impl_type);
                    pact_emit_line("");
                    j = (j + 1);
                }
            }
            i = (i + 1);
        }
    }
    const pact_list* fn_def_lines = cg_lines;
    cg_lines = pre_fn_lines;
    pact_emit_all_mono_typedefs();
    pact_emit_all_option_result_types();
    pact_emit_all_mono_fns();
    if ((pact_list_len(cg_closure_defs) > 0)) {
        int64_t ci = 0;
        while ((ci < pact_list_len(cg_closure_defs))) {
            pact_list_push(cg_lines, (void*)(const char*)pact_list_get(cg_closure_defs, ci));
            ci = (ci + 1);
        }
    }
    int64_t fi = 0;
    while ((fi < pact_list_len(fn_def_lines))) {
        pact_list_push(cg_lines, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(fn_def_lines, fi));
        fi = (fi + 1);
    }
    if ((pact_list_len(cg_global_inits) > 0)) {
        pact_emit_line("static void __pact_init_globals(void) {");
        int64_t gi = 0;
        while ((gi < pact_list_len(cg_global_inits))) {
            pact_list_push(cg_lines, (void*)(const char*)pact_list_get(cg_global_inits, gi));
            gi = (gi + 1);
        }
        pact_emit_line("}");
        pact_emit_line("");
    }
    pact_emit_line("int main(int argc, char** argv) {");
    cg_indent = (cg_indent + 1);
    pact_emit_line("pact_g_argc = argc;");
    pact_emit_line("pact_g_argv = (const char**)argv;");
    if ((pact_list_len(cg_global_inits) > 0)) {
        pact_emit_line("__pact_init_globals();");
    }
    pact_emit_line("pact_main();");
    pact_emit_line("return 0;");
    cg_indent = (cg_indent - 1);
    pact_emit_line("}");
    pact_pop_scope();
    return pact_join_lines();
}

const char* pact_dots_to_slashes(const char* s) {
    const char* result = "";
    int64_t i = 0;
    while ((i < pact_str_len(s))) {
        if ((pact_str_char_at(s, i) == 46)) {
            result = pact_str_concat(result, "/");
        } else {
            result = pact_str_concat(result, pact_str_substr(s, i, 1));
        }
        i = (i + 1);
    }
    return result;
}

const char* pact_find_src_root(const char* source_path) {
    int64_t i = 0;
    while ((i < (pact_str_len(source_path) - 4))) {
        if (((pact_str_char_at(source_path, i) == 47) && pact_str_eq(pact_str_substr(source_path, i, 5), "/src/"))) {
            return pact_str_substr(source_path, 0, (i + 5));
        }
        i = (i + 1);
    }
    if (((pact_str_len(source_path) >= 4) && pact_str_eq(pact_str_substr(source_path, 0, 4), "src/"))) {
        return "src/";
    }
    return pact_path_dirname(source_path);
}

const char* pact_resolve_module_path(const char* dotted_path, const char* src_root) {
    const char* rel = pact_dots_to_slashes(dotted_path);
    const char* full = pact_path_join(src_root, pact_str_concat(rel, ".pact"));
    if ((pact_file_exists(full) == 1)) {
        return full;
    }
    char _si_0[4096];
    snprintf(_si_0, 4096, "error: module not found: %s", dotted_path);
    printf("%s\n", strdup(_si_0));
    char _si_1[4096];
    snprintf(_si_1, 4096, "  looked at: %s", full);
    printf("%s\n", strdup(_si_1));
    return "";
}

int64_t pact_should_import_item(int64_t item, int64_t import_node) {
    if (((int64_t)(intptr_t)pact_list_get(np_is_pub, item) != 1)) {
        return 0;
    }
    const int64_t names_sl = (int64_t)(intptr_t)pact_list_get(np_args, import_node);
    if ((names_sl == (-1))) {
        return 1;
    }
    const char* item_name = (const char*)pact_list_get(np_name, item);
    int64_t i = 0;
    while ((i < pact_sublist_length(names_sl))) {
        const int64_t name_node = pact_sublist_get(names_sl, i);
        if (pact_str_eq((const char*)pact_list_get(np_name, name_node), item_name)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_merge_programs(int64_t main_prog, pact_list* imported, pact_list* import_nodes_list) {
    pact_list* _l0 = pact_list_new();
    pact_list* all_fns = _l0;
    pact_list* _l1 = pact_list_new();
    pact_list* all_types = _l1;
    pact_list* _l2 = pact_list_new();
    pact_list* all_lets = _l2;
    pact_list* _l3 = pact_list_new();
    pact_list* all_traits = _l3;
    pact_list* _l4 = pact_list_new();
    pact_list* all_impls = _l4;
    int64_t pi = 0;
    while ((pi < pact_list_len(imported))) {
        const int64_t prog = (int64_t)(intptr_t)pact_list_get(imported, pi);
        const int64_t imp_node = (int64_t)(intptr_t)pact_list_get(import_nodes_list, pi);
        const int64_t fns_sl = (int64_t)(intptr_t)pact_list_get(np_params, prog);
        int64_t fi = 0;
        while ((fi < pact_sublist_length(fns_sl))) {
            const int64_t f = pact_sublist_get(fns_sl, fi);
            if ((pact_should_import_item(f, imp_node) == 1)) {
                pact_list_push(all_fns, (void*)(intptr_t)f);
            }
            fi = (fi + 1);
        }
        const int64_t types_sl = (int64_t)(intptr_t)pact_list_get(np_fields, prog);
        int64_t ti = 0;
        while ((ti < pact_sublist_length(types_sl))) {
            const int64_t t = pact_sublist_get(types_sl, ti);
            if ((pact_should_import_item(t, imp_node) == 1)) {
                pact_list_push(all_types, (void*)(intptr_t)t);
            }
            ti = (ti + 1);
        }
        const int64_t lets_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, prog);
        int64_t li = 0;
        while ((li < pact_sublist_length(lets_sl))) {
            const int64_t l = pact_sublist_get(lets_sl, li);
            if ((pact_should_import_item(l, imp_node) == 1)) {
                pact_list_push(all_lets, (void*)(intptr_t)l);
            }
            li = (li + 1);
        }
        const int64_t traits_sl = (int64_t)(intptr_t)pact_list_get(np_arms, prog);
        int64_t tri = 0;
        while ((tri < pact_sublist_length(traits_sl))) {
            const int64_t tr = pact_sublist_get(traits_sl, tri);
            if ((pact_should_import_item(tr, imp_node) == 1)) {
                pact_list_push(all_traits, (void*)(intptr_t)tr);
            }
            tri = (tri + 1);
        }
        const int64_t impls_sl = (int64_t)(intptr_t)pact_list_get(np_methods, prog);
        int64_t ii = 0;
        while ((ii < pact_sublist_length(impls_sl))) {
            pact_list_push(all_impls, (void*)(intptr_t)pact_sublist_get(impls_sl, ii));
            ii = (ii + 1);
        }
        pi = (pi + 1);
    }
    const int64_t main_fns = (int64_t)(intptr_t)pact_list_get(np_params, main_prog);
    int64_t fi = 0;
    while ((fi < pact_sublist_length(main_fns))) {
        pact_list_push(all_fns, (void*)(intptr_t)pact_sublist_get(main_fns, fi));
        fi = (fi + 1);
    }
    const int64_t main_types = (int64_t)(intptr_t)pact_list_get(np_fields, main_prog);
    int64_t ti = 0;
    while ((ti < pact_sublist_length(main_types))) {
        pact_list_push(all_types, (void*)(intptr_t)pact_sublist_get(main_types, ti));
        ti = (ti + 1);
    }
    const int64_t main_lets = (int64_t)(intptr_t)pact_list_get(np_stmts, main_prog);
    int64_t li = 0;
    while ((li < pact_sublist_length(main_lets))) {
        pact_list_push(all_lets, (void*)(intptr_t)pact_sublist_get(main_lets, li));
        li = (li + 1);
    }
    const int64_t main_traits = (int64_t)(intptr_t)pact_list_get(np_arms, main_prog);
    int64_t tri = 0;
    while ((tri < pact_sublist_length(main_traits))) {
        pact_list_push(all_traits, (void*)(intptr_t)pact_sublist_get(main_traits, tri));
        tri = (tri + 1);
    }
    const int64_t main_impls = (int64_t)(intptr_t)pact_list_get(np_methods, main_prog);
    int64_t ii = 0;
    while ((ii < pact_sublist_length(main_impls))) {
        pact_list_push(all_impls, (void*)(intptr_t)pact_sublist_get(main_impls, ii));
        ii = (ii + 1);
    }
    const int64_t merged_fns = pact_new_sublist();
    fi = 0;
    while ((fi < pact_list_len(all_fns))) {
        pact_sublist_push(merged_fns, (int64_t)(intptr_t)pact_list_get(all_fns, fi));
        fi = (fi + 1);
    }
    pact_finalize_sublist(merged_fns);
    const int64_t merged_types = pact_new_sublist();
    ti = 0;
    while ((ti < pact_list_len(all_types))) {
        pact_sublist_push(merged_types, (int64_t)(intptr_t)pact_list_get(all_types, ti));
        ti = (ti + 1);
    }
    pact_finalize_sublist(merged_types);
    const int64_t merged_lets = pact_new_sublist();
    li = 0;
    while ((li < pact_list_len(all_lets))) {
        pact_sublist_push(merged_lets, (int64_t)(intptr_t)pact_list_get(all_lets, li));
        li = (li + 1);
    }
    pact_finalize_sublist(merged_lets);
    const int64_t merged_traits = pact_new_sublist();
    tri = 0;
    while ((tri < pact_list_len(all_traits))) {
        pact_sublist_push(merged_traits, (int64_t)(intptr_t)pact_list_get(all_traits, tri));
        tri = (tri + 1);
    }
    pact_finalize_sublist(merged_traits);
    const int64_t merged_impls = pact_new_sublist();
    ii = 0;
    while ((ii < pact_list_len(all_impls))) {
        pact_sublist_push(merged_impls, (int64_t)(intptr_t)pact_list_get(all_impls, ii));
        ii = (ii + 1);
    }
    pact_finalize_sublist(merged_impls);
    const int64_t merged = pact_new_node(pact_NodeKind_Program);
    pact_list_pop(np_params);
    pact_list_push(np_params, (void*)(intptr_t)merged_fns);
    pact_list_pop(np_fields);
    pact_list_push(np_fields, (void*)(intptr_t)merged_types);
    pact_list_pop(np_stmts);
    pact_list_push(np_stmts, (void*)(intptr_t)merged_lets);
    pact_list_pop(np_arms);
    pact_list_push(np_arms, (void*)(intptr_t)merged_traits);
    pact_list_pop(np_methods);
    pact_list_push(np_methods, (void*)(intptr_t)merged_impls);
    return merged;
}

int64_t pact_is_file_loaded(const char* path) {
    int64_t i = 0;
    while ((i < pact_list_len(loaded_files))) {
        if (pact_str_eq((const char*)pact_list_get(loaded_files, i), path)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

void pact_collect_imports(int64_t program, const char* src_root, pact_list* all_programs) {
    const int64_t imports_sl = (int64_t)(intptr_t)pact_list_get(np_elements, program);
    if ((imports_sl == (-1))) {
        return;
    }
    int64_t i = 0;
    while ((i < pact_sublist_length(imports_sl))) {
        const int64_t imp_node = pact_sublist_get(imports_sl, i);
        const char* dotted_path = (const char*)pact_list_get(np_str_val, imp_node);
        const char* file_path = pact_resolve_module_path(dotted_path, src_root);
        if (pact_str_eq(file_path, "")) {
            i = (i + 1);
            continue;
        }
        if ((pact_is_file_loaded(file_path) == 1)) {
            i = (i + 1);
            continue;
        }
        pact_list_push(loaded_files, (void*)file_path);
        const char* source = pact_read_file(file_path);
        pact_lex(source);
        pos = 0;
        const int64_t imported_prog = pact_parse_program();
        pact_collect_imports(imported_prog, src_root, all_programs);
        pact_list_push(all_programs, (void*)(intptr_t)imported_prog);
        pact_list_push(import_map_paths, (void*)file_path);
        pact_list_push(import_map_nodes, (void*)(intptr_t)imp_node);
        i = (i + 1);
    }
}

void pact_main(void) {
    if ((pact_arg_count() < 2)) {
        printf("%s\n", "Usage: pactc <source.pact> [output.c]");
        printf("%s\n", "  Compiles a Pact source file to C.");
        return;
    }
    const char* source_path = pact_get_arg(1);
    const char* source = pact_read_file(source_path);
    pact_lex(source);
    pos = 0;
    const int64_t program_node = pact_parse_program();
    pact_list_push(loaded_files, (void*)source_path);
    const char* src_root = pact_find_src_root(source_path);
    pact_list* _l0 = pact_list_new();
    pact_list* imported_programs = _l0;
    pact_collect_imports(program_node, src_root, imported_programs);
    int64_t final_program = program_node;
    if ((pact_list_len(imported_programs) > 0)) {
        final_program = pact_merge_programs(program_node, imported_programs, import_map_nodes);
    }
    const char* c_output = pact_generate(final_program);
    if ((pact_arg_count() >= 3)) {
        const char* out_path = pact_get_arg(2);
        pact_write_file(out_path, c_output);
    } else {
        printf("%s\n", c_output);
    }
}

static void __pact_init_globals(void) {
pact_list* _l0 = pact_list_new();
    tok_kinds = _l0;
pact_list* _l1 = pact_list_new();
    tok_values = _l1;
pact_list* _l2 = pact_list_new();
    tok_lines = _l2;
pact_list* _l3 = pact_list_new();
    tok_cols = _l3;
pact_list* _l4 = pact_list_new();
    np_kind = _l4;
pact_list* _l5 = pact_list_new();
    np_int_val = _l5;
pact_list* _l6 = pact_list_new();
    np_str_val = _l6;
pact_list* _l7 = pact_list_new();
    np_name = _l7;
pact_list* _l8 = pact_list_new();
    np_op = _l8;
pact_list* _l9 = pact_list_new();
    np_left = _l9;
pact_list* _l10 = pact_list_new();
    np_right = _l10;
pact_list* _l11 = pact_list_new();
    np_body = _l11;
pact_list* _l12 = pact_list_new();
    np_condition = _l12;
pact_list* _l13 = pact_list_new();
    np_then_body = _l13;
pact_list* _l14 = pact_list_new();
    np_else_body = _l14;
pact_list* _l15 = pact_list_new();
    np_scrutinee = _l15;
pact_list* _l16 = pact_list_new();
    np_pattern = _l16;
pact_list* _l17 = pact_list_new();
    np_guard = _l17;
pact_list* _l18 = pact_list_new();
    np_value = _l18;
pact_list* _l19 = pact_list_new();
    np_target = _l19;
pact_list* _l20 = pact_list_new();
    np_iterable = _l20;
pact_list* _l21 = pact_list_new();
    np_var_name = _l21;
pact_list* _l22 = pact_list_new();
    np_is_mut = _l22;
pact_list* _l23 = pact_list_new();
    np_is_pub = _l23;
pact_list* _l24 = pact_list_new();
    np_inclusive = _l24;
pact_list* _l25 = pact_list_new();
    np_start = _l25;
pact_list* _l26 = pact_list_new();
    np_end = _l26;
pact_list* _l27 = pact_list_new();
    np_obj = _l27;
pact_list* _l28 = pact_list_new();
    np_method = _l28;
pact_list* _l29 = pact_list_new();
    np_index = _l29;
pact_list* _l30 = pact_list_new();
    np_return_type = _l30;
pact_list* _l31 = pact_list_new();
    np_type_name = _l31;
pact_list* _l32 = pact_list_new();
    np_trait_name = _l32;
pact_list* _l33 = pact_list_new();
    sl_items = _l33;
pact_list* _l34 = pact_list_new();
    sl_start = _l34;
pact_list* _l35 = pact_list_new();
    sl_len = _l35;
pact_list* _l36 = pact_list_new();
    np_params = _l36;
pact_list* _l37 = pact_list_new();
    np_args = _l37;
pact_list* _l38 = pact_list_new();
    np_stmts = _l38;
pact_list* _l39 = pact_list_new();
    np_arms = _l39;
pact_list* _l40 = pact_list_new();
    np_fields = _l40;
pact_list* _l41 = pact_list_new();
    np_elements = _l41;
pact_list* _l42 = pact_list_new();
    np_methods = _l42;
pact_list* _l43 = pact_list_new();
    np_type_params = _l43;
pact_list* _l44 = pact_list_new();
    np_effects = _l44;
pact_list* _l45 = pact_list_new();
    np_captures = _l45;
pact_list* _l46 = pact_list_new();
    np_type_ann = _l46;
pact_list* _l47 = pact_list_new();
    np_handlers = _l47;
pact_list* _l48 = pact_list_new();
    cg_lines = _l48;
pact_list* _l49 = pact_list_new();
    cg_global_inits = _l49;
pact_list* _l50 = pact_list_new();
    struct_reg_names = _l50;
pact_list* _l51 = pact_list_new();
    enum_reg_names = _l51;
pact_list* _l52 = pact_list_new();
    enum_reg_variant_names = _l52;
pact_list* _l53 = pact_list_new();
    enum_reg_variant_enum_idx = _l53;
pact_list* _l54 = pact_list_new();
    var_enum_names = _l54;
pact_list* _l55 = pact_list_new();
    var_enum_types = _l55;
pact_list* _l56 = pact_list_new();
    fn_enum_ret_names = _l56;
pact_list* _l57 = pact_list_new();
    fn_enum_ret_types = _l57;
pact_list* _l58 = pact_list_new();
    emitted_let_names = _l58;
pact_list* _l59 = pact_list_new();
    emitted_fn_names = _l59;
pact_list* _l60 = pact_list_new();
    cg_closure_defs = _l60;
pact_list* _l61 = pact_list_new();
    closure_capture_names = _l61;
pact_list* _l62 = pact_list_new();
    closure_capture_types = _l62;
pact_list* _l63 = pact_list_new();
    closure_capture_muts = _l63;
pact_list* _l64 = pact_list_new();
    closure_capture_starts = _l64;
pact_list* _l65 = pact_list_new();
    closure_capture_counts = _l65;
pact_list* _l66 = pact_list_new();
    mut_captured_vars = _l66;
pact_list* _l67 = pact_list_new();
    trait_reg_names = _l67;
pact_list* _l68 = pact_list_new();
    trait_reg_method_sl = _l68;
pact_list* _l69 = pact_list_new();
    impl_reg_trait = _l69;
pact_list* _l70 = pact_list_new();
    impl_reg_type = _l70;
pact_list* _l71 = pact_list_new();
    impl_reg_methods_sl = _l71;
pact_list* _l72 = pact_list_new();
    from_reg_source = _l72;
pact_list* _l73 = pact_list_new();
    from_reg_target = _l73;
pact_list* _l74 = pact_list_new();
    from_reg_method_sl = _l74;
pact_list* _l75 = pact_list_new();
    var_struct_names = _l75;
pact_list* _l76 = pact_list_new();
    var_struct_types = _l76;
pact_list* _l77 = pact_list_new();
    sf_reg_struct = _l77;
pact_list* _l78 = pact_list_new();
    sf_reg_field = _l78;
pact_list* _l79 = pact_list_new();
    sf_reg_type = _l79;
pact_list* _l80 = pact_list_new();
    sf_reg_stype = _l80;
pact_list* _l81 = pact_list_new();
    var_closure_names = _l81;
pact_list* _l82 = pact_list_new();
    var_closure_sigs = _l82;
pact_list* _l83 = pact_list_new();
    generic_fn_names = _l83;
pact_list* _l84 = pact_list_new();
    generic_fn_nodes = _l84;
pact_list* _l85 = pact_list_new();
    mono_fn_bases = _l85;
pact_list* _l86 = pact_list_new();
    mono_fn_args = _l86;
pact_list* _l87 = pact_list_new();
    mono_base_names = _l87;
pact_list* _l88 = pact_list_new();
    mono_concrete_args = _l88;
pact_list* _l89 = pact_list_new();
    mono_c_names = _l89;
pact_list* _l90 = pact_list_new();
    var_option_names = _l90;
pact_list* _l91 = pact_list_new();
    var_option_inner = _l91;
pact_list* _l92 = pact_list_new();
    var_result_names = _l92;
pact_list* _l93 = pact_list_new();
    var_result_ok = _l93;
pact_list* _l94 = pact_list_new();
    var_result_err = _l94;
pact_list* _l95 = pact_list_new();
    emitted_option_types = _l95;
pact_list* _l96 = pact_list_new();
    emitted_result_types = _l96;
pact_list* _l97 = pact_list_new();
    scope_names = _l97;
pact_list* _l98 = pact_list_new();
    scope_types = _l98;
pact_list* _l99 = pact_list_new();
    scope_muts = _l99;
pact_list* _l100 = pact_list_new();
    scope_frame_starts = _l100;
pact_list* _l101 = pact_list_new();
    fn_reg_names = _l101;
pact_list* _l102 = pact_list_new();
    fn_reg_ret = _l102;
pact_list* _l103 = pact_list_new();
    fn_reg_effect_sl = _l103;
pact_list* _l104 = pact_list_new();
    effect_reg_names = _l104;
pact_list* _l105 = pact_list_new();
    effect_reg_parent = _l105;
pact_list* _l106 = pact_list_new();
    var_list_elem_names = _l106;
pact_list* _l107 = pact_list_new();
    var_list_elem_types = _l107;
pact_list* _l108 = pact_list_new();
    match_scrut_strs = _l108;
pact_list* _l109 = pact_list_new();
    match_scrut_types = _l109;
pact_list* _l110 = pact_list_new();
    loaded_files = _l110;
pact_list* _l111 = pact_list_new();
    import_map_paths = _l111;
pact_list* _l112 = pact_list_new();
    import_map_nodes = _l112;
}

int main(int argc, char** argv) {
    pact_g_argc = argc;
    pact_g_argv = (const char**)argv;
    __pact_init_globals();
    pact_main();
    return 0;
}