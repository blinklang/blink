#include "runtime.h"

static pact_ctx __pact_ctx;

typedef struct {
} pact_ue_lex_vtable;

static pact_ue_lex_vtable pact_ue_lex_vtable_default = {
};

static pact_ue_lex_vtable* __pact_ue_lex = &pact_ue_lex_vtable_default;

typedef struct {
} pact_ue_diag_vtable;

static pact_ue_diag_vtable pact_ue_diag_vtable_default = {
};

static pact_ue_diag_vtable* __pact_ue_diag = &pact_ue_diag_vtable_default;

typedef struct {
} pact_ue_parse_vtable;

static pact_ue_parse_vtable pact_ue_parse_vtable_default = {
};

static pact_ue_parse_vtable* __pact_ue_parse = &pact_ue_parse_vtable_default;

typedef struct {
} pact_ue_typecheck_vtable;

static pact_ue_typecheck_vtable pact_ue_typecheck_vtable_default = {
};

static pact_ue_typecheck_vtable* __pact_ue_typecheck = &pact_ue_typecheck_vtable_default;

typedef struct {
} pact_ue_codegen_vtable;

static pact_ue_codegen_vtable pact_ue_codegen_vtable_default = {
};

static pact_ue_codegen_vtable* __pact_ue_codegen = &pact_ue_codegen_vtable_default;

typedef struct {
} pact_ue_format_vtable;

static pact_ue_format_vtable pact_ue_format_vtable_default = {
};

static pact_ue_format_vtable* __pact_ue_format = &pact_ue_format_vtable_default;

typedef struct {
} pact_ue_daemon_vtable;

static pact_ue_daemon_vtable pact_ue_daemon_vtable_default = {
};

static pact_ue_daemon_vtable* __pact_ue_daemon = &pact_ue_daemon_vtable_default;

typedef enum { pact_TokenKind_Fn, pact_TokenKind_Let, pact_TokenKind_Mut, pact_TokenKind_Type, pact_TokenKind_Trait, pact_TokenKind_Impl, pact_TokenKind_If, pact_TokenKind_Else, pact_TokenKind_Match, pact_TokenKind_For, pact_TokenKind_In, pact_TokenKind_While, pact_TokenKind_Loop, pact_TokenKind_Break, pact_TokenKind_Continue, pact_TokenKind_Return, pact_TokenKind_Pub, pact_TokenKind_With, pact_TokenKind_Handler, pact_TokenKind_Self, pact_TokenKind_Test, pact_TokenKind_Import, pact_TokenKind_As, pact_TokenKind_Mod, pact_TokenKind_Effect, pact_TokenKind_Assert, pact_TokenKind_AssertEq, pact_TokenKind_AssertNe, pact_TokenKind_Ident, pact_TokenKind_Int, pact_TokenKind_Float, pact_TokenKind_StringStart, pact_TokenKind_StringEnd, pact_TokenKind_StringPart, pact_TokenKind_InterpStart, pact_TokenKind_InterpEnd, pact_TokenKind_LParen, pact_TokenKind_RParen, pact_TokenKind_LBrace, pact_TokenKind_RBrace, pact_TokenKind_LBracket, pact_TokenKind_RBracket, pact_TokenKind_Colon, pact_TokenKind_Comma, pact_TokenKind_Dot, pact_TokenKind_DotDot, pact_TokenKind_DotDoteq, pact_TokenKind_Arrow, pact_TokenKind_FatArrow, pact_TokenKind_At, pact_TokenKind_Plus, pact_TokenKind_Minus, pact_TokenKind_Star, pact_TokenKind_Slash, pact_TokenKind_Percent, pact_TokenKind_Equals, pact_TokenKind_EqEq, pact_TokenKind_NotEq, pact_TokenKind_Less, pact_TokenKind_Greater, pact_TokenKind_LessEq, pact_TokenKind_GreaterEq, pact_TokenKind_And, pact_TokenKind_Or, pact_TokenKind_Bang, pact_TokenKind_Question, pact_TokenKind_DoubleQuestion, pact_TokenKind_Pipe, pact_TokenKind_PipeArrow, pact_TokenKind_PlusEq, pact_TokenKind_MinusEq, pact_TokenKind_StarEq, pact_TokenKind_SlashEq, pact_TokenKind_Newline, pact_TokenKind_EOF, pact_TokenKind_Comment, pact_TokenKind_DocComment } pact_TokenKind;

typedef struct {
    int64_t kind;
    const char* value;
    int64_t line;
    int64_t col;
} pact_Token;

typedef enum { pact_NodeKind_IntLit, pact_NodeKind_FloatLit, pact_NodeKind_Ident, pact_NodeKind_Call, pact_NodeKind_MethodCall, pact_NodeKind_BinOp, pact_NodeKind_UnaryOp, pact_NodeKind_InterpString, pact_NodeKind_BoolLit, pact_NodeKind_TupleLit, pact_NodeKind_ListLit, pact_NodeKind_StructLit, pact_NodeKind_FieldAccess, pact_NodeKind_IndexExpr, pact_NodeKind_RangeLit, pact_NodeKind_IfExpr, pact_NodeKind_MatchExpr, pact_NodeKind_Closure, pact_NodeKind_LetBinding, pact_NodeKind_ExprStmt, pact_NodeKind_Assignment, pact_NodeKind_CompoundAssign, pact_NodeKind_Return, pact_NodeKind_ForIn, pact_NodeKind_WhileLoop, pact_NodeKind_LoopExpr, pact_NodeKind_Break, pact_NodeKind_Continue, pact_NodeKind_Block, pact_NodeKind_FnDef, pact_NodeKind_Param, pact_NodeKind_Program, pact_NodeKind_TypeDef, pact_NodeKind_TypeField, pact_NodeKind_TypeVariant, pact_NodeKind_TraitDef, pact_NodeKind_ImplBlock, pact_NodeKind_TestBlock, pact_NodeKind_IntPattern, pact_NodeKind_WildcardPattern, pact_NodeKind_IdentPattern, pact_NodeKind_TuplePattern, pact_NodeKind_StringPattern, pact_NodeKind_OrPattern, pact_NodeKind_RangePattern, pact_NodeKind_StructPattern, pact_NodeKind_EnumPattern, pact_NodeKind_AsPattern, pact_NodeKind_MatchArm, pact_NodeKind_StructLitField, pact_NodeKind_WithBlock, pact_NodeKind_WithResource, pact_NodeKind_HandlerExpr, pact_NodeKind_Annotation, pact_NodeKind_ModBlock, pact_NodeKind_ImportStmt, pact_NodeKind_TypeAnn, pact_NodeKind_TypeParam, pact_NodeKind_EffectDecl, pact_NodeKind_AsyncScope, pact_NodeKind_AsyncSpawn, pact_NodeKind_AwaitExpr, pact_NodeKind_ChannelNew } pact_NodeKind;

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

typedef struct {
    const char* name;
    int64_t has_data;
} pact_EnumReg;

typedef struct {
    const char* name;
    int64_t enum_idx;
    const char* field_names;
    const char* field_types;
    int64_t field_count;
} pact_EnumVariant;

typedef struct {
    const char* name;
    const char* enum_type;
} pact_VarEnumEntry;

typedef struct {
    const char* name;
    const char* enum_type;
} pact_FnEnumRetEntry;

typedef struct {
    const char* name;
    int64_t ctype;
    int64_t is_mut;
} pact_CaptureEntry;

typedef struct {
    int64_t start;
    int64_t count;
} pact_ClosureCapInfo;

typedef struct {
    const char* name;
    int64_t method_sl;
} pact_TraitEntry;

typedef struct {
    const char* trait_name;
    const char* type_name;
    int64_t methods_sl;
} pact_ImplEntry;

typedef struct {
    const char* source;
    const char* target;
    int64_t method_sl;
} pact_FromImplEntry;

typedef struct {
    const char* source;
    const char* target;
    int64_t method_sl;
} pact_TryFromImplEntry;

typedef struct {
    const char* name;
    const char* stype;
} pact_VarStructEntry;

typedef struct {
    const char* struct_name;
    const char* field_name;
    int64_t field_type;
    const char* stype;
} pact_StructFieldEntry;

typedef struct {
    const char* name;
    const char* sig;
} pact_VarClosureEntry;

typedef struct {
    const char* name;
    int64_t node;
} pact_GenericFnEntry;

typedef struct {
    const char* base;
    const char* args;
} pact_MonoFnInstance;

typedef struct {
    const char* base;
    const char* args;
    const char* c_name;
} pact_MonoInstance;

typedef struct {
    const char* name;
    int64_t inner;
} pact_VarOptionEntry;

typedef struct {
    const char* name;
    int64_t ok_type;
    int64_t err_type;
} pact_VarResultEntry;

typedef struct {
    const char* name;
    int64_t inner;
    const char* next_fn;
    const char* next_name;
} pact_VarIteratorEntry;

typedef struct {
    const char* name;
    const char* target;
} pact_VarAliasEntry;

typedef struct {
    const char* name;
    int64_t inner;
} pact_VarHandleEntry;

typedef struct {
    const char* name;
    int64_t inner;
} pact_VarChannelEntry;

typedef struct {
    const char* name;
    int64_t ctype;
    int64_t is_mut;
} pact_ScopeVar;

typedef struct {
    const char* name;
    int64_t ret;
    int64_t effect_sl;
} pact_FnRegEntry;

typedef struct {
    const char* name;
    const char* stype;
} pact_FnRetStructEntry;

typedef struct {
    const char* name;
    int64_t kind;
    int64_t inner1;
    int64_t inner2;
} pact_RetType;

typedef struct {
    const char* name;
    int64_t parent;
} pact_EffectEntry;

typedef struct {
    const char* name;
    const char* handle;
} pact_UeEffect;

typedef struct {
    const char* name;
    const char* params;
    const char* ret;
    const char* effect_handle;
} pact_UeMethod;

typedef struct {
    const char* name;
    int64_t elem_type;
    const char* struct_name;
} pact_VarListElemEntry;

typedef struct {
    const char* name;
    int64_t key_type;
    int64_t value_type;
    const char* value_struct;
} pact_VarMapEntry;

typedef struct {
    const char* str_val;
    int64_t scrut_type;
} pact_MatchScrutEntry;

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
static pact_list* diag_severity;
static pact_list* diag_name;
static pact_list* diag_code;
static pact_list* diag_message;
static pact_list* diag_file;
static pact_list* diag_line;
static pact_list* diag_col;
static pact_list* diag_help;
static pact_list* diag_end_line;
static pact_list* diag_end_col;
static int64_t diag_format = 0;
static const char* diag_source_file = "";
static int64_t diag_count = 0;
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
static pact_list* np_leading_comments;
static pact_list* np_doc_comment;
static pact_list* np_line;
static pact_list* np_col;
static pact_list* np_end_line;
static pact_list* np_end_col;
static pact_list* pending_comments;
static const char* pending_doc_comment = "";
static pact_list* annotation_nodes;
static int64_t pos = 0;
static const int64_t TK_INT = 0;
static const int64_t TK_FLOAT = 1;
static const int64_t TK_BOOL = 2;
static const int64_t TK_STR = 3;
static const int64_t TK_VOID = 4;
static const int64_t TK_LIST = 5;
static const int64_t TK_OPTION = 6;
static const int64_t TK_RESULT = 7;
static const int64_t TK_FN = 8;
static const int64_t TK_STRUCT = 9;
static const int64_t TK_ENUM = 10;
static const int64_t TK_TYPEVAR = 11;
static const int64_t TK_UNKNOWN = 12;
static const int64_t TK_CLOSURE = 13;
static const int64_t TK_ITERATOR = 14;
static const int64_t TK_HANDLE = 15;
static const int64_t TK_CHANNEL = 16;
static const int64_t TK_TUPLE = 17;
static const int64_t TK_MAP = 18;
static pact_list* ty_kind;
static pact_list* ty_name;
static pact_list* ty_inner1;
static pact_list* ty_inner2;
static pact_list* ty_params_start;
static pact_list* ty_params_count;
static pact_list* ty_param_list;
static int64_t TYPE_INT = (-1);
static int64_t TYPE_FLOAT = (-1);
static int64_t TYPE_BOOL = (-1);
static int64_t TYPE_STR = (-1);
static int64_t TYPE_VOID = (-1);
static int64_t TYPE_UNKNOWN = (-1);
static pact_list* named_type_names;
static pact_list* named_type_ids;
static pact_list* sfield_struct_id;
static pact_list* sfield_name;
static pact_list* sfield_type_id;
static pact_list* evar_enum_id;
static pact_list* evar_name;
static pact_list* evar_tag;
static pact_list* evar_has_data;
static pact_list* evfield_var_idx;
static pact_list* evfield_name;
static pact_list* evfield_type_id;
static pact_map* named_type_map;
static pact_map* fnsig_map;
static pact_list* fnsig_name;
static pact_list* fnsig_ret;
static pact_list* fnsig_params_start;
static pact_list* fnsig_params_count;
static pact_list* fnsig_param_list;
static pact_list* fnsig_type_params_start;
static pact_list* fnsig_type_params_count;
static pact_list* fnsig_type_param_names;
static pact_list* tc_trait_names;
static pact_list* tc_trait_method_names;
static pact_list* tc_fn_effects;
static int64_t tc_current_fn_ret = (-1);
static const char* tc_current_fn_name = "";
static pact_list* tc_errors;
static pact_list* tc_warnings;
static int64_t tc_inc_enabled = 0;
static pact_map* tc_inc_filter;
static pact_list* nr_scope_names;
static pact_list* nr_scope_muts;
static pact_list* nr_scope_types;
static pact_list* nr_scope_frames;
static pact_list* nr_impl_type_names;
static pact_list* nr_impl_method_names;
static const int64_t CT_INT = 0;
static const int64_t CT_FLOAT = 1;
static const int64_t CT_BOOL = 2;
static const int64_t CT_STRING = 3;
static const int64_t CT_LIST = 4;
static const int64_t CT_VOID = 5;
static const int64_t CT_CLOSURE = 6;
static const int64_t CT_OPTION = 7;
static const int64_t CT_RESULT = 8;
static const int64_t CT_ITERATOR = 9;
static const int64_t CT_HANDLE = 10;
static const int64_t CT_CHANNEL = 11;
static const int64_t CT_TAGGED_ENUM = 12;
static const int64_t CT_MAP = 13;
static pact_list* cg_lines;
static int64_t cg_indent = 0;
static int64_t cg_temp_counter = 0;
static pact_list* cg_global_inits;
static pact_list* struct_reg_names;
static pact_list* enum_regs;
static pact_list* enum_variants;
static pact_list* var_enums;
static pact_list* fn_enum_rets;
static pact_list* emitted_let_names;
static pact_list* emitted_fn_names;
static pact_map* struct_reg_set;
static pact_map* enum_reg_set;
static pact_map* emitted_fn_set;
static pact_map* emitted_let_set;
static pact_map* emitted_option_set;
static pact_map* emitted_result_set;
static pact_map* emitted_iter_set;
static pact_list* cg_closure_defs;
static int64_t cg_closure_counter = 0;
static pact_list* closure_captures;
static pact_list* closure_cap_infos;
static int64_t cg_closure_cap_start = (-1);
static int64_t cg_closure_cap_count = 0;
static pact_list* mut_captured_vars;
static pact_list* trait_entries;
static pact_list* impl_entries;
static pact_list* from_entries;
static pact_list* tryfrom_entries;
static pact_list* var_structs;
static pact_list* var_struct_frame_starts;
static pact_list* sf_entries;
static pact_list* var_closures;
static pact_list* var_closure_frame_starts;
static pact_list* generic_fns;
static pact_list* mono_fns;
static pact_list* mono_instances;
static pact_list* var_options;
static pact_list* var_option_frame_starts;
static pact_list* var_results;
static pact_list* var_result_frame_starts;
static pact_list* emitted_option_types;
static pact_list* emitted_result_types;
static pact_list* emitted_iter_types;
static int64_t emitted_range_iter = 0;
static int64_t emitted_str_iter = 0;
static pact_list* var_iterators;
static pact_list* var_iterator_frame_starts;
static pact_list* var_aliases;
static pact_list* var_alias_frame_starts;
static pact_list* emitted_map_iters;
static pact_list* emitted_filter_iters;
static pact_list* emitted_take_iters;
static pact_list* emitted_skip_iters;
static pact_list* emitted_chain_iters;
static pact_list* emitted_flat_map_iters;
static pact_list* var_handles;
static pact_list* var_handle_frame_starts;
static pact_list* var_channels;
static pact_list* var_channel_frame_starts;
static int64_t cg_let_target_type = 0;
static const char* cg_let_target_name = "";
static const char* cg_handler_vtable_field = "";
static int64_t cg_handler_is_user_effect = 0;
static int64_t cg_in_handler_body = 0;
static const char* cg_handler_body_vtable_type = "";
static const char* cg_handler_body_field = "";
static int64_t cg_handler_body_is_ue = 0;
static int64_t cg_handler_body_idx = 0;
static pact_list* scope_vars;
static pact_list* scope_frame_starts;
static pact_list* fn_regs;
static pact_list* fn_ret_structs;
static pact_list* fn_ret_types;
static pact_list* effect_entries;
static pact_list* ue_effects;
static pact_list* ue_methods;
static pact_list* cap_budget_names;
static int64_t cap_budget_active = 0;
static const char* cg_current_fn_name = "";
static int64_t cg_current_fn_ret = 0;
static pact_list* var_list_elems;
static pact_list* var_list_elem_frame_starts;
static pact_list* var_maps;
static pact_list* var_map_frame_starts;
static int64_t cg_program_node = 0;
static int64_t cg_uses_async = 0;
static int64_t cg_async_wrapper_counter = 0;
static pact_list* cg_async_scope_stack;
static int64_t cg_async_scope_counter = 0;
static pact_list* match_scruts;
static const char* match_scrut_enum = "";
static int64_t cg_debug_mode = 0;
static pact_list* prescan_mut_names;
static pact_list* prescan_closure_idents;
static const char* expr_result_str = "";
static int64_t expr_result_type = 0;
static const char* expr_closure_sig = "";
static int64_t expr_option_inner = (-1);
static int64_t expr_result_ok_type = (-1);
static int64_t expr_result_err_type = (-1);
static int64_t expr_list_elem_type = (-1);
static const char* expr_iter_next_fn = "";
static const char* ifs_iter_var = "";
static const char* ifs_next_fn = "";
static int64_t ifs_elem_type = 0;
static const char* ifs_opt_type = "";
static pact_list* fmt_lines;
static int64_t fmt_indent = 0;
static const int64_t fmt_max_line = 100;
static pact_list* binop_parts;
static pact_list* binop_ops;
static pact_list* ma_fn_names;
static pact_list* ma_write_items;
static pact_list* ma_write_starts;
static pact_list* ma_write_counts;
static pact_list* ma_globals;
static pact_list* ma_call_edges_from;
static pact_list* ma_call_edges_to;
static pact_map* fn_name_map;
static pact_map* global_set;
static pact_map* global_idx_map;
static pact_map* mutating_method_set;
static pact_list* writes_mat;
static int64_t writes_mat_cols = 0;
static pact_list* sr_save_local;
static pact_list* sr_save_global;
static pact_map* sr_restore_globals;
static const char* sr_current_fn = "";
static const int64_t SK_FN = 0;
static const int64_t SK_STRUCT = 1;
static const int64_t SK_ENUM = 2;
static const int64_t SK_TRAIT = 3;
static const int64_t SK_LET = 4;
static const int64_t DK_CALLS = 0;
static const int64_t DK_USES_TYPE = 1;
static const int64_t DK_FIELD_ACCESS = 2;
static const int64_t VIS_PRIVATE = 0;
static const int64_t VIS_PUB = 1;
static pact_list* si_sym_name;
static pact_list* si_sym_kind;
static pact_list* si_sym_module;
static pact_list* si_sym_file;
static pact_list* si_sym_line;
static pact_list* si_sym_vis;
static pact_list* si_sym_effects;
static pact_list* si_sym_sig;
static pact_list* si_sym_ret_type;
static pact_list* si_sym_param_types;
static pact_list* si_sym_doc;
static pact_list* si_sym_intent;
static pact_list* si_sym_requires;
static pact_list* si_sym_ensures;
static pact_list* si_sym_end_line;
static int64_t si_sym_count = 0;
static pact_list* si_dep_from;
static pact_list* si_dep_to;
static pact_list* si_dep_kind;
static int64_t si_dep_count = 0;
static pact_list* si_rdep_from;
static pact_list* si_rdep_to;
static int64_t si_rdep_count = 0;
static pact_list* si_file_path;
static pact_list* si_file_mtime;
static pact_list* si_file_sym_start;
static pact_list* si_file_sym_end;
static int64_t si_file_count = 0;
static pact_map* sym_name_map;
static pact_map* file_path_map;
static pact_list* fw_path;
static pact_list* fw_mtime;
static int64_t fw_count = 0;
static pact_list* fw_dirty_path;
static int64_t fw_dirty_count = 0;
static int64_t fw_poll_interval = 500;
static pact_map* path_map;
static pact_list* qr_keys;
static pact_list* qr_vals;
static pact_list* inc_snap_path;
static pact_list* inc_snap_mtime;
static int64_t inc_snap_count = 0;
static pact_list* inc_dirty_path;
static int64_t inc_dirty_count = 0;
static pact_list* inc_affected;
static int64_t inc_affected_count = 0;
static pact_map* affected_map;
static pact_map* snap_path_map;
static int64_t daemon_running = 0;
static int64_t daemon_socket_fd = (-1);
static const char* daemon_pid_path = "";
static const char* daemon_sock_path = "";
static const char* daemon_project_root = "";
static const char* daemon_source_path = "";
static int64_t daemon_start_time = 0;
static int64_t daemon_check_count = 0;
static int64_t daemon_program = (-1);
static pact_list* dr_keys;
static pact_list* dr_vals;
static const int64_t CH_CR = 13;
static const int64_t CH_HASH = 35;
static const int64_t CH_z = 122;
static const int64_t CH_TILDE = 126;
static const int64_t CH_CARET = 94;
static const int64_t CH_r = 114;
static const int64_t TOML_STRING = 0;
static const int64_t TOML_INT = 1;
static const int64_t TOML_BOOL = 2;
static const int64_t TOML_ARRAY = 3;
static const int64_t TOML_INLINE_TABLE = 4;
static pact_list* toml_keys;
static pact_list* toml_values;
static pact_list* toml_types;
static pact_list* arr_table_names;
static pact_list* arr_table_counts;
static const char* tmp_str = "";
static int64_t tmp_pos = 0;
static int64_t lock_version = 0;
static const char* lock_pact_version = "";
static const char* lock_generated = "";
static pact_list* lock_pkg_names;
static pact_list* lock_pkg_versions;
static pact_list* lock_pkg_sources;
static pact_list* lock_pkg_hashes;
static pact_list* lock_pkg_caps;
static int64_t lockfile_loaded = 0;
static pact_list* loaded_files;
static pact_list* import_map_paths;
static pact_list* import_map_nodes;

pact_Token pact_make_token(int64_t kind, const char* value, int64_t line, int64_t col);
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
void pact_diag_emit(const char* severity, const char* name, const char* code, const char* message, int64_t line, int64_t col, const char* help);
void pact_diag_error(const char* name, const char* code, const char* message, int64_t line, int64_t col, const char* help);
void pact_diag_error_no_loc(const char* name, const char* code, const char* message, const char* help);
void pact_diag_error_at(const char* name, const char* code, const char* message, int64_t node_id, const char* help);
void pact_diag_warn(const char* name, const char* code, const char* message, int64_t line, int64_t col, const char* help);
void pact_diag_warn_no_loc(const char* name, const char* code, const char* message, const char* help);
void pact_diag_warn_at(const char* name, const char* code, const char* message, int64_t node_id, const char* help);
void pact_diag_emit_range(const char* severity, const char* name, const char* code, const char* message, int64_t line, int64_t col, int64_t end_line, int64_t end_col, const char* help);
const char* pact_json_escape(const char* s);
void pact_diag_flush(void);
void pact_diag_print_json(int64_t idx);
void pact_diag_print_human(int64_t idx);
void pact_diag_reset(void);
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
void pact_skip_comments(void);
void pact_maybe_newline(void);
void pact_attach_comments(int64_t node);
void pact_flush_pending_comments(void);
void pact_attach_pending_annotations(int64_t node);
int64_t pact_parse_import_stmt(void);
int64_t pact_parse_program(void);
int64_t pact_parse_type_params(void);
int64_t pact_parse_type_def(void);
int64_t pact_parse_type_annotation(void);
int64_t pact_parse_effect_op_sig(void);
int64_t pact_parse_effect_decl(void);
int64_t pact_parse_fn_def(void);
int64_t pact_parse_test_block(void);
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
int64_t pact_new_type(int64_t kind, const char* name);
int64_t pact_make_list_type(int64_t inner);
int64_t pact_make_option_type(int64_t inner);
int64_t pact_make_result_type(int64_t ok_type, int64_t err_type);
int64_t pact_make_fn_type(int64_t ret_type, pact_list* param_types);
int64_t pact_make_typevar(const char* name);
int64_t pact_make_tuple_type(pact_list* elem_types);
int64_t pact_make_map_type(int64_t key_type, int64_t value_type);
int64_t pact_lookup_named_type(const char* name);
int64_t pact_resolve_type_name(const char* name);
int64_t pact_get_struct_field_tid(int64_t struct_tid, const char* fname);
int64_t pact_get_variant_by_name(int64_t enum_tid, const char* vname);
int64_t pact_lookup_fnsig(const char* name);
int64_t pact_instantiate_return_type(int64_t sig, int64_t args_sl);
void pact_tc_error(const char* msg);
void pact_tc_warn(const char* msg);
void pact_tc_set_incremental_filter(pact_list* names);
void pact_tc_clear_incremental_filter(void);
int64_t pact_tc_should_check_fn(const char* name);
int64_t pact_resolve_type_ann(int64_t ann_node);
void pact_register_struct_type(int64_t td);
void pact_register_enum_type(int64_t td);
void pact_register_fn_sig(int64_t fn_node);
const char* pact_tc_get_fn_effects(const char* name);
void pact_register_trait(int64_t tr_node);
void pact_init_types(void);
int64_t pact_check_types(int64_t program);
void pact_nr_push_scope(void);
void pact_nr_pop_scope(void);
void pact_nr_define(const char* name);
void pact_nr_define_mut(const char* name, int64_t is_mut);
void pact_nr_define_typed(const char* name, int64_t is_mut, int64_t tid);
int64_t pact_nr_is_defined(const char* name);
int64_t pact_nr_is_mut(const char* name);
int64_t pact_nr_get_type(const char* name);
int64_t pact_is_builtin_fn(const char* name);
int64_t pact_get_builtin_fn_ret(const char* name);
int64_t pact_is_variant_name(const char* name);
int64_t pact_get_variant_enum_tid(const char* name);
int64_t pact_is_known_type(const char* name);
int64_t pact_nr_has_impl_method(const char* type_name, const char* method);
void pact_resolve_names(int64_t program);
void pact_nr_check_fn(int64_t fn_node);
void pact_nr_check_type_ref(const char* name);
void pact_nr_check_node(int64_t node);
void pact_nr_check_pattern(int64_t node);
int64_t pact_types_compatible(int64_t a, int64_t b);
int64_t pact_type_kind(int64_t tid);
int64_t pact_is_bool_compat(int64_t tid);
int64_t pact_infer_type(int64_t node);
int64_t pact_resolve_param_type(int64_t p);
void pact_tc_check_fn(int64_t fn_node);
void pact_tc_check_body(int64_t node);
void pact_tc_check_pattern_types(int64_t node);
void pact_tc_infer_program(int64_t program);
const char* pact_type_to_str(int64_t tid);
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
void pact_reg_fn_struct_ret(const char* name, const char* stype);
const char* pact_get_fn_ret_struct(const char* name);
void pact_reg_fn_ret_type(const char* name, int64_t kind, int64_t inner1, int64_t inner2);
pact_RetType pact_get_fn_ret_type(const char* name);
const char* pact_resolve_ret_type_from_ann(int64_t fn_node);
void pact_reg_fn_ret_from_ann(const char* name, int64_t fn_node);
int64_t pact_reg_effect(const char* name, int64_t parent);
int64_t pact_get_effect_idx(const char* name);
int64_t pact_effect_satisfies(const char* caller_effect, const char* callee_effect);
void pact_check_effect_propagation(const char* callee_name);
void pact_check_capabilities_budget(const char* fn_name, int64_t effects_sl);
void pact_init_builtin_effects(void);
const char* pact_get_ue_handle(const char* effect_name);
const char* pact_get_ue_top_for_handle(const char* handle);
int64_t pact_is_user_effect_handle(const char* name);
int64_t pact_ue_has_method(const char* handle, const char* method);
int64_t pact_is_fn_registered(const char* name);
int64_t pact_get_fn_ret(const char* name);
void pact_set_list_elem_type(const char* name, int64_t elem_type);
int64_t pact_get_list_elem_type(const char* name);
void pact_set_list_elem_struct(const char* name, const char* struct_name);
const char* pact_get_list_elem_struct(const char* name);
void pact_set_map_types(const char* name, int64_t key_type, int64_t value_type);
int64_t pact_get_map_key_type(const char* name);
int64_t pact_get_map_value_type(const char* name);
void pact_set_map_value_struct(const char* name, const char* struct_name);
const char* pact_get_map_value_struct(const char* name);
int64_t pact_is_struct_type(const char* name);
int64_t pact_is_enum_type(const char* name);
const char* pact_resolve_variant(const char* name);
const char* pact_get_var_enum(const char* name);
int64_t pact_is_data_enum(const char* name);
int64_t pact_get_variant_index(const char* enum_name, const char* variant_name);
int64_t pact_get_variant_tag(const char* enum_name, const char* variant_name);
int64_t pact_get_variant_field_count(int64_t variant_idx);
const char* pact_get_variant_field_name(int64_t variant_idx, int64_t field_idx);
const char* pact_get_variant_field_type_str(int64_t variant_idx, int64_t field_idx);
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
int64_t pact_find_tryfrom_impl(const char* source, const char* target);
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
void pact_set_var_iterator(const char* name, int64_t inner, const char* next_fn);
int64_t pact_get_var_iterator_inner(const char* name);
const char* pact_get_var_iter_next_fn(const char* name);
void pact_set_var_alias(const char* name, const char* target);
const char* pact_get_var_alias(const char* name);
void pact_set_var_handle(const char* name, int64_t inner);
int64_t pact_get_var_handle_inner(const char* name);
void pact_set_var_channel(const char* name, int64_t inner);
int64_t pact_get_var_channel_inner(const char* name);
void pact_emit_option_typedef(int64_t inner);
void pact_emit_result_typedef(int64_t ok_t, int64_t err_t);
void pact_ensure_iter_type(int64_t inner);
void pact_ensure_range_iter(void);
void pact_ensure_str_iter(void);
void pact_emit_range_iter_typedef(void);
void pact_emit_str_iter_typedef(void);
const char* pact_list_iter_c_type(int64_t inner);
void pact_emit_list_iter_typedef(int64_t inner);
void pact_emit_all_iter_types(void);
void pact_emit_iter_types_from(int64_t list_start, int64_t map_start, int64_t filter_start, int64_t take_start, int64_t skip_start, int64_t chain_start, int64_t flat_map_start);
int pact_has_int_in_list(pact_list* lst, int64_t val);
void pact_ensure_map_iter(int64_t inner);
void pact_ensure_filter_iter(int64_t inner);
void pact_ensure_take_iter(int64_t inner);
void pact_ensure_skip_iter(int64_t inner);
void pact_ensure_chain_iter(int64_t inner);
void pact_ensure_flat_map_iter(int64_t inner);
void pact_emit_map_iter_typedef(int64_t inner);
void pact_emit_filter_iter_typedef(int64_t inner);
void pact_emit_take_iter_typedef(int64_t inner);
void pact_emit_skip_iter_typedef(int64_t inner);
void pact_emit_chain_iter_typedef(int64_t inner);
void pact_emit_flat_map_iter_typedef(int64_t inner);
void pact_emit_all_option_result_types(void);
void pact_emit_option_result_types_from(int64_t opt_start, int64_t res_start);
const char* pact_fresh_temp(const char* prefix);
void pact_emit_line(const char* line);
const char* pact_join_lines(void);
void pact_emit_method_call(int64_t node);
int64_t pact_list_contains_str(pact_list* lst, const char* val);
int64_t pact_is_in_scope(const char* name);
void pact_collect_free_vars(int64_t node, pact_list* params, pact_list* locals, pact_list* result);
void pact_collect_free_vars_block(int64_t block, pact_list* params, pact_list* locals, pact_list* result);
pact_list* pact_analyze_captures(int64_t body, int64_t params_sl);
void pact_prescan_collect_muts(int64_t node);
void pact_prescan_collect_muts_block(int64_t block);
void pact_prescan_collect_closure_idents(int64_t node);
void pact_prescan_collect_closure_idents_block(int64_t block);
void pact_prescan_closures_in_node(int64_t node);
void pact_prescan_closures_in_block(int64_t block);
void pact_prescan_mut_captures(int64_t block);
void pact_emit_closure(int64_t node);
void pact_iter_from_source(const char* obj_str, int64_t obj_type);
void pact_emit_expr(int64_t node);
void pact_emit_handler_expr(int64_t node);
void pact_emit_async_spawn_closure(int64_t closure_node, int64_t wrapper_idx, const char* wrapper_name, const char* task_fn_name);
void pact_emit_await_expr(int64_t node);
void pact_emit_async_scope(int64_t node);
void pact_emit_binop(int64_t node);
void pact_emit_unaryop(int64_t node);
void pact_emit_call(int64_t node);
const char* pact_escape_c_string(const char* s);
void pact_emit_interp_string(int64_t node);
void pact_emit_list_lit(int64_t node);
const char* pact_infer_struct_type_args(const char* type_name, pact_list* field_types);
void pact_emit_struct_lit(int64_t node);
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
void pact_emit_mono_typedefs_from(int64_t start);
void pact_emit_mono_fns_from(int64_t start);
void pact_emit_struct_typedef(int64_t td_node);
void pact_emit_enum_typedef(int64_t td_node);
void pact_emit_top_level_let(int64_t node);
const char* pact_generate(int64_t program);
void pact_fmt_emit(const char* line);
void pact_fmt_emit_raw(const char* line);
int64_t pact_fmt_line_len(const char* line);
int64_t pact_fmt_needs_wrap(const char* line);
const char* pact_fmt_join(void);
const char* pact_format_type_ann(int64_t node);
const char* pact_format_pattern(int64_t node);
int64_t pact_op_precedence(const char* op);
int64_t pact_needs_parens(int64_t child, const char* parent_op, int64_t is_right);
const char* pact_format_expr(int64_t node);
const char* pact_fmt_escape_str_literal(const char* s);
const char* pact_format_interp_string(int64_t node);
const char* pact_format_closure_inline(int64_t node);
const char* pact_format_param(int64_t node);
const char* pact_format_block_inline(int64_t node);
int64_t pact_is_simple_expr_kind(int64_t kind);
const char* pact_format_if_inline(int64_t node);
const char* pact_format_match_inline(int64_t node);
const char* pact_format_handler_inline(int64_t node);
void pact_emit_call_wrapped(int64_t node, const char* prefix);
void pact_emit_list_wrapped(int64_t node, const char* prefix);
void pact_emit_struct_lit_wrapped(int64_t node, const char* prefix);
void pact_emit_binop_wrapped(int64_t node, const char* prefix);
void pact_flatten_binop_chain(int64_t node);
void pact_emit_method_chain_wrapped(int64_t node, const char* prefix);
int64_t pact_is_method_chain(int64_t node);
int64_t pact_chain_depth(int64_t node);
void pact_emit_expr_wrapped(int64_t node, const char* prefix, const char* suffix);
void pact_emit_comments(int64_t node);
void pact_format_stmt(int64_t node);
void pact_format_if_stmt(int64_t node);
void pact_format_if_chain(int64_t node, const char* prefix);
const char* pact_format_else_if(int64_t node);
void pact_format_match_stmt(int64_t node);
void pact_format_match_arm(int64_t node);
void pact_format_with_block(int64_t node);
void pact_format_block_body(int64_t node);
const char* pact_format_fn_sig_suffix(const char* ret, int64_t ret_ann, int64_t effects_sl);
void pact_format_fn_def(int64_t node);
void pact_format_type_def(int64_t node);
void pact_format_trait_def(int64_t node);
void pact_format_impl_block(int64_t node);
void pact_format_test_block(int64_t node);
int64_t pact_annotation_order(const char* name);
void pact_format_annotation(int64_t node);
void pact_format_import(int64_t node);
void pact_format_effect_decl(int64_t node);
void pact_format_effect_op_sig(int64_t node);
const char* pact_format(int64_t program);
void pact_init_mutating_methods(void);
int64_t pact_is_mutating_method(const char* name);
int64_t pact_is_global(const char* name);
int64_t pact_fn_index(const char* name);
int64_t pact_global_index(const char* name);
int64_t pact_mat_has_write(int64_t fn_idx, int64_t gi);
void pact_mat_set_write(int64_t fn_idx, int64_t gi);
int64_t pact_fn_has_write(int64_t fn_idx, const char* global_name);
void pact_add_write(int64_t fn_idx, const char* global_name);
const char* pact_extract_ident_name(int64_t node);
void pact_walk_expr(int64_t node, int64_t fn_idx);
void pact_walk_stmts(int64_t stmts_sl, int64_t fn_idx);
int64_t pact_propagate_writes(void);
void pact_rebuild_write_lists(void);
void pact_analyze_mutations(int64_t program);
int64_t pact_get_fn_write_count(const char* name);
const char* pact_get_fn_write_at(const char* name, int64_t wi);
pact_list* pact_get_all_globals(void);
int64_t pact_fn_writes_to(const char* fn_name, const char* global_name);
void pact_sr_reset(void);
void pact_sr_add_save(const char* local_name, const char* global_name);
const char* pact_sr_is_save_local(const char* name);
int64_t pact_sr_is_saved_global(const char* name);
void pact_sr_check_call(int64_t call_node, const char* callee_name);
void pact_sr_scan_stmts(int64_t stmts_sl);
void pact_sr_scan_node(int64_t node);
void pact_sr_analyze_fn(int64_t fn_node);
void pact_analyze_save_restore(int64_t program);
const char* pact_extract_intent(const char* doc);
const char* pact_extract_annotation_args(int64_t node, const char* ann_name);
int64_t pact_add_symbol(const char* name, int64_t kind, const char* module, const char* file, int64_t line, int64_t vis, const char* effects, const char* sig, const char* ret_type, const char* param_types);
void pact_si_add_dep(int64_t from_idx, int64_t to_idx, int64_t kind);
void pact_add_rdep(int64_t from_idx, int64_t to_idx);
int64_t pact_register_file(const char* path, int64_t mtime, int64_t sym_start);
int64_t pact_sym_index(const char* name);
const char* pact_collect_param_types(int64_t fn_node);
const char* pact_collect_effects(int64_t fn_node);
void pact_walk_deps(int64_t node, int64_t from_idx);
void pact_walk_dep_stmts(int64_t stmts_sl, int64_t from_idx);
void pact_register_type_dep(int64_t from_idx, const char* type_name);
void pact_build_reverse_deps(void);
void pact_si_build(int64_t program, const char* file_path, const char* module_name);
pact_list* pact_si_get_rdeps(int64_t sym_idx);
int64_t pact_si_find_sym(const char* name);
pact_list* pact_si_file_symbols(const char* path);
void pact_si_reset(void);
const char* pact_sym_kind_name(int64_t kind);
const char* pact_dep_kind_name(int64_t kind);
void pact_fw_init(void);
int64_t pact_fw_poll(void);
pact_list* pact_fw_get_dirty(void);
void pact_fw_clear_dirty(void);
void pact_fw_add_file(const char* path);
void pact_fw_reset(void);
const char* pact_escape_str(const char* s);
const char* pact_effects_to_json_array(const char* effects);
const char* pact_vis_name(int64_t vis);
const char* pact_symbol_to_json(int64_t idx);
const char* pact_wrap_results(const char* items);
int64_t pact_effects_contain(const char* effects, const char* target);
const char* pact_query_by_signature(const char* module);
const char* pact_query_by_effect(const char* effect_name);
const char* pact_query_pub_pure(void);
const char* pact_query_by_name(const char* name);
const char* pact_query_filtered(int64_t vis_filter, const char* module_filter, const char* effect_filter, int64_t pure_only, const char* name_filter);
const char* pact_symbol_to_intent_json(int64_t idx);
const char* pact_symbol_to_contract_json(int64_t idx);
const char* pact_extract_lines(const char* content, int64_t start_line, int64_t end_line);
const char* pact_symbol_to_full_json(int64_t idx);
const char* pact_format_symbol_for_layer(const char* layer, int64_t idx);
const char* pact_query_filtered_layer(const char* layer, int64_t vis_filter, const char* module_filter, const char* effect_filter, int64_t pure_only, const char* name_filter);
int64_t pact_qr_skip_ws(const char* s, int64_t pos);
const char* pact_qr_parse_string(const char* s, int64_t pos);
int64_t pact_qr_end_of_string(const char* s, int64_t pos);
int64_t pact_qr_parse_request(const char* s);
const char* pact_qr_get(const char* key);
const char* pact_query_dispatch(const char* request);
void pact_inc_snapshot(void);
void pact_inc_detect_changes(void);
void pact_mark_affected(int64_t sym_idx);
void pact_inc_compute_affected(void);
int64_t pact_inc_needs_recheck(int64_t sym_idx);
void pact_inc_reset(void);
const char* pact_dj_escape(const char* s);
int64_t pact_dr_skip_ws(const char* s, int64_t p);
const char* pact_dr_parse_string(const char* s, int64_t p);
int64_t pact_dr_end_of_string(const char* s, int64_t p);
int64_t pact_dr_parse_request(const char* s);
const char* pact_dr_get(const char* key);
const char* pact_daemon_extract_type(const char* request);
const char* pact_daemon_diags_to_json(void);
const char* pact_daemon_handle_check(void);
const char* pact_daemon_handle_query(const char* request);
const char* pact_daemon_handle_status(void);
const char* pact_daemon_handle_stop(void);
void pact_daemon_loop(void);
void pact_daemon_stop(void);
void pact_daemon_start(const char* root, const char* source);
int64_t pact_is_ws(int64_t c);
int64_t pact_is_newline(int64_t c);
int64_t pact_is_bare_key_char(int64_t c);
int64_t pact_skip_ws(const char* content, int64_t pos);
int64_t pact_skip_to_newline(const char* content, int64_t pos);
int64_t pact_skip_ws_and_newlines(const char* content, int64_t pos);
void pact_store_entry(const char* key, const char* value, int64_t vtype);
int64_t pact_find_key_index(const char* key);
int64_t pact_get_arr_table_count(const char* name);
int64_t pact_inc_arr_table_count(const char* name);
void pact_parse_quoted_string(const char* content, int64_t pos);
void pact_parse_bare_key(const char* content, int64_t pos);
void pact_parse_key(const char* content, int64_t pos);
void pact_parse_dotted_key(const char* content, int64_t pos);
void pact_parse_integer(const char* content, int64_t pos);
void pact_parse_array_value(const char* content, int64_t pos, const char* full_key);
void pact_parse_inline_table(const char* content, int64_t pos, const char* prefix);
void pact_parse_value(const char* content, int64_t pos, const char* full_key);
void pact_parse_section_header(const char* content, int64_t pos);
void pact_parse_array_table_header(const char* content, int64_t pos);
int64_t pact_toml_parse(const char* content);
const char* pact_toml_get(const char* key);
int64_t pact_toml_get_int(const char* key);
int64_t pact_toml_has(const char* key);
int64_t pact_toml_array_len(const char* key);
const char* pact_toml_get_array_item(const char* key, int64_t index);
int64_t pact_toml_get_array_len(const char* key);
int64_t pact_toml_clear(void);
void pact_lockfile_clear(void);
int64_t pact_lockfile_pkg_count(void);
int64_t pact_lockfile_find_pkg(const char* name);
const char* pact_lockfile_get_pkg_hash(const char* name);
int64_t pact_lockfile_verify_hash(const char* name, const char* expected_hash);
void pact_lockfile_add_pkg(const char* name, const char* version, const char* source, const char* hash, const char* caps);
void pact_lockfile_set_metadata(const char* pact_version, const char* generated);
int64_t pact_str_compare(const char* a, const char* b);
void pact_sort_packages(void);
const char* pact_format_caps_toml(const char* caps);
int64_t pact_lockfile_write(const char* path);
const char* pact_parse_caps_for_pkg(const char* prefix);
int64_t pact_lockfile_load(const char* path);
const char* pact_dots_to_slashes(const char* s);
const char* pact_find_src_root(const char* source_path);
void pact_ensure_lockfile_loaded(const char* src_root);
const char* pact_compiler_get_home(void);
const char* pact_resolve_from_lockfile(const char* dotted_path, const char* src_root);
const char* pact_resolve_module_path(const char* dotted_path, const char* src_root);
int64_t pact_should_import_item(int64_t item, int64_t import_node);
int64_t pact_merge_programs(int64_t main_prog, pact_list* imported, pact_list* import_nodes_list);
int64_t pact_is_file_loaded(const char* path);
void pact_collect_imports(int64_t program, const char* src_root, pact_list* all_programs);
void pact_main(void);

pact_Token pact_make_token(int64_t kind, const char* value, int64_t line, int64_t col) {
    pact_Token _s0 = { .kind = kind, .value = value, .line = line, .col = col };
    return _s0;
}

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
        _match_0 = "}";
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
        _match_0 = "\?";
    } else if ((kind == pact_TokenKind_DoubleQuestion)) {
        _match_0 = "\?\?";
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
    } else if ((kind == pact_TokenKind_Comment)) {
        _match_0 = "COMMENT";
    } else if ((kind == pact_TokenKind_DocComment)) {
        _match_0 = "DOC_COMMENT";
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
                const int64_t t_line = line;
                const int64_t t_col = col;
                const int is_doc = (pact_peek_at(source, pos, 2) == CH_SLASH);
                if (is_doc) {
                    pos = (pos + 3);
                    col = (col + 3);
                } else {
                    pos = (pos + 2);
                    col = (col + 2);
                }
                const int64_t text_start = pos;
                while (((pos < pact_str_len(source)) && (pact_peek(source, pos) != CH_NEWLINE))) {
                    pos = (pos + 1);
                    col = (col + 1);
                }
                const char* text = pact_str_substr(source, text_start, (pos - text_start));
                if (is_doc) {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_DocComment);
                    pact_list_push(tok_values, (void*)text);
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_DocComment;
                } else {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Comment);
                    pact_list_push(tok_values, (void*)text);
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_Comment;
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
                    pact_list_push(tok_values, (void*)"}");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_RBrace;
                } else if ((brace_depth == 1)) {
                    pact_list_pop(mode_stack);
                    pact_list_pop(brace_depth_stack);
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_InterpEnd);
                    pact_list_push(tok_values, (void*)"}");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_InterpEnd;
                } else {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_RBrace);
                    pact_list_push(tok_values, (void*)"}");
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
                    pact_list_push(tok_values, (void*)"\?\?");
                    pact_list_push(tok_lines, (void*)(intptr_t)t_line);
                    pact_list_push(tok_cols, (void*)(intptr_t)t_col);
                    last_kind = pact_TokenKind_DoubleQuestion;
                } else {
                    pact_list_push(tok_kinds, (void*)(intptr_t)pact_TokenKind_Question);
                    pact_list_push(tok_values, (void*)"\?");
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
                        } else if ((esc == CH_RBRACE)) {
                            string_buf = pact_str_concat(string_buf, "}");
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
    } else if ((kind == pact_NodeKind_AsyncScope)) {
        _match_0 = "AsyncScope";
    } else if ((kind == pact_NodeKind_AsyncSpawn)) {
        _match_0 = "AsyncSpawn";
    } else if ((kind == pact_NodeKind_AwaitExpr)) {
        _match_0 = "AwaitExpr";
    } else if ((kind == pact_NodeKind_ChannelNew)) {
        _match_0 = "ChannelNew";
    } else {
        _match_0 = "Unknown";
    }
    return _match_0;
}

void pact_diag_emit(const char* severity, const char* name, const char* code, const char* message, int64_t line, int64_t col, const char* help) {
    pact_list_push(diag_severity, (void*)severity);
    pact_list_push(diag_name, (void*)name);
    pact_list_push(diag_code, (void*)code);
    pact_list_push(diag_message, (void*)message);
    pact_list_push(diag_file, (void*)diag_source_file);
    pact_list_push(diag_line, (void*)(intptr_t)line);
    pact_list_push(diag_col, (void*)(intptr_t)col);
    pact_list_push(diag_help, (void*)help);
    pact_list_push(diag_end_line, (void*)(intptr_t)0);
    pact_list_push(diag_end_col, (void*)(intptr_t)0);
    if (pact_str_eq(severity, "error")) {
        diag_count = (diag_count + 1);
    }
}

void pact_diag_error(const char* name, const char* code, const char* message, int64_t line, int64_t col, const char* help) {
    pact_diag_emit("error", name, code, message, line, col, help);
}

void pact_diag_error_no_loc(const char* name, const char* code, const char* message, const char* help) {
    pact_diag_emit("error", name, code, message, 0, 0, help);
}

void pact_diag_error_at(const char* name, const char* code, const char* message, int64_t node_id, const char* help) {
    const int64_t line = (int64_t)(intptr_t)pact_list_get(np_line, node_id);
    const int64_t col = (int64_t)(intptr_t)pact_list_get(np_col, node_id);
    pact_diag_emit("error", name, code, message, line, col, help);
}

void pact_diag_warn(const char* name, const char* code, const char* message, int64_t line, int64_t col, const char* help) {
    pact_diag_emit("warning", name, code, message, line, col, help);
}

void pact_diag_warn_no_loc(const char* name, const char* code, const char* message, const char* help) {
    pact_diag_emit("warning", name, code, message, 0, 0, help);
}

void pact_diag_warn_at(const char* name, const char* code, const char* message, int64_t node_id, const char* help) {
    const int64_t line = (int64_t)(intptr_t)pact_list_get(np_line, node_id);
    const int64_t col = (int64_t)(intptr_t)pact_list_get(np_col, node_id);
    pact_diag_emit("warning", name, code, message, line, col, help);
}

void pact_diag_emit_range(const char* severity, const char* name, const char* code, const char* message, int64_t line, int64_t col, int64_t end_line, int64_t end_col, const char* help) {
    pact_list_push(diag_severity, (void*)severity);
    pact_list_push(diag_name, (void*)name);
    pact_list_push(diag_code, (void*)code);
    pact_list_push(diag_message, (void*)message);
    pact_list_push(diag_file, (void*)diag_source_file);
    pact_list_push(diag_line, (void*)(intptr_t)line);
    pact_list_push(diag_col, (void*)(intptr_t)col);
    pact_list_push(diag_help, (void*)help);
    pact_list_push(diag_end_line, (void*)(intptr_t)end_line);
    pact_list_push(diag_end_col, (void*)(intptr_t)end_col);
    if (pact_str_eq(severity, "error")) {
        diag_count = (diag_count + 1);
    }
}

const char* pact_json_escape(const char* s) {
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
            } else if ((ch == 13)) {
                result = pact_str_concat(result, "\\r");
            } else {
                if ((ch == 9)) {
                    result = pact_str_concat(result, "\\t");
                } else {
                    result = pact_str_concat(result, pact_str_substr(s, i, 1));
                }
            }
        }
        i = (i + 1);
    }
    return result;
}

void pact_diag_flush(void) {
    int64_t i = 0;
    while ((i < pact_list_len(diag_severity))) {
        if ((diag_format == 1)) {
            pact_diag_print_json(i);
        } else {
            pact_diag_print_human(i);
        }
        i = (i + 1);
    }
    if ((diag_format == 1)) {
    } else if ((diag_count > 0)) {
        char _si_0[4096];
        snprintf(_si_0, 4096, "%lld error(s) found", (long long)diag_count);
        printf("%s\n", strdup(_si_0));
    }
}

void pact_diag_print_json(int64_t idx) {
    const char* sev = pact_json_escape((const char*)pact_list_get(diag_severity, idx));
    const char* name = pact_json_escape((const char*)pact_list_get(diag_name, idx));
    const char* code = pact_json_escape((const char*)pact_list_get(diag_code, idx));
    const char* msg = pact_json_escape((const char*)pact_list_get(diag_message, idx));
    const char* file = pact_json_escape((const char*)pact_list_get(diag_file, idx));
    const int64_t line = (int64_t)(intptr_t)pact_list_get(diag_line, idx);
    const int64_t col = (int64_t)(intptr_t)pact_list_get(diag_col, idx);
    const char* help = (const char*)pact_list_get(diag_help, idx);
    const int64_t el = (int64_t)(intptr_t)pact_list_get(diag_end_line, idx);
    const int64_t ec = (int64_t)(intptr_t)pact_list_get(diag_end_col, idx);
    char _si_0[4096];
    snprintf(_si_0, 4096, "\"span\":{\"file\":\"%s\",\"line\":%lld,\"col\":%lld", file, (long long)line, (long long)col);
    const char* span = strdup(_si_0);
    if ((el > 0)) {
        char _si_1[4096];
        snprintf(_si_1, 4096, ",\"end_line\":%lld,\"end_col\":%lld", (long long)el, (long long)ec);
        span = pact_str_concat(span, strdup(_si_1));
    }
    span = pact_str_concat(span, "}");
    char _si_2[4096];
    snprintf(_si_2, 4096, "{\"severity\":\"%s\",\"name\":\"%s\",\"code\":\"%s\",\"message\":\"%s\",%s", sev, name, code, msg, span);
    const char* json = strdup(_si_2);
    if ((!pact_str_eq(help, ""))) {
        json = pact_str_concat(pact_str_concat(pact_str_concat(json, ",\"help\":\""), pact_json_escape(help)), "\"");
    }
    json = pact_str_concat(json, "}");
    printf("%s\n", json);
}

void pact_diag_print_human(int64_t idx) {
    const char* sev = (const char*)pact_list_get(diag_severity, idx);
    const char* name = (const char*)pact_list_get(diag_name, idx);
    const char* msg = (const char*)pact_list_get(diag_message, idx);
    const char* file = (const char*)pact_list_get(diag_file, idx);
    const int64_t line = (int64_t)(intptr_t)pact_list_get(diag_line, idx);
    const int64_t col = (int64_t)(intptr_t)pact_list_get(diag_col, idx);
    const char* help = (const char*)pact_list_get(diag_help, idx);
    char _si_0[4096];
    snprintf(_si_0, 4096, "%s[%s]: %s", sev, name, msg);
    printf("%s\n", strdup(_si_0));
    if ((line > 0)) {
        char _si_1[4096];
        snprintf(_si_1, 4096, "  --> %s:%lld:%lld", file, (long long)line, (long long)col);
        printf("%s\n", strdup(_si_1));
    }
    if ((!pact_str_eq(help, ""))) {
        char _si_2[4096];
        snprintf(_si_2, 4096, "  help: %s", help);
        printf("%s\n", strdup(_si_2));
    }
}

void pact_diag_reset(void) {
    pact_list* _l0 = pact_list_new();
    diag_severity = _l0;
    pact_list* _l1 = pact_list_new();
    diag_name = _l1;
    pact_list* _l2 = pact_list_new();
    diag_code = _l2;
    pact_list* _l3 = pact_list_new();
    diag_message = _l3;
    pact_list* _l4 = pact_list_new();
    diag_file = _l4;
    pact_list* _l5 = pact_list_new();
    diag_line = _l5;
    pact_list* _l6 = pact_list_new();
    diag_col = _l6;
    pact_list* _l7 = pact_list_new();
    diag_help = _l7;
    pact_list* _l8 = pact_list_new();
    diag_end_line = _l8;
    pact_list* _l9 = pact_list_new();
    diag_end_col = _l9;
    diag_count = 0;
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
    pact_list_push(np_leading_comments, (void*)"");
    pact_list_push(np_doc_comment, (void*)"");
    pact_list_push(np_line, (void*)(intptr_t)pact_peek_line());
    pact_list_push(np_col, (void*)(intptr_t)pact_peek_col());
    pact_list_push(np_end_line, (void*)(intptr_t)(-1));
    pact_list_push(np_end_col, (void*)(intptr_t)(-1));
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
        snprintf(_si_0, 4096, "expected token kind %lld, got %lld", (long long)kind, (long long)pact_peek_kind());
        pact_diag_error("UnexpectedToken", "E1100", strdup(_si_0), pact_peek_line(), pact_peek_col(), "");
    }
    return pact_advance();
}

const char* pact_expect_value(int64_t kind) {
    if ((pact_peek_kind() != kind)) {
        if (((kind == pact_TokenKind_Ident) && pact_is_keyword(pact_peek_kind()))) {
            char _si_0[4096];
            snprintf(_si_0, 4096, "'%s' is a keyword and cannot be used as an identifier", pact_peek_value());
            pact_diag_error("KeywordAsIdentifier", "E1103", strdup(_si_0), pact_peek_line(), pact_peek_col(), "use a different name");
        } else {
            char _si_1[4096];
            snprintf(_si_1, 4096, "expected token kind %lld, got %lld", (long long)kind, (long long)pact_peek_kind());
            pact_diag_error("UnexpectedToken", "E1100", strdup(_si_1), pact_peek_line(), pact_peek_col(), "");
        }
    }
    return pact_advance_value();
}

void pact_skip_newlines(void) {
    while (((pact_at(pact_TokenKind_Newline) || pact_at(pact_TokenKind_Comment)) || pact_at(pact_TokenKind_DocComment))) {
        if (pact_at(pact_TokenKind_Comment)) {
            pact_list_push(pending_comments, (void*)pact_peek_value());
        } else if (pact_at(pact_TokenKind_DocComment)) {
            if ((!pact_str_eq(pending_doc_comment, ""))) {
                pending_doc_comment = pact_str_concat(pending_doc_comment, "\n");
            }
            pending_doc_comment = pact_str_concat(pending_doc_comment, pact_peek_value());
        }
        pact_advance();
    }
}

void pact_skip_comments(void) {
    while ((pact_at(pact_TokenKind_Comment) || pact_at(pact_TokenKind_DocComment))) {
        if (pact_at(pact_TokenKind_Comment)) {
            pact_list_push(pending_comments, (void*)pact_peek_value());
        } else if (pact_at(pact_TokenKind_DocComment)) {
            if ((!pact_str_eq(pending_doc_comment, ""))) {
                pending_doc_comment = pact_str_concat(pending_doc_comment, "\n");
            }
            pending_doc_comment = pact_str_concat(pending_doc_comment, pact_peek_value());
        }
        pact_advance();
    }
}

void pact_maybe_newline(void) {
    if (pact_at(pact_TokenKind_Newline)) {
        pact_advance();
    }
}

void pact_attach_comments(int64_t node) {
    if ((!pact_str_eq(pending_doc_comment, ""))) {
        pact_list_set(np_doc_comment, node, (void*)pending_doc_comment);
        pending_doc_comment = "";
    }
    if ((pact_list_len(pending_comments) > 0)) {
        const char* combined = "";
        int64_t i = 0;
        while ((i < pact_list_len(pending_comments))) {
            if ((i > 0)) {
                combined = pact_str_concat(combined, "\n");
            }
            combined = pact_str_concat(combined, (const char*)pact_list_get(pending_comments, i));
            i = (i + 1);
        }
        pact_list_set(np_leading_comments, node, (void*)combined);
        pact_list* _l0 = pact_list_new();
        pending_comments = _l0;
    }
}

void pact_flush_pending_comments(void) {
    pact_list* _l0 = pact_list_new();
    pending_comments = _l0;
    pending_doc_comment = "";
}

void pact_attach_pending_annotations(int64_t node) {
    if ((pact_list_len(annotation_nodes) > 0)) {
        const int64_t anns_sl = pact_new_sublist();
        int64_t ai = 0;
        while ((ai < pact_list_len(annotation_nodes))) {
            pact_sublist_push(anns_sl, (int64_t)(intptr_t)pact_list_get(annotation_nodes, ai));
            ai = (ai + 1);
        }
        pact_finalize_sublist(anns_sl);
        pact_list_set(np_handlers, node, (void*)(intptr_t)anns_sl);
        pact_list* _l0 = pact_list_new();
        annotation_nodes = _l0;
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
    pact_list* _l8 = pact_list_new();
    pact_list* test_nodes = _l8;
    pact_list* _l9 = pact_list_new();
    annotation_nodes = _l9;
    pact_skip_newlines();
    while ((!pact_at(pact_TokenKind_EOF))) {
        pact_skip_newlines();
        if (pact_at(pact_TokenKind_EOF)) {
            break;
        }
        if (pact_at(pact_TokenKind_At)) {
            pact_advance();
            const char* ann_name = pact_expect_value(pact_TokenKind_Ident);
            const int64_t ann_nd = pact_new_node(pact_NodeKind_Annotation);
            pact_attach_comments(ann_nd);
            pact_list_set(np_name, ann_nd, (void*)ann_name);
            if (pact_at(pact_TokenKind_LParen)) {
                pact_advance();
                pact_skip_newlines();
                pact_list* _l10 = pact_list_new();
                pact_list* ann_arg_nodes = _l10;
                while (((!pact_at(pact_TokenKind_RParen)) && (!pact_at(pact_TokenKind_EOF)))) {
                    const char* arg_name = pact_expect_value(pact_TokenKind_Ident);
                    const char* full_arg = arg_name;
                    if (pact_at(pact_TokenKind_Dot)) {
                        pact_advance();
                        const char* child = pact_expect_value(pact_TokenKind_Ident);
                        full_arg = pact_str_concat(pact_str_concat(full_arg, "."), child);
                    }
                    const int64_t arg_nd = pact_new_node(pact_NodeKind_Ident);
                    pact_list_set(np_name, arg_nd, (void*)full_arg);
                    pact_list_push(ann_arg_nodes, (void*)(intptr_t)arg_nd);
                    pact_skip_newlines();
                    if (pact_at(pact_TokenKind_Comma)) {
                        pact_advance();
                        pact_skip_newlines();
                    }
                }
                pact_expect(pact_TokenKind_RParen);
                if ((pact_list_len(ann_arg_nodes) > 0)) {
                    const int64_t ann_args_sl = pact_new_sublist();
                    int64_t ai = 0;
                    while ((ai < pact_list_len(ann_arg_nodes))) {
                        pact_sublist_push(ann_args_sl, (int64_t)(intptr_t)pact_list_get(ann_arg_nodes, ai));
                        ai = (ai + 1);
                    }
                    pact_finalize_sublist(ann_args_sl);
                    pact_list_set(np_args, ann_nd, (void*)(intptr_t)ann_args_sl);
                }
            }
            pact_list_push(annotation_nodes, (void*)(intptr_t)ann_nd);
            pact_skip_newlines();
        } else if (pact_at(pact_TokenKind_Import)) {
            pact_advance();
            const int64_t imp = pact_parse_import_stmt();
            pact_attach_comments(imp);
            pact_list_push(import_nodes, (void*)(intptr_t)imp);
            pact_skip_newlines();
        } else {
            if (pact_at(pact_TokenKind_Type)) {
                const int64_t td = pact_parse_type_def();
                pact_attach_comments(td);
                pact_attach_pending_annotations(td);
                pact_list_push(type_nodes, (void*)(intptr_t)td);
            } else if (pact_at(pact_TokenKind_Trait)) {
                const int64_t tr = pact_parse_trait_def();
                pact_attach_comments(tr);
                pact_attach_pending_annotations(tr);
                pact_list_push(trait_nodes, (void*)(intptr_t)tr);
            } else {
                if (pact_at(pact_TokenKind_Impl)) {
                    const int64_t im = pact_parse_impl_block();
                    pact_attach_comments(im);
                    pact_attach_pending_annotations(im);
                    pact_list_push(impl_nodes, (void*)(intptr_t)im);
                } else if (pact_at(pact_TokenKind_Let)) {
                    const int64_t lb = pact_parse_let_binding();
                    pact_attach_comments(lb);
                    pact_attach_pending_annotations(lb);
                    pact_list_push(let_nodes, (void*)(intptr_t)lb);
                } else {
                    if (pact_at(pact_TokenKind_Pub)) {
                        pact_advance();
                        pact_skip_newlines();
                        if (pact_at(pact_TokenKind_Fn)) {
                            const int64_t f = pact_parse_fn_def();
                            pact_attach_comments(f);
                            pact_list_set(np_is_pub, f, (void*)(intptr_t)1);
                            pact_attach_pending_annotations(f);
                            pact_list_push(fn_nodes, (void*)(intptr_t)f);
                        } else if (pact_at(pact_TokenKind_Type)) {
                            const int64_t td = pact_parse_type_def();
                            pact_attach_comments(td);
                            pact_list_set(np_is_pub, td, (void*)(intptr_t)1);
                            pact_attach_pending_annotations(td);
                            pact_list_push(type_nodes, (void*)(intptr_t)td);
                        } else {
                            if (pact_at(pact_TokenKind_Trait)) {
                                const int64_t tr = pact_parse_trait_def();
                                pact_attach_comments(tr);
                                pact_list_set(np_is_pub, tr, (void*)(intptr_t)1);
                                pact_attach_pending_annotations(tr);
                                pact_list_push(trait_nodes, (void*)(intptr_t)tr);
                            } else if (pact_at(pact_TokenKind_Let)) {
                                const int64_t lb = pact_parse_let_binding();
                                pact_attach_comments(lb);
                                pact_list_set(np_is_pub, lb, (void*)(intptr_t)1);
                                pact_attach_pending_annotations(lb);
                                pact_list_push(let_nodes, (void*)(intptr_t)lb);
                            } else {
                                if (pact_at(pact_TokenKind_Effect)) {
                                    const int64_t ed = pact_parse_effect_decl();
                                    pact_attach_comments(ed);
                                    pact_list_set(np_is_pub, ed, (void*)(intptr_t)1);
                                    pact_attach_pending_annotations(ed);
                                    pact_list_push(effect_decl_nodes, (void*)(intptr_t)ed);
                                } else {
                                    pact_diag_error("UnexpectedToken", "E1100", "expected fn, type, trait, or effect after pub", pact_peek_line(), pact_peek_col(), "");
                                    pact_advance();
                                }
                            }
                        }
                    } else if (pact_at(pact_TokenKind_Effect)) {
                        const int64_t ed = pact_parse_effect_decl();
                        pact_attach_comments(ed);
                        pact_attach_pending_annotations(ed);
                        pact_list_push(effect_decl_nodes, (void*)(intptr_t)ed);
                    } else {
                        if (pact_at(pact_TokenKind_Test)) {
                            pact_advance();
                            const int64_t tb = pact_parse_test_block();
                            pact_attach_comments(tb);
                            pact_attach_pending_annotations(tb);
                            pact_list_push(test_nodes, (void*)(intptr_t)tb);
                        } else if (pact_at(pact_TokenKind_Fn)) {
                            const int64_t f = pact_parse_fn_def();
                            pact_attach_comments(f);
                            pact_attach_pending_annotations(f);
                            pact_list_push(fn_nodes, (void*)(intptr_t)f);
                        } else {
                            char _si_11[4096];
                            snprintf(_si_11, 4096, "unexpected token at top level: %lld", (long long)pact_peek_kind());
                            pact_diag_error("UnexpectedToken", "E1100", strdup(_si_11), pact_peek_line(), pact_peek_col(), "");
                            pact_advance();
                        }
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
    int64_t annotations_sl = (-1);
    if ((pact_list_len(annotation_nodes) > 0)) {
        annotations_sl = pact_new_sublist();
        i = 0;
        while ((i < pact_list_len(annotation_nodes))) {
            pact_sublist_push(annotations_sl, (int64_t)(intptr_t)pact_list_get(annotation_nodes, i));
            i = (i + 1);
        }
        pact_finalize_sublist(annotations_sl);
    }
    int64_t tests_sl = (-1);
    if ((pact_list_len(test_nodes) > 0)) {
        tests_sl = pact_new_sublist();
        i = 0;
        while ((i < pact_list_len(test_nodes))) {
            pact_sublist_push(tests_sl, (int64_t)(intptr_t)pact_list_get(test_nodes, i));
            i = (i + 1);
        }
        pact_finalize_sublist(tests_sl);
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
    pact_list_set(np_handlers, prog, (void*)(intptr_t)annotations_sl);
    pact_list_set(np_captures, prog, (void*)(intptr_t)tests_sl);
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
    int64_t td_end_line = (-1);
    int64_t td_end_col = (-1);
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
            } else if (pact_at(pact_TokenKind_LParen)) {
                pact_advance();
                pact_skip_newlines();
                pact_list* _l1 = pact_list_new();
                pact_list* vfield_nodes = _l1;
                if ((!pact_at(pact_TokenKind_RParen))) {
                    const char* vf_name = pact_expect_value(pact_TokenKind_Ident);
                    pact_expect(pact_TokenKind_Colon);
                    const int64_t vf_type = pact_parse_type_annotation();
                    const int64_t vf = pact_new_node(pact_NodeKind_TypeField);
                    pact_list_set(np_name, vf, (void*)vf_name);
                    pact_list_set(np_value, vf, (void*)(intptr_t)vf_type);
                    pact_list_push(vfield_nodes, (void*)(intptr_t)vf);
                    while (pact_at(pact_TokenKind_Comma)) {
                        pact_advance();
                        pact_skip_newlines();
                        if (pact_at(pact_TokenKind_RParen)) {
                            break;
                        }
                        const char* vf_name2 = pact_expect_value(pact_TokenKind_Ident);
                        pact_expect(pact_TokenKind_Colon);
                        const int64_t vf_type2 = pact_parse_type_annotation();
                        const int64_t vf2 = pact_new_node(pact_NodeKind_TypeField);
                        pact_list_set(np_name, vf2, (void*)vf_name2);
                        pact_list_set(np_value, vf2, (void*)(intptr_t)vf_type2);
                        pact_list_push(vfield_nodes, (void*)(intptr_t)vf2);
                    }
                }
                pact_skip_newlines();
                pact_expect(pact_TokenKind_RParen);
                int64_t vflds = (-1);
                if ((pact_list_len(vfield_nodes) > 0)) {
                    vflds = pact_new_sublist();
                    int64_t vi = 0;
                    while ((vi < pact_list_len(vfield_nodes))) {
                        pact_sublist_push(vflds, (int64_t)(intptr_t)pact_list_get(vfield_nodes, vi));
                        vi = (vi + 1);
                    }
                    pact_finalize_sublist(vflds);
                }
                const int64_t tv = pact_new_node(pact_NodeKind_TypeVariant);
                pact_list_set(np_name, tv, (void*)fname);
                pact_list_set(np_fields, tv, (void*)(intptr_t)vflds);
                pact_list_push(field_nodes, (void*)(intptr_t)tv);
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
        td_end_line = pact_peek_line();
        td_end_col = pact_peek_col();
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
    if ((td_end_line != (-1))) {
        pact_list_set(np_end_line, td, (void*)(intptr_t)td_end_line);
        pact_list_set(np_end_col, td, (void*)(intptr_t)td_end_col);
    }
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
    if (pact_at(pact_TokenKind_Question)) {
        pact_advance();
        const int64_t inner_sl = pact_new_sublist();
        pact_sublist_push(inner_sl, ta);
        pact_finalize_sublist(inner_sl);
        const int64_t opt = pact_new_node(pact_NodeKind_TypeAnn);
        pact_list_pop(np_name);
        pact_list_push(np_name, (void*)"Option");
        pact_list_pop(np_elements);
        pact_list_push(np_elements, (void*)(intptr_t)inner_sl);
        return opt;
    }
    return ta;
}

int64_t pact_parse_effect_op_sig(void) {
    pact_expect(pact_TokenKind_Fn);
    const char* op_name = pact_expect_value(pact_TokenKind_Ident);
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
    const int64_t params_sl = pact_new_sublist();
    int64_t i = 0;
    while ((i < pact_list_len(param_nodes))) {
        pact_sublist_push(params_sl, (int64_t)(intptr_t)pact_list_get(param_nodes, i));
        i = (i + 1);
    }
    pact_finalize_sublist(params_sl);
    const int64_t nd = pact_new_node(pact_NodeKind_FnDef);
    pact_list_pop(np_name);
    pact_list_push(np_name, (void*)op_name);
    pact_list_pop(np_params);
    pact_list_push(np_params, (void*)(intptr_t)params_sl);
    pact_list_pop(np_return_type);
    pact_list_push(np_return_type, (void*)ret_str);
    return nd;
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
            pact_skip_newlines();
            int64_t child_methods_sl = (-1);
            if (pact_at(pact_TokenKind_LBrace)) {
                pact_advance();
                pact_skip_newlines();
                pact_list* _l1 = pact_list_new();
                pact_list* ops = _l1;
                while (((!pact_at(pact_TokenKind_RBrace)) && (!pact_at(pact_TokenKind_EOF)))) {
                    pact_list_push(ops, (void*)(intptr_t)pact_parse_effect_op_sig());
                    pact_skip_newlines();
                }
                pact_expect(pact_TokenKind_RBrace);
                child_methods_sl = pact_new_sublist();
                int64_t oi = 0;
                while ((oi < pact_list_len(ops))) {
                    pact_sublist_push(child_methods_sl, (int64_t)(intptr_t)pact_list_get(ops, oi));
                    oi = (oi + 1);
                }
                pact_finalize_sublist(child_methods_sl);
            }
            const int64_t child = pact_new_node(pact_NodeKind_EffectDecl);
            pact_list_pop(np_name);
            pact_list_push(np_name, (void*)child_name);
            pact_list_pop(np_methods);
            pact_list_push(np_methods, (void*)(intptr_t)child_methods_sl);
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
    int64_t ret_ann = (-1);
    if (pact_at(pact_TokenKind_Arrow)) {
        pact_advance();
        const int64_t rt = pact_parse_type_annotation();
        ret_str = (const char*)pact_list_get(np_name, rt);
        ret_ann = rt;
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
    if ((ret_ann != (-1))) {
        pact_list_set(np_type_ann, nd, (void*)(intptr_t)ret_ann);
    }
    if ((body_id != (-1))) {
        const int64_t fn_end_l = (int64_t)(intptr_t)pact_list_get(np_end_line, body_id);
        const int64_t fn_end_c = (int64_t)(intptr_t)pact_list_get(np_end_col, body_id);
        if ((fn_end_l != (-1))) {
            pact_list_set(np_end_line, nd, (void*)(intptr_t)fn_end_l);
            pact_list_set(np_end_col, nd, (void*)(intptr_t)fn_end_c);
        }
    }
    return nd;
}

int64_t pact_parse_test_block(void) {
    const int64_t name_node = pact_parse_interp_string();
    const int64_t name_parts_sl = (int64_t)(intptr_t)pact_list_get(np_elements, name_node);
    const char* test_name = "";
    if (((name_parts_sl != (-1)) && (pact_sublist_length(name_parts_sl) > 0))) {
        test_name = (const char*)pact_list_get(np_str_val, pact_sublist_get(name_parts_sl, 0));
    }
    pact_skip_newlines();
    const int64_t body = pact_parse_block();
    const int64_t nd = pact_new_node(pact_NodeKind_TestBlock);
    pact_list_set(np_str_val, nd, (void*)test_name);
    pact_list_set(np_name, nd, (void*)test_name);
    pact_list_set(np_body, nd, (void*)(intptr_t)body);
    const int64_t tb_end_l = (int64_t)(intptr_t)pact_list_get(np_end_line, body);
    if ((tb_end_l != (-1))) {
        pact_list_set(np_end_line, nd, (void*)(intptr_t)tb_end_l);
        pact_list_set(np_end_col, nd, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(np_end_col, body));
    }
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
    const int64_t trait_end_line = pact_peek_line();
    const int64_t trait_end_col = pact_peek_col();
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
    pact_list_set(np_end_line, nd, (void*)(intptr_t)trait_end_line);
    pact_list_set(np_end_col, nd, (void*)(intptr_t)trait_end_col);
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
    const int64_t impl_end_line = pact_peek_line();
    const int64_t impl_end_col = pact_peek_col();
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
    pact_list_set(np_end_line, nd, (void*)(intptr_t)impl_end_line);
    pact_list_set(np_end_col, nd, (void*)(intptr_t)impl_end_col);
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
    while (((!pact_at(pact_TokenKind_RBrace)) && (!pact_at(pact_TokenKind_EOF)))) {
        pact_list_push(stmt_nodes, (void*)(intptr_t)pact_parse_stmt());
        pact_skip_newlines();
    }
    const int64_t rbrace_line = pact_peek_line();
    const int64_t rbrace_col = pact_peek_col();
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
    pact_list_set(np_end_line, nd, (void*)(intptr_t)rbrace_line);
    pact_list_set(np_end_col, nd, (void*)(intptr_t)rbrace_col);
    return nd;
}

int64_t pact_parse_stmt(void) {
    const int has_pending = ((pact_list_len(pending_comments) > 0) || (!pact_str_eq(pending_doc_comment, "")));
    if (pact_at(pact_TokenKind_While)) {
        const int64_t nd = pact_parse_while_loop();
        if (has_pending) {
            pact_attach_comments(nd);
        }
        return nd;
    }
    if (pact_at(pact_TokenKind_Loop)) {
        const int64_t nd = pact_parse_loop_expr();
        if (has_pending) {
            pact_attach_comments(nd);
        }
        return nd;
    }
    if (pact_at(pact_TokenKind_Break)) {
        pact_advance();
        pact_maybe_newline();
        const int64_t nd = pact_new_node(pact_NodeKind_Break);
        if (has_pending) {
            pact_attach_comments(nd);
        }
        return nd;
    }
    if (pact_at(pact_TokenKind_Continue)) {
        pact_advance();
        pact_maybe_newline();
        const int64_t nd = pact_new_node(pact_NodeKind_Continue);
        if (has_pending) {
            pact_attach_comments(nd);
        }
        return nd;
    }
    if (pact_at(pact_TokenKind_Let)) {
        const int64_t nd = pact_parse_let_binding();
        if (has_pending) {
            pact_attach_comments(nd);
        }
        return nd;
    }
    if (pact_at(pact_TokenKind_For)) {
        const int64_t nd = pact_parse_for_in();
        if (has_pending) {
            pact_attach_comments(nd);
        }
        return nd;
    }
    if (pact_at(pact_TokenKind_Return)) {
        const int64_t nd = pact_parse_return_stmt();
        if (has_pending) {
            pact_attach_comments(nd);
        }
        return nd;
    }
    if (pact_at(pact_TokenKind_If)) {
        const int64_t nd = pact_parse_if_expr();
        if (has_pending) {
            pact_attach_comments(nd);
        }
        pact_maybe_newline();
        return nd;
    }
    if (pact_at(pact_TokenKind_With)) {
        const int64_t nd = pact_parse_with_block();
        if (has_pending) {
            pact_attach_comments(nd);
        }
        pact_maybe_newline();
        return nd;
    }
    if (((pact_at(pact_TokenKind_Assert) || pact_at(pact_TokenKind_AssertEq)) || pact_at(pact_TokenKind_AssertNe))) {
        const int64_t assert_kind = pact_peek_kind();
        const char* assert_name = "assert";
        if ((assert_kind == pact_TokenKind_AssertEq)) {
            assert_name = "assert_eq";
        } else if ((assert_kind == pact_TokenKind_AssertNe)) {
            assert_name = "assert_ne";
        }
        pact_advance();
        pact_expect(pact_TokenKind_LParen);
        pact_list* _l0 = pact_list_new();
        pact_list* assert_arg_nodes = _l0;
        pact_list_push(assert_arg_nodes, (void*)(intptr_t)pact_parse_expr());
        while (pact_at(pact_TokenKind_Comma)) {
            pact_advance();
            pact_skip_newlines();
            if (pact_at(pact_TokenKind_RParen)) {
                break;
            }
            pact_list_push(assert_arg_nodes, (void*)(intptr_t)pact_parse_expr());
        }
        pact_expect(pact_TokenKind_RParen);
        const int64_t args_sl = pact_new_sublist();
        int64_t ai = 0;
        while ((ai < pact_list_len(assert_arg_nodes))) {
            pact_sublist_push(args_sl, (int64_t)(intptr_t)pact_list_get(assert_arg_nodes, ai));
            ai = (ai + 1);
        }
        pact_finalize_sublist(args_sl);
        const int64_t fn_ident = pact_new_node(pact_NodeKind_Ident);
        pact_list_set(np_name, fn_ident, (void*)assert_name);
        const int64_t call_nd = pact_new_node(pact_NodeKind_Call);
        pact_list_set(np_left, call_nd, (void*)(intptr_t)fn_ident);
        pact_list_set(np_args, call_nd, (void*)(intptr_t)args_sl);
        pact_maybe_newline();
        const int64_t stmt_nd = pact_new_node(pact_NodeKind_ExprStmt);
        pact_list_set(np_value, stmt_nd, (void*)(intptr_t)call_nd);
        if (has_pending) {
            pact_attach_comments(stmt_nd);
        }
        return stmt_nd;
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
        if (has_pending) {
            pact_attach_comments(nd);
        }
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
        if (has_pending) {
            pact_attach_comments(nd);
        }
        return nd;
    }
    pact_maybe_newline();
    const int64_t nd = pact_new_node(pact_NodeKind_ExprStmt);
    pact_list_pop(np_value);
    pact_list_push(np_value, (void*)(intptr_t)expr);
    if (has_pending) {
        pact_attach_comments(nd);
    }
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
    int64_t peek_pos = pos;
    while (((peek_pos < pact_list_len(tok_kinds)) && ((((int64_t)(intptr_t)pact_list_get(tok_kinds, peek_pos) == pact_TokenKind_Newline) || ((int64_t)(intptr_t)pact_list_get(tok_kinds, peek_pos) == pact_TokenKind_Comment)) || ((int64_t)(intptr_t)pact_list_get(tok_kinds, peek_pos) == pact_TokenKind_DocComment)))) {
        peek_pos = (peek_pos + 1);
    }
    if (((peek_pos < pact_list_len(tok_kinds)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, peek_pos) == pact_TokenKind_Else))) {
        pact_skip_newlines();
    }
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
        pact_list_push(np_op, (void*)"\?\?");
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
            if ((((pact_str_eq(member, "scope") && ((int64_t)(intptr_t)pact_list_get(np_kind, node) == pact_NodeKind_Ident)) && pact_str_eq((const char*)pact_list_get(np_name, node), "async")) && pact_at(pact_TokenKind_LBrace))) {
                const int64_t body = pact_parse_block();
                const int64_t nd = pact_new_node(pact_NodeKind_AsyncScope);
                pact_list_set(np_body, nd, (void*)(intptr_t)body);
                node = nd;
            } else if (pact_str_eq(member, "await")) {
                const int64_t nd = pact_new_node(pact_NodeKind_AwaitExpr);
                pact_list_set(np_obj, nd, (void*)(intptr_t)node);
                node = nd;
            } else {
                if ((((pact_str_eq(member, "new") && ((int64_t)(intptr_t)pact_list_get(np_kind, node) == pact_NodeKind_Ident)) && pact_str_eq((const char*)pact_list_get(np_name, node), "channel")) && pact_at(pact_TokenKind_LBracket))) {
                    const int64_t tparams = pact_parse_type_params();
                    pact_expect(pact_TokenKind_LParen);
                    pact_list* _l0 = pact_list_new();
                    pact_list* cn_arg_nodes = _l0;
                    if ((!pact_at(pact_TokenKind_RParen))) {
                        pact_skip_named_arg_label();
                        pact_list_push(cn_arg_nodes, (void*)(intptr_t)pact_parse_expr());
                        while (pact_at(pact_TokenKind_Comma)) {
                            pact_advance();
                            pact_skip_newlines();
                            pact_list_push(cn_arg_nodes, (void*)(intptr_t)pact_parse_expr());
                        }
                    }
                    pact_expect(pact_TokenKind_RParen);
                    const int64_t cn_args = pact_new_sublist();
                    int64_t cni = 0;
                    while ((cni < pact_list_len(cn_arg_nodes))) {
                        pact_sublist_push(cn_args, (int64_t)(intptr_t)pact_list_get(cn_arg_nodes, cni));
                        cni = (cni + 1);
                    }
                    pact_finalize_sublist(cn_args);
                    const int64_t nd = pact_new_node(pact_NodeKind_ChannelNew);
                    pact_list_set(np_type_params, nd, (void*)(intptr_t)tparams);
                    pact_list_set(np_args, nd, (void*)(intptr_t)cn_args);
                    node = nd;
                } else if (pact_at(pact_TokenKind_LParen)) {
                    pact_advance();
                    pact_list* _l1 = pact_list_new();
                    pact_list* arg_nodes = _l1;
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
            }
        } else if (pact_at(pact_TokenKind_LParen)) {
            pact_advance();
            pact_list* _l2 = pact_list_new();
            pact_list* call_arg_nodes = _l2;
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
                pact_list_push(np_op, (void*)"\?");
                pact_list_pop(np_left);
                pact_list_push(np_left, (void*)(intptr_t)node);
                node = nd;
            } else {
                if ((pact_at(pact_TokenKind_Newline) || pact_at(pact_TokenKind_Comment))) {
                    int64_t peek_pos = pos;
                    while (((peek_pos < pact_list_len(tok_kinds)) && ((((int64_t)(intptr_t)pact_list_get(tok_kinds, peek_pos) == pact_TokenKind_Newline) || ((int64_t)(intptr_t)pact_list_get(tok_kinds, peek_pos) == pact_TokenKind_Comment)) || ((int64_t)(intptr_t)pact_list_get(tok_kinds, peek_pos) == pact_TokenKind_DocComment)))) {
                        peek_pos = (peek_pos + 1);
                    }
                    if (((peek_pos < pact_list_len(tok_kinds)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, peek_pos) == pact_TokenKind_Dot))) {
                        pact_skip_newlines();
                    } else {
                        running = 0;
                    }
                } else {
                    running = 0;
                }
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
    int64_t peek_pos = pos;
    if (((peek_pos >= pact_list_len(tok_kinds)) || ((int64_t)(intptr_t)pact_list_get(tok_kinds, peek_pos) != pact_TokenKind_LBrace))) {
        return 0;
    }
    peek_pos = (peek_pos + 1);
    while (((peek_pos < pact_list_len(tok_kinds)) && ((((int64_t)(intptr_t)pact_list_get(tok_kinds, peek_pos) == pact_TokenKind_Newline) || ((int64_t)(intptr_t)pact_list_get(tok_kinds, peek_pos) == pact_TokenKind_Comment)) || ((int64_t)(intptr_t)pact_list_get(tok_kinds, peek_pos) == pact_TokenKind_DocComment)))) {
        peek_pos = (peek_pos + 1);
    }
    if ((peek_pos >= pact_list_len(tok_kinds))) {
        return 0;
    }
    if (((int64_t)(intptr_t)pact_list_get(tok_kinds, peek_pos) == pact_TokenKind_RBrace)) {
        return 1;
    }
    if (((int64_t)(intptr_t)pact_list_get(tok_kinds, peek_pos) != pact_TokenKind_Ident)) {
        return 0;
    }
    peek_pos = (peek_pos + 1);
    if (((peek_pos < pact_list_len(tok_kinds)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, peek_pos) == pact_TokenKind_Colon))) {
        return 1;
    }
    return 0;
}

int64_t pact_parse_primary(void) {
    if (pact_at(pact_TokenKind_Match)) {
        const int64_t next_pos = (pos + 1);
        const int next_ok = ((((((((((((next_pos < pact_list_len(tok_kinds)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_RParen)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_RBrace)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_Comma)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_Dot)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_Newline)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_EOF)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_Equals)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_EqEq)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_RBracket)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_StringEnd)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_InterpEnd));
        if (next_ok) {
            return pact_parse_match_expr();
        }
        pact_diag_error("KeywordAsIdentifier", "E1103", "'match' is a keyword and cannot be used as an identifier", pact_peek_line(), pact_peek_col(), "use a different name");
        pact_advance();
        const int64_t nd = pact_new_node(pact_NodeKind_Ident);
        pact_list_pop(np_name);
        pact_list_push(np_name, (void*)"match");
        return nd;
    }
    if (pact_at(pact_TokenKind_If)) {
        const int64_t next_pos = (pos + 1);
        const int next_ok = ((((((((((((next_pos < pact_list_len(tok_kinds)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_RParen)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_RBrace)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_Comma)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_Dot)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_Newline)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_EOF)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_Equals)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_EqEq)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_RBracket)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_StringEnd)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) != pact_TokenKind_InterpEnd));
        if (next_ok) {
            return pact_parse_if_expr();
        }
        pact_diag_error("KeywordAsIdentifier", "E1103", "'if' is a keyword and cannot be used as an identifier", pact_peek_line(), pact_peek_col(), "use a different name");
        pact_advance();
        const int64_t nd = pact_new_node(pact_NodeKind_Ident);
        pact_list_pop(np_name);
        pact_list_push(np_name, (void*)"if");
        return nd;
    }
    if (pact_at(pact_TokenKind_Self)) {
        pact_advance();
        const int64_t nd = pact_new_node(pact_NodeKind_Ident);
        pact_list_pop(np_name);
        pact_list_push(np_name, (void*)"self");
        return nd;
    }
    if (pact_at(pact_TokenKind_Fn)) {
        const int64_t next_pos = (pos + 1);
        if (((next_pos < pact_list_len(tok_kinds)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) == pact_TokenKind_LParen))) {
            return pact_parse_closure();
        }
        pact_diag_error("KeywordAsIdentifier", "E1103", "'fn' is a keyword and cannot be used as an identifier", pact_peek_line(), pact_peek_col(), "use a different name");
        pact_advance();
        const int64_t nd = pact_new_node(pact_NodeKind_Ident);
        pact_list_pop(np_name);
        pact_list_push(np_name, (void*)"fn");
        return nd;
    }
    if (pact_at(pact_TokenKind_Handler)) {
        const int64_t next_pos = (pos + 1);
        if (((next_pos < pact_list_len(tok_kinds)) && ((int64_t)(intptr_t)pact_list_get(tok_kinds, next_pos) == pact_TokenKind_Ident))) {
            return pact_parse_handler_expr();
        }
        pact_diag_error("KeywordAsIdentifier", "E1103", "'handler' is a keyword and cannot be used as an identifier", pact_peek_line(), pact_peek_col(), "use a different name");
        pact_advance();
        const int64_t nd = pact_new_node(pact_NodeKind_Ident);
        pact_list_pop(np_name);
        pact_list_push(np_name, (void*)"handler");
        return nd;
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
    if (pact_is_keyword(pact_peek_kind())) {
        const char* kw_name = pact_peek_value();
        char _si_1[4096];
        snprintf(_si_1, 4096, "'%s' is a keyword and cannot be used as an identifier", kw_name);
        pact_diag_error("KeywordAsIdentifier", "E1103", strdup(_si_1), pact_peek_line(), pact_peek_col(), "use a different name");
        pact_advance();
        const int64_t nd = pact_new_node(pact_NodeKind_Ident);
        pact_list_pop(np_name);
        pact_list_push(np_name, (void*)kw_name);
        return nd;
    }
    char _si_2[4096];
    snprintf(_si_2, 4096, "unexpected token %lld", (long long)pact_peek_kind());
    pact_diag_error("UnexpectedToken", "E1100", strdup(_si_2), pact_peek_line(), pact_peek_col(), "");
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
            snprintf(_si_1, 4096, "unexpected token in string: %lld", (long long)pact_peek_kind());
            pact_diag_error("UnexpectedToken", "E1101", strdup(_si_1), pact_peek_line(), pact_peek_col(), "");
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
    snprintf(_si_4, 4096, "unexpected token in pattern: %lld", (long long)pact_peek_kind());
    pact_diag_error("UnexpectedToken", "E1102", strdup(_si_4), pact_peek_line(), pact_peek_col(), "");
    pact_advance();
    return pact_new_node(pact_NodeKind_WildcardPattern);
}

int64_t pact_new_type(int64_t kind, const char* name) {
    const int64_t idx = pact_list_len(ty_kind);
    pact_list_push(ty_kind, (void*)(intptr_t)kind);
    pact_list_push(ty_name, (void*)name);
    pact_list_push(ty_inner1, (void*)(intptr_t)(-1));
    pact_list_push(ty_inner2, (void*)(intptr_t)(-1));
    pact_list_push(ty_params_start, (void*)(intptr_t)(-1));
    pact_list_push(ty_params_count, (void*)(intptr_t)0);
    return idx;
}

int64_t pact_make_list_type(int64_t inner) {
    const int64_t t = pact_new_type(TK_LIST, "List");
    pact_list_set(ty_inner1, t, (void*)(intptr_t)inner);
    return t;
}

int64_t pact_make_option_type(int64_t inner) {
    const int64_t t = pact_new_type(TK_OPTION, "Option");
    pact_list_set(ty_inner1, t, (void*)(intptr_t)inner);
    return t;
}

int64_t pact_make_result_type(int64_t ok_type, int64_t err_type) {
    const int64_t t = pact_new_type(TK_RESULT, "Result");
    pact_list_set(ty_inner1, t, (void*)(intptr_t)ok_type);
    pact_list_set(ty_inner2, t, (void*)(intptr_t)err_type);
    return t;
}

int64_t pact_make_fn_type(int64_t ret_type, pact_list* param_types) {
    const int64_t t = pact_new_type(TK_FN, "Fn");
    pact_list_set(ty_inner1, t, (void*)(intptr_t)ret_type);
    const int64_t start = pact_list_len(ty_param_list);
    int64_t i = 0;
    while ((i < pact_list_len(param_types))) {
        pact_list_push(ty_param_list, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(param_types, i));
        i = (i + 1);
    }
    pact_list_set(ty_params_start, t, (void*)(intptr_t)start);
    pact_list_set(ty_params_count, t, (void*)(intptr_t)pact_list_len(param_types));
    return t;
}

int64_t pact_make_typevar(const char* name) {
    return pact_new_type(TK_TYPEVAR, name);
}

int64_t pact_make_tuple_type(pact_list* elem_types) {
    const int64_t t = pact_new_type(TK_TUPLE, "Tuple");
    const int64_t start = pact_list_len(ty_param_list);
    int64_t i = 0;
    while ((i < pact_list_len(elem_types))) {
        pact_list_push(ty_param_list, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(elem_types, i));
        i = (i + 1);
    }
    pact_list_set(ty_params_start, t, (void*)(intptr_t)start);
    pact_list_set(ty_params_count, t, (void*)(intptr_t)pact_list_len(elem_types));
    return t;
}

int64_t pact_make_map_type(int64_t key_type, int64_t value_type) {
    const int64_t t = pact_new_type(TK_MAP, "Map");
    pact_list_set(ty_inner1, t, (void*)(intptr_t)key_type);
    pact_list_set(ty_inner2, t, (void*)(intptr_t)value_type);
    return t;
}

int64_t pact_lookup_named_type(const char* name) {
    if ((pact_map_has(named_type_map, name) != 0)) {
        return (int64_t)(intptr_t)pact_map_get(named_type_map, name);
    }
    return (-1);
}

int64_t pact_resolve_type_name(const char* name) {
    if (pact_str_eq(name, "Int")) {
        return TYPE_INT;
    }
    if (pact_str_eq(name, "Float")) {
        return TYPE_FLOAT;
    }
    if (pact_str_eq(name, "Bool")) {
        return TYPE_BOOL;
    }
    if (pact_str_eq(name, "Str")) {
        return TYPE_STR;
    }
    if ((pact_str_eq(name, "Void") || pact_str_eq(name, ""))) {
        return TYPE_VOID;
    }
    return pact_lookup_named_type(name);
}

int64_t pact_get_struct_field_tid(int64_t struct_tid, const char* fname) {
    int64_t i = 0;
    while ((i < pact_list_len(sfield_struct_id))) {
        if ((((int64_t)(intptr_t)pact_list_get(sfield_struct_id, i) == struct_tid) && pact_str_eq((const char*)pact_list_get(sfield_name, i), fname))) {
            return (int64_t)(intptr_t)pact_list_get(sfield_type_id, i);
        }
        i = (i + 1);
    }
    return (-1);
}

int64_t pact_get_variant_by_name(int64_t enum_tid, const char* vname) {
    int64_t i = 0;
    while ((i < pact_list_len(evar_enum_id))) {
        if ((((int64_t)(intptr_t)pact_list_get(evar_enum_id, i) == enum_tid) && pact_str_eq((const char*)pact_list_get(evar_name, i), vname))) {
            return i;
        }
        i = (i + 1);
    }
    return (-1);
}

int64_t pact_lookup_fnsig(const char* name) {
    if ((pact_map_has(fnsig_map, name) != 0)) {
        return (int64_t)(intptr_t)pact_map_get(fnsig_map, name);
    }
    return (-1);
}

int64_t pact_instantiate_return_type(int64_t sig, int64_t args_sl) {
    const int64_t ret = (int64_t)(intptr_t)pact_list_get(fnsig_ret, sig);
    if (((ret < 0) || (ret >= pact_list_len(ty_kind)))) {
        return ret;
    }
    if (((int64_t)(intptr_t)pact_list_get(ty_kind, ret) != TK_TYPEVAR)) {
        return ret;
    }
    const char* tp_name = (const char*)pact_list_get(ty_name, ret);
    const int64_t tp_start = (int64_t)(intptr_t)pact_list_get(fnsig_type_params_start, sig);
    const int64_t tp_count = (int64_t)(intptr_t)pact_list_get(fnsig_type_params_count, sig);
    const int64_t param_start = (int64_t)(intptr_t)pact_list_get(fnsig_params_start, sig);
    const int64_t param_count = (int64_t)(intptr_t)pact_list_get(fnsig_params_count, sig);
    int64_t ti = 0;
    while ((ti < tp_count)) {
        if (pact_str_eq((const char*)pact_list_get(fnsig_type_param_names, (tp_start + ti)), tp_name)) {
            int64_t pi = 0;
            while ((pi < param_count)) {
                const int64_t ptid = (int64_t)(intptr_t)pact_list_get(fnsig_param_list, (param_start + pi));
                if (((((ptid >= 0) && (ptid < pact_list_len(ty_kind))) && ((int64_t)(intptr_t)pact_list_get(ty_kind, ptid) == TK_TYPEVAR)) && pact_str_eq((const char*)pact_list_get(ty_name, ptid), tp_name))) {
                    if (((args_sl != (-1)) && (pi < pact_sublist_length(args_sl)))) {
                        return pact_infer_type(pact_sublist_get(args_sl, pi));
                    }
                }
                pi = (pi + 1);
            }
        }
        ti = (ti + 1);
    }
    return ret;
}

void pact_tc_error(const char* msg) {
    pact_list_push(tc_errors, (void*)msg);
    pact_diag_error_no_loc("TypeError", "E0300", msg, "");
}

void pact_tc_warn(const char* msg) {
    pact_list_push(tc_warnings, (void*)msg);
}

void pact_tc_set_incremental_filter(pact_list* names) {
    tc_inc_filter = pact_map_new();
    int64_t i = 0;
    while ((i < pact_list_len(names))) {
        pact_map_set(tc_inc_filter, (const char*)pact_list_get(names, i), (void*)(intptr_t)1);
        i = (i + 1);
    }
    tc_inc_enabled = 1;
}

void pact_tc_clear_incremental_filter(void) {
    tc_inc_filter = pact_map_new();
    tc_inc_enabled = 0;
}

int64_t pact_tc_should_check_fn(const char* name) {
    if ((tc_inc_enabled == 0)) {
        return 1;
    }
    return pact_map_has(tc_inc_filter, name);
}

int64_t pact_resolve_type_ann(int64_t ann_node) {
    if ((ann_node == (-1))) {
        return TYPE_UNKNOWN;
    }
    const char* name = (const char*)pact_list_get(np_name, ann_node);
    const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, ann_node);
    if (pact_str_eq(name, "List")) {
        if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) >= 1))) {
            const int64_t inner = pact_resolve_type_ann(pact_sublist_get(elems_sl, 0));
            return pact_make_list_type(inner);
        }
        return pact_make_list_type(TYPE_UNKNOWN);
    }
    if (pact_str_eq(name, "Option")) {
        if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) >= 1))) {
            const int64_t inner = pact_resolve_type_ann(pact_sublist_get(elems_sl, 0));
            return pact_make_option_type(inner);
        }
        return pact_make_option_type(TYPE_UNKNOWN);
    }
    if (pact_str_eq(name, "Result")) {
        if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) >= 2))) {
            const int64_t ok_t = pact_resolve_type_ann(pact_sublist_get(elems_sl, 0));
            const int64_t err_t = pact_resolve_type_ann(pact_sublist_get(elems_sl, 1));
            return pact_make_result_type(ok_t, err_t);
        }
        return pact_make_result_type(TYPE_UNKNOWN, TYPE_UNKNOWN);
    }
    if (pact_str_eq(name, "Map")) {
        if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) >= 2))) {
            const int64_t key_t = pact_resolve_type_ann(pact_sublist_get(elems_sl, 0));
            const int64_t val_t = pact_resolve_type_ann(pact_sublist_get(elems_sl, 1));
            return pact_make_map_type(key_t, val_t);
        }
        return pact_make_map_type(TYPE_UNKNOWN, TYPE_UNKNOWN);
    }
    const int64_t resolved = pact_resolve_type_name(name);
    if ((resolved != (-1))) {
        return resolved;
    }
    return pact_make_typevar(name);
}

void pact_register_struct_type(int64_t td) {
    const char* name = (const char*)pact_list_get(np_name, td);
    const int64_t tid = pact_new_type(TK_STRUCT, name);
    pact_list_push(named_type_names, (void*)name);
    pact_list_push(named_type_ids, (void*)(intptr_t)tid);
    pact_map_set(named_type_map, name, (void*)(intptr_t)tid);
    const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, td);
    if ((flds_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(flds_sl))) {
            const int64_t f = pact_sublist_get(flds_sl, i);
            const char* fname = (const char*)pact_list_get(np_name, f);
            const int64_t ftype_ann = (int64_t)(intptr_t)pact_list_get(np_value, f);
            const int64_t ftype_id = pact_resolve_type_ann(ftype_ann);
            pact_list_push(sfield_struct_id, (void*)(intptr_t)tid);
            pact_list_push(sfield_name, (void*)fname);
            pact_list_push(sfield_type_id, (void*)(intptr_t)ftype_id);
            i = (i + 1);
        }
    }
}

void pact_register_enum_type(int64_t td) {
    const char* name = (const char*)pact_list_get(np_name, td);
    const int64_t tid = pact_new_type(TK_ENUM, name);
    pact_list_push(named_type_names, (void*)name);
    pact_list_push(named_type_ids, (void*)(intptr_t)tid);
    pact_map_set(named_type_map, name, (void*)(intptr_t)tid);
    const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, td);
    if ((flds_sl != (-1))) {
        int64_t tag = 0;
        int64_t i = 0;
        while ((i < pact_sublist_length(flds_sl))) {
            const int64_t v = pact_sublist_get(flds_sl, i);
            const char* vname = (const char*)pact_list_get(np_name, v);
            const int64_t var_idx = pact_list_len(evar_enum_id);
            pact_list_push(evar_enum_id, (void*)(intptr_t)tid);
            pact_list_push(evar_name, (void*)vname);
            pact_list_push(evar_tag, (void*)(intptr_t)tag);
            const int64_t vflds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, v);
            if (((vflds_sl != (-1)) && (pact_sublist_length(vflds_sl) > 0))) {
                pact_list_push(evar_has_data, (void*)(intptr_t)1);
                int64_t fi = 0;
                while ((fi < pact_sublist_length(vflds_sl))) {
                    const int64_t vf = pact_sublist_get(vflds_sl, fi);
                    const char* vf_name = (const char*)pact_list_get(np_name, vf);
                    const int64_t vf_type_ann = (int64_t)(intptr_t)pact_list_get(np_value, vf);
                    const int64_t vf_type_id = pact_resolve_type_ann(vf_type_ann);
                    pact_list_push(evfield_var_idx, (void*)(intptr_t)var_idx);
                    pact_list_push(evfield_name, (void*)vf_name);
                    pact_list_push(evfield_type_id, (void*)(intptr_t)vf_type_id);
                    fi = (fi + 1);
                }
            } else {
                pact_list_push(evar_has_data, (void*)(intptr_t)0);
            }
            tag = (tag + 1);
            i = (i + 1);
        }
    }
}

void pact_register_fn_sig(int64_t fn_node) {
    const char* name = (const char*)pact_list_get(np_name, fn_node);
    const char* ret_str = (const char*)pact_list_get(np_return_type, fn_node);
    const int64_t ret_ann = (int64_t)(intptr_t)pact_list_get(np_type_ann, fn_node);
    int64_t ret_tid = TYPE_VOID;
    if ((ret_ann != (-1))) {
        ret_tid = pact_resolve_type_ann(ret_ann);
    } else if ((!pact_str_eq(ret_str, ""))) {
        ret_tid = pact_resolve_type_name(ret_str);
        if ((ret_tid == (-1))) {
            ret_tid = TYPE_VOID;
        }
    }
    const int64_t sig_idx = pact_list_len(fnsig_name);
    pact_list_push(fnsig_name, (void*)name);
    pact_map_set(fnsig_map, name, (void*)(intptr_t)sig_idx);
    pact_list_push(fnsig_ret, (void*)(intptr_t)ret_tid);
    const int64_t start = pact_list_len(fnsig_param_list);
    pact_list_push(fnsig_params_start, (void*)(intptr_t)start);
    const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, fn_node);
    int64_t count = 0;
    if ((params_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(params_sl))) {
            const int64_t p = pact_sublist_get(params_sl, i);
            const char* ptype_str = (const char*)pact_list_get(np_type_name, p);
            const int64_t ptype_ann = (int64_t)(intptr_t)pact_list_get(np_type_ann, p);
            int64_t ptid = TYPE_UNKNOWN;
            if ((ptype_ann != (-1))) {
                ptid = pact_resolve_type_ann(ptype_ann);
            } else if ((!pact_str_eq(ptype_str, ""))) {
                ptid = pact_resolve_type_name(ptype_str);
                if ((ptid == (-1))) {
                    ptid = TYPE_UNKNOWN;
                }
            }
            pact_list_push(fnsig_param_list, (void*)(intptr_t)ptid);
            count = (count + 1);
            i = (i + 1);
        }
    }
    pact_list_push(fnsig_params_count, (void*)(intptr_t)count);
    const int64_t tparams_sl = (int64_t)(intptr_t)pact_list_get(np_type_params, fn_node);
    const int64_t tp_start = pact_list_len(fnsig_type_param_names);
    int64_t tp_count = 0;
    if ((tparams_sl != (-1))) {
        int64_t ti = 0;
        while ((ti < pact_sublist_length(tparams_sl))) {
            const int64_t tp = pact_sublist_get(tparams_sl, ti);
            pact_list_push(fnsig_type_param_names, (void*)(const char*)pact_list_get(np_name, tp));
            tp_count = (tp_count + 1);
            ti = (ti + 1);
        }
    }
    pact_list_push(fnsig_type_params_start, (void*)(intptr_t)tp_start);
    pact_list_push(fnsig_type_params_count, (void*)(intptr_t)tp_count);
    const int64_t effects_sl = (int64_t)(intptr_t)pact_list_get(np_effects, fn_node);
    const char* effs = "";
    if ((effects_sl != (-1))) {
        int64_t ei = 0;
        while ((ei < pact_sublist_length(effects_sl))) {
            const int64_t eff = pact_sublist_get(effects_sl, ei);
            if ((ei > 0)) {
                effs = pact_str_concat(effs, ",");
            }
            effs = pact_str_concat(effs, (const char*)pact_list_get(np_name, eff));
            ei = (ei + 1);
        }
    }
    pact_list_push(tc_fn_effects, (void*)effs);
}

const char* pact_tc_get_fn_effects(const char* name) {
    const int64_t sig = pact_lookup_fnsig(name);
    if ((sig == (-1))) {
        return "";
    }
    if ((sig >= pact_list_len(tc_fn_effects))) {
        return "";
    }
    return (const char*)pact_list_get(tc_fn_effects, sig);
}

void pact_register_trait(int64_t tr_node) {
    const char* name = (const char*)pact_list_get(np_name, tr_node);
    pact_list_push(tc_trait_names, (void*)name);
    const int64_t methods_sl = (int64_t)(intptr_t)pact_list_get(np_methods, tr_node);
    if ((methods_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(methods_sl))) {
            const int64_t m = pact_sublist_get(methods_sl, i);
            char _si_0[4096];
            snprintf(_si_0, 4096, "%s.%s", name, (const char*)pact_list_get(np_name, m));
            pact_list_push(tc_trait_method_names, (void*)strdup(_si_0));
            i = (i + 1);
        }
    }
}

void pact_init_types(void) {
    pact_list* _l0 = pact_list_new();
    ty_kind = _l0;
    pact_list* _l1 = pact_list_new();
    ty_name = _l1;
    pact_list* _l2 = pact_list_new();
    ty_inner1 = _l2;
    pact_list* _l3 = pact_list_new();
    ty_inner2 = _l3;
    pact_list* _l4 = pact_list_new();
    ty_params_start = _l4;
    pact_list* _l5 = pact_list_new();
    ty_params_count = _l5;
    pact_list* _l6 = pact_list_new();
    ty_param_list = _l6;
    pact_list* _l7 = pact_list_new();
    named_type_names = _l7;
    pact_list* _l8 = pact_list_new();
    named_type_ids = _l8;
    named_type_map = pact_map_new();
    pact_list* _l9 = pact_list_new();
    sfield_struct_id = _l9;
    pact_list* _l10 = pact_list_new();
    sfield_name = _l10;
    pact_list* _l11 = pact_list_new();
    sfield_type_id = _l11;
    pact_list* _l12 = pact_list_new();
    evar_enum_id = _l12;
    pact_list* _l13 = pact_list_new();
    evar_name = _l13;
    pact_list* _l14 = pact_list_new();
    evar_tag = _l14;
    pact_list* _l15 = pact_list_new();
    evar_has_data = _l15;
    pact_list* _l16 = pact_list_new();
    evfield_var_idx = _l16;
    pact_list* _l17 = pact_list_new();
    evfield_name = _l17;
    pact_list* _l18 = pact_list_new();
    evfield_type_id = _l18;
    pact_list* _l19 = pact_list_new();
    fnsig_name = _l19;
    fnsig_map = pact_map_new();
    pact_list* _l20 = pact_list_new();
    fnsig_ret = _l20;
    pact_list* _l21 = pact_list_new();
    fnsig_params_start = _l21;
    pact_list* _l22 = pact_list_new();
    fnsig_params_count = _l22;
    pact_list* _l23 = pact_list_new();
    fnsig_param_list = _l23;
    pact_list* _l24 = pact_list_new();
    fnsig_type_params_start = _l24;
    pact_list* _l25 = pact_list_new();
    fnsig_type_params_count = _l25;
    pact_list* _l26 = pact_list_new();
    fnsig_type_param_names = _l26;
    pact_list* _l27 = pact_list_new();
    tc_trait_names = _l27;
    pact_list* _l28 = pact_list_new();
    tc_trait_method_names = _l28;
    pact_list* _l29 = pact_list_new();
    tc_fn_effects = _l29;
    tc_current_fn_ret = (-1);
    tc_current_fn_name = "";
    pact_list* _l30 = pact_list_new();
    tc_errors = _l30;
    pact_list* _l31 = pact_list_new();
    tc_warnings = _l31;
    TYPE_INT = pact_new_type(TK_INT, "Int");
    TYPE_FLOAT = pact_new_type(TK_FLOAT, "Float");
    TYPE_BOOL = pact_new_type(TK_BOOL, "Bool");
    TYPE_STR = pact_new_type(TK_STR, "Str");
    TYPE_VOID = pact_new_type(TK_VOID, "Void");
    TYPE_UNKNOWN = pact_new_type(TK_UNKNOWN, "\?");
}

int64_t pact_check_types(int64_t program) {
    pact_init_types();
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
            if ((is_enum != 0)) {
                pact_register_enum_type(td);
            } else {
                pact_register_struct_type(td);
            }
            i = (i + 1);
        }
    }
    const int64_t fns_sl = (int64_t)(intptr_t)pact_list_get(np_params, program);
    if ((fns_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(fns_sl))) {
            pact_register_fn_sig(pact_sublist_get(fns_sl, i));
            i = (i + 1);
        }
    }
    const int64_t traits_sl = (int64_t)(intptr_t)pact_list_get(np_arms, program);
    if ((traits_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(traits_sl))) {
            pact_register_trait(pact_sublist_get(traits_sl, i));
            i = (i + 1);
        }
    }
    const int64_t impls_sl = (int64_t)(intptr_t)pact_list_get(np_methods, program);
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
                    const char* orig_name = (const char*)pact_list_get(np_name, m);
                    char _si_0[4096];
                    snprintf(_si_0, 4096, "%s_%s", impl_type, orig_name);
                    pact_list_set(np_name, m, (void*)strdup(_si_0));
                    pact_register_fn_sig(m);
                    pact_list_set(np_name, m, (void*)orig_name);
                    j = (j + 1);
                }
            }
            i = (i + 1);
        }
    }
    pact_resolve_names(program);
    pact_tc_infer_program(program);
    return pact_list_len(tc_errors);
}

void pact_nr_push_scope(void) {
    pact_list_push(nr_scope_frames, (void*)(intptr_t)pact_list_len(nr_scope_names));
}

void pact_nr_pop_scope(void) {
    const int64_t start = (int64_t)(intptr_t)pact_list_get(nr_scope_frames, (pact_list_len(nr_scope_frames) - 1));
    pact_list_pop(nr_scope_frames);
    while ((pact_list_len(nr_scope_names) > start)) {
        pact_list_pop(nr_scope_names);
        pact_list_pop(nr_scope_muts);
        pact_list_pop(nr_scope_types);
    }
}

void pact_nr_define(const char* name) {
    pact_list_push(nr_scope_names, (void*)name);
    pact_list_push(nr_scope_muts, (void*)(intptr_t)0);
    pact_list_push(nr_scope_types, (void*)(intptr_t)TYPE_UNKNOWN);
}

void pact_nr_define_mut(const char* name, int64_t is_mut) {
    pact_list_push(nr_scope_names, (void*)name);
    pact_list_push(nr_scope_muts, (void*)(intptr_t)is_mut);
    pact_list_push(nr_scope_types, (void*)(intptr_t)TYPE_UNKNOWN);
}

void pact_nr_define_typed(const char* name, int64_t is_mut, int64_t tid) {
    pact_list_push(nr_scope_names, (void*)name);
    pact_list_push(nr_scope_muts, (void*)(intptr_t)is_mut);
    pact_list_push(nr_scope_types, (void*)(intptr_t)tid);
}

int64_t pact_nr_is_defined(const char* name) {
    int64_t i = (pact_list_len(nr_scope_names) - 1);
    while ((i >= 0)) {
        if (pact_str_eq((const char*)pact_list_get(nr_scope_names, i), name)) {
            return 1;
        }
        i = (i - 1);
    }
    return 0;
}

int64_t pact_nr_is_mut(const char* name) {
    int64_t i = (pact_list_len(nr_scope_names) - 1);
    while ((i >= 0)) {
        if (pact_str_eq((const char*)pact_list_get(nr_scope_names, i), name)) {
            return (int64_t)(intptr_t)pact_list_get(nr_scope_muts, i);
        }
        i = (i - 1);
    }
    return 0;
}

int64_t pact_nr_get_type(const char* name) {
    int64_t i = (pact_list_len(nr_scope_names) - 1);
    while ((i >= 0)) {
        if (pact_str_eq((const char*)pact_list_get(nr_scope_names, i), name)) {
            return (int64_t)(intptr_t)pact_list_get(nr_scope_types, i);
        }
        i = (i - 1);
    }
    return TYPE_UNKNOWN;
}

int64_t pact_is_builtin_fn(const char* name) {
    if (pact_str_eq(name, "arg_count")) {
        return 1;
    }
    if (pact_str_eq(name, "get_arg")) {
        return 1;
    }
    if (pact_str_eq(name, "read_file")) {
        return 1;
    }
    if (pact_str_eq(name, "write_file")) {
        return 1;
    }
    if (pact_str_eq(name, "file_exists")) {
        return 1;
    }
    if (pact_str_eq(name, "path_join")) {
        return 1;
    }
    if (pact_str_eq(name, "path_dirname")) {
        return 1;
    }
    if (pact_str_eq(name, "path_basename")) {
        return 1;
    }
    if (pact_str_eq(name, "shell_exec")) {
        return 1;
    }
    if (pact_str_eq(name, "exit")) {
        return 1;
    }
    if (pact_str_eq(name, "is_dir")) {
        return 1;
    }
    if (pact_str_eq(name, "get_env")) {
        return 1;
    }
    if (pact_str_eq(name, "time_ms")) {
        return 1;
    }
    if (pact_str_eq(name, "Some")) {
        return 1;
    }
    if (pact_str_eq(name, "None")) {
        return 1;
    }
    if (pact_str_eq(name, "Ok")) {
        return 1;
    }
    if (pact_str_eq(name, "Err")) {
        return 1;
    }
    if (pact_str_eq(name, "assert")) {
        return 1;
    }
    if (pact_str_eq(name, "assert_eq")) {
        return 1;
    }
    if (pact_str_eq(name, "assert_ne")) {
        return 1;
    }
    if (pact_str_eq(name, "debug_assert")) {
        return 1;
    }
    if (pact_str_eq(name, "Map")) {
        return 1;
    }
    if (pact_str_eq(name, "Channel")) {
        return 1;
    }
    if (pact_str_eq(name, "unix_socket_listen")) {
        return 1;
    }
    if (pact_str_eq(name, "unix_socket_connect")) {
        return 1;
    }
    if (pact_str_eq(name, "unix_socket_accept")) {
        return 1;
    }
    if (pact_str_eq(name, "unix_socket_close")) {
        return 1;
    }
    if (pact_str_eq(name, "socket_read_line")) {
        return 1;
    }
    if (pact_str_eq(name, "socket_write")) {
        return 1;
    }
    if (pact_str_eq(name, "file_mtime")) {
        return 1;
    }
    if (pact_str_eq(name, "getpid")) {
        return 1;
    }
    return 0;
}

int64_t pact_get_builtin_fn_ret(const char* name) {
    if (pact_str_eq(name, "arg_count")) {
        return TYPE_INT;
    }
    if (pact_str_eq(name, "get_arg")) {
        return TYPE_STR;
    }
    if (pact_str_eq(name, "read_file")) {
        return TYPE_STR;
    }
    if (pact_str_eq(name, "write_file")) {
        return TYPE_VOID;
    }
    if (pact_str_eq(name, "file_exists")) {
        return TYPE_INT;
    }
    if (pact_str_eq(name, "path_join")) {
        return TYPE_STR;
    }
    if (pact_str_eq(name, "path_dirname")) {
        return TYPE_STR;
    }
    if (pact_str_eq(name, "path_basename")) {
        return TYPE_STR;
    }
    if (pact_str_eq(name, "shell_exec")) {
        return TYPE_INT;
    }
    if (pact_str_eq(name, "exit")) {
        return TYPE_VOID;
    }
    if (pact_str_eq(name, "is_dir")) {
        return TYPE_INT;
    }
    if (pact_str_eq(name, "get_env")) {
        return pact_make_option_type(TYPE_STR);
    }
    if (pact_str_eq(name, "time_ms")) {
        return TYPE_INT;
    }
    if (pact_str_eq(name, "assert")) {
        return TYPE_VOID;
    }
    if (pact_str_eq(name, "assert_eq")) {
        return TYPE_VOID;
    }
    if (pact_str_eq(name, "assert_ne")) {
        return TYPE_VOID;
    }
    if (pact_str_eq(name, "debug_assert")) {
        return TYPE_VOID;
    }
    if (pact_str_eq(name, "unix_socket_listen")) {
        return TYPE_INT;
    }
    if (pact_str_eq(name, "unix_socket_connect")) {
        return TYPE_INT;
    }
    if (pact_str_eq(name, "unix_socket_accept")) {
        return TYPE_INT;
    }
    if (pact_str_eq(name, "unix_socket_close")) {
        return TYPE_VOID;
    }
    if (pact_str_eq(name, "socket_read_line")) {
        return TYPE_STR;
    }
    if (pact_str_eq(name, "socket_write")) {
        return TYPE_VOID;
    }
    if (pact_str_eq(name, "file_mtime")) {
        return TYPE_INT;
    }
    if (pact_str_eq(name, "getpid")) {
        return TYPE_INT;
    }
    return TYPE_UNKNOWN;
}

int64_t pact_is_variant_name(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(evar_name))) {
        if (pact_str_eq((const char*)pact_list_get(evar_name, i), name)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_get_variant_enum_tid(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(evar_name))) {
        if (pact_str_eq((const char*)pact_list_get(evar_name, i), name)) {
            return (int64_t)(intptr_t)pact_list_get(evar_enum_id, i);
        }
        i = (i + 1);
    }
    return TYPE_UNKNOWN;
}

int64_t pact_is_known_type(const char* name) {
    if ((((pact_str_eq(name, "Int") || pact_str_eq(name, "Float")) || pact_str_eq(name, "Bool")) || pact_str_eq(name, "Str"))) {
        return 1;
    }
    if ((((pact_str_eq(name, "Void") || pact_str_eq(name, "List")) || pact_str_eq(name, "Option")) || pact_str_eq(name, "Result"))) {
        return 1;
    }
    if ((((pact_str_eq(name, "Iterator") || pact_str_eq(name, "Handle")) || pact_str_eq(name, "Channel")) || pact_str_eq(name, "Map"))) {
        return 1;
    }
    if ((pact_str_eq(name, "Fn") || pact_str_eq(name, "Self"))) {
        return 1;
    }
    if ((pact_lookup_named_type(name) != (-1))) {
        return 1;
    }
    return 0;
}

int64_t pact_nr_has_impl_method(const char* type_name, const char* method) {
    int64_t i = 0;
    while ((i < pact_list_len(nr_impl_type_names))) {
        if ((pact_str_eq((const char*)pact_list_get(nr_impl_type_names, i), type_name) && pact_str_eq((const char*)pact_list_get(nr_impl_method_names, i), method))) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

void pact_resolve_names(int64_t program) {
    pact_list* _l0 = pact_list_new();
    nr_scope_names = _l0;
    pact_list* _l1 = pact_list_new();
    nr_scope_muts = _l1;
    pact_list* _l2 = pact_list_new();
    nr_scope_types = _l2;
    pact_list* _l3 = pact_list_new();
    nr_scope_frames = _l3;
    pact_list* _l4 = pact_list_new();
    nr_impl_type_names = _l4;
    pact_list* _l5 = pact_list_new();
    nr_impl_method_names = _l5;
    pact_nr_push_scope();
    const int64_t lets_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, program);
    if ((lets_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(lets_sl))) {
            const int64_t l = pact_sublist_get(lets_sl, i);
            pact_nr_define((const char*)pact_list_get(np_name, l));
            i = (i + 1);
        }
    }
    const int64_t fns_sl = (int64_t)(intptr_t)pact_list_get(np_params, program);
    if ((fns_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(fns_sl))) {
            pact_nr_define((const char*)pact_list_get(np_name, pact_sublist_get(fns_sl, i)));
            i = (i + 1);
        }
    }
    const int64_t impls_sl = (int64_t)(intptr_t)pact_list_get(np_methods, program);
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
                    pact_list_push(nr_impl_type_names, (void*)impl_type);
                    pact_list_push(nr_impl_method_names, (void*)(const char*)pact_list_get(np_name, m));
                    j = (j + 1);
                }
            }
            i = (i + 1);
        }
    }
    if ((fns_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(fns_sl))) {
            const int64_t fn_node = pact_sublist_get(fns_sl, i);
            pact_nr_check_fn(fn_node);
            i = (i + 1);
        }
    }
    if ((impls_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(impls_sl))) {
            const int64_t im = pact_sublist_get(impls_sl, i);
            const int64_t methods_sl = (int64_t)(intptr_t)pact_list_get(np_methods, im);
            if ((methods_sl != (-1))) {
                int64_t j = 0;
                while ((j < pact_sublist_length(methods_sl))) {
                    pact_nr_check_fn(pact_sublist_get(methods_sl, j));
                    j = (j + 1);
                }
            }
            i = (i + 1);
        }
    }
    pact_nr_pop_scope();
}

void pact_nr_check_fn(int64_t fn_node) {
    pact_nr_push_scope();
    const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, fn_node);
    if ((params_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(params_sl))) {
            const int64_t p = pact_sublist_get(params_sl, i);
            pact_nr_define((const char*)pact_list_get(np_name, p));
            pact_nr_check_type_ref((const char*)pact_list_get(np_type_name, p));
            i = (i + 1);
        }
    }
    const char* ret_str = (const char*)pact_list_get(np_return_type, fn_node);
    if ((!pact_str_eq(ret_str, ""))) {
        pact_nr_check_type_ref(ret_str);
    }
    const int64_t body = (int64_t)(intptr_t)pact_list_get(np_body, fn_node);
    if ((body != (-1))) {
        pact_nr_check_node(body);
    }
    pact_nr_pop_scope();
}

void pact_nr_check_type_ref(const char* name) {
    if (pact_str_eq(name, "")) {
        return;
    }
    if ((pact_is_known_type(name) != 0)) {
        return;
    }
    if ((pact_str_len(name) == 1)) {
        return;
    }
    char _si_0[4096];
    snprintf(_si_0, 4096, "unknown type '%s'", name);
    pact_list_push(tc_errors, (void*)strdup(_si_0));
    char _si_1[4096];
    snprintf(_si_1, 4096, "unknown type '%s'", name);
    pact_diag_error_no_loc("UnknownType", "E0301", strdup(_si_1), "");
}

void pact_nr_check_node(int64_t node) {
    if ((node == (-1))) {
        return;
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_Block)) {
        pact_nr_push_scope();
        const int64_t stmts_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, node);
        if ((stmts_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(stmts_sl))) {
                pact_nr_check_node(pact_sublist_get(stmts_sl, i));
                i = (i + 1);
            }
        }
        pact_nr_pop_scope();
        return;
    }
    if ((kind == pact_NodeKind_LetBinding)) {
        const int64_t val = (int64_t)(intptr_t)pact_list_get(np_value, node);
        if ((val != (-1))) {
            pact_nr_check_node(val);
        }
        pact_nr_define_mut((const char*)pact_list_get(np_name, node), (int64_t)(intptr_t)pact_list_get(np_is_mut, node));
        return;
    }
    if (((kind == pact_NodeKind_Assignment) || (kind == pact_NodeKind_CompoundAssign))) {
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_target, node));
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_value, node));
        return;
    }
    if ((kind == pact_NodeKind_ExprStmt)) {
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_value, node));
        return;
    }
    if ((kind == pact_NodeKind_Return)) {
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_value, node));
        return;
    }
    if ((kind == pact_NodeKind_Ident)) {
        const char* name = (const char*)pact_list_get(np_name, node);
        if (((pact_str_eq(name, "true") || pact_str_eq(name, "false")) || pact_str_eq(name, "None"))) {
            return;
        }
        if (((((((pact_str_eq(name, "io") || pact_str_eq(name, "fs")) || pact_str_eq(name, "net")) || pact_str_eq(name, "db")) || pact_str_eq(name, "env")) || pact_str_eq(name, "async")) || pact_str_eq(name, "channel"))) {
            return;
        }
        if ((pact_nr_is_defined(name) != 0)) {
            return;
        }
        if ((pact_is_variant_name(name) != 0)) {
            return;
        }
        if ((pact_is_builtin_fn(name) != 0)) {
            return;
        }
        if ((pact_is_known_type(name) != 0)) {
            return;
        }
        char _si_0[4096];
        snprintf(_si_0, 4096, "undefined variable '%s'", name);
        pact_list_push(tc_errors, (void*)strdup(_si_0));
        char _si_1[4096];
        snprintf(_si_1, 4096, "undefined variable '%s'", name);
        pact_diag_error_at("UndefinedVariable", "E0302", strdup(_si_1), node, "");
        return;
    }
    if ((((kind == pact_NodeKind_IntLit) || (kind == pact_NodeKind_FloatLit)) || (kind == pact_NodeKind_BoolLit))) {
        return;
    }
    if ((kind == pact_NodeKind_InterpString)) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        if ((elems_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(elems_sl))) {
                const int64_t part = pact_sublist_get(elems_sl, i);
                const int64_t pk = (int64_t)(intptr_t)pact_list_get(np_kind, part);
                if (((pk == pact_NodeKind_Ident) && pact_str_eq((const char*)pact_list_get(np_str_val, part), (const char*)pact_list_get(np_name, part)))) {
                    const int64_t _skip = 0;
                } else {
                    pact_nr_check_node(part);
                }
                i = (i + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_Call)) {
        const int64_t callee = (int64_t)(intptr_t)pact_list_get(np_left, node);
        if ((callee != (-1))) {
            const int64_t callee_kind = (int64_t)(intptr_t)pact_list_get(np_kind, callee);
            if ((callee_kind == pact_NodeKind_Ident)) {
                const char* fn_name = (const char*)pact_list_get(np_name, callee);
                if (((((pact_nr_is_defined(fn_name) == 0) && (pact_is_builtin_fn(fn_name) == 0)) && (pact_is_variant_name(fn_name) == 0)) && (pact_is_known_type(fn_name) == 0))) {
                    char _si_2[4096];
                    snprintf(_si_2, 4096, "undefined function '%s'", fn_name);
                    pact_list_push(tc_errors, (void*)strdup(_si_2));
                    char _si_3[4096];
                    snprintf(_si_3, 4096, "undefined function '%s'", fn_name);
                    pact_diag_error_at("UndefinedFunction", "E0303", strdup(_si_3), node, "");
                }
            } else {
                pact_nr_check_node(callee);
            }
        }
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if ((args_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(args_sl))) {
                pact_nr_check_node(pact_sublist_get(args_sl, i));
                i = (i + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_MethodCall)) {
        const int64_t obj = (int64_t)(intptr_t)pact_list_get(np_obj, node);
        if ((obj != (-1))) {
            pact_nr_check_node(obj);
        }
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if ((args_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(args_sl))) {
                pact_nr_check_node(pact_sublist_get(args_sl, i));
                i = (i + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_FieldAccess)) {
        const int64_t obj = (int64_t)(intptr_t)pact_list_get(np_obj, node);
        if ((obj != (-1))) {
            pact_nr_check_node(obj);
        }
        return;
    }
    if ((kind == pact_NodeKind_IndexExpr)) {
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_obj, node));
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_index, node));
        return;
    }
    if ((kind == pact_NodeKind_BinOp)) {
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_left, node));
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_right, node));
        return;
    }
    if ((kind == pact_NodeKind_UnaryOp)) {
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_right, node));
        return;
    }
    if ((kind == pact_NodeKind_IfExpr)) {
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_condition, node));
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_then_body, node));
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_else_body, node));
        return;
    }
    if ((kind == pact_NodeKind_WhileLoop)) {
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_condition, node));
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_LoopExpr)) {
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_ForIn)) {
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_iterable, node));
        pact_nr_push_scope();
        pact_nr_define((const char*)pact_list_get(np_var_name, node));
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_body, node));
        pact_nr_pop_scope();
        return;
    }
    if (((kind == pact_NodeKind_Break) || (kind == pact_NodeKind_Continue))) {
        return;
    }
    if ((kind == pact_NodeKind_MatchExpr)) {
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_scrutinee, node));
        const int64_t arms_sl = (int64_t)(intptr_t)pact_list_get(np_arms, node);
        if ((arms_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(arms_sl))) {
                const int64_t arm = pact_sublist_get(arms_sl, i);
                pact_nr_push_scope();
                pact_nr_check_pattern((int64_t)(intptr_t)pact_list_get(np_pattern, arm));
                const int64_t guard = (int64_t)(intptr_t)pact_list_get(np_guard, arm);
                if ((guard != (-1))) {
                    pact_nr_check_node(guard);
                }
                pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_body, arm));
                pact_nr_pop_scope();
                i = (i + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_Closure)) {
        pact_nr_push_scope();
        const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, node);
        if ((params_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(params_sl))) {
                pact_nr_define((const char*)pact_list_get(np_name, pact_sublist_get(params_sl, i)));
                i = (i + 1);
            }
        }
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_body, node));
        pact_nr_pop_scope();
        return;
    }
    if ((kind == pact_NodeKind_StructLit)) {
        const char* type_name = (const char*)pact_list_get(np_type_name, node);
        if ((!pact_str_eq(type_name, ""))) {
            pact_nr_check_type_ref(type_name);
        }
        const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, node);
        if ((flds_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(flds_sl))) {
                const int64_t f = pact_sublist_get(flds_sl, i);
                pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_value, f));
                i = (i + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_ListLit)) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        if ((elems_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(elems_sl))) {
                pact_nr_check_node(pact_sublist_get(elems_sl, i));
                i = (i + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_TupleLit)) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        if ((elems_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(elems_sl))) {
                pact_nr_check_node(pact_sublist_get(elems_sl, i));
                i = (i + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_RangeLit)) {
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_start, node));
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_end, node));
        return;
    }
    if ((kind == pact_NodeKind_WithBlock)) {
        const int64_t handlers_sl = (int64_t)(intptr_t)pact_list_get(np_handlers, node);
        if ((handlers_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(handlers_sl))) {
                pact_nr_check_node(pact_sublist_get(handlers_sl, i));
                i = (i + 1);
            }
        }
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_WithResource)) {
        pact_nr_push_scope();
        pact_nr_define((const char*)pact_list_get(np_name, node));
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_value, node));
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_body, node));
        pact_nr_pop_scope();
        return;
    }
    if ((kind == pact_NodeKind_HandlerExpr)) {
        const int64_t methods_sl = (int64_t)(intptr_t)pact_list_get(np_methods, node);
        if ((methods_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(methods_sl))) {
                pact_nr_check_fn(pact_sublist_get(methods_sl, i));
                i = (i + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_AsyncScope)) {
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_AsyncSpawn)) {
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_AwaitExpr)) {
        pact_nr_check_node((int64_t)(intptr_t)pact_list_get(np_value, node));
        return;
    }
    if ((kind == pact_NodeKind_ChannelNew)) {
        return;
    }
    const int64_t _skip = 0;
}

void pact_nr_check_pattern(int64_t node) {
    if ((node == (-1))) {
        return;
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_IdentPattern)) {
        const char* name = (const char*)pact_list_get(np_name, node);
        if ((!pact_str_eq(name, "_"))) {
            pact_nr_define(name);
        }
        return;
    }
    if ((((kind == pact_NodeKind_IntPattern) || (kind == pact_NodeKind_StringPattern)) || (kind == pact_NodeKind_WildcardPattern))) {
        return;
    }
    if ((kind == pact_NodeKind_EnumPattern)) {
        const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, node);
        if ((flds_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(flds_sl))) {
                pact_nr_check_pattern(pact_sublist_get(flds_sl, i));
                i = (i + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_StructPattern)) {
        const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, node);
        if ((flds_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(flds_sl))) {
                const int64_t f = pact_sublist_get(flds_sl, i);
                pact_nr_define((const char*)pact_list_get(np_name, f));
                i = (i + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_TuplePattern)) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        if ((elems_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(elems_sl))) {
                pact_nr_check_pattern(pact_sublist_get(elems_sl, i));
                i = (i + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_OrPattern)) {
        pact_nr_check_pattern((int64_t)(intptr_t)pact_list_get(np_left, node));
        pact_nr_check_pattern((int64_t)(intptr_t)pact_list_get(np_right, node));
        return;
    }
    if ((kind == pact_NodeKind_RangePattern)) {
        return;
    }
    if ((kind == pact_NodeKind_AsPattern)) {
        pact_nr_check_pattern((int64_t)(intptr_t)pact_list_get(np_pattern, node));
        pact_nr_define((const char*)pact_list_get(np_name, node));
        return;
    }
    const int64_t _skip = 0;
}

int64_t pact_types_compatible(int64_t a, int64_t b) {
    if ((a == b)) {
        return 1;
    }
    if (((a == TYPE_UNKNOWN) || (b == TYPE_UNKNOWN))) {
        return 1;
    }
    if (((a < 0) || (b < 0))) {
        return 1;
    }
    if (((a >= pact_list_len(ty_kind)) || (b >= pact_list_len(ty_kind)))) {
        return 1;
    }
    const int64_t ka = (int64_t)(intptr_t)pact_list_get(ty_kind, a);
    const int64_t kb = (int64_t)(intptr_t)pact_list_get(ty_kind, b);
    if (((ka == TK_TYPEVAR) || (kb == TK_TYPEVAR))) {
        return 1;
    }
    if ((((ka == TK_INT) || (ka == TK_BOOL)) && ((kb == TK_INT) || (kb == TK_BOOL)))) {
        return 1;
    }
    if ((ka == kb)) {
        if ((((ka == TK_LIST) || (ka == TK_OPTION)) || (ka == TK_ITERATOR))) {
            return pact_types_compatible((int64_t)(intptr_t)pact_list_get(ty_inner1, a), (int64_t)(intptr_t)pact_list_get(ty_inner1, b));
        }
        if ((ka == TK_MAP)) {
            if ((pact_types_compatible((int64_t)(intptr_t)pact_list_get(ty_inner1, a), (int64_t)(intptr_t)pact_list_get(ty_inner1, b)) == 0)) {
                return 0;
            }
            return pact_types_compatible((int64_t)(intptr_t)pact_list_get(ty_inner2, a), (int64_t)(intptr_t)pact_list_get(ty_inner2, b));
        }
        if ((ka == TK_RESULT)) {
            if ((pact_types_compatible((int64_t)(intptr_t)pact_list_get(ty_inner1, a), (int64_t)(intptr_t)pact_list_get(ty_inner1, b)) == 0)) {
                return 0;
            }
            return pact_types_compatible((int64_t)(intptr_t)pact_list_get(ty_inner2, a), (int64_t)(intptr_t)pact_list_get(ty_inner2, b));
        }
        if (((ka == TK_STRUCT) || (ka == TK_ENUM))) {
            return 0;
        }
        return 1;
    }
    return 0;
}

int64_t pact_type_kind(int64_t tid) {
    if (((tid < 0) || (tid >= pact_list_len(ty_kind)))) {
        return TK_UNKNOWN;
    }
    return (int64_t)(intptr_t)pact_list_get(ty_kind, tid);
}

int64_t pact_is_bool_compat(int64_t tid) {
    if ((tid == TYPE_UNKNOWN)) {
        return 1;
    }
    if ((tid == TYPE_BOOL)) {
        return 1;
    }
    if ((tid == TYPE_INT)) {
        return 1;
    }
    const int64_t k = pact_type_kind(tid);
    if (((k == TK_BOOL) || (k == TK_INT))) {
        return 1;
    }
    return 0;
}

int64_t pact_infer_type(int64_t node) {
    if ((node == (-1))) {
        return TYPE_UNKNOWN;
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_IntLit)) {
        return TYPE_INT;
    }
    if ((kind == pact_NodeKind_FloatLit)) {
        return TYPE_FLOAT;
    }
    if ((kind == pact_NodeKind_BoolLit)) {
        return TYPE_BOOL;
    }
    if ((kind == pact_NodeKind_InterpString)) {
        return TYPE_STR;
    }
    if ((kind == pact_NodeKind_Ident)) {
        const char* name = (const char*)pact_list_get(np_name, node);
        if ((pact_str_eq(name, "true") || pact_str_eq(name, "false"))) {
            return TYPE_BOOL;
        }
        if (pact_str_eq(name, "None")) {
            return pact_make_option_type(TYPE_UNKNOWN);
        }
        const int64_t vt = pact_nr_get_type(name);
        if ((vt != TYPE_UNKNOWN)) {
            return vt;
        }
        if ((pact_is_variant_name(name) != 0)) {
            return pact_get_variant_enum_tid(name);
        }
        return TYPE_UNKNOWN;
    }
    if ((kind == pact_NodeKind_BinOp)) {
        const char* op = (const char*)pact_list_get(np_op, node);
        const int64_t lt = pact_infer_type((int64_t)(intptr_t)pact_list_get(np_left, node));
        const int64_t rt = pact_infer_type((int64_t)(intptr_t)pact_list_get(np_right, node));
        if ((((((pact_str_eq(op, "==") || pact_str_eq(op, "!=")) || pact_str_eq(op, "<")) || pact_str_eq(op, ">")) || pact_str_eq(op, "<=")) || pact_str_eq(op, ">="))) {
            return TYPE_BOOL;
        }
        if ((pact_str_eq(op, "&&") || pact_str_eq(op, "||"))) {
            if ((pact_is_bool_compat(lt) == 0)) {
                char _si_0[4096];
                snprintf(_si_0, 4096, "logical operator '%s' requires Bool operands, got %s", op, pact_type_to_str(lt));
                pact_tc_error(strdup(_si_0));
            }
            if ((pact_is_bool_compat(rt) == 0)) {
                char _si_1[4096];
                snprintf(_si_1, 4096, "logical operator '%s' requires Bool operands, got %s", op, pact_type_to_str(rt));
                pact_tc_error(strdup(_si_1));
            }
            return TYPE_BOOL;
        }
        if (pact_str_eq(op, "+")) {
            if (((pact_type_kind(lt) == TK_STR) || (pact_type_kind(rt) == TK_STR))) {
                return TYPE_STR;
            }
        }
        if (((((pact_str_eq(op, "+") || pact_str_eq(op, "-")) || pact_str_eq(op, "*")) || pact_str_eq(op, "/")) || pact_str_eq(op, "%"))) {
            if (((lt != TYPE_UNKNOWN) && (rt != TYPE_UNKNOWN))) {
                if ((pact_types_compatible(lt, rt) == 0)) {
                    char _si_2[4096];
                    snprintf(_si_2, 4096, "binary '%s': incompatible types %s and %s", op, pact_type_to_str(lt), pact_type_to_str(rt));
                    pact_tc_error(strdup(_si_2));
                }
            }
            if ((lt != TYPE_UNKNOWN)) {
                return lt;
            }
            return rt;
        }
        if ((lt != TYPE_UNKNOWN)) {
            return lt;
        }
        return rt;
    }
    if ((kind == pact_NodeKind_UnaryOp)) {
        const char* op = (const char*)pact_list_get(np_op, node);
        const int64_t operand = pact_infer_type((int64_t)(intptr_t)pact_list_get(np_right, node));
        if (pact_str_eq(op, "!")) {
            return TYPE_BOOL;
        }
        if (pact_str_eq(op, "-")) {
            return operand;
        }
        if (pact_str_eq(op, "\?")) {
            if (((tc_current_fn_ret >= 0) && (tc_current_fn_ret < pact_list_len(ty_kind)))) {
                const int64_t ret_kind = (int64_t)(intptr_t)pact_list_get(ty_kind, tc_current_fn_ret);
                if (((ret_kind != TK_RESULT) && (ret_kind != TK_UNKNOWN))) {
                    char _si_3[4096];
                    snprintf(_si_3, 4096, "'\?' operator used in function '%s' which does not return Result", tc_current_fn_name);
                    pact_list_push(tc_errors, (void*)strdup(_si_3));
                    char _si_4[4096];
                    snprintf(_si_4, 4096, "'\?' operator used in function '%s' which does not return Result", tc_current_fn_name);
                    pact_diag_error_at("TypeError", "E0300", strdup(_si_4), node, "change the return type to Result");
                }
            }
            const int64_t ok = pact_type_kind(operand);
            if ((ok == TK_OPTION)) {
                return (int64_t)(intptr_t)pact_list_get(ty_inner1, operand);
            }
            if ((ok == TK_RESULT)) {
                return (int64_t)(intptr_t)pact_list_get(ty_inner1, operand);
            }
            return operand;
        }
        if (pact_str_eq(op, "\?\?")) {
            const int64_t operand_k = pact_type_kind(operand);
            if (((operand_k != TK_OPTION) && (operand_k != TK_UNKNOWN))) {
                char _si_5[4096];
                snprintf(_si_5, 4096, "'\?\?' operator requires Option value, got %s", pact_type_to_str(operand));
                pact_tc_error(strdup(_si_5));
            }
            if ((operand_k == TK_OPTION)) {
                return (int64_t)(intptr_t)pact_list_get(ty_inner1, operand);
            }
            return operand;
        }
        return operand;
    }
    if ((kind == pact_NodeKind_Call)) {
        const int64_t callee = (int64_t)(intptr_t)pact_list_get(np_left, node);
        if ((callee != (-1))) {
            const int64_t callee_kind = (int64_t)(intptr_t)pact_list_get(np_kind, callee);
            if ((callee_kind == pact_NodeKind_Ident)) {
                const char* fn_name = (const char*)pact_list_get(np_name, callee);
                if (pact_str_eq(fn_name, "Some")) {
                    const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
                    if (((args_sl != (-1)) && (pact_sublist_length(args_sl) >= 1))) {
                        const int64_t inner = pact_infer_type(pact_sublist_get(args_sl, 0));
                        return pact_make_option_type(inner);
                    }
                    return pact_make_option_type(TYPE_UNKNOWN);
                }
                if (pact_str_eq(fn_name, "Ok")) {
                    const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
                    if (((args_sl != (-1)) && (pact_sublist_length(args_sl) >= 1))) {
                        const int64_t inner = pact_infer_type(pact_sublist_get(args_sl, 0));
                        return pact_make_result_type(inner, TYPE_UNKNOWN);
                    }
                    return pact_make_result_type(TYPE_UNKNOWN, TYPE_UNKNOWN);
                }
                if (pact_str_eq(fn_name, "Err")) {
                    const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
                    if (((args_sl != (-1)) && (pact_sublist_length(args_sl) >= 1))) {
                        const int64_t inner = pact_infer_type(pact_sublist_get(args_sl, 0));
                        return pact_make_result_type(TYPE_UNKNOWN, inner);
                    }
                    return pact_make_result_type(TYPE_UNKNOWN, TYPE_UNKNOWN);
                }
                if ((pact_is_builtin_fn(fn_name) != 0)) {
                    return pact_get_builtin_fn_ret(fn_name);
                }
                if ((pact_is_variant_name(fn_name) != 0)) {
                    return pact_get_variant_enum_tid(fn_name);
                }
                const int64_t sig = pact_lookup_fnsig(fn_name);
                if ((sig != (-1))) {
                    const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
                    int64_t arg_count = 0;
                    if ((args_sl != (-1))) {
                        arg_count = pact_sublist_length(args_sl);
                    }
                    const int64_t expected = (int64_t)(intptr_t)pact_list_get(fnsig_params_count, sig);
                    if ((arg_count != expected)) {
                        char _si_6[4096];
                        snprintf(_si_6, 4096, "function '%s' expects %lld argument(s), got %lld", fn_name, (long long)expected, (long long)arg_count);
                        pact_tc_error(strdup(_si_6));
                    }
                    const int64_t tp_count = (int64_t)(intptr_t)pact_list_get(fnsig_type_params_count, sig);
                    if ((tp_count > 0)) {
                        return pact_instantiate_return_type(sig, args_sl);
                    }
                    return (int64_t)(intptr_t)pact_list_get(fnsig_ret, sig);
                }
            } else if ((callee_kind == pact_NodeKind_FieldAccess)) {
                const int64_t obj = (int64_t)(intptr_t)pact_list_get(np_obj, callee);
                if (((obj != (-1)) && ((int64_t)(intptr_t)pact_list_get(np_kind, obj) == pact_NodeKind_Ident))) {
                    const char* type_name = (const char*)pact_list_get(np_name, obj);
                    const int64_t tid = pact_lookup_named_type(type_name);
                    if ((tid != (-1))) {
                        return tid;
                    }
                }
            }
        }
        return TYPE_UNKNOWN;
    }
    if ((kind == pact_NodeKind_MethodCall)) {
        const int64_t obj_node = (int64_t)(intptr_t)pact_list_get(np_obj, node);
        const char* method = (const char*)pact_list_get(np_method, node);
        const int64_t obj_t = pact_infer_type(obj_node);
        const int64_t obj_k = pact_type_kind(obj_t);
        if ((obj_k == TK_LIST)) {
            if ((pact_str_eq(method, "len") || pact_str_eq(method, "count"))) {
                return TYPE_INT;
            }
            if (pact_str_eq(method, "get")) {
                return (int64_t)(intptr_t)pact_list_get(ty_inner1, obj_t);
            }
            if ((((pact_str_eq(method, "push") || pact_str_eq(method, "set")) || pact_str_eq(method, "pop")) || pact_str_eq(method, "for_each"))) {
                return TYPE_VOID;
            }
            if (((((pact_str_eq(method, "map") || pact_str_eq(method, "filter")) || pact_str_eq(method, "take")) || pact_str_eq(method, "skip")) || pact_str_eq(method, "collect"))) {
                return obj_t;
            }
            if (((pact_str_eq(method, "contains") || pact_str_eq(method, "any")) || pact_str_eq(method, "all"))) {
                return TYPE_BOOL;
            }
            if (pact_str_eq(method, "find")) {
                return pact_make_option_type((int64_t)(intptr_t)pact_list_get(ty_inner1, obj_t));
            }
            if (pact_str_eq(method, "fold")) {
                const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
                if (((args_sl != (-1)) && (pact_sublist_length(args_sl) >= 1))) {
                    return pact_infer_type(pact_sublist_get(args_sl, 0));
                }
                return TYPE_UNKNOWN;
            }
        }
        if ((obj_k == TK_STR)) {
            if (pact_str_eq(method, "len")) {
                return TYPE_INT;
            }
            if (((pact_str_eq(method, "contains") || pact_str_eq(method, "starts_with")) || pact_str_eq(method, "ends_with"))) {
                return TYPE_BOOL;
            }
            if ((((((pact_str_eq(method, "substring") || pact_str_eq(method, "concat")) || pact_str_eq(method, "trim")) || pact_str_eq(method, "to_lower")) || pact_str_eq(method, "to_upper")) || pact_str_eq(method, "replace"))) {
                return TYPE_STR;
            }
            if ((pact_str_eq(method, "char_at") || pact_str_eq(method, "index_of"))) {
                return TYPE_INT;
            }
            if (pact_str_eq(method, "split")) {
                return pact_make_list_type(TYPE_STR);
            }
        }
        if ((obj_k == TK_INT)) {
            if (pact_str_eq(method, "to_str")) {
                return TYPE_STR;
            }
            if (((pact_str_eq(method, "abs") || pact_str_eq(method, "min")) || pact_str_eq(method, "max"))) {
                return TYPE_INT;
            }
        }
        if ((obj_k == TK_OPTION)) {
            if (pact_str_eq(method, "unwrap")) {
                return (int64_t)(intptr_t)pact_list_get(ty_inner1, obj_t);
            }
            if ((pact_str_eq(method, "is_some") || pact_str_eq(method, "is_none"))) {
                return TYPE_BOOL;
            }
        }
        if ((obj_k == TK_RESULT)) {
            if (pact_str_eq(method, "unwrap")) {
                return (int64_t)(intptr_t)pact_list_get(ty_inner1, obj_t);
            }
            if (pact_str_eq(method, "unwrap_err")) {
                return (int64_t)(intptr_t)pact_list_get(ty_inner2, obj_t);
            }
            if ((pact_str_eq(method, "is_ok") || pact_str_eq(method, "is_err"))) {
                return TYPE_BOOL;
            }
        }
        if ((obj_k == TK_MAP)) {
            if (pact_str_eq(method, "len")) {
                return TYPE_INT;
            }
            if ((pact_str_eq(method, "has") || pact_str_eq(method, "remove"))) {
                return TYPE_INT;
            }
            if (pact_str_eq(method, "set")) {
                return TYPE_VOID;
            }
            if (pact_str_eq(method, "get")) {
                return (int64_t)(intptr_t)pact_list_get(ty_inner2, obj_t);
            }
            if (pact_str_eq(method, "keys")) {
                return pact_make_list_type((int64_t)(intptr_t)pact_list_get(ty_inner1, obj_t));
            }
            if (pact_str_eq(method, "values")) {
                return pact_make_list_type((int64_t)(intptr_t)pact_list_get(ty_inner2, obj_t));
            }
        }
        if (((obj_k == TK_STRUCT) || (obj_k == TK_ENUM))) {
            const char* tname = (const char*)pact_list_get(ty_name, obj_t);
            char _si_7[4096];
            snprintf(_si_7, 4096, "%s_%s", tname, method);
            const char* sig_name = strdup(_si_7);
            const int64_t sig = pact_lookup_fnsig(sig_name);
            if ((sig != (-1))) {
                return (int64_t)(intptr_t)pact_list_get(fnsig_ret, sig);
            }
        }
        return TYPE_UNKNOWN;
    }
    if ((kind == pact_NodeKind_FieldAccess)) {
        const int64_t obj_node = (int64_t)(intptr_t)pact_list_get(np_obj, node);
        const char* fname = (const char*)pact_list_get(np_name, node);
        if ((obj_node == (-1))) {
            return TYPE_UNKNOWN;
        }
        if (((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident)) {
            const char* obj_name = (const char*)pact_list_get(np_name, obj_node);
            const int64_t tid = pact_lookup_named_type(obj_name);
            if (((tid != (-1)) && (pact_type_kind(tid) == TK_ENUM))) {
                return tid;
            }
        }
        const int64_t obj_t = pact_infer_type(obj_node);
        if ((pact_type_kind(obj_t) == TK_STRUCT)) {
            const int64_t ft = pact_get_struct_field_tid(obj_t, fname);
            if ((ft != (-1))) {
                return ft;
            }
        }
        return TYPE_UNKNOWN;
    }
    if ((kind == pact_NodeKind_IndexExpr)) {
        const int64_t obj_t = pact_infer_type((int64_t)(intptr_t)pact_list_get(np_obj, node));
        if ((pact_type_kind(obj_t) == TK_LIST)) {
            return (int64_t)(intptr_t)pact_list_get(ty_inner1, obj_t);
        }
        return TYPE_UNKNOWN;
    }
    if ((kind == pact_NodeKind_ListLit)) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) > 0))) {
            const int64_t first_t = pact_infer_type(pact_sublist_get(elems_sl, 0));
            return pact_make_list_type(first_t);
        }
        return pact_make_list_type(TYPE_UNKNOWN);
    }
    if ((kind == pact_NodeKind_StructLit)) {
        const char* sname = (const char*)pact_list_get(np_type_name, node);
        if ((!pact_str_eq(sname, ""))) {
            const int64_t tid = pact_lookup_named_type(sname);
            if ((tid != (-1))) {
                return tid;
            }
        }
        return TYPE_UNKNOWN;
    }
    if ((kind == pact_NodeKind_TupleLit)) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        if ((elems_sl != (-1))) {
            pact_list* _l8 = pact_list_new();
            pact_list* elem_types = _l8;
            int64_t i = 0;
            while ((i < pact_sublist_length(elems_sl))) {
                pact_list_push(elem_types, (void*)(intptr_t)pact_infer_type(pact_sublist_get(elems_sl, i)));
                i = (i + 1);
            }
            return pact_make_tuple_type(elem_types);
        }
        return TYPE_UNKNOWN;
    }
    if ((kind == pact_NodeKind_IfExpr)) {
        const int64_t cond_t = pact_infer_type((int64_t)(intptr_t)pact_list_get(np_condition, node));
        if ((pact_is_bool_compat(cond_t) == 0)) {
            char _si_9[4096];
            snprintf(_si_9, 4096, "if condition must be Bool, got %s", pact_type_to_str(cond_t));
            pact_tc_error(strdup(_si_9));
        }
        const int64_t then_t = pact_infer_type((int64_t)(intptr_t)pact_list_get(np_then_body, node));
        const int64_t else_node = (int64_t)(intptr_t)pact_list_get(np_else_body, node);
        if ((else_node != (-1))) {
            const int64_t else_t = pact_infer_type(else_node);
            if (((then_t != TYPE_UNKNOWN) && (else_t != TYPE_UNKNOWN))) {
                if ((pact_types_compatible(then_t, else_t) == 0)) {
                    char _si_10[4096];
                    snprintf(_si_10, 4096, "if branches have incompatible types: %s vs %s", pact_type_to_str(then_t), pact_type_to_str(else_t));
                    pact_tc_error(strdup(_si_10));
                }
            }
            if ((then_t != TYPE_UNKNOWN)) {
                return then_t;
            }
            return else_t;
        }
        return then_t;
    }
    if ((kind == pact_NodeKind_MatchExpr)) {
        const int64_t arms_sl = (int64_t)(intptr_t)pact_list_get(np_arms, node);
        if (((arms_sl != (-1)) && (pact_sublist_length(arms_sl) > 0))) {
            const int64_t first_arm = pact_sublist_get(arms_sl, 0);
            return pact_infer_type((int64_t)(intptr_t)pact_list_get(np_body, first_arm));
        }
        return TYPE_UNKNOWN;
    }
    if ((kind == pact_NodeKind_Block)) {
        const int64_t stmts_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, node);
        if (((stmts_sl != (-1)) && (pact_sublist_length(stmts_sl) > 0))) {
            const int64_t last = pact_sublist_get(stmts_sl, (pact_sublist_length(stmts_sl) - 1));
            const int64_t last_k = (int64_t)(intptr_t)pact_list_get(np_kind, last);
            if ((last_k == pact_NodeKind_ExprStmt)) {
                return pact_infer_type((int64_t)(intptr_t)pact_list_get(np_value, last));
            }
            if ((last_k == pact_NodeKind_Return)) {
                return pact_infer_type((int64_t)(intptr_t)pact_list_get(np_value, last));
            }
            if ((((((((((((last_k == pact_NodeKind_IfExpr) || (last_k == pact_NodeKind_MatchExpr)) || (last_k == pact_NodeKind_Call)) || (last_k == pact_NodeKind_MethodCall)) || (last_k == pact_NodeKind_Ident)) || (last_k == pact_NodeKind_IntLit)) || (last_k == pact_NodeKind_FloatLit)) || (last_k == pact_NodeKind_BoolLit)) || (last_k == pact_NodeKind_InterpString)) || (last_k == pact_NodeKind_BinOp)) || (last_k == pact_NodeKind_UnaryOp))) {
                return pact_infer_type(last);
            }
        }
        return TYPE_VOID;
    }
    if ((kind == pact_NodeKind_RangeLit)) {
        return pact_make_list_type(TYPE_INT);
    }
    if ((kind == pact_NodeKind_Closure)) {
        return TYPE_UNKNOWN;
    }
    return TYPE_UNKNOWN;
}

int64_t pact_resolve_param_type(int64_t p) {
    const char* ptype_str = (const char*)pact_list_get(np_type_name, p);
    const int64_t ptype_ann = (int64_t)(intptr_t)pact_list_get(np_type_ann, p);
    if ((ptype_ann != (-1))) {
        return pact_resolve_type_ann(ptype_ann);
    }
    if ((!pact_str_eq(ptype_str, ""))) {
        const int64_t t = pact_resolve_type_name(ptype_str);
        if ((t != (-1))) {
            return t;
        }
    }
    return TYPE_UNKNOWN;
}

void pact_tc_check_fn(int64_t fn_node) {
    pact_nr_push_scope();
    const char* fn_name = (const char*)pact_list_get(np_name, fn_node);
    const char* prev_fn_name = tc_current_fn_name;
    const int64_t prev_fn_ret = tc_current_fn_ret;
    tc_current_fn_name = fn_name;
    const int64_t sig = pact_lookup_fnsig(fn_name);
    if ((sig != (-1))) {
        tc_current_fn_ret = (int64_t)(intptr_t)pact_list_get(fnsig_ret, sig);
    }
    const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, fn_node);
    if ((params_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(params_sl))) {
            const int64_t p = pact_sublist_get(params_sl, i);
            const char* pname = (const char*)pact_list_get(np_name, p);
            const int64_t ptid = pact_resolve_param_type(p);
            pact_nr_define_typed(pname, 0, ptid);
            i = (i + 1);
        }
    }
    const int64_t body = (int64_t)(intptr_t)pact_list_get(np_body, fn_node);
    if ((body != (-1))) {
        pact_tc_check_body(body);
        if ((sig != (-1))) {
            const int64_t declared_ret = (int64_t)(intptr_t)pact_list_get(fnsig_ret, sig);
            if (((declared_ret != TYPE_VOID) && (declared_ret != TYPE_UNKNOWN))) {
                const int64_t inferred_ret = pact_infer_type(body);
                if ((inferred_ret != TYPE_UNKNOWN)) {
                    if ((pact_types_compatible(declared_ret, inferred_ret) == 0)) {
                        char _si_0[4096];
                        snprintf(_si_0, 4096, "function '%s' declared return type %s but body returns %s", fn_name, pact_type_to_str(declared_ret), pact_type_to_str(inferred_ret));
                        pact_tc_error(strdup(_si_0));
                    }
                }
            }
        }
    }
    tc_current_fn_name = prev_fn_name;
    tc_current_fn_ret = prev_fn_ret;
    pact_nr_pop_scope();
}

void pact_tc_check_body(int64_t node) {
    if ((node == (-1))) {
        return;
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_Block)) {
        pact_nr_push_scope();
        const int64_t stmts_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, node);
        if ((stmts_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(stmts_sl))) {
                pact_tc_check_body(pact_sublist_get(stmts_sl, i));
                i = (i + 1);
            }
        }
        pact_nr_pop_scope();
        return;
    }
    if ((kind == pact_NodeKind_LetBinding)) {
        const char* vname = (const char*)pact_list_get(np_name, node);
        const int64_t val = (int64_t)(intptr_t)pact_list_get(np_value, node);
        const int64_t is_mut = (int64_t)(intptr_t)pact_list_get(np_is_mut, node);
        const char* type_str = (const char*)pact_list_get(np_type_name, node);
        const int64_t type_ann = (int64_t)(intptr_t)pact_list_get(np_type_ann, node);
        int64_t declared_tid = TYPE_UNKNOWN;
        if ((type_ann != (-1))) {
            declared_tid = pact_resolve_type_ann(type_ann);
        } else if ((!pact_str_eq(type_str, ""))) {
            const int64_t rt = pact_resolve_type_name(type_str);
            if ((rt != (-1))) {
                declared_tid = rt;
            }
        }
        int64_t inferred_tid = TYPE_UNKNOWN;
        if ((val != (-1))) {
            inferred_tid = pact_infer_type(val);
            pact_tc_check_body(val);
        }
        if (((declared_tid != TYPE_UNKNOWN) && (inferred_tid != TYPE_UNKNOWN))) {
            if ((pact_types_compatible(declared_tid, inferred_tid) == 0)) {
                char _si_0[4096];
                snprintf(_si_0, 4096, "variable '%s': declared type %s but got %s", vname, pact_type_to_str(declared_tid), pact_type_to_str(inferred_tid));
                pact_tc_error(strdup(_si_0));
            }
        }
        int64_t final_tid = declared_tid;
        if ((final_tid == TYPE_UNKNOWN)) {
            final_tid = inferred_tid;
        }
        pact_nr_define_typed(vname, is_mut, final_tid);
        return;
    }
    if (((kind == pact_NodeKind_Assignment) || (kind == pact_NodeKind_CompoundAssign))) {
        const int64_t target = (int64_t)(intptr_t)pact_list_get(np_target, node);
        const int64_t val = (int64_t)(intptr_t)pact_list_get(np_value, node);
        if (((target != (-1)) && (val != (-1)))) {
            const int64_t target_t = pact_infer_type(target);
            const int64_t val_t = pact_infer_type(val);
            if (((target_t != TYPE_UNKNOWN) && (val_t != TYPE_UNKNOWN))) {
                if ((pact_types_compatible(target_t, val_t) == 0)) {
                    char _si_1[4096];
                    snprintf(_si_1, 4096, "assignment: cannot assign %s to %s", pact_type_to_str(val_t), pact_type_to_str(target_t));
                    pact_tc_error(strdup(_si_1));
                }
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_IfExpr)) {
        const int64_t cond_t = pact_infer_type((int64_t)(intptr_t)pact_list_get(np_condition, node));
        if ((pact_is_bool_compat(cond_t) == 0)) {
            char _si_2[4096];
            snprintf(_si_2, 4096, "if condition must be Bool, got %s", pact_type_to_str(cond_t));
            pact_tc_error(strdup(_si_2));
        }
        pact_tc_check_body((int64_t)(intptr_t)pact_list_get(np_then_body, node));
        pact_tc_check_body((int64_t)(intptr_t)pact_list_get(np_else_body, node));
        return;
    }
    if ((kind == pact_NodeKind_WhileLoop)) {
        const int64_t cond_t = pact_infer_type((int64_t)(intptr_t)pact_list_get(np_condition, node));
        if ((pact_is_bool_compat(cond_t) == 0)) {
            char _si_3[4096];
            snprintf(_si_3, 4096, "while condition must be Bool, got %s", pact_type_to_str(cond_t));
            pact_tc_error(strdup(_si_3));
        }
        pact_tc_check_body((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_ForIn)) {
        pact_nr_push_scope();
        const int64_t iter_t = pact_infer_type((int64_t)(intptr_t)pact_list_get(np_iterable, node));
        int64_t elem_t = TYPE_UNKNOWN;
        if ((pact_type_kind(iter_t) == TK_LIST)) {
            elem_t = (int64_t)(intptr_t)pact_list_get(ty_inner1, iter_t);
        }
        pact_nr_define_typed((const char*)pact_list_get(np_var_name, node), 0, elem_t);
        pact_tc_check_body((int64_t)(intptr_t)pact_list_get(np_body, node));
        pact_nr_pop_scope();
        return;
    }
    if ((kind == pact_NodeKind_MatchExpr)) {
        pact_tc_check_body((int64_t)(intptr_t)pact_list_get(np_scrutinee, node));
        const int64_t arms_sl = (int64_t)(intptr_t)pact_list_get(np_arms, node);
        if ((arms_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(arms_sl))) {
                const int64_t arm = pact_sublist_get(arms_sl, i);
                pact_nr_push_scope();
                pact_tc_check_pattern_types((int64_t)(intptr_t)pact_list_get(np_pattern, arm));
                pact_tc_check_body((int64_t)(intptr_t)pact_list_get(np_body, arm));
                pact_nr_pop_scope();
                i = (i + 1);
            }
            int64_t has_wildcard = 0;
            int64_t ai = 0;
            while ((ai < pact_sublist_length(arms_sl))) {
                const int64_t arm = pact_sublist_get(arms_sl, ai);
                const int64_t pat = (int64_t)(intptr_t)pact_list_get(np_pattern, arm);
                if ((pat != (-1))) {
                    const int64_t pk = (int64_t)(intptr_t)pact_list_get(np_kind, pat);
                    if (((pk == pact_NodeKind_WildcardPattern) || (pk == pact_NodeKind_IdentPattern))) {
                        has_wildcard = 1;
                    }
                }
                ai = (ai + 1);
            }
            if ((has_wildcard == 0)) {
                pact_tc_warn("match expression may not be exhaustive (no wildcard or catch-all arm)");
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_LoopExpr)) {
        pact_tc_check_body((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_WithBlock)) {
        pact_tc_check_body((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_WithResource)) {
        pact_nr_push_scope();
        pact_nr_define((const char*)pact_list_get(np_name, node));
        pact_tc_check_body((int64_t)(intptr_t)pact_list_get(np_value, node));
        pact_tc_check_body((int64_t)(intptr_t)pact_list_get(np_body, node));
        pact_nr_pop_scope();
        return;
    }
    if ((kind == pact_NodeKind_AsyncScope)) {
        pact_tc_check_body((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_AsyncSpawn)) {
        pact_tc_check_body((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_Closure)) {
        pact_nr_push_scope();
        const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, node);
        if ((params_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(params_sl))) {
                const int64_t p = pact_sublist_get(params_sl, i);
                const char* pname = (const char*)pact_list_get(np_name, p);
                const int64_t ptid = pact_resolve_param_type(p);
                pact_nr_define_typed(pname, 0, ptid);
                i = (i + 1);
            }
        }
        pact_tc_check_body((int64_t)(intptr_t)pact_list_get(np_body, node));
        pact_nr_pop_scope();
        return;
    }
    if ((kind == pact_NodeKind_ExprStmt)) {
        const int64_t val = (int64_t)(intptr_t)pact_list_get(np_value, node);
        if ((val != (-1))) {
            pact_infer_type(val);
        }
        return;
    }
    if ((kind == pact_NodeKind_Return)) {
        const int64_t val = (int64_t)(intptr_t)pact_list_get(np_value, node);
        if ((val != (-1))) {
            pact_infer_type(val);
        }
        return;
    }
    const int64_t _skip = 0;
}

void pact_tc_check_pattern_types(int64_t node) {
    if ((node == (-1))) {
        return;
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_IdentPattern)) {
        const char* name = (const char*)pact_list_get(np_name, node);
        if ((!pact_str_eq(name, "_"))) {
            pact_nr_define(name);
        }
        return;
    }
    if ((kind == pact_NodeKind_EnumPattern)) {
        const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, node);
        if ((flds_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(flds_sl))) {
                pact_tc_check_pattern_types(pact_sublist_get(flds_sl, i));
                i = (i + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_StructPattern)) {
        const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, node);
        if ((flds_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(flds_sl))) {
                pact_nr_define((const char*)pact_list_get(np_name, pact_sublist_get(flds_sl, i)));
                i = (i + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_TuplePattern)) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        if ((elems_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(elems_sl))) {
                pact_tc_check_pattern_types(pact_sublist_get(elems_sl, i));
                i = (i + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_OrPattern)) {
        pact_tc_check_pattern_types((int64_t)(intptr_t)pact_list_get(np_left, node));
        pact_tc_check_pattern_types((int64_t)(intptr_t)pact_list_get(np_right, node));
        return;
    }
    if ((kind == pact_NodeKind_AsPattern)) {
        pact_tc_check_pattern_types((int64_t)(intptr_t)pact_list_get(np_pattern, node));
        pact_nr_define((const char*)pact_list_get(np_name, node));
        return;
    }
    const int64_t _skip = 0;
}

void pact_tc_infer_program(int64_t program) {
    pact_list* _l0 = pact_list_new();
    nr_scope_names = _l0;
    pact_list* _l1 = pact_list_new();
    nr_scope_muts = _l1;
    pact_list* _l2 = pact_list_new();
    nr_scope_types = _l2;
    pact_list* _l3 = pact_list_new();
    nr_scope_frames = _l3;
    pact_nr_push_scope();
    const int64_t lets_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, program);
    if ((lets_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(lets_sl))) {
            const int64_t l = pact_sublist_get(lets_sl, i);
            pact_nr_define((const char*)pact_list_get(np_name, l));
            i = (i + 1);
        }
    }
    const int64_t fns_sl = (int64_t)(intptr_t)pact_list_get(np_params, program);
    if ((fns_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(fns_sl))) {
            pact_nr_define((const char*)pact_list_get(np_name, pact_sublist_get(fns_sl, i)));
            i = (i + 1);
        }
    }
    if ((fns_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(fns_sl))) {
            const int64_t fn_node = pact_sublist_get(fns_sl, i);
            if ((pact_tc_should_check_fn((const char*)pact_list_get(np_name, fn_node)) != 0)) {
                pact_tc_check_fn(fn_node);
            }
            i = (i + 1);
        }
    }
    const int64_t impls_sl = (int64_t)(intptr_t)pact_list_get(np_methods, program);
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
                    const char* orig_name = (const char*)pact_list_get(np_name, m);
                    char _si_4[4096];
                    snprintf(_si_4, 4096, "%s_%s", impl_type, orig_name);
                    const char* qualified = strdup(_si_4);
                    if ((pact_tc_should_check_fn(qualified) != 0)) {
                        pact_list_set(np_name, m, (void*)qualified);
                        pact_tc_check_fn(m);
                        pact_list_set(np_name, m, (void*)orig_name);
                    }
                    j = (j + 1);
                }
            }
            i = (i + 1);
        }
    }
    pact_nr_pop_scope();
}

const char* pact_type_to_str(int64_t tid) {
    if (((tid < 0) || (tid >= pact_list_len(ty_kind)))) {
        return "<\?>";
    }
    const int64_t k = (int64_t)(intptr_t)pact_list_get(ty_kind, tid);
    const char* name = (const char*)pact_list_get(ty_name, tid);
    if ((k == TK_INT)) {
        return "Int";
    }
    if ((k == TK_FLOAT)) {
        return "Float";
    }
    if ((k == TK_BOOL)) {
        return "Bool";
    }
    if ((k == TK_STR)) {
        return "Str";
    }
    if ((k == TK_VOID)) {
        return "Void";
    }
    if ((k == TK_UNKNOWN)) {
        return "\?";
    }
    if ((k == TK_TYPEVAR)) {
        return name;
    }
    if ((k == TK_STRUCT)) {
        return name;
    }
    if ((k == TK_ENUM)) {
        return name;
    }
    if ((k == TK_LIST)) {
        const int64_t inner = (int64_t)(intptr_t)pact_list_get(ty_inner1, tid);
        char _si_0[4096];
        snprintf(_si_0, 4096, "List[%s]", pact_type_to_str(inner));
        return strdup(_si_0);
    }
    if ((k == TK_OPTION)) {
        const int64_t inner = (int64_t)(intptr_t)pact_list_get(ty_inner1, tid);
        char _si_1[4096];
        snprintf(_si_1, 4096, "Option[%s]", pact_type_to_str(inner));
        return strdup(_si_1);
    }
    if ((k == TK_RESULT)) {
        const int64_t ok_t = (int64_t)(intptr_t)pact_list_get(ty_inner1, tid);
        const int64_t err_t = (int64_t)(intptr_t)pact_list_get(ty_inner2, tid);
        char _si_2[4096];
        snprintf(_si_2, 4096, "Result[%s, %s]", pact_type_to_str(ok_t), pact_type_to_str(err_t));
        return strdup(_si_2);
    }
    if ((k == TK_MAP)) {
        const int64_t key_t = (int64_t)(intptr_t)pact_list_get(ty_inner1, tid);
        const int64_t val_t = (int64_t)(intptr_t)pact_list_get(ty_inner2, tid);
        char _si_3[4096];
        snprintf(_si_3, 4096, "Map[%s, %s]", pact_type_to_str(key_t), pact_type_to_str(val_t));
        return strdup(_si_3);
    }
    if ((k == TK_FN)) {
        const int64_t ret = (int64_t)(intptr_t)pact_list_get(ty_inner1, tid);
        const int64_t start = (int64_t)(intptr_t)pact_list_get(ty_params_start, tid);
        const int64_t count = (int64_t)(intptr_t)pact_list_get(ty_params_count, tid);
        const char* params = "";
        int64_t i = 0;
        while ((i < count)) {
            if ((i > 0)) {
                params = pact_str_concat(params, ", ");
            }
            params = pact_str_concat(params, pact_type_to_str((int64_t)(intptr_t)pact_list_get(ty_param_list, (start + i))));
            i = (i + 1);
        }
        char _si_4[4096];
        snprintf(_si_4, 4096, "Fn(%s) -> %s", params, pact_type_to_str(ret));
        return strdup(_si_4);
    }
    if ((k == TK_TUPLE)) {
        const int64_t start = (int64_t)(intptr_t)pact_list_get(ty_params_start, tid);
        const int64_t count = (int64_t)(intptr_t)pact_list_get(ty_params_count, tid);
        const char* elems = "";
        int64_t i = 0;
        while ((i < count)) {
            if ((i > 0)) {
                elems = pact_str_concat(elems, ", ");
            }
            elems = pact_str_concat(elems, pact_type_to_str((int64_t)(intptr_t)pact_list_get(ty_param_list, (start + i))));
            i = (i + 1);
        }
        char _si_5[4096];
        snprintf(_si_5, 4096, "(%s)", elems);
        return strdup(_si_5);
    }
    return name;
}

void pact_push_scope(void) {
    pact_list_push(scope_frame_starts, (void*)(intptr_t)pact_list_len(scope_vars));
    pact_list_push(var_struct_frame_starts, (void*)(intptr_t)pact_list_len(var_structs));
    pact_list_push(var_closure_frame_starts, (void*)(intptr_t)pact_list_len(var_closures));
    pact_list_push(var_option_frame_starts, (void*)(intptr_t)pact_list_len(var_options));
    pact_list_push(var_result_frame_starts, (void*)(intptr_t)pact_list_len(var_results));
    pact_list_push(var_iterator_frame_starts, (void*)(intptr_t)pact_list_len(var_iterators));
    pact_list_push(var_alias_frame_starts, (void*)(intptr_t)pact_list_len(var_aliases));
    pact_list_push(var_handle_frame_starts, (void*)(intptr_t)pact_list_len(var_handles));
    pact_list_push(var_channel_frame_starts, (void*)(intptr_t)pact_list_len(var_channels));
    pact_list_push(var_list_elem_frame_starts, (void*)(intptr_t)pact_list_len(var_list_elems));
    pact_list_push(var_map_frame_starts, (void*)(intptr_t)pact_list_len(var_maps));
}

void pact_pop_scope(void) {
    const int64_t start = (int64_t)(intptr_t)pact_list_get(scope_frame_starts, (pact_list_len(scope_frame_starts) - 1));
    pact_list_pop(scope_frame_starts);
    while ((pact_list_len(scope_vars) > start)) {
        pact_list_pop(scope_vars);
    }
    const int64_t vs_start = (int64_t)(intptr_t)pact_list_get(var_struct_frame_starts, (pact_list_len(var_struct_frame_starts) - 1));
    pact_list_pop(var_struct_frame_starts);
    while ((pact_list_len(var_structs) > vs_start)) {
        pact_list_pop(var_structs);
    }
    const int64_t vc_start = (int64_t)(intptr_t)pact_list_get(var_closure_frame_starts, (pact_list_len(var_closure_frame_starts) - 1));
    pact_list_pop(var_closure_frame_starts);
    while ((pact_list_len(var_closures) > vc_start)) {
        pact_list_pop(var_closures);
    }
    const int64_t vo_start = (int64_t)(intptr_t)pact_list_get(var_option_frame_starts, (pact_list_len(var_option_frame_starts) - 1));
    pact_list_pop(var_option_frame_starts);
    while ((pact_list_len(var_options) > vo_start)) {
        pact_list_pop(var_options);
    }
    const int64_t vr_start = (int64_t)(intptr_t)pact_list_get(var_result_frame_starts, (pact_list_len(var_result_frame_starts) - 1));
    pact_list_pop(var_result_frame_starts);
    while ((pact_list_len(var_results) > vr_start)) {
        pact_list_pop(var_results);
    }
    const int64_t vi_start = (int64_t)(intptr_t)pact_list_get(var_iterator_frame_starts, (pact_list_len(var_iterator_frame_starts) - 1));
    pact_list_pop(var_iterator_frame_starts);
    while ((pact_list_len(var_iterators) > vi_start)) {
        pact_list_pop(var_iterators);
    }
    const int64_t va_start = (int64_t)(intptr_t)pact_list_get(var_alias_frame_starts, (pact_list_len(var_alias_frame_starts) - 1));
    pact_list_pop(var_alias_frame_starts);
    while ((pact_list_len(var_aliases) > va_start)) {
        pact_list_pop(var_aliases);
    }
    const int64_t vh_start = (int64_t)(intptr_t)pact_list_get(var_handle_frame_starts, (pact_list_len(var_handle_frame_starts) - 1));
    pact_list_pop(var_handle_frame_starts);
    while ((pact_list_len(var_handles) > vh_start)) {
        pact_list_pop(var_handles);
    }
    const int64_t vch_start = (int64_t)(intptr_t)pact_list_get(var_channel_frame_starts, (pact_list_len(var_channel_frame_starts) - 1));
    pact_list_pop(var_channel_frame_starts);
    while ((pact_list_len(var_channels) > vch_start)) {
        pact_list_pop(var_channels);
    }
    const int64_t vle_start = (int64_t)(intptr_t)pact_list_get(var_list_elem_frame_starts, (pact_list_len(var_list_elem_frame_starts) - 1));
    pact_list_pop(var_list_elem_frame_starts);
    while ((pact_list_len(var_list_elems) > vle_start)) {
        pact_list_pop(var_list_elems);
    }
    const int64_t vm_start = (int64_t)(intptr_t)pact_list_get(var_map_frame_starts, (pact_list_len(var_map_frame_starts) - 1));
    pact_list_pop(var_map_frame_starts);
    while ((pact_list_len(var_maps) > vm_start)) {
        pact_list_pop(var_maps);
    }
}

void pact_set_var(const char* name, int64_t ctype, int64_t is_mut) {
    pact_ScopeVar _s0 = { .name = name, .ctype = ctype, .is_mut = is_mut };
    pact_ScopeVar* _box1 = (pact_ScopeVar*)pact_alloc(sizeof(pact_ScopeVar));
    *_box1 = _s0;
    pact_list_push(scope_vars, (void*)_box1);
}

int64_t pact_get_var_type(const char* name) {
    int64_t i = (pact_list_len(scope_vars) - 1);
    while ((i >= 0)) {
        pact_ScopeVar _ub0 = *(pact_ScopeVar*)pact_list_get(scope_vars, i);
        const pact_ScopeVar sv = _ub0;
        if (pact_str_eq(sv.name, name)) {
            return sv.ctype;
        }
        i = (i - 1);
    }
    return CT_INT;
}

int64_t pact_get_var_mut(const char* name) {
    int64_t i = (pact_list_len(scope_vars) - 1);
    while ((i >= 0)) {
        pact_ScopeVar _ub0 = *(pact_ScopeVar*)pact_list_get(scope_vars, i);
        const pact_ScopeVar sv = _ub0;
        if (pact_str_eq(sv.name, name)) {
            return sv.is_mut;
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
        pact_CaptureEntry _ub0 = *(pact_CaptureEntry*)pact_list_get(closure_captures, (cg_closure_cap_start + i));
        if (pact_str_eq(_ub0.name, name)) {
            return i;
        }
        i = (i + 1);
    }
    return (-1);
}

const char* pact_capture_cast_expr(int64_t idx) {
    pact_CaptureEntry _ub0 = *(pact_CaptureEntry*)pact_list_get(closure_captures, (cg_closure_cap_start + idx));
    const int64_t ct = _ub0.ctype;
    const char* _if_1;
    if ((ct == CT_INT)) {
        char _si_2[4096];
        snprintf(_si_2, 4096, "(int64_t)(intptr_t)pact_closure_get_capture(__self, %lld)", (long long)idx);
        _if_1 = strdup(_si_2);
    } else {
        const char* _if_3;
        if ((ct == CT_FLOAT)) {
            char _si_4[4096];
            snprintf(_si_4, 4096, "*(double*)pact_closure_get_capture(__self, %lld)", (long long)idx);
            _if_3 = strdup(_si_4);
        } else {
            const char* _if_5;
            if ((ct == CT_STRING)) {
                char _si_6[4096];
                snprintf(_si_6, 4096, "(const char*)pact_closure_get_capture(__self, %lld)", (long long)idx);
                _if_5 = strdup(_si_6);
            } else {
                const char* _if_7;
                if ((ct == CT_BOOL)) {
                    char _si_8[4096];
                    snprintf(_si_8, 4096, "(int)(intptr_t)pact_closure_get_capture(__self, %lld)", (long long)idx);
                    _if_7 = strdup(_si_8);
                } else {
                    const char* _if_9;
                    if ((ct == CT_LIST)) {
                        char _si_10[4096];
                        snprintf(_si_10, 4096, "(pact_list*)pact_closure_get_capture(__self, %lld)", (long long)idx);
                        _if_9 = strdup(_si_10);
                    } else {
                        const char* _if_11;
                        if ((ct == CT_MAP)) {
                            char _si_12[4096];
                            snprintf(_si_12, 4096, "(pact_map*)pact_closure_get_capture(__self, %lld)", (long long)idx);
                            _if_11 = strdup(_si_12);
                        } else {
                            const char* _if_13;
                            if ((ct == CT_CLOSURE)) {
                                char _si_14[4096];
                                snprintf(_si_14, 4096, "(pact_closure*)pact_closure_get_capture(__self, %lld)", (long long)idx);
                                _if_13 = strdup(_si_14);
                            } else {
                                char _si_15[4096];
                                snprintf(_si_15, 4096, "pact_closure_get_capture(__self, %lld)", (long long)idx);
                                _if_13 = strdup(_si_15);
                            }
                            _if_11 = _if_13;
                        }
                        _if_9 = _if_11;
                    }
                    _if_7 = _if_9;
                }
                _if_5 = _if_7;
            }
            _if_3 = _if_5;
        }
        _if_1 = _if_3;
    }
    return _if_1;
}

void pact_reg_fn(const char* name, int64_t ret) {
    pact_FnRegEntry _s0 = { .name = name, .ret = ret, .effect_sl = (-1) };
    pact_FnRegEntry* _box1 = (pact_FnRegEntry*)pact_alloc(sizeof(pact_FnRegEntry));
    *_box1 = _s0;
    pact_list_push(fn_regs, (void*)_box1);
}

void pact_reg_fn_with_effects(const char* name, int64_t ret, int64_t effects_sl) {
    pact_FnRegEntry _s0 = { .name = name, .ret = ret, .effect_sl = effects_sl };
    pact_FnRegEntry* _box1 = (pact_FnRegEntry*)pact_alloc(sizeof(pact_FnRegEntry));
    *_box1 = _s0;
    pact_list_push(fn_regs, (void*)_box1);
}

int64_t pact_get_fn_effect_sl(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(fn_regs))) {
        pact_FnRegEntry _ub0 = *(pact_FnRegEntry*)pact_list_get(fn_regs, i);
        const pact_FnRegEntry fr = _ub0;
        if (pact_str_eq(fr.name, name)) {
            return fr.effect_sl;
        }
        i = (i + 1);
    }
    return (-1);
}

void pact_reg_fn_struct_ret(const char* name, const char* stype) {
    pact_FnRetStructEntry _s0 = { .name = name, .stype = stype };
    pact_FnRetStructEntry* _box1 = (pact_FnRetStructEntry*)pact_alloc(sizeof(pact_FnRetStructEntry));
    *_box1 = _s0;
    pact_list_push(fn_ret_structs, (void*)_box1);
}

const char* pact_get_fn_ret_struct(const char* name) {
    int64_t i = (pact_list_len(fn_ret_structs) - 1);
    while ((i >= 0)) {
        pact_FnRetStructEntry _ub0 = *(pact_FnRetStructEntry*)pact_list_get(fn_ret_structs, i);
        const pact_FnRetStructEntry frs = _ub0;
        if (pact_str_eq(frs.name, name)) {
            return frs.stype;
        }
        i = (i - 1);
    }
    return "";
}

void pact_reg_fn_ret_type(const char* name, int64_t kind, int64_t inner1, int64_t inner2) {
    pact_RetType _s0 = { .name = name, .kind = kind, .inner1 = inner1, .inner2 = inner2 };
    pact_RetType* _box1 = (pact_RetType*)pact_alloc(sizeof(pact_RetType));
    *_box1 = _s0;
    pact_list_push(fn_ret_types, (void*)_box1);
}

pact_RetType pact_get_fn_ret_type(const char* name) {
    int64_t i = (pact_list_len(fn_ret_types) - 1);
    while ((i >= 0)) {
        pact_RetType _ub0 = *(pact_RetType*)pact_list_get(fn_ret_types, i);
        const pact_RetType rt = _ub0;
        if (pact_str_eq(rt.name, name)) {
            return rt;
        }
        i = (i - 1);
    }
    pact_RetType _s1 = { .name = "", .kind = CT_VOID, .inner1 = (-1), .inner2 = (-1) };
    return _s1;
}

const char* pact_resolve_ret_type_from_ann(int64_t fn_node) {
    const char* ret_str = (const char*)pact_list_get(np_return_type, fn_node);
    const int64_t ta = (int64_t)(intptr_t)pact_list_get(np_type_ann, fn_node);
    if (pact_str_eq(ret_str, "Result")) {
        if ((ta != (-1))) {
            const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, ta);
            if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) >= 2))) {
                const int64_t ok_ann = pact_sublist_get(elems_sl, 0);
                const int64_t err_ann = pact_sublist_get(elems_sl, 1);
                const int64_t ok_t = pact_type_from_name((const char*)pact_list_get(np_name, ok_ann));
                const int64_t err_t = pact_type_from_name((const char*)pact_list_get(np_name, err_ann));
                return pact_result_c_type(ok_t, err_t);
            }
        }
        return pact_result_c_type(CT_INT, CT_STRING);
    }
    if (pact_str_eq(ret_str, "Option")) {
        if ((ta != (-1))) {
            const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, ta);
            if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) >= 1))) {
                const int64_t inner_ann = pact_sublist_get(elems_sl, 0);
                const int64_t inner_t = pact_type_from_name((const char*)pact_list_get(np_name, inner_ann));
                return pact_option_c_type(inner_t);
            }
        }
        return pact_option_c_type(CT_INT);
    }
    return "";
}

void pact_reg_fn_ret_from_ann(const char* name, int64_t fn_node) {
    const char* ret_str = (const char*)pact_list_get(np_return_type, fn_node);
    const int64_t ta = (int64_t)(intptr_t)pact_list_get(np_type_ann, fn_node);
    if (pact_str_eq(ret_str, "Result")) {
        if ((ta != (-1))) {
            const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, ta);
            if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) >= 2))) {
                const int64_t ok_ann = pact_sublist_get(elems_sl, 0);
                const int64_t err_ann = pact_sublist_get(elems_sl, 1);
                const int64_t ok_t = pact_type_from_name((const char*)pact_list_get(np_name, ok_ann));
                const int64_t err_t = pact_type_from_name((const char*)pact_list_get(np_name, err_ann));
                pact_reg_fn_ret_type(name, CT_RESULT, ok_t, err_t);
                pact_ensure_result_type(ok_t, err_t);
            }
        } else {
            pact_reg_fn_ret_type(name, CT_RESULT, CT_INT, CT_STRING);
            pact_ensure_result_type(CT_INT, CT_STRING);
        }
    }
    if (pact_str_eq(ret_str, "Option")) {
        if ((ta != (-1))) {
            const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, ta);
            if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) >= 1))) {
                const int64_t inner_ann = pact_sublist_get(elems_sl, 0);
                const int64_t inner_t = pact_type_from_name((const char*)pact_list_get(np_name, inner_ann));
                pact_reg_fn_ret_type(name, CT_OPTION, inner_t, (-1));
                pact_ensure_option_type(inner_t);
            }
        } else {
            pact_reg_fn_ret_type(name, CT_OPTION, CT_INT, (-1));
            pact_ensure_option_type(CT_INT);
        }
    }
    if ((pact_str_eq(ret_str, "List") && (ta != (-1)))) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, ta);
        if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) >= 1))) {
            const int64_t elem_ann = pact_sublist_get(elems_sl, 0);
            const char* elem_name = (const char*)pact_list_get(np_name, elem_ann);
            const int64_t elem_t = pact_type_from_name(elem_name);
            pact_reg_fn_ret_type(name, CT_LIST, elem_t, (-1));
        }
    }
}

int64_t pact_reg_effect(const char* name, int64_t parent) {
    const int64_t idx = pact_list_len(effect_entries);
    pact_EffectEntry _s0 = { .name = name, .parent = parent };
    pact_EffectEntry* _box1 = (pact_EffectEntry*)pact_alloc(sizeof(pact_EffectEntry));
    *_box1 = _s0;
    pact_list_push(effect_entries, (void*)_box1);
    return idx;
}

int64_t pact_get_effect_idx(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(effect_entries))) {
        pact_EffectEntry _ub0 = *(pact_EffectEntry*)pact_list_get(effect_entries, i);
        if (pact_str_eq(_ub0.name, name)) {
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
    pact_EffectEntry _ub0 = *(pact_EffectEntry*)pact_list_get(effect_entries, callee_idx);
    const int64_t parent_idx = _ub0.parent;
    if ((parent_idx == (-1))) {
        return 0;
    }
    pact_EffectEntry _ub1 = *(pact_EffectEntry*)pact_list_get(effect_entries, parent_idx);
    const char* parent_name = _ub1.name;
    if (pact_str_eq(parent_name, caller_effect)) {
        return 1;
    }
    return 0;
}

void pact_check_effect_propagation(const char* callee_name) {
    if ((pact_str_eq(cg_current_fn_name, "main") || pact_str_starts_with(cg_current_fn_name, "__test_"))) {
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
            snprintf(_si_0, 4096, "function '%s' requires effect '%s' but caller '%s' does not declare it", callee_name, callee_eff, cg_current_fn_name);
            char _si_1[4096];
            snprintf(_si_1, 4096, "add '! %s' to the function signature of '%s'", callee_eff, cg_current_fn_name);
            pact_diag_error_no_loc("UndeclaredEffect", "E0500", strdup(_si_0), strdup(_si_1));
        }
        ci = (ci + 1);
    }
}

void pact_check_capabilities_budget(const char* fn_name, int64_t effects_sl) {
    if ((cap_budget_active == 0)) {
        return;
    }
    if ((pact_str_eq(fn_name, "main") || pact_str_starts_with(fn_name, "__test_"))) {
        return;
    }
    if ((effects_sl == (-1))) {
        return;
    }
    const int64_t count = pact_sublist_length(effects_sl);
    int64_t ei = 0;
    while ((ei < count)) {
        const int64_t eff_node = pact_sublist_get(effects_sl, ei);
        const char* eff_name = (const char*)pact_list_get(np_name, eff_node);
        int64_t allowed = 0;
        int64_t bi = 0;
        while ((bi < pact_list_len(cap_budget_names))) {
            const char* budget_eff = (const char*)pact_list_get(cap_budget_names, bi);
            if ((pact_effect_satisfies(budget_eff, eff_name) != 0)) {
                allowed = 1;
            }
            bi = (bi + 1);
        }
        if ((allowed == 0)) {
            char _si_0[4096];
            snprintf(_si_0, 4096, "function '%s' uses effect '%s' which is not in @capabilities budget", fn_name, eff_name);
            pact_diag_error_no_loc("InsufficientCapability", "E0501", strdup(_si_0), "add the effect to @capabilities");
        }
        ei = (ei + 1);
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
    const int64_t async_idx = pact_reg_effect("Async", (-1));
    pact_reg_effect("Async.Spawn", async_idx);
    pact_reg_effect("Async.Channel", async_idx);
}

const char* pact_get_ue_handle(const char* effect_name) {
    int64_t i = 0;
    while ((i < pact_list_len(ue_effects))) {
        pact_UeEffect _ub0 = *(pact_UeEffect*)pact_list_get(ue_effects, i);
        const pact_UeEffect ue = _ub0;
        if (pact_str_eq(ue.name, effect_name)) {
            return ue.handle;
        }
        i = (i + 1);
    }
    return "";
}

const char* pact_get_ue_top_for_handle(const char* handle) {
    int64_t i = 0;
    while ((i < pact_list_len(ue_effects))) {
        pact_UeEffect _ub0 = *(pact_UeEffect*)pact_list_get(ue_effects, i);
        const pact_UeEffect ue = _ub0;
        if (pact_str_eq(ue.handle, handle)) {
            return ue.name;
        }
        i = (i + 1);
    }
    return "";
}

int64_t pact_is_user_effect_handle(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(ue_effects))) {
        pact_UeEffect _ub0 = *(pact_UeEffect*)pact_list_get(ue_effects, i);
        if (pact_str_eq(_ub0.handle, name)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_ue_has_method(const char* handle, const char* method) {
    int64_t i = 0;
    while ((i < pact_list_len(ue_methods))) {
        pact_UeMethod _ub0 = *(pact_UeMethod*)pact_list_get(ue_methods, i);
        const pact_UeMethod uem = _ub0;
        if ((pact_str_eq(uem.effect_handle, handle) && pact_str_eq(uem.name, method))) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_is_fn_registered(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(fn_regs))) {
        pact_FnRegEntry _ub0 = *(pact_FnRegEntry*)pact_list_get(fn_regs, i);
        if (pact_str_eq(_ub0.name, name)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_get_fn_ret(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(fn_regs))) {
        pact_FnRegEntry _ub0 = *(pact_FnRegEntry*)pact_list_get(fn_regs, i);
        const pact_FnRegEntry fr = _ub0;
        if (pact_str_eq(fr.name, name)) {
            return fr.ret;
        }
        i = (i + 1);
    }
    return CT_VOID;
}

void pact_set_list_elem_type(const char* name, int64_t elem_type) {
    pact_VarListElemEntry _s0 = { .name = name, .elem_type = elem_type, .struct_name = "" };
    pact_VarListElemEntry* _box1 = (pact_VarListElemEntry*)pact_alloc(sizeof(pact_VarListElemEntry));
    *_box1 = _s0;
    pact_list_push(var_list_elems, (void*)_box1);
}

int64_t pact_get_list_elem_type(const char* name) {
    int64_t i = (pact_list_len(var_list_elems) - 1);
    while ((i >= 0)) {
        pact_VarListElemEntry _ub0 = *(pact_VarListElemEntry*)pact_list_get(var_list_elems, i);
        const pact_VarListElemEntry e = _ub0;
        if ((pact_str_eq(e.name, name) && (e.elem_type != (-1)))) {
            return e.elem_type;
        }
        i = (i - 1);
    }
    return (-1);
}

void pact_set_list_elem_struct(const char* name, const char* struct_name) {
    pact_VarListElemEntry _s0 = { .name = name, .elem_type = (-1), .struct_name = struct_name };
    pact_VarListElemEntry* _box1 = (pact_VarListElemEntry*)pact_alloc(sizeof(pact_VarListElemEntry));
    *_box1 = _s0;
    pact_list_push(var_list_elems, (void*)_box1);
}

const char* pact_get_list_elem_struct(const char* name) {
    int64_t i = (pact_list_len(var_list_elems) - 1);
    while ((i >= 0)) {
        pact_VarListElemEntry _ub0 = *(pact_VarListElemEntry*)pact_list_get(var_list_elems, i);
        const pact_VarListElemEntry e = _ub0;
        if ((pact_str_eq(e.name, name) && (!pact_str_eq(e.struct_name, "")))) {
            return e.struct_name;
        }
        i = (i - 1);
    }
    return "";
}

void pact_set_map_types(const char* name, int64_t key_type, int64_t value_type) {
    pact_VarMapEntry _s0 = { .name = name, .key_type = key_type, .value_type = value_type, .value_struct = "" };
    pact_VarMapEntry* _box1 = (pact_VarMapEntry*)pact_alloc(sizeof(pact_VarMapEntry));
    *_box1 = _s0;
    pact_list_push(var_maps, (void*)_box1);
}

int64_t pact_get_map_key_type(const char* name) {
    int64_t i = (pact_list_len(var_maps) - 1);
    while ((i >= 0)) {
        pact_VarMapEntry _ub0 = *(pact_VarMapEntry*)pact_list_get(var_maps, i);
        const pact_VarMapEntry vm = _ub0;
        if (pact_str_eq(vm.name, name)) {
            return vm.key_type;
        }
        i = (i - 1);
    }
    return CT_STRING;
}

int64_t pact_get_map_value_type(const char* name) {
    int64_t i = (pact_list_len(var_maps) - 1);
    while ((i >= 0)) {
        pact_VarMapEntry _ub0 = *(pact_VarMapEntry*)pact_list_get(var_maps, i);
        const pact_VarMapEntry vm = _ub0;
        if (pact_str_eq(vm.name, name)) {
            return vm.value_type;
        }
        i = (i - 1);
    }
    return CT_INT;
}

void pact_set_map_value_struct(const char* name, const char* struct_name) {
    int64_t i = (pact_list_len(var_maps) - 1);
    while ((i >= 0)) {
        pact_VarMapEntry _ub0 = *(pact_VarMapEntry*)pact_list_get(var_maps, i);
        const pact_VarMapEntry vm = _ub0;
        if (pact_str_eq(vm.name, name)) {
            pact_VarMapEntry _s1 = { .name = name, .key_type = vm.key_type, .value_type = vm.value_type, .value_struct = struct_name };
            pact_VarMapEntry* _box2 = (pact_VarMapEntry*)pact_alloc(sizeof(pact_VarMapEntry));
            *_box2 = _s1;
            pact_list_set(var_maps, i, (void*)_box2);
            return;
        }
        i = (i - 1);
    }
}

const char* pact_get_map_value_struct(const char* name) {
    int64_t i = (pact_list_len(var_maps) - 1);
    while ((i >= 0)) {
        pact_VarMapEntry _ub0 = *(pact_VarMapEntry*)pact_list_get(var_maps, i);
        const pact_VarMapEntry vm = _ub0;
        if (pact_str_eq(vm.name, name)) {
            return vm.value_struct;
        }
        i = (i - 1);
    }
    return "";
}

int64_t pact_is_struct_type(const char* name) {
    return pact_map_has(struct_reg_set, name);
}

int64_t pact_is_enum_type(const char* name) {
    return pact_map_has(enum_reg_set, name);
}

const char* pact_resolve_variant(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(enum_variants))) {
        pact_EnumVariant _ub0 = *(pact_EnumVariant*)pact_list_get(enum_variants, i);
        const pact_EnumVariant evar = _ub0;
        if (pact_str_eq(evar.name, name)) {
            pact_EnumReg _ub1 = *(pact_EnumReg*)pact_list_get(enum_regs, evar.enum_idx);
            return _ub1.name;
        }
        i = (i + 1);
    }
    return "";
}

const char* pact_get_var_enum(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(var_enums))) {
        pact_VarEnumEntry _ub0 = *(pact_VarEnumEntry*)pact_list_get(var_enums, i);
        const pact_VarEnumEntry ve = _ub0;
        if (pact_str_eq(ve.name, name)) {
            return ve.enum_type;
        }
        i = (i + 1);
    }
    return "";
}

int64_t pact_is_data_enum(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(enum_regs))) {
        pact_EnumReg _ub0 = *(pact_EnumReg*)pact_list_get(enum_regs, i);
        const pact_EnumReg ereg = _ub0;
        if (pact_str_eq(ereg.name, name)) {
            return ereg.has_data;
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_get_variant_index(const char* enum_name, const char* variant_name) {
    int64_t i = 0;
    while ((i < pact_list_len(enum_variants))) {
        pact_EnumVariant _ub0 = *(pact_EnumVariant*)pact_list_get(enum_variants, i);
        const pact_EnumVariant evar = _ub0;
        if (pact_str_eq(evar.name, variant_name)) {
            pact_EnumReg _ub1 = *(pact_EnumReg*)pact_list_get(enum_regs, evar.enum_idx);
            if (pact_str_eq(_ub1.name, enum_name)) {
                return i;
            }
        }
        i = (i + 1);
    }
    return (-1);
}

int64_t pact_get_variant_tag(const char* enum_name, const char* variant_name) {
    int64_t tag = 0;
    int64_t i = 0;
    while ((i < pact_list_len(enum_variants))) {
        pact_EnumVariant _ub0 = *(pact_EnumVariant*)pact_list_get(enum_variants, i);
        const pact_EnumVariant evar = _ub0;
        pact_EnumReg _ub1 = *(pact_EnumReg*)pact_list_get(enum_regs, evar.enum_idx);
        if (pact_str_eq(_ub1.name, enum_name)) {
            if (pact_str_eq(evar.name, variant_name)) {
                return tag;
            }
            tag = (tag + 1);
        }
        i = (i + 1);
    }
    return (-1);
}

int64_t pact_get_variant_field_count(int64_t variant_idx) {
    if (((variant_idx < 0) || (variant_idx >= pact_list_len(enum_variants)))) {
        return 0;
    }
    pact_EnumVariant _ub0 = *(pact_EnumVariant*)pact_list_get(enum_variants, variant_idx);
    return _ub0.field_count;
}

const char* pact_get_variant_field_name(int64_t variant_idx, int64_t field_idx) {
    pact_EnumVariant _ub0 = *(pact_EnumVariant*)pact_list_get(enum_variants, variant_idx);
    const char* names_str = _ub0.field_names;
    if (pact_str_eq(names_str, "")) {
        return "";
    }
    int64_t seg_start = 0;
    int64_t seg_idx = 0;
    int64_t i = 0;
    while ((i <= pact_str_len(names_str))) {
        if (((i == pact_str_len(names_str)) || (pact_str_char_at(names_str, i) == 44))) {
            if ((seg_idx == field_idx)) {
                return pact_str_substr(names_str, seg_start, (i - seg_start));
            }
            seg_start = (i + 1);
            seg_idx = (seg_idx + 1);
        }
        i = (i + 1);
    }
    return "";
}

const char* pact_get_variant_field_type_str(int64_t variant_idx, int64_t field_idx) {
    pact_EnumVariant _ub0 = *(pact_EnumVariant*)pact_list_get(enum_variants, variant_idx);
    const char* types_str = _ub0.field_types;
    if (pact_str_eq(types_str, "")) {
        return "";
    }
    int64_t seg_start = 0;
    int64_t seg_idx = 0;
    int64_t i = 0;
    while ((i <= pact_str_len(types_str))) {
        if (((i == pact_str_len(types_str)) || (pact_str_char_at(types_str, i) == 44))) {
            if ((seg_idx == field_idx)) {
                return pact_str_substr(types_str, seg_start, (i - seg_start));
            }
            seg_start = (i + 1);
            seg_idx = (seg_idx + 1);
        }
        i = (i + 1);
    }
    return "";
}

const char* pact_get_fn_enum_ret(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(fn_enum_rets))) {
        pact_FnEnumRetEntry _ub0 = *(pact_FnEnumRetEntry*)pact_list_get(fn_enum_rets, i);
        const pact_FnEnumRetEntry fe = _ub0;
        if (pact_str_eq(fe.name, name)) {
            return fe.enum_type;
        }
        i = (i + 1);
    }
    return "";
}

void pact_set_var_struct(const char* name, const char* type_name) {
    pact_VarStructEntry _s0 = { .name = name, .stype = type_name };
    pact_VarStructEntry* _box1 = (pact_VarStructEntry*)pact_alloc(sizeof(pact_VarStructEntry));
    *_box1 = _s0;
    pact_list_push(var_structs, (void*)_box1);
}

const char* pact_get_var_struct(const char* name) {
    int64_t i = (pact_list_len(var_structs) - 1);
    while ((i >= 0)) {
        pact_VarStructEntry _ub0 = *(pact_VarStructEntry*)pact_list_get(var_structs, i);
        const pact_VarStructEntry vs = _ub0;
        if (pact_str_eq(vs.name, name)) {
            return vs.stype;
        }
        i = (i - 1);
    }
    return "";
}

int64_t pact_get_struct_field_type(const char* sname, const char* fname) {
    int64_t i = 0;
    while ((i < pact_list_len(sf_entries))) {
        pact_StructFieldEntry _ub0 = *(pact_StructFieldEntry*)pact_list_get(sf_entries, i);
        const pact_StructFieldEntry sf = _ub0;
        if ((pact_str_eq(sf.struct_name, sname) && pact_str_eq(sf.field_name, fname))) {
            return sf.field_type;
        }
        i = (i + 1);
    }
    return CT_VOID;
}

const char* pact_get_struct_field_stype(const char* sname, const char* fname) {
    int64_t i = 0;
    while ((i < pact_list_len(sf_entries))) {
        pact_StructFieldEntry _ub0 = *(pact_StructFieldEntry*)pact_list_get(sf_entries, i);
        const pact_StructFieldEntry sf = _ub0;
        if ((pact_str_eq(sf.struct_name, sname) && pact_str_eq(sf.field_name, fname))) {
            return sf.stype;
        }
        i = (i + 1);
    }
    return "";
}

void pact_set_var_closure(const char* name, const char* sig) {
    pact_VarClosureEntry _s0 = { .name = name, .sig = sig };
    pact_VarClosureEntry* _box1 = (pact_VarClosureEntry*)pact_alloc(sizeof(pact_VarClosureEntry));
    *_box1 = _s0;
    pact_list_push(var_closures, (void*)_box1);
}

const char* pact_get_var_closure_sig(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(var_closures))) {
        pact_VarClosureEntry _ub0 = *(pact_VarClosureEntry*)pact_list_get(var_closures, i);
        const pact_VarClosureEntry vc = _ub0;
        if (pact_str_eq(vc.name, name)) {
            return vc.sig;
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
    while ((i < pact_list_len(generic_fns))) {
        pact_GenericFnEntry _ub0 = *(pact_GenericFnEntry*)pact_list_get(generic_fns, i);
        if (pact_str_eq(_ub0.name, name)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_get_generic_fn_node(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(generic_fns))) {
        pact_GenericFnEntry _ub0 = *(pact_GenericFnEntry*)pact_list_get(generic_fns, i);
        const pact_GenericFnEntry gf = _ub0;
        if (pact_str_eq(gf.name, name)) {
            return gf.node;
        }
        i = (i + 1);
    }
    return (-1);
}

void pact_register_mono_fn(const char* base, const char* args) {
    int64_t i = 0;
    while ((i < pact_list_len(mono_fns))) {
        pact_MonoFnInstance _ub0 = *(pact_MonoFnInstance*)pact_list_get(mono_fns, i);
        const pact_MonoFnInstance mf = _ub0;
        if ((pact_str_eq(mf.base, base) && pact_str_eq(mf.args, args))) {
            return;
        }
        i = (i + 1);
    }
    pact_MonoFnInstance _s1 = { .base = base, .args = args };
    pact_MonoFnInstance* _box2 = (pact_MonoFnInstance*)pact_alloc(sizeof(pact_MonoFnInstance));
    *_box2 = _s1;
    pact_list_push(mono_fns, (void*)_box2);
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
                        const char* _if_5;
                        if ((ct == CT_ITERATOR)) {
                            _if_5 = "Iterator";
                        } else {
                            const char* _if_6;
                            if ((ct == CT_HANDLE)) {
                                _if_6 = "Handle";
                            } else {
                                const char* _if_7;
                                if ((ct == CT_CHANNEL)) {
                                    _if_7 = "Channel";
                                } else {
                                    const char* _if_8;
                                    if ((ct == CT_MAP)) {
                                        _if_8 = "Map";
                                    } else {
                                        _if_8 = "Void";
                                    }
                                    _if_7 = _if_8;
                                }
                                _if_6 = _if_7;
                            }
                            _if_5 = _if_6;
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
    pact_MonoInstance _s0 = { .base = base, .args = args, .c_name = c_name };
    pact_MonoInstance* _box1 = (pact_MonoInstance*)pact_alloc(sizeof(pact_MonoInstance));
    *_box1 = _s0;
    pact_list_push(mono_instances, (void*)_box1);
    return c_name;
}

const char* pact_lookup_mono_instance(const char* base, const char* args) {
    int64_t i = 0;
    while ((i < pact_list_len(mono_instances))) {
        pact_MonoInstance _ub0 = *(pact_MonoInstance*)pact_list_get(mono_instances, i);
        const pact_MonoInstance m = _ub0;
        if ((pact_str_eq(m.base, base) && pact_str_eq(m.args, args))) {
            return m.c_name;
        }
        i = (i + 1);
    }
    return "";
}

int64_t pact_is_trait_type(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(trait_entries))) {
        pact_TraitEntry _ub0 = *(pact_TraitEntry*)pact_list_get(trait_entries, i);
        if (pact_str_eq(_ub0.name, name)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_lookup_impl_method(const char* type_name, const char* method) {
    int64_t i = 0;
    while ((i < pact_list_len(impl_entries))) {
        pact_ImplEntry _ub0 = *(pact_ImplEntry*)pact_list_get(impl_entries, i);
        const pact_ImplEntry ie = _ub0;
        if (pact_str_eq(ie.type_name, type_name)) {
            int64_t j = 0;
            while ((j < pact_sublist_length(ie.methods_sl))) {
                const int64_t m = pact_sublist_get(ie.methods_sl, j);
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
    while ((i < pact_list_len(impl_entries))) {
        pact_ImplEntry _ub0 = *(pact_ImplEntry*)pact_list_get(impl_entries, i);
        const pact_ImplEntry ie = _ub0;
        if ((pact_str_eq(ie.trait_name, trait_name) && pact_str_eq(ie.type_name, type_name))) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_get_impl_method_ret(const char* type_name, const char* method) {
    int64_t i = 0;
    while ((i < pact_list_len(impl_entries))) {
        pact_ImplEntry _ub0 = *(pact_ImplEntry*)pact_list_get(impl_entries, i);
        const pact_ImplEntry ie = _ub0;
        if (pact_str_eq(ie.type_name, type_name)) {
            int64_t j = 0;
            while ((j < pact_sublist_length(ie.methods_sl))) {
                const int64_t m = pact_sublist_get(ie.methods_sl, j);
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
    while ((i < pact_list_len(from_entries))) {
        pact_FromImplEntry _ub0 = *(pact_FromImplEntry*)pact_list_get(from_entries, i);
        const pact_FromImplEntry fe = _ub0;
        if ((pact_str_eq(fe.source, source) && pact_str_eq(fe.target, target))) {
            return fe.method_sl;
        }
        i = (i + 1);
    }
    return (-1);
}

int64_t pact_find_tryfrom_impl(const char* source, const char* target) {
    int64_t i = 0;
    while ((i < pact_list_len(tryfrom_entries))) {
        pact_TryFromImplEntry _ub0 = *(pact_TryFromImplEntry*)pact_list_get(tryfrom_entries, i);
        const pact_TryFromImplEntry te = _ub0;
        if ((pact_str_eq(te.source, source) && pact_str_eq(te.target, target))) {
            return te.method_sl;
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
    return pact_map_has(emitted_let_set, name);
}

int64_t pact_is_emitted_fn(const char* name) {
    return pact_map_has(emitted_fn_set, name);
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
                            const char* _if_6;
                            if ((ct == CT_ITERATOR)) {
                                _if_6 = "void*";
                            } else {
                                const char* _if_7;
                                if ((ct == CT_HANDLE)) {
                                    _if_7 = "pact_handle*";
                                } else {
                                    const char* _if_8;
                                    if ((ct == CT_CHANNEL)) {
                                        _if_8 = "pact_channel*";
                                    } else {
                                        const char* _if_9;
                                        if ((ct == CT_MAP)) {
                                            _if_9 = "pact_map*";
                                        } else {
                                            _if_9 = "void";
                                        }
                                        _if_8 = _if_9;
                                    }
                                    _if_7 = _if_8;
                                }
                                _if_6 = _if_7;
                            }
                            _if_5 = _if_6;
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
    } else if ((pact_str_eq(name, "Iterator"))) {
        _match_0 = CT_ITERATOR;
    } else if ((pact_str_eq(name, "Map"))) {
        _match_0 = CT_MAP;
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
                        const char* _if_5;
                        if ((ct == CT_ITERATOR)) {
                            _if_5 = "iter";
                        } else {
                            const char* _if_6;
                            if ((ct == CT_HANDLE)) {
                                _if_6 = "handle";
                            } else {
                                const char* _if_7;
                                if ((ct == CT_CHANNEL)) {
                                    _if_7 = "channel";
                                } else {
                                    const char* _if_8;
                                    if ((ct == CT_MAP)) {
                                        _if_8 = "map";
                                    } else {
                                        _if_8 = "void";
                                    }
                                    _if_7 = _if_8;
                                }
                                _if_6 = _if_7;
                            }
                            _if_5 = _if_6;
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

void pact_ensure_option_type(int64_t inner) {
    char _si_0[4096];
    snprintf(_si_0, 4096, "%lld", (long long)inner);
    const char* key = strdup(_si_0);
    if ((pact_map_has(emitted_option_set, key) != 0)) {
        return;
    }
    pact_map_set(emitted_option_set, key, (void*)(intptr_t)1);
    pact_list_push(emitted_option_types, (void*)(intptr_t)inner);
}

void pact_ensure_result_type(int64_t ok_t, int64_t err_t) {
    char _si_0[4096];
    snprintf(_si_0, 4096, "%lld_%lld", (long long)ok_t, (long long)err_t);
    const char* key = strdup(_si_0);
    if ((pact_map_has(emitted_result_set, key) != 0)) {
        return;
    }
    pact_map_set(emitted_result_set, key, (void*)(intptr_t)1);
    pact_list_push(emitted_result_types, (void*)key);
}

void pact_set_var_option(const char* name, int64_t inner) {
    pact_VarOptionEntry _s0 = { .name = name, .inner = inner };
    pact_VarOptionEntry* _box1 = (pact_VarOptionEntry*)pact_alloc(sizeof(pact_VarOptionEntry));
    *_box1 = _s0;
    pact_list_push(var_options, (void*)_box1);
}

int64_t pact_get_var_option_inner(const char* name) {
    int64_t i = (pact_list_len(var_options) - 1);
    while ((i >= 0)) {
        pact_VarOptionEntry _ub0 = *(pact_VarOptionEntry*)pact_list_get(var_options, i);
        const pact_VarOptionEntry vo = _ub0;
        if (pact_str_eq(vo.name, name)) {
            return vo.inner;
        }
        i = (i - 1);
    }
    return (-1);
}

void pact_set_var_result(const char* name, int64_t ok_t, int64_t err_t) {
    pact_VarResultEntry _s0 = { .name = name, .ok_type = ok_t, .err_type = err_t };
    pact_VarResultEntry* _box1 = (pact_VarResultEntry*)pact_alloc(sizeof(pact_VarResultEntry));
    *_box1 = _s0;
    pact_list_push(var_results, (void*)_box1);
}

int64_t pact_get_var_result_ok(const char* name) {
    int64_t i = (pact_list_len(var_results) - 1);
    while ((i >= 0)) {
        pact_VarResultEntry _ub0 = *(pact_VarResultEntry*)pact_list_get(var_results, i);
        const pact_VarResultEntry vr = _ub0;
        if (pact_str_eq(vr.name, name)) {
            return vr.ok_type;
        }
        i = (i - 1);
    }
    return (-1);
}

int64_t pact_get_var_result_err(const char* name) {
    int64_t i = (pact_list_len(var_results) - 1);
    while ((i >= 0)) {
        pact_VarResultEntry _ub0 = *(pact_VarResultEntry*)pact_list_get(var_results, i);
        const pact_VarResultEntry vr = _ub0;
        if (pact_str_eq(vr.name, name)) {
            return vr.err_type;
        }
        i = (i - 1);
    }
    return (-1);
}

void pact_set_var_iterator(const char* name, int64_t inner, const char* next_fn) {
    pact_VarIteratorEntry _s0 = { .name = name, .inner = inner, .next_fn = next_fn, .next_name = "" };
    pact_VarIteratorEntry* _box1 = (pact_VarIteratorEntry*)pact_alloc(sizeof(pact_VarIteratorEntry));
    *_box1 = _s0;
    pact_list_push(var_iterators, (void*)_box1);
}

int64_t pact_get_var_iterator_inner(const char* name) {
    int64_t i = (pact_list_len(var_iterators) - 1);
    while ((i >= 0)) {
        pact_VarIteratorEntry _ub0 = *(pact_VarIteratorEntry*)pact_list_get(var_iterators, i);
        const pact_VarIteratorEntry vi = _ub0;
        if (pact_str_eq(vi.name, name)) {
            return vi.inner;
        }
        i = (i - 1);
    }
    return (-1);
}

const char* pact_get_var_iter_next_fn(const char* name) {
    int64_t i = (pact_list_len(var_iterators) - 1);
    while ((i >= 0)) {
        pact_VarIteratorEntry _ub0 = *(pact_VarIteratorEntry*)pact_list_get(var_iterators, i);
        const pact_VarIteratorEntry vi = _ub0;
        if (pact_str_eq(vi.name, name)) {
            return vi.next_fn;
        }
        i = (i - 1);
    }
    return "";
}

void pact_set_var_alias(const char* name, const char* target) {
    pact_VarAliasEntry _s0 = { .name = name, .target = target };
    pact_VarAliasEntry* _box1 = (pact_VarAliasEntry*)pact_alloc(sizeof(pact_VarAliasEntry));
    *_box1 = _s0;
    pact_list_push(var_aliases, (void*)_box1);
}

const char* pact_get_var_alias(const char* name) {
    int64_t i = (pact_list_len(var_aliases) - 1);
    while ((i >= 0)) {
        pact_VarAliasEntry _ub0 = *(pact_VarAliasEntry*)pact_list_get(var_aliases, i);
        const pact_VarAliasEntry va = _ub0;
        if (pact_str_eq(va.name, name)) {
            return va.target;
        }
        i = (i - 1);
    }
    return "";
}

void pact_set_var_handle(const char* name, int64_t inner) {
    pact_VarHandleEntry _s0 = { .name = name, .inner = inner };
    pact_VarHandleEntry* _box1 = (pact_VarHandleEntry*)pact_alloc(sizeof(pact_VarHandleEntry));
    *_box1 = _s0;
    pact_list_push(var_handles, (void*)_box1);
}

int64_t pact_get_var_handle_inner(const char* name) {
    int64_t i = (pact_list_len(var_handles) - 1);
    while ((i >= 0)) {
        pact_VarHandleEntry _ub0 = *(pact_VarHandleEntry*)pact_list_get(var_handles, i);
        const pact_VarHandleEntry vh = _ub0;
        if (pact_str_eq(vh.name, name)) {
            return vh.inner;
        }
        i = (i - 1);
    }
    return (-1);
}

void pact_set_var_channel(const char* name, int64_t inner) {
    pact_VarChannelEntry _s0 = { .name = name, .inner = inner };
    pact_VarChannelEntry* _box1 = (pact_VarChannelEntry*)pact_alloc(sizeof(pact_VarChannelEntry));
    *_box1 = _s0;
    pact_list_push(var_channels, (void*)_box1);
}

int64_t pact_get_var_channel_inner(const char* name) {
    int64_t i = (pact_list_len(var_channels) - 1);
    while ((i >= 0)) {
        pact_VarChannelEntry _ub0 = *(pact_VarChannelEntry*)pact_list_get(var_channels, i);
        const pact_VarChannelEntry vch = _ub0;
        if (pact_str_eq(vch.name, name)) {
            return vch.inner;
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

void pact_ensure_iter_type(int64_t inner) {
    char _si_0[4096];
    snprintf(_si_0, 4096, "%lld", (long long)inner);
    const char* key = strdup(_si_0);
    if ((pact_map_has(emitted_iter_set, key) != 0)) {
        return;
    }
    pact_map_set(emitted_iter_set, key, (void*)(intptr_t)1);
    pact_list_push(emitted_iter_types, (void*)(intptr_t)inner);
    pact_ensure_option_type(inner);
}

void pact_ensure_range_iter(void) {
    if ((emitted_range_iter != 0)) {
        return;
    }
    emitted_range_iter = 1;
    pact_ensure_option_type(CT_INT);
}

void pact_ensure_str_iter(void) {
    if ((emitted_str_iter != 0)) {
        return;
    }
    emitted_str_iter = 1;
    pact_ensure_option_type(CT_INT);
}

void pact_emit_range_iter_typedef(void) {
    pact_emit_line("typedef struct { int64_t current; int64_t end; int is_inclusive; } pact_RangeIterator;");
    pact_emit_line("");
    pact_emit_line("static pact_Option_int pact_RangeIterator_next(pact_RangeIterator* self) {");
    pact_emit_line("    int in_range = self->is_inclusive \? (self->current <= self->end) : (self->current < self->end);");
    pact_emit_line("    if (in_range) {");
    pact_emit_line("        int64_t val = self->current;");
    pact_emit_line("        self->current++;");
    pact_emit_line("        return (pact_Option_int){ .tag = 1, .value = val };");
    pact_emit_line("    }");
    pact_emit_line("    return (pact_Option_int){ .tag = 0 };");
    pact_emit_line("}");
    pact_emit_line("");
}

void pact_emit_str_iter_typedef(void) {
    pact_emit_line("typedef struct { const char* str; int64_t index; int64_t len; } pact_StrIterator;");
    pact_emit_line("");
    pact_emit_line("static pact_Option_int pact_StrIterator_next(pact_StrIterator* self) {");
    pact_emit_line("    if (self->index < self->len) {");
    pact_emit_line("        int64_t val = (int64_t)(unsigned char)self->str[self->index];");
    pact_emit_line("        self->index++;");
    pact_emit_line("        return (pact_Option_int){ .tag = 1, .value = val };");
    pact_emit_line("    }");
    pact_emit_line("    return (pact_Option_int){ .tag = 0 };");
    pact_emit_line("}");
    pact_emit_line("");
}

const char* pact_list_iter_c_type(int64_t inner) {
    char _si_0[4096];
    snprintf(_si_0, 4096, "pact_ListIterator_%s", pact_c_type_tag(inner));
    return strdup(_si_0);
}

void pact_emit_list_iter_typedef(int64_t inner) {
    const char* tag = pact_c_type_tag(inner);
    char _si_0[4096];
    snprintf(_si_0, 4096, "pact_ListIterator_%s", tag);
    const char* tname = strdup(_si_0);
    const char* opt_name = pact_option_c_type(inner);
    const char* c_inner = pact_c_type_str(inner);
    char _si_1[4096];
    snprintf(_si_1, 4096, "typedef struct { pact_list* items; int64_t index; } %s;", tname);
    pact_emit_line(strdup(_si_1));
    pact_emit_line("");
    char _si_2[4096];
    snprintf(_si_2, 4096, "static %s %s_next(%s* self) {", opt_name, tname, tname);
    pact_emit_line(strdup(_si_2));
    pact_emit_line("    if (self->index < pact_list_len(self->items)) {");
    if ((inner == CT_INT)) {
        pact_emit_line("        int64_t val = (int64_t)(intptr_t)pact_list_get(self->items, self->index);");
    } else if ((inner == CT_STRING)) {
        pact_emit_line("        const char* val = (const char*)pact_list_get(self->items, self->index);");
    } else {
        if ((inner == CT_FLOAT)) {
            pact_emit_line("        double val = *(double*)pact_list_get(self->items, self->index);");
        } else {
            char _si_3[4096];
            snprintf(_si_3, 4096, "        %s val = (%s)(intptr_t)pact_list_get(self->items, self->index);", c_inner, c_inner);
            pact_emit_line(strdup(_si_3));
        }
    }
    pact_emit_line("        self->index++;");
    char _si_4[4096];
    snprintf(_si_4, 4096, "        return (%s){ .tag = 1, .value = val };", opt_name);
    pact_emit_line(strdup(_si_4));
    pact_emit_line("    }");
    char _si_5[4096];
    snprintf(_si_5, 4096, "    return (%s){ .tag = 0 };", opt_name);
    pact_emit_line(strdup(_si_5));
    pact_emit_line("}");
    pact_emit_line("");
    char _si_6[4096];
    snprintf(_si_6, 4096, "static %s pact_list_into_iter_%s(pact_list* self) {", tname, tag);
    pact_emit_line(strdup(_si_6));
    char _si_7[4096];
    snprintf(_si_7, 4096, "    return (%s){ .items = self, .index = 0 };", tname);
    pact_emit_line(strdup(_si_7));
    pact_emit_line("}");
    pact_emit_line("");
}

void pact_emit_all_iter_types(void) {
    if ((emitted_range_iter != 0)) {
        pact_emit_range_iter_typedef();
    }
    if ((emitted_str_iter != 0)) {
        pact_emit_str_iter_typedef();
    }
    int64_t i = 0;
    while ((i < pact_list_len(emitted_iter_types))) {
        pact_emit_list_iter_typedef((int64_t)(intptr_t)pact_list_get(emitted_iter_types, i));
        i = (i + 1);
    }
    i = 0;
    while ((i < pact_list_len(emitted_map_iters))) {
        pact_emit_map_iter_typedef((int64_t)(intptr_t)pact_list_get(emitted_map_iters, i));
        i = (i + 1);
    }
    i = 0;
    while ((i < pact_list_len(emitted_filter_iters))) {
        pact_emit_filter_iter_typedef((int64_t)(intptr_t)pact_list_get(emitted_filter_iters, i));
        i = (i + 1);
    }
    i = 0;
    while ((i < pact_list_len(emitted_take_iters))) {
        pact_emit_take_iter_typedef((int64_t)(intptr_t)pact_list_get(emitted_take_iters, i));
        i = (i + 1);
    }
    i = 0;
    while ((i < pact_list_len(emitted_skip_iters))) {
        pact_emit_skip_iter_typedef((int64_t)(intptr_t)pact_list_get(emitted_skip_iters, i));
        i = (i + 1);
    }
    i = 0;
    while ((i < pact_list_len(emitted_chain_iters))) {
        pact_emit_chain_iter_typedef((int64_t)(intptr_t)pact_list_get(emitted_chain_iters, i));
        i = (i + 1);
    }
    i = 0;
    while ((i < pact_list_len(emitted_flat_map_iters))) {
        pact_emit_flat_map_iter_typedef((int64_t)(intptr_t)pact_list_get(emitted_flat_map_iters, i));
        i = (i + 1);
    }
}

void pact_emit_iter_types_from(int64_t list_start, int64_t map_start, int64_t filter_start, int64_t take_start, int64_t skip_start, int64_t chain_start, int64_t flat_map_start) {
    int64_t i = list_start;
    while ((i < pact_list_len(emitted_iter_types))) {
        pact_emit_list_iter_typedef((int64_t)(intptr_t)pact_list_get(emitted_iter_types, i));
        i = (i + 1);
    }
    i = map_start;
    while ((i < pact_list_len(emitted_map_iters))) {
        pact_emit_map_iter_typedef((int64_t)(intptr_t)pact_list_get(emitted_map_iters, i));
        i = (i + 1);
    }
    i = filter_start;
    while ((i < pact_list_len(emitted_filter_iters))) {
        pact_emit_filter_iter_typedef((int64_t)(intptr_t)pact_list_get(emitted_filter_iters, i));
        i = (i + 1);
    }
    i = take_start;
    while ((i < pact_list_len(emitted_take_iters))) {
        pact_emit_take_iter_typedef((int64_t)(intptr_t)pact_list_get(emitted_take_iters, i));
        i = (i + 1);
    }
    i = skip_start;
    while ((i < pact_list_len(emitted_skip_iters))) {
        pact_emit_skip_iter_typedef((int64_t)(intptr_t)pact_list_get(emitted_skip_iters, i));
        i = (i + 1);
    }
    i = chain_start;
    while ((i < pact_list_len(emitted_chain_iters))) {
        pact_emit_chain_iter_typedef((int64_t)(intptr_t)pact_list_get(emitted_chain_iters, i));
        i = (i + 1);
    }
    i = flat_map_start;
    while ((i < pact_list_len(emitted_flat_map_iters))) {
        pact_emit_flat_map_iter_typedef((int64_t)(intptr_t)pact_list_get(emitted_flat_map_iters, i));
        i = (i + 1);
    }
}

int pact_has_int_in_list(pact_list* lst, int64_t val) {
    int64_t i = 0;
    while ((i < pact_list_len(lst))) {
        if (((int64_t)(intptr_t)pact_list_get(lst, i) == val)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

void pact_ensure_map_iter(int64_t inner) {
    if (pact_has_int_in_list(emitted_map_iters, inner)) {
        return;
    }
    pact_list_push(emitted_map_iters, (void*)(intptr_t)inner);
    pact_ensure_option_type(inner);
}

void pact_ensure_filter_iter(int64_t inner) {
    if (pact_has_int_in_list(emitted_filter_iters, inner)) {
        return;
    }
    pact_list_push(emitted_filter_iters, (void*)(intptr_t)inner);
    pact_ensure_option_type(inner);
}

void pact_ensure_take_iter(int64_t inner) {
    if (pact_has_int_in_list(emitted_take_iters, inner)) {
        return;
    }
    pact_list_push(emitted_take_iters, (void*)(intptr_t)inner);
    pact_ensure_option_type(inner);
}

void pact_ensure_skip_iter(int64_t inner) {
    if (pact_has_int_in_list(emitted_skip_iters, inner)) {
        return;
    }
    pact_list_push(emitted_skip_iters, (void*)(intptr_t)inner);
    pact_ensure_option_type(inner);
}

void pact_ensure_chain_iter(int64_t inner) {
    if (pact_has_int_in_list(emitted_chain_iters, inner)) {
        return;
    }
    pact_list_push(emitted_chain_iters, (void*)(intptr_t)inner);
    pact_ensure_option_type(inner);
}

void pact_ensure_flat_map_iter(int64_t inner) {
    if (pact_has_int_in_list(emitted_flat_map_iters, inner)) {
        return;
    }
    pact_list_push(emitted_flat_map_iters, (void*)(intptr_t)inner);
    pact_ensure_option_type(inner);
}

void pact_emit_map_iter_typedef(int64_t inner) {
    const char* tag = pact_c_type_tag(inner);
    const char* opt = pact_option_c_type(inner);
    const char* c_inner = pact_c_type_str(inner);
    char _si_0[4096];
    snprintf(_si_0, 4096, "typedef struct { void* source; %s (*source_next)(void*); pact_closure* fn; } pact_MapIterator_%s;", opt, tag);
    pact_emit_line(strdup(_si_0));
    pact_emit_line("");
    char _si_1[4096];
    snprintf(_si_1, 4096, "static %s pact_MapIterator_%s_next(pact_MapIterator_%s* self) {", opt, tag, tag);
    pact_emit_line(strdup(_si_1));
    char _si_2[4096];
    snprintf(_si_2, 4096, "    %s __src = self->source_next(self->source);", opt);
    pact_emit_line(strdup(_si_2));
    char _si_3[4096];
    snprintf(_si_3, 4096, "    if (__src.tag == 0) return (%s){ .tag = 0 };", opt);
    pact_emit_line(strdup(_si_3));
    char _si_4[4096];
    snprintf(_si_4, 4096, "    %s __val = ((%s (*)(pact_closure*, %s))self->fn->fn_ptr)(self->fn, __src.value);", c_inner, c_inner, c_inner);
    pact_emit_line(strdup(_si_4));
    char _si_5[4096];
    snprintf(_si_5, 4096, "    return (%s){ .tag = 1, .value = __val };", opt);
    pact_emit_line(strdup(_si_5));
    pact_emit_line("}");
    pact_emit_line("");
}

void pact_emit_filter_iter_typedef(int64_t inner) {
    const char* tag = pact_c_type_tag(inner);
    const char* opt = pact_option_c_type(inner);
    const char* c_inner = pact_c_type_str(inner);
    char _si_0[4096];
    snprintf(_si_0, 4096, "typedef struct { void* source; %s (*source_next)(void*); pact_closure* fn; } pact_FilterIterator_%s;", opt, tag);
    pact_emit_line(strdup(_si_0));
    pact_emit_line("");
    char _si_1[4096];
    snprintf(_si_1, 4096, "static %s pact_FilterIterator_%s_next(pact_FilterIterator_%s* self) {", opt, tag, tag);
    pact_emit_line(strdup(_si_1));
    pact_emit_line("    while (1) {");
    char _si_2[4096];
    snprintf(_si_2, 4096, "        %s __src = self->source_next(self->source);", opt);
    pact_emit_line(strdup(_si_2));
    char _si_3[4096];
    snprintf(_si_3, 4096, "        if (__src.tag == 0) return (%s){ .tag = 0 };", opt);
    pact_emit_line(strdup(_si_3));
    char _si_4[4096];
    snprintf(_si_4, 4096, "        if (((int (*)(pact_closure*, %s))self->fn->fn_ptr)(self->fn, __src.value)) {", c_inner);
    pact_emit_line(strdup(_si_4));
    pact_emit_line("            return __src;");
    pact_emit_line("        }");
    pact_emit_line("    }");
    pact_emit_line("}");
    pact_emit_line("");
}

void pact_emit_take_iter_typedef(int64_t inner) {
    const char* tag = pact_c_type_tag(inner);
    const char* opt = pact_option_c_type(inner);
    char _si_0[4096];
    snprintf(_si_0, 4096, "typedef struct { void* source; %s (*source_next)(void*); int64_t limit; int64_t count; } pact_TakeIterator_%s;", opt, tag);
    pact_emit_line(strdup(_si_0));
    pact_emit_line("");
    char _si_1[4096];
    snprintf(_si_1, 4096, "static %s pact_TakeIterator_%s_next(pact_TakeIterator_%s* self) {", opt, tag, tag);
    pact_emit_line(strdup(_si_1));
    char _si_2[4096];
    snprintf(_si_2, 4096, "    if (self->count >= self->limit) return (%s){ .tag = 0 };", opt);
    pact_emit_line(strdup(_si_2));
    char _si_3[4096];
    snprintf(_si_3, 4096, "    %s __src = self->source_next(self->source);", opt);
    pact_emit_line(strdup(_si_3));
    pact_emit_line("    if (__src.tag == 0) return __src;");
    pact_emit_line("    self->count++;");
    pact_emit_line("    return __src;");
    pact_emit_line("}");
    pact_emit_line("");
}

void pact_emit_skip_iter_typedef(int64_t inner) {
    const char* tag = pact_c_type_tag(inner);
    const char* opt = pact_option_c_type(inner);
    char _si_0[4096];
    snprintf(_si_0, 4096, "typedef struct { void* source; %s (*source_next)(void*); int64_t skip_n; int64_t skipped; } pact_SkipIterator_%s;", opt, tag);
    pact_emit_line(strdup(_si_0));
    pact_emit_line("");
    char _si_1[4096];
    snprintf(_si_1, 4096, "static %s pact_SkipIterator_%s_next(pact_SkipIterator_%s* self) {", opt, tag, tag);
    pact_emit_line(strdup(_si_1));
    pact_emit_line("    while (self->skipped < self->skip_n) {");
    char _si_2[4096];
    snprintf(_si_2, 4096, "        %s __src = self->source_next(self->source);", opt);
    pact_emit_line(strdup(_si_2));
    pact_emit_line("        if (__src.tag == 0) return __src;");
    pact_emit_line("        self->skipped++;");
    pact_emit_line("    }");
    pact_emit_line("    return self->source_next(self->source);");
    pact_emit_line("}");
    pact_emit_line("");
}

void pact_emit_chain_iter_typedef(int64_t inner) {
    const char* tag = pact_c_type_tag(inner);
    const char* opt = pact_option_c_type(inner);
    char _si_0[4096];
    snprintf(_si_0, 4096, "typedef struct { void* source_a; %s (*next_a)(void*); void* source_b; %s (*next_b)(void*); int phase; } pact_ChainIterator_%s;", opt, opt, tag);
    pact_emit_line(strdup(_si_0));
    pact_emit_line("");
    char _si_1[4096];
    snprintf(_si_1, 4096, "static %s pact_ChainIterator_%s_next(pact_ChainIterator_%s* self) {", opt, tag, tag);
    pact_emit_line(strdup(_si_1));
    pact_emit_line("    if (self->phase == 0) {");
    char _si_2[4096];
    snprintf(_si_2, 4096, "        %s __src = self->next_a(self->source_a);", opt);
    pact_emit_line(strdup(_si_2));
    pact_emit_line("        if (__src.tag != 0) return __src;");
    pact_emit_line("        self->phase = 1;");
    pact_emit_line("    }");
    pact_emit_line("    return self->next_b(self->source_b);");
    pact_emit_line("}");
    pact_emit_line("");
}

void pact_emit_flat_map_iter_typedef(int64_t inner) {
    const char* tag = pact_c_type_tag(inner);
    const char* opt = pact_option_c_type(inner);
    const char* c_inner = pact_c_type_str(inner);
    char _si_0[4096];
    snprintf(_si_0, 4096, "typedef struct { void* source; %s (*source_next)(void*); pact_closure* fn; pact_list* buffer; int64_t buf_idx; } pact_FlatMapIterator_%s;", opt, tag);
    pact_emit_line(strdup(_si_0));
    pact_emit_line("");
    char _si_1[4096];
    snprintf(_si_1, 4096, "static %s pact_FlatMapIterator_%s_next(pact_FlatMapIterator_%s* self) {", opt, tag, tag);
    pact_emit_line(strdup(_si_1));
    pact_emit_line("    while (1) {");
    pact_emit_line("        if (self->buffer && self->buf_idx < pact_list_len(self->buffer)) {");
    if ((inner == CT_INT)) {
        char _si_2[4096];
        snprintf(_si_2, 4096, "            %s val = (int64_t)(intptr_t)pact_list_get(self->buffer, self->buf_idx);", c_inner);
        pact_emit_line(strdup(_si_2));
    } else if ((inner == CT_STRING)) {
        char _si_3[4096];
        snprintf(_si_3, 4096, "            %s val = (const char*)pact_list_get(self->buffer, self->buf_idx);", c_inner);
        pact_emit_line(strdup(_si_3));
    } else {
        if ((inner == CT_FLOAT)) {
            pact_emit_line("            double val = *(double*)pact_list_get(self->buffer, self->buf_idx);");
        } else {
            char _si_4[4096];
            snprintf(_si_4, 4096, "            %s val = (%s)(intptr_t)pact_list_get(self->buffer, self->buf_idx);", c_inner, c_inner);
            pact_emit_line(strdup(_si_4));
        }
    }
    pact_emit_line("            self->buf_idx++;");
    char _si_5[4096];
    snprintf(_si_5, 4096, "            return (%s){ .tag = 1, .value = val };", opt);
    pact_emit_line(strdup(_si_5));
    pact_emit_line("        }");
    char _si_6[4096];
    snprintf(_si_6, 4096, "        %s __src = self->source_next(self->source);", opt);
    pact_emit_line(strdup(_si_6));
    char _si_7[4096];
    snprintf(_si_7, 4096, "        if (__src.tag == 0) return (%s){ .tag = 0 };", opt);
    pact_emit_line(strdup(_si_7));
    char _si_8[4096];
    snprintf(_si_8, 4096, "        self->buffer = ((pact_list* (*)(pact_closure*, %s))self->fn->fn_ptr)(self->fn, __src.value);", c_inner);
    pact_emit_line(strdup(_si_8));
    pact_emit_line("        self->buf_idx = 0;");
    pact_emit_line("    }");
    pact_emit_line("}");
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

void pact_emit_option_result_types_from(int64_t opt_start, int64_t res_start) {
    int64_t i = opt_start;
    while ((i < pact_list_len(emitted_option_types))) {
        pact_emit_option_typedef((int64_t)(intptr_t)pact_list_get(emitted_option_types, i));
        i = (i + 1);
    }
    i = res_start;
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

void pact_emit_method_call(int64_t node) {
    const int64_t obj_node = (int64_t)(intptr_t)pact_list_get(np_obj, node);
    const char* method = (const char*)pact_list_get(np_method, node);
    if (((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident)) {
        const char* mc_obj_name = (const char*)pact_list_get(np_name, obj_node);
        if (((pact_is_enum_type(mc_obj_name) != 0) && (pact_is_data_enum(mc_obj_name) != 0))) {
            const int64_t vidx = pact_get_variant_index(mc_obj_name, method);
            if ((vidx >= 0)) {
                const int64_t tag = pact_get_variant_tag(mc_obj_name, method);
                const int64_t fcount = pact_get_variant_field_count(vidx);
                const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
                char _si_0[4096];
                snprintf(_si_0, 4096, "(pact_%s){.tag = %lld", mc_obj_name, (long long)tag);
                const char* init_str = strdup(_si_0);
                if (((fcount > 0) && (args_sl != (-1)))) {
                    char _si_1[4096];
                    snprintf(_si_1, 4096, ", .data.%s = {", method);
                    init_str = pact_str_concat(init_str, strdup(_si_1));
                    int64_t fi = 0;
                    while (((fi < pact_sublist_length(args_sl)) && (fi < fcount))) {
                        if ((fi > 0)) {
                            init_str = pact_str_concat(init_str, ", ");
                        }
                        const char* field_name = pact_get_variant_field_name(vidx, fi);
                        pact_emit_expr(pact_sublist_get(args_sl, fi));
                        const char* arg_str = expr_result_str;
                        char _si_2[4096];
                        snprintf(_si_2, 4096, ".%s = %s", field_name, arg_str);
                        init_str = pact_str_concat(init_str, strdup(_si_2));
                        fi = (fi + 1);
                    }
                    init_str = pact_str_concat(init_str, "}");
                }
                init_str = pact_str_concat(init_str, "}");
                expr_result_str = init_str;
                expr_result_type = CT_INT;
                return;
            }
        }
    }
    if (((((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident) && pact_str_eq((const char*)pact_list_get(np_name, obj_node), "io")) && pact_str_eq(method, "println"))) {
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* arg_str = expr_result_str;
            const int64_t arg_type = expr_result_type;
            if ((arg_type == CT_INT)) {
                char _si_3[4096];
                snprintf(_si_3, 4096, "printf(\"%%lld\\n\", (long long)%s);", arg_str);
                pact_emit_line(strdup(_si_3));
            } else if ((arg_type == CT_FLOAT)) {
                char _si_4[4096];
                snprintf(_si_4, 4096, "printf(\"%%g\\n\", %s);", arg_str);
                pact_emit_line(strdup(_si_4));
            } else {
                if ((arg_type == CT_BOOL)) {
                    char _si_5[4096];
                    snprintf(_si_5, 4096, "printf(\"%%s\\n\", %s \? \"true\" : \"false\");", arg_str);
                    pact_emit_line(strdup(_si_5));
                } else {
                    char _si_6[4096];
                    snprintf(_si_6, 4096, "printf(\"%%s\\n\", %s);", arg_str);
                    pact_emit_line(strdup(_si_6));
                }
            }
        } else {
            pact_emit_line("printf(\"\\n\");");
        }
        expr_result_str = "0";
        expr_result_type = CT_VOID;
        return;
    }
    if (((((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident) && pact_str_eq((const char*)pact_list_get(np_name, obj_node), "io")) && pact_str_eq(method, "print"))) {
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* arg_str = expr_result_str;
            const int64_t arg_type = expr_result_type;
            if ((arg_type == CT_INT)) {
                char _si_7[4096];
                snprintf(_si_7, 4096, "printf(\"%%lld\", (long long)%s);", arg_str);
                pact_emit_line(strdup(_si_7));
            } else if ((arg_type == CT_FLOAT)) {
                char _si_8[4096];
                snprintf(_si_8, 4096, "printf(\"%%g\", %s);", arg_str);
                pact_emit_line(strdup(_si_8));
            } else {
                if ((arg_type == CT_BOOL)) {
                    char _si_9[4096];
                    snprintf(_si_9, 4096, "printf(\"%%s\", %s \? \"true\" : \"false\");", arg_str);
                    pact_emit_line(strdup(_si_9));
                } else {
                    char _si_10[4096];
                    snprintf(_si_10, 4096, "printf(\"%%s\", %s);", arg_str);
                    pact_emit_line(strdup(_si_10));
                }
            }
        }
        expr_result_str = "0";
        expr_result_type = CT_VOID;
        return;
    }
    if (((((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident) && pact_str_eq((const char*)pact_list_get(np_name, obj_node), "io")) && pact_str_eq(method, "eprintln"))) {
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* arg_str = expr_result_str;
            const int64_t arg_type = expr_result_type;
            if ((arg_type == CT_INT)) {
                char _si_11[4096];
                snprintf(_si_11, 4096, "fprintf(stderr, \"%%lld\\n\", (long long)%s);", arg_str);
                pact_emit_line(strdup(_si_11));
            } else if ((arg_type == CT_FLOAT)) {
                char _si_12[4096];
                snprintf(_si_12, 4096, "fprintf(stderr, \"%%g\\n\", %s);", arg_str);
                pact_emit_line(strdup(_si_12));
            } else {
                if ((arg_type == CT_BOOL)) {
                    char _si_13[4096];
                    snprintf(_si_13, 4096, "fprintf(stderr, \"%%s\\n\", %s \? \"true\" : \"false\");", arg_str);
                    pact_emit_line(strdup(_si_13));
                } else {
                    char _si_14[4096];
                    snprintf(_si_14, 4096, "fprintf(stderr, \"%%s\\n\", %s);", arg_str);
                    pact_emit_line(strdup(_si_14));
                }
            }
        } else {
            pact_emit_line("fprintf(stderr, \"\\n\");");
        }
        expr_result_str = "0";
        expr_result_type = CT_VOID;
        return;
    }
    if (((((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident) && pact_str_eq((const char*)pact_list_get(np_name, obj_node), "io")) && pact_str_eq(method, "eprint"))) {
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* arg_str = expr_result_str;
            const int64_t arg_type = expr_result_type;
            if ((arg_type == CT_INT)) {
                char _si_15[4096];
                snprintf(_si_15, 4096, "fprintf(stderr, \"%%lld\", (long long)%s);", arg_str);
                pact_emit_line(strdup(_si_15));
            } else if ((arg_type == CT_FLOAT)) {
                char _si_16[4096];
                snprintf(_si_16, 4096, "fprintf(stderr, \"%%g\", %s);", arg_str);
                pact_emit_line(strdup(_si_16));
            } else {
                if ((arg_type == CT_BOOL)) {
                    char _si_17[4096];
                    snprintf(_si_17, 4096, "fprintf(stderr, \"%%s\", %s \? \"true\" : \"false\");", arg_str);
                    pact_emit_line(strdup(_si_17));
                } else {
                    char _si_18[4096];
                    snprintf(_si_18, 4096, "fprintf(stderr, \"%%s\", %s);", arg_str);
                    pact_emit_line(strdup(_si_18));
                }
            }
        }
        expr_result_str = "0";
        expr_result_type = CT_VOID;
        return;
    }
    if (((((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident) && pact_str_eq((const char*)pact_list_get(np_name, obj_node), "io")) && pact_str_eq(method, "log"))) {
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* arg_str = expr_result_str;
            const int64_t arg_type = expr_result_type;
            if ((arg_type == CT_INT)) {
                char _si_19[4096];
                snprintf(_si_19, 4096, "fprintf(stderr, \"[LOG] %%lld\\n\", (long long)%s);", arg_str);
                pact_emit_line(strdup(_si_19));
            } else if ((arg_type == CT_FLOAT)) {
                char _si_20[4096];
                snprintf(_si_20, 4096, "fprintf(stderr, \"[LOG] %%g\\n\", %s);", arg_str);
                pact_emit_line(strdup(_si_20));
            } else {
                char _si_21[4096];
                snprintf(_si_21, 4096, "fprintf(stderr, \"[LOG] %%s\\n\", %s);", arg_str);
                pact_emit_line(strdup(_si_21));
            }
        }
        expr_result_str = "0";
        expr_result_type = CT_VOID;
        return;
    }
    if (((((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident) && pact_str_eq((const char*)pact_list_get(np_name, obj_node), "async")) && pact_str_eq(method, "spawn"))) {
        cg_uses_async = 1;
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
            const int64_t spawn_arg_node = pact_sublist_get(args_sl, 0);
            const int64_t wrapper_idx = cg_async_wrapper_counter;
            cg_async_wrapper_counter = (cg_async_wrapper_counter + 1);
            char _si_22[4096];
            snprintf(_si_22, 4096, "__async_wrapper_%lld", (long long)wrapper_idx);
            const char* wrapper_name = strdup(_si_22);
            char _si_23[4096];
            snprintf(_si_23, 4096, "__async_task_%lld", (long long)wrapper_idx);
            const char* task_fn_name = strdup(_si_23);
            const char* handle_tmp = pact_fresh_temp("__handle_");
            const char* arg_tmp = pact_fresh_temp("__spawn_arg_");
            if (((int64_t)(intptr_t)pact_list_get(np_kind, spawn_arg_node) == pact_NodeKind_Closure)) {
                const int64_t cap_reg_idx = pact_list_len(closure_cap_infos);
                pact_emit_async_spawn_closure(spawn_arg_node, wrapper_idx, wrapper_name, task_fn_name);
                char _si_24[4096];
                snprintf(_si_24, 4096, "pact_handle* %s = pact_handle_new();", handle_tmp);
                pact_emit_line(strdup(_si_24));
                char _si_25[4096];
                snprintf(_si_25, 4096, "__async_arg_%lld_t* %s = (__async_arg_%lld_t*)pact_alloc(sizeof(__async_arg_%lld_t));", (long long)wrapper_idx, arg_tmp, (long long)wrapper_idx, (long long)wrapper_idx);
                pact_emit_line(strdup(_si_25));
                char _si_26[4096];
                snprintf(_si_26, 4096, "%s->handle = %s;", arg_tmp, handle_tmp);
                pact_emit_line(strdup(_si_26));
                pact_ClosureCapInfo _ub27 = *(pact_ClosureCapInfo*)pact_list_get(closure_cap_infos, cap_reg_idx);
                const pact_ClosureCapInfo ac_info = _ub27;
                if ((ac_info.count > 0)) {
                    char _si_28[4096];
                    snprintf(_si_28, 4096, "__acaps_%lld", (long long)wrapper_idx);
                    const char* caps_var = strdup(_si_28);
                    char _si_29[4096];
                    snprintf(_si_29, 4096, "void** %s = (void**)pact_alloc(sizeof(void*) * %lld);", caps_var, (long long)ac_info.count);
                    pact_emit_line(strdup(_si_29));
                    int64_t ci2 = 0;
                    while ((ci2 < ac_info.count)) {
                        pact_CaptureEntry _ub30 = *(pact_CaptureEntry*)pact_list_get(closure_captures, (ac_info.start + ci2));
                        const pact_CaptureEntry cap_e = _ub30;
                        if ((cap_e.is_mut != 0)) {
                            char _si_31[4096];
                            snprintf(_si_31, 4096, "%s[%lld] = (void*)%s_cell;", caps_var, (long long)ci2, cap_e.name);
                            pact_emit_line(strdup(_si_31));
                        } else if ((cap_e.ctype == CT_INT)) {
                            char _si_32[4096];
                            snprintf(_si_32, 4096, "%s[%lld] = (void*)(intptr_t)%s;", caps_var, (long long)ci2, cap_e.name);
                            pact_emit_line(strdup(_si_32));
                        } else {
                            if ((cap_e.ctype == CT_FLOAT)) {
                                const char* fp_tmp = pact_fresh_temp("__fp_");
                                char _si_33[4096];
                                snprintf(_si_33, 4096, "{double* %s = (double*)pact_alloc(sizeof(double)); *%s = %s; %s[%lld] = (void*)%s;}", fp_tmp, fp_tmp, cap_e.name, caps_var, (long long)ci2, fp_tmp);
                                pact_emit_line(strdup(_si_33));
                            } else if ((cap_e.ctype == CT_BOOL)) {
                                char _si_34[4096];
                                snprintf(_si_34, 4096, "%s[%lld] = (void*)(intptr_t)%s;", caps_var, (long long)ci2, cap_e.name);
                                pact_emit_line(strdup(_si_34));
                            } else {
                                char _si_35[4096];
                                snprintf(_si_35, 4096, "%s[%lld] = (void*)%s;", caps_var, (long long)ci2, cap_e.name);
                                pact_emit_line(strdup(_si_35));
                            }
                        }
                        ci2 = (ci2 + 1);
                    }
                    char _si_36[4096];
                    snprintf(_si_36, 4096, "%s->captures = %s;", arg_tmp, caps_var);
                    pact_emit_line(strdup(_si_36));
                    char _si_37[4096];
                    snprintf(_si_37, 4096, "%s->capture_count = %lld;", arg_tmp, (long long)ac_info.count);
                    pact_emit_line(strdup(_si_37));
                }
                char _si_38[4096];
                snprintf(_si_38, 4096, "pact_threadpool_submit(__pact_pool, %s, (void*)%s);", wrapper_name, arg_tmp);
                pact_emit_line(strdup(_si_38));
            } else {
                pact_emit_expr(spawn_arg_node);
                const char* closure_str = expr_result_str;
                pact_list_push(cg_closure_defs, (void*)"typedef struct {");
                pact_list_push(cg_closure_defs, (void*)"    pact_closure* closure;");
                pact_list_push(cg_closure_defs, (void*)"    pact_handle* handle;");
                char _si_39[4096];
                snprintf(_si_39, 4096, "} __async_arg_%lld_t;", (long long)wrapper_idx);
                pact_list_push(cg_closure_defs, (void*)strdup(_si_39));
                pact_list_push(cg_closure_defs, (void*)"");
                char _si_40[4096];
                snprintf(_si_40, 4096, "static void %s(void* __arg) {", wrapper_name);
                pact_list_push(cg_closure_defs, (void*)strdup(_si_40));
                char _si_41[4096];
                snprintf(_si_41, 4096, "    __async_arg_%lld_t* __a = (__async_arg_%lld_t*)__arg;", (long long)wrapper_idx, (long long)wrapper_idx);
                pact_list_push(cg_closure_defs, (void*)strdup(_si_41));
                pact_list_push(cg_closure_defs, (void*)"    pact_closure* __cl = __a->closure;");
                pact_list_push(cg_closure_defs, (void*)"    pact_handle* __h = __a->handle;");
                pact_list_push(cg_closure_defs, (void*)"    int64_t __r = ((int64_t(*)(pact_closure*))__cl->fn_ptr)(__cl);");
                pact_list_push(cg_closure_defs, (void*)"    pact_handle_set_result(__h, (void*)(intptr_t)__r);");
                pact_list_push(cg_closure_defs, (void*)"    free(__arg);");
                pact_list_push(cg_closure_defs, (void*)"}");
                pact_list_push(cg_closure_defs, (void*)"");
                char _si_42[4096];
                snprintf(_si_42, 4096, "pact_handle* %s = pact_handle_new();", handle_tmp);
                pact_emit_line(strdup(_si_42));
                char _si_43[4096];
                snprintf(_si_43, 4096, "__async_arg_%lld_t* %s = (__async_arg_%lld_t*)pact_alloc(sizeof(__async_arg_%lld_t));", (long long)wrapper_idx, arg_tmp, (long long)wrapper_idx, (long long)wrapper_idx);
                pact_emit_line(strdup(_si_43));
                char _si_44[4096];
                snprintf(_si_44, 4096, "%s->closure = %s;", arg_tmp, closure_str);
                pact_emit_line(strdup(_si_44));
                char _si_45[4096];
                snprintf(_si_45, 4096, "%s->handle = %s;", arg_tmp, handle_tmp);
                pact_emit_line(strdup(_si_45));
                char _si_46[4096];
                snprintf(_si_46, 4096, "pact_threadpool_submit(__pact_pool, %s, (void*)%s);", wrapper_name, arg_tmp);
                pact_emit_line(strdup(_si_46));
            }
            if ((pact_list_len(cg_async_scope_stack) > 0)) {
                const char* scope_list = (const char*)pact_list_get(cg_async_scope_stack, (pact_list_len(cg_async_scope_stack) - 1));
                char _si_47[4096];
                snprintf(_si_47, 4096, "pact_list_push(%s, (void*)%s);", scope_list, handle_tmp);
                pact_emit_line(strdup(_si_47));
            }
            pact_set_var_handle(handle_tmp, CT_INT);
            expr_result_str = handle_tmp;
            expr_result_type = CT_HANDLE;
        } else {
            expr_result_str = "0";
            expr_result_type = CT_VOID;
        }
        return;
    }
    if (((((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident) && pact_str_eq((const char*)pact_list_get(np_name, obj_node), "fs")) && pact_str_eq(method, "read"))) {
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* arg_str = expr_result_str;
            char _si_48[4096];
            snprintf(_si_48, 4096, "pact_read_file(%s)", arg_str);
            expr_result_str = strdup(_si_48);
            expr_result_type = CT_STRING;
        } else {
            expr_result_str = "\"\"";
            expr_result_type = CT_STRING;
        }
        return;
    }
    if (((((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident) && pact_str_eq((const char*)pact_list_get(np_name, obj_node), "fs")) && pact_str_eq(method, "write"))) {
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if (((args_sl != (-1)) && (pact_sublist_length(args_sl) >= 2))) {
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* path_str = expr_result_str;
            pact_emit_expr(pact_sublist_get(args_sl, 1));
            const char* content_str = expr_result_str;
            char _si_49[4096];
            snprintf(_si_49, 4096, "pact_write_file(%s, %s);", path_str, content_str);
            pact_emit_line(strdup(_si_49));
        }
        expr_result_str = "0";
        expr_result_type = CT_VOID;
        return;
    }
    if (((((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident) && pact_str_eq((const char*)pact_list_get(np_name, obj_node), "fs")) && pact_str_eq(method, "list_dir"))) {
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if (((args_sl != (-1)) && (pact_sublist_length(args_sl) >= 1))) {
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* arg_str = expr_result_str;
            char _si_50[4096];
            snprintf(_si_50, 4096, "pact_list_dir(%s)", arg_str);
            expr_result_str = strdup(_si_50);
            expr_result_type = CT_LIST;
            expr_list_elem_type = CT_STRING;
        } else {
            expr_result_str = "pact_list_new()";
            expr_result_type = CT_LIST;
            expr_list_elem_type = CT_STRING;
        }
        return;
    }
    if (((((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident) && pact_str_eq((const char*)pact_list_get(np_name, obj_node), "env")) && pact_str_eq(method, "args"))) {
        const char* tmp = pact_fresh_temp("_args_");
        char _si_51[4096];
        snprintf(_si_51, 4096, "pact_list* %s = pact_list_new();", tmp);
        pact_emit_line(strdup(_si_51));
        pact_emit_line("for (int __ai = 0; __ai < pact_g_argc; __ai++) {");
        char _si_52[4096];
        snprintf(_si_52, 4096, "    pact_list_push(%s, (void*)pact_g_argv[__ai]);", tmp);
        pact_emit_line(strdup(_si_52));
        pact_emit_line("}");
        pact_set_list_elem_type(tmp, CT_STRING);
        expr_result_str = tmp;
        expr_result_type = CT_LIST;
        expr_list_elem_type = CT_STRING;
        return;
    }
    if (((((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident) && pact_str_eq((const char*)pact_list_get(np_name, obj_node), "default")) && (cg_in_handler_body != 0))) {
        char _si_53[4096];
        snprintf(_si_53, 4096, "__handler_%lld_outer", (long long)cg_handler_body_idx);
        const char* outer_name = strdup(_si_53);
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        const char* args_str = "";
        if ((args_sl != (-1))) {
            int64_t ai = 0;
            while ((ai < pact_sublist_length(args_sl))) {
                if ((ai > 0)) {
                    args_str = pact_str_concat(args_str, ", ");
                }
                pact_emit_expr(pact_sublist_get(args_sl, ai));
                args_str = pact_str_concat(args_str, expr_result_str);
                ai = (ai + 1);
            }
        }
        char _si_54[4096];
        snprintf(_si_54, 4096, "%s->%s(%s)", outer_name, method, args_str);
        expr_result_str = strdup(_si_54);
        expr_result_type = CT_VOID;
        return;
    }
    if (((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident)) {
        const char* handle_name = (const char*)pact_list_get(np_name, obj_node);
        if ((pact_is_user_effect_handle(handle_name) != 0)) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            const char* args_str = "";
            if ((args_sl != (-1))) {
                int64_t ai = 0;
                while ((ai < pact_sublist_length(args_sl))) {
                    if ((ai > 0)) {
                        args_str = pact_str_concat(args_str, ", ");
                    }
                    pact_emit_expr(pact_sublist_get(args_sl, ai));
                    args_str = pact_str_concat(args_str, expr_result_str);
                    ai = (ai + 1);
                }
            }
            int64_t ue_ret_type = CT_VOID;
            int64_t mi = 0;
            while ((mi < pact_list_len(ue_methods))) {
                pact_UeMethod _ub55 = *(pact_UeMethod*)pact_list_get(ue_methods, mi);
                const pact_UeMethod uem = _ub55;
                if ((pact_str_eq(uem.effect_handle, handle_name) && pact_str_eq(uem.name, method))) {
                    if (pact_str_eq(uem.ret, "int64_t")) {
                        ue_ret_type = CT_INT;
                    } else if (pact_str_eq(uem.ret, "const char*")) {
                        ue_ret_type = CT_STRING;
                    } else {
                        if (pact_str_eq(uem.ret, "double")) {
                            ue_ret_type = CT_FLOAT;
                        } else if (pact_str_eq(uem.ret, "int")) {
                            ue_ret_type = CT_BOOL;
                        }
                    }
                    break;
                }
                mi = (mi + 1);
            }
            if ((ue_ret_type == CT_VOID)) {
                char _si_56[4096];
                snprintf(_si_56, 4096, "__pact_ue_%s->%s(%s);", handle_name, method, args_str);
                pact_emit_line(strdup(_si_56));
                expr_result_str = "0";
            } else {
                char _si_57[4096];
                snprintf(_si_57, 4096, "__pact_ue_%s->%s(%s)", handle_name, method, args_str);
                expr_result_str = strdup(_si_57);
            }
            expr_result_type = ue_ret_type;
            return;
        }
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
                    char _si_58[4096];
                    snprintf(_si_58, 4096, "%s_%s", type_name, method);
                    const char* mangled = strdup(_si_58);
                    const char* args_str = first_str;
                    int64_t i = 1;
                    while ((i < pact_sublist_length(args_sl))) {
                        args_str = pact_str_concat(args_str, ", ");
                        pact_emit_expr(pact_sublist_get(args_sl, i));
                        args_str = pact_str_concat(args_str, expr_result_str);
                        i = (i + 1);
                    }
                    char _si_59[4096];
                    snprintf(_si_59, 4096, "pact_%s(%s)", mangled, args_str);
                    expr_result_str = strdup(_si_59);
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
                    char _si_60[4096];
                    snprintf(_si_60, 4096, "%s_%s", target_type, from_name);
                    const char* mangled = strdup(_si_60);
                    char _si_61[4096];
                    snprintf(_si_61, 4096, "pact_%s(%s)", mangled, arg_str);
                    expr_result_str = strdup(_si_61);
                    expr_result_type = pact_get_fn_ret(mangled);
                    if ((expr_result_type == CT_VOID)) {
                        pact_set_var_struct(expr_result_str, target_type);
                    }
                    return;
                }
            }
        }
    }
    if (((int64_t)(intptr_t)pact_list_get(np_kind, obj_node) == pact_NodeKind_Ident)) {
        const char* target_type = (const char*)pact_list_get(np_name, obj_node);
        if ((pact_str_eq(method, "try_from") && ((pact_is_struct_type(target_type) != 0) || (pact_is_enum_type(target_type) != 0)))) {
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
                const int64_t tf_methods = pact_find_tryfrom_impl(src, target_type);
                if (((tf_methods != (-1)) && (pact_sublist_length(tf_methods) > 0))) {
                    const int64_t tf_fn = pact_sublist_get(tf_methods, 0);
                    const char* tf_name = (const char*)pact_list_get(np_name, tf_fn);
                    char _si_62[4096];
                    snprintf(_si_62, 4096, "%s_%s", target_type, tf_name);
                    const char* mangled = strdup(_si_62);
                    char _si_63[4096];
                    snprintf(_si_63, 4096, "pact_%s(%s)", mangled, arg_str);
                    expr_result_str = strdup(_si_63);
                    expr_result_type = pact_get_fn_ret(mangled);
                    pact_RetType _sr64 = pact_get_fn_ret_type(mangled);
                    const pact_RetType tf_rt = _sr64;
                    if (((tf_rt.inner1 != (-1)) && (tf_rt.inner2 != (-1)))) {
                        expr_result_ok_type = tf_rt.inner1;
                        expr_result_err_type = tf_rt.inner2;
                        pact_set_var_result(expr_result_str, tf_rt.inner1, tf_rt.inner2);
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
            char _si_65[4096];
            snprintf(_si_65, 4096, "(double)%s", obj_str);
            expr_result_str = strdup(_si_65);
            expr_result_type = CT_FLOAT;
            return;
        }
        if (((target == CT_INT) && (obj_type == CT_FLOAT))) {
            char _si_66[4096];
            snprintf(_si_66, 4096, "(int64_t)%s", obj_str);
            expr_result_str = strdup(_si_66);
            expr_result_type = CT_INT;
            return;
        }
        if (((target == CT_STRING) && (obj_type == CT_INT))) {
            char _si_67[4096];
            snprintf(_si_67, 4096, "pact_int_to_str(%s)", obj_str);
            expr_result_str = strdup(_si_67);
            expr_result_type = CT_STRING;
            return;
        }
        if (((target == CT_STRING) && (obj_type == CT_FLOAT))) {
            char _si_68[4096];
            snprintf(_si_68, 4096, "pact_float_to_str(%s)", obj_str);
            expr_result_str = strdup(_si_68);
            expr_result_type = CT_STRING;
            return;
        }
        const char* src_name = pact_type_name_from_ct(obj_type);
        const char* src_struct = pact_get_var_struct(obj_str);
        if ((!pact_str_eq(src_struct, ""))) {
            src_name = src_struct;
        }
        const char* tgt_name = pact_type_name_from_ct(target);
        if (((target == CT_VOID) && (!pact_str_eq(cg_let_target_name, "")))) {
            tgt_name = cg_let_target_name;
        }
        const int64_t from_methods = pact_find_from_impl(src_name, tgt_name);
        if (((from_methods != (-1)) && (pact_sublist_length(from_methods) > 0))) {
            const int64_t from_fn = pact_sublist_get(from_methods, 0);
            const char* from_name = (const char*)pact_list_get(np_name, from_fn);
            char _si_69[4096];
            snprintf(_si_69, 4096, "%s_%s", tgt_name, from_name);
            const char* mangled = strdup(_si_69);
            char _si_70[4096];
            snprintf(_si_70, 4096, "pact_%s(%s)", mangled, obj_str);
            expr_result_str = strdup(_si_70);
            expr_result_type = target;
            return;
        }
        pact_emit_line("/* into() conversion not found */");
        expr_result_str = obj_str;
        expr_result_type = obj_type;
        return;
    }
    if ((pact_str_eq(method, "to_float") && (obj_type == CT_INT))) {
        char _si_71[4096];
        snprintf(_si_71, 4096, "(double)%s", obj_str);
        expr_result_str = strdup(_si_71);
        expr_result_type = CT_FLOAT;
        return;
    }
    if ((pact_str_eq(method, "to_int") && (obj_type == CT_FLOAT))) {
        char _si_72[4096];
        snprintf(_si_72, 4096, "(int64_t)%s", obj_str);
        expr_result_str = strdup(_si_72);
        expr_result_type = CT_INT;
        return;
    }
    if (pact_str_eq(method, "to_string")) {
        if ((obj_type == CT_INT)) {
            char _si_73[4096];
            snprintf(_si_73, 4096, "pact_int_to_str(%s)", obj_str);
            expr_result_str = strdup(_si_73);
            expr_result_type = CT_STRING;
            return;
        }
        if ((obj_type == CT_FLOAT)) {
            char _si_74[4096];
            snprintf(_si_74, 4096, "pact_float_to_str(%s)", obj_str);
            expr_result_str = strdup(_si_74);
            expr_result_type = CT_STRING;
            return;
        }
    }
    if ((obj_type == CT_STRING)) {
        if (pact_str_eq(method, "len")) {
            char _si_75[4096];
            snprintf(_si_75, 4096, "pact_str_len(%s)", obj_str);
            expr_result_str = strdup(_si_75);
            expr_result_type = CT_INT;
            return;
        }
        if ((pact_str_eq(method, "char_at") || pact_str_eq(method, "charAt"))) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* idx_str = expr_result_str;
            char _si_76[4096];
            snprintf(_si_76, 4096, "pact_str_char_at(%s, %s)", obj_str, idx_str);
            expr_result_str = strdup(_si_76);
            expr_result_type = CT_INT;
            return;
        }
        if ((pact_str_eq(method, "substring") || pact_str_eq(method, "substr"))) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* start_str = expr_result_str;
            pact_emit_expr(pact_sublist_get(args_sl, 1));
            const char* len_str = expr_result_str;
            char _si_77[4096];
            snprintf(_si_77, 4096, "pact_str_substr(%s, %s, %s)", obj_str, start_str, len_str);
            expr_result_str = strdup(_si_77);
            expr_result_type = CT_STRING;
            return;
        }
        if (pact_str_eq(method, "contains")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* needle_str = expr_result_str;
            char _si_78[4096];
            snprintf(_si_78, 4096, "pact_str_contains(%s, %s)", obj_str, needle_str);
            expr_result_str = strdup(_si_78);
            expr_result_type = CT_BOOL;
            return;
        }
        if (pact_str_eq(method, "starts_with")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* pfx_str = expr_result_str;
            char _si_79[4096];
            snprintf(_si_79, 4096, "pact_str_starts_with(%s, %s)", obj_str, pfx_str);
            expr_result_str = strdup(_si_79);
            expr_result_type = CT_BOOL;
            return;
        }
        if (pact_str_eq(method, "ends_with")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* sfx_str = expr_result_str;
            char _si_80[4096];
            snprintf(_si_80, 4096, "pact_str_ends_with(%s, %s)", obj_str, sfx_str);
            expr_result_str = strdup(_si_80);
            expr_result_type = CT_BOOL;
            return;
        }
        if (pact_str_eq(method, "concat")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* other_str = expr_result_str;
            char _si_81[4096];
            snprintf(_si_81, 4096, "pact_str_concat(%s, %s)", obj_str, other_str);
            expr_result_str = strdup(_si_81);
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
            if ((val_type != CT_INT)) {
                pact_set_list_elem_type(obj_str, val_type);
            }
            const char* val_struct = pact_get_var_struct(val_str);
            if (((val_type == CT_VOID) && (!pact_str_eq(val_struct, "")))) {
                pact_set_list_elem_struct(obj_str, val_struct);
                pact_set_list_elem_type(obj_str, CT_VOID);
                const char* box_tmp = pact_fresh_temp("_box");
                char _si_82[4096];
                snprintf(_si_82, 4096, "pact_%s* %s = (pact_%s*)pact_alloc(sizeof(pact_%s));", val_struct, box_tmp, val_struct, val_struct);
                pact_emit_line(strdup(_si_82));
                char _si_83[4096];
                snprintf(_si_83, 4096, "*%s = %s;", box_tmp, val_str);
                pact_emit_line(strdup(_si_83));
                char _si_84[4096];
                snprintf(_si_84, 4096, "pact_list_push(%s, (void*)%s);", obj_str, box_tmp);
                pact_emit_line(strdup(_si_84));
            } else if ((val_type == CT_INT)) {
                char _si_85[4096];
                snprintf(_si_85, 4096, "pact_list_push(%s, (void*)(intptr_t)%s);", obj_str, val_str);
                pact_emit_line(strdup(_si_85));
            } else {
                if ((val_type == CT_FLOAT)) {
                    const char* box_tmp = pact_fresh_temp("_fbox");
                    char _si_86[4096];
                    snprintf(_si_86, 4096, "double* %s = (double*)pact_alloc(sizeof(double));", box_tmp);
                    pact_emit_line(strdup(_si_86));
                    char _si_87[4096];
                    snprintf(_si_87, 4096, "*%s = %s;", box_tmp, val_str);
                    pact_emit_line(strdup(_si_87));
                    char _si_88[4096];
                    snprintf(_si_88, 4096, "pact_list_push(%s, (void*)%s);", obj_str, box_tmp);
                    pact_emit_line(strdup(_si_88));
                } else {
                    char _si_89[4096];
                    snprintf(_si_89, 4096, "pact_list_push(%s, (void*)%s);", obj_str, val_str);
                    pact_emit_line(strdup(_si_89));
                }
            }
            expr_result_str = "0";
            expr_result_type = CT_VOID;
            return;
        }
        if (pact_str_eq(method, "pop")) {
            char _si_90[4096];
            snprintf(_si_90, 4096, "pact_list_pop(%s);", obj_str);
            pact_emit_line(strdup(_si_90));
            expr_result_str = "0";
            expr_result_type = CT_VOID;
            return;
        }
        if (pact_str_eq(method, "len")) {
            char _si_91[4096];
            snprintf(_si_91, 4096, "pact_list_len(%s)", obj_str);
            expr_result_str = strdup(_si_91);
            expr_result_type = CT_INT;
            return;
        }
        if (pact_str_eq(method, "get")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* idx_str = expr_result_str;
            const int64_t elem_type = pact_get_list_elem_type(obj_str);
            const char* elem_struct = pact_get_list_elem_struct(obj_str);
            if (((elem_type == CT_VOID) && (!pact_str_eq(elem_struct, "")))) {
                const char* ub_tmp = pact_fresh_temp("_ub");
                char _si_92[4096];
                snprintf(_si_92, 4096, "pact_%s %s = *(pact_%s*)pact_list_get(%s, %s);", elem_struct, ub_tmp, elem_struct, obj_str, idx_str);
                pact_emit_line(strdup(_si_92));
                pact_set_var_struct(ub_tmp, elem_struct);
                expr_result_str = ub_tmp;
                expr_result_type = CT_VOID;
            } else if ((elem_type == CT_STRING)) {
                char _si_93[4096];
                snprintf(_si_93, 4096, "(const char*)pact_list_get(%s, %s)", obj_str, idx_str);
                expr_result_str = strdup(_si_93);
                expr_result_type = CT_STRING;
            } else {
                if ((elem_type == CT_LIST)) {
                    char _si_94[4096];
                    snprintf(_si_94, 4096, "(pact_list*)pact_list_get(%s, %s)", obj_str, idx_str);
                    expr_result_str = strdup(_si_94);
                    expr_result_type = CT_LIST;
                    pact_set_list_elem_type(expr_result_str, CT_INT);
                } else if ((elem_type == CT_FLOAT)) {
                    char _si_95[4096];
                    snprintf(_si_95, 4096, "*(double*)pact_list_get(%s, %s)", obj_str, idx_str);
                    expr_result_str = strdup(_si_95);
                    expr_result_type = CT_FLOAT;
                } else {
                    char _si_96[4096];
                    snprintf(_si_96, 4096, "(int64_t)(intptr_t)pact_list_get(%s, %s)", obj_str, idx_str);
                    expr_result_str = strdup(_si_96);
                    expr_result_type = CT_INT;
                }
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
            const char* val_struct2 = pact_get_var_struct(val_str2);
            if (((val_type2 == CT_VOID) && (!pact_str_eq(val_struct2, "")))) {
                const char* box_tmp = pact_fresh_temp("_box");
                char _si_97[4096];
                snprintf(_si_97, 4096, "pact_%s* %s = (pact_%s*)pact_alloc(sizeof(pact_%s));", val_struct2, box_tmp, val_struct2, val_struct2);
                pact_emit_line(strdup(_si_97));
                char _si_98[4096];
                snprintf(_si_98, 4096, "*%s = %s;", box_tmp, val_str2);
                pact_emit_line(strdup(_si_98));
                char _si_99[4096];
                snprintf(_si_99, 4096, "pact_list_set(%s, %s, (void*)%s);", obj_str, idx_str, box_tmp);
                pact_emit_line(strdup(_si_99));
            } else if ((val_type2 == CT_INT)) {
                char _si_100[4096];
                snprintf(_si_100, 4096, "pact_list_set(%s, %s, (void*)(intptr_t)%s);", obj_str, idx_str, val_str2);
                pact_emit_line(strdup(_si_100));
            } else {
                if ((val_type2 == CT_FLOAT)) {
                    const char* box_tmp = pact_fresh_temp("_fbox");
                    char _si_101[4096];
                    snprintf(_si_101, 4096, "double* %s = (double*)pact_alloc(sizeof(double));", box_tmp);
                    pact_emit_line(strdup(_si_101));
                    char _si_102[4096];
                    snprintf(_si_102, 4096, "*%s = %s;", box_tmp, val_str2);
                    pact_emit_line(strdup(_si_102));
                    char _si_103[4096];
                    snprintf(_si_103, 4096, "pact_list_set(%s, %s, (void*)%s);", obj_str, idx_str, box_tmp);
                    pact_emit_line(strdup(_si_103));
                } else {
                    char _si_104[4096];
                    snprintf(_si_104, 4096, "pact_list_set(%s, %s, (void*)%s);", obj_str, idx_str, val_str2);
                    pact_emit_line(strdup(_si_104));
                }
            }
            expr_result_str = "0";
            expr_result_type = CT_VOID;
            return;
        }
    }
    if ((((obj_type == CT_LIST) || (obj_type == CT_ITERATOR)) && ((((((((((((((pact_str_eq(method, "count") || pact_str_eq(method, "collect")) || pact_str_eq(method, "for_each")) || pact_str_eq(method, "any")) || pact_str_eq(method, "all")) || pact_str_eq(method, "find")) || pact_str_eq(method, "fold")) || pact_str_eq(method, "map")) || pact_str_eq(method, "filter")) || pact_str_eq(method, "take")) || pact_str_eq(method, "skip")) || pact_str_eq(method, "chain")) || pact_str_eq(method, "flat_map")) || pact_str_eq(method, "enumerate")) || pact_str_eq(method, "zip")))) {
        if (pact_str_eq(method, "map")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* fn_str = expr_result_str;
            pact_iter_from_source(obj_str, obj_type);
            const char* src_var = ifs_iter_var;
            const char* src_next = ifs_next_fn;
            const int64_t elem_type = ifs_elem_type;
            const char* tag = pact_c_type_tag(elem_type);
            pact_ensure_map_iter(elem_type);
            const char* adapter_var = pact_fresh_temp("__map_");
            char _si_105[4096];
            snprintf(_si_105, 4096, "pact_MapIterator_%s %s = { .source = &%s, .source_next = (%s (*)(void*))%s, .fn = %s };", tag, adapter_var, src_var, ifs_opt_type, src_next, fn_str);
            pact_emit_line(strdup(_si_105));
            char _si_106[4096];
            snprintf(_si_106, 4096, "pact_MapIterator_%s_next", tag);
            pact_set_var_iterator(adapter_var, elem_type, strdup(_si_106));
            expr_result_str = adapter_var;
            expr_result_type = CT_ITERATOR;
            char _si_107[4096];
            snprintf(_si_107, 4096, "pact_MapIterator_%s_next", tag);
            expr_iter_next_fn = strdup(_si_107);
            expr_list_elem_type = elem_type;
            return;
        }
        if (pact_str_eq(method, "filter")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* fn_str = expr_result_str;
            pact_iter_from_source(obj_str, obj_type);
            const char* src_var = ifs_iter_var;
            const char* src_next = ifs_next_fn;
            const int64_t elem_type = ifs_elem_type;
            const char* tag = pact_c_type_tag(elem_type);
            pact_ensure_filter_iter(elem_type);
            const char* adapter_var = pact_fresh_temp("__filter_");
            char _si_108[4096];
            snprintf(_si_108, 4096, "pact_FilterIterator_%s %s = { .source = &%s, .source_next = (%s (*)(void*))%s, .fn = %s };", tag, adapter_var, src_var, ifs_opt_type, src_next, fn_str);
            pact_emit_line(strdup(_si_108));
            char _si_109[4096];
            snprintf(_si_109, 4096, "pact_FilterIterator_%s_next", tag);
            pact_set_var_iterator(adapter_var, elem_type, strdup(_si_109));
            expr_result_str = adapter_var;
            expr_result_type = CT_ITERATOR;
            char _si_110[4096];
            snprintf(_si_110, 4096, "pact_FilterIterator_%s_next", tag);
            expr_iter_next_fn = strdup(_si_110);
            expr_list_elem_type = elem_type;
            return;
        }
        if (pact_str_eq(method, "take")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* n_str = expr_result_str;
            pact_iter_from_source(obj_str, obj_type);
            const char* src_var = ifs_iter_var;
            const char* src_next = ifs_next_fn;
            const int64_t elem_type = ifs_elem_type;
            const char* tag = pact_c_type_tag(elem_type);
            pact_ensure_take_iter(elem_type);
            const char* adapter_var = pact_fresh_temp("__take_");
            char _si_111[4096];
            snprintf(_si_111, 4096, "pact_TakeIterator_%s %s = { .source = &%s, .source_next = (%s (*)(void*))%s, .limit = %s, .count = 0 };", tag, adapter_var, src_var, ifs_opt_type, src_next, n_str);
            pact_emit_line(strdup(_si_111));
            char _si_112[4096];
            snprintf(_si_112, 4096, "pact_TakeIterator_%s_next", tag);
            pact_set_var_iterator(adapter_var, elem_type, strdup(_si_112));
            expr_result_str = adapter_var;
            expr_result_type = CT_ITERATOR;
            char _si_113[4096];
            snprintf(_si_113, 4096, "pact_TakeIterator_%s_next", tag);
            expr_iter_next_fn = strdup(_si_113);
            expr_list_elem_type = elem_type;
            return;
        }
        if (pact_str_eq(method, "skip")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* n_str = expr_result_str;
            pact_iter_from_source(obj_str, obj_type);
            const char* src_var = ifs_iter_var;
            const char* src_next = ifs_next_fn;
            const int64_t elem_type = ifs_elem_type;
            const char* tag = pact_c_type_tag(elem_type);
            pact_ensure_skip_iter(elem_type);
            const char* adapter_var = pact_fresh_temp("__skip_");
            char _si_114[4096];
            snprintf(_si_114, 4096, "pact_SkipIterator_%s %s = { .source = &%s, .source_next = (%s (*)(void*))%s, .skip_n = %s, .skipped = 0 };", tag, adapter_var, src_var, ifs_opt_type, src_next, n_str);
            pact_emit_line(strdup(_si_114));
            char _si_115[4096];
            snprintf(_si_115, 4096, "pact_SkipIterator_%s_next", tag);
            pact_set_var_iterator(adapter_var, elem_type, strdup(_si_115));
            expr_result_str = adapter_var;
            expr_result_type = CT_ITERATOR;
            char _si_116[4096];
            snprintf(_si_116, 4096, "pact_SkipIterator_%s_next", tag);
            expr_iter_next_fn = strdup(_si_116);
            expr_list_elem_type = elem_type;
            return;
        }
        if (pact_str_eq(method, "chain")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* other_str = expr_result_str;
            const int64_t other_type = expr_result_type;
            pact_iter_from_source(obj_str, obj_type);
            const char* src_a_var = ifs_iter_var;
            const char* next_a = ifs_next_fn;
            const int64_t elem_type = ifs_elem_type;
            const char* opt_t = ifs_opt_type;
            const char* tag = pact_c_type_tag(elem_type);
            pact_iter_from_source(other_str, other_type);
            const char* src_b_var = ifs_iter_var;
            const char* next_b = ifs_next_fn;
            pact_ensure_chain_iter(elem_type);
            const char* adapter_var = pact_fresh_temp("__chain_");
            char _si_117[4096];
            snprintf(_si_117, 4096, "pact_ChainIterator_%s %s = { .source_a = &%s, .next_a = (%s (*)(void*))%s, .source_b = &%s, .next_b = (%s (*)(void*))%s, .phase = 0 };", tag, adapter_var, src_a_var, opt_t, next_a, src_b_var, opt_t, next_b);
            pact_emit_line(strdup(_si_117));
            char _si_118[4096];
            snprintf(_si_118, 4096, "pact_ChainIterator_%s_next", tag);
            pact_set_var_iterator(adapter_var, elem_type, strdup(_si_118));
            expr_result_str = adapter_var;
            expr_result_type = CT_ITERATOR;
            char _si_119[4096];
            snprintf(_si_119, 4096, "pact_ChainIterator_%s_next", tag);
            expr_iter_next_fn = strdup(_si_119);
            expr_list_elem_type = elem_type;
            return;
        }
        if (pact_str_eq(method, "flat_map")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* fn_str = expr_result_str;
            pact_iter_from_source(obj_str, obj_type);
            const char* src_var = ifs_iter_var;
            const char* src_next = ifs_next_fn;
            const int64_t elem_type = ifs_elem_type;
            const char* tag = pact_c_type_tag(elem_type);
            pact_ensure_flat_map_iter(elem_type);
            const char* adapter_var = pact_fresh_temp("__flatmap_");
            char _si_120[4096];
            snprintf(_si_120, 4096, "pact_FlatMapIterator_%s %s = { .source = &%s, .source_next = (%s (*)(void*))%s, .fn = %s, .buffer = NULL, .buf_idx = 0 };", tag, adapter_var, src_var, ifs_opt_type, src_next, fn_str);
            pact_emit_line(strdup(_si_120));
            char _si_121[4096];
            snprintf(_si_121, 4096, "pact_FlatMapIterator_%s_next", tag);
            pact_set_var_iterator(adapter_var, elem_type, strdup(_si_121));
            expr_result_str = adapter_var;
            expr_result_type = CT_ITERATOR;
            char _si_122[4096];
            snprintf(_si_122, 4096, "pact_FlatMapIterator_%s_next", tag);
            expr_iter_next_fn = strdup(_si_122);
            expr_list_elem_type = elem_type;
            return;
        }
        if (pact_str_eq(method, "enumerate")) {
            pact_iter_from_source(obj_str, obj_type);
            const char* src_var = ifs_iter_var;
            const char* src_next = ifs_next_fn;
            const int64_t elem_type = ifs_elem_type;
            const char* opt_t = ifs_opt_type;
            const char* tag = pact_c_type_tag(elem_type);
            const char* result_list = pact_fresh_temp("__enum_");
            const char* next_var = pact_fresh_temp("__enum_next_");
            const char* i_var = pact_fresh_temp("__enum_i_");
            char _si_123[4096];
            snprintf(_si_123, 4096, "pact_list* %s = pact_list_new();", result_list);
            pact_emit_line(strdup(_si_123));
            char _si_124[4096];
            snprintf(_si_124, 4096, "int64_t %s = 0;", i_var);
            pact_emit_line(strdup(_si_124));
            pact_emit_line("while (1) {");
            cg_indent = (cg_indent + 1);
            char _si_125[4096];
            snprintf(_si_125, 4096, "%s %s = ((%s (*)(void*))%s)(&%s);", opt_t, next_var, opt_t, src_next, src_var);
            pact_emit_line(strdup(_si_125));
            char _si_126[4096];
            snprintf(_si_126, 4096, "if (%s.tag == 0) break;", next_var);
            pact_emit_line(strdup(_si_126));
            const char* pair_var = pact_fresh_temp("__enum_pair_");
            char _si_127[4096];
            snprintf(_si_127, 4096, "pact_list* %s = pact_list_new();", pair_var);
            pact_emit_line(strdup(_si_127));
            char _si_128[4096];
            snprintf(_si_128, 4096, "pact_list_push(%s, (void*)(intptr_t)%s);", pair_var, i_var);
            pact_emit_line(strdup(_si_128));
            if ((elem_type == CT_INT)) {
                char _si_129[4096];
                snprintf(_si_129, 4096, "pact_list_push(%s, (void*)(intptr_t)%s.value);", pair_var, next_var);
                pact_emit_line(strdup(_si_129));
            } else {
                char _si_130[4096];
                snprintf(_si_130, 4096, "pact_list_push(%s, (void*)%s.value);", pair_var, next_var);
                pact_emit_line(strdup(_si_130));
            }
            char _si_131[4096];
            snprintf(_si_131, 4096, "pact_list_push(%s, (void*)%s);", result_list, pair_var);
            pact_emit_line(strdup(_si_131));
            char _si_132[4096];
            snprintf(_si_132, 4096, "%s++;", i_var);
            pact_emit_line(strdup(_si_132));
            cg_indent = (cg_indent - 1);
            pact_emit_line("}");
            pact_set_list_elem_type(result_list, CT_LIST);
            expr_result_str = result_list;
            expr_result_type = CT_LIST;
            expr_list_elem_type = CT_LIST;
            return;
        }
        if (pact_str_eq(method, "zip")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* other_str = expr_result_str;
            const int64_t other_type = expr_result_type;
            pact_iter_from_source(obj_str, obj_type);
            const char* src_a_var = ifs_iter_var;
            const char* next_a = ifs_next_fn;
            const int64_t elem_type_a = ifs_elem_type;
            const char* opt_a = ifs_opt_type;
            pact_iter_from_source(other_str, other_type);
            const char* src_b_var = ifs_iter_var;
            const char* next_b = ifs_next_fn;
            const int64_t elem_type_b = ifs_elem_type;
            const char* opt_b = ifs_opt_type;
            const char* result_list = pact_fresh_temp("__zip_");
            const char* next_a_var = pact_fresh_temp("__zip_na_");
            const char* next_b_var = pact_fresh_temp("__zip_nb_");
            char _si_133[4096];
            snprintf(_si_133, 4096, "pact_list* %s = pact_list_new();", result_list);
            pact_emit_line(strdup(_si_133));
            pact_emit_line("while (1) {");
            cg_indent = (cg_indent + 1);
            char _si_134[4096];
            snprintf(_si_134, 4096, "%s %s = ((%s (*)(void*))%s)(&%s);", opt_a, next_a_var, opt_a, next_a, src_a_var);
            pact_emit_line(strdup(_si_134));
            char _si_135[4096];
            snprintf(_si_135, 4096, "if (%s.tag == 0) break;", next_a_var);
            pact_emit_line(strdup(_si_135));
            char _si_136[4096];
            snprintf(_si_136, 4096, "%s %s = ((%s (*)(void*))%s)(&%s);", opt_b, next_b_var, opt_b, next_b, src_b_var);
            pact_emit_line(strdup(_si_136));
            char _si_137[4096];
            snprintf(_si_137, 4096, "if (%s.tag == 0) break;", next_b_var);
            pact_emit_line(strdup(_si_137));
            const char* pair_var = pact_fresh_temp("__zip_pair_");
            char _si_138[4096];
            snprintf(_si_138, 4096, "pact_list* %s = pact_list_new();", pair_var);
            pact_emit_line(strdup(_si_138));
            if ((elem_type_a == CT_INT)) {
                char _si_139[4096];
                snprintf(_si_139, 4096, "pact_list_push(%s, (void*)(intptr_t)%s.value);", pair_var, next_a_var);
                pact_emit_line(strdup(_si_139));
            } else {
                char _si_140[4096];
                snprintf(_si_140, 4096, "pact_list_push(%s, (void*)%s.value);", pair_var, next_a_var);
                pact_emit_line(strdup(_si_140));
            }
            if ((elem_type_b == CT_INT)) {
                char _si_141[4096];
                snprintf(_si_141, 4096, "pact_list_push(%s, (void*)(intptr_t)%s.value);", pair_var, next_b_var);
                pact_emit_line(strdup(_si_141));
            } else {
                char _si_142[4096];
                snprintf(_si_142, 4096, "pact_list_push(%s, (void*)%s.value);", pair_var, next_b_var);
                pact_emit_line(strdup(_si_142));
            }
            char _si_143[4096];
            snprintf(_si_143, 4096, "pact_list_push(%s, (void*)%s);", result_list, pair_var);
            pact_emit_line(strdup(_si_143));
            cg_indent = (cg_indent - 1);
            pact_emit_line("}");
            pact_set_list_elem_type(result_list, CT_LIST);
            expr_result_str = result_list;
            expr_result_type = CT_LIST;
            expr_list_elem_type = CT_LIST;
            return;
        }
        if (pact_str_eq(method, "collect")) {
            pact_iter_from_source(obj_str, obj_type);
            const char* src_var = ifs_iter_var;
            const char* src_next = ifs_next_fn;
            const int64_t elem_type = ifs_elem_type;
            const char* opt_t = ifs_opt_type;
            const char* result_list = pact_fresh_temp("__collect_");
            const char* next_var = pact_fresh_temp("__collect_next_");
            char _si_144[4096];
            snprintf(_si_144, 4096, "pact_list* %s = pact_list_new();", result_list);
            pact_emit_line(strdup(_si_144));
            pact_emit_line("while (1) {");
            cg_indent = (cg_indent + 1);
            char _si_145[4096];
            snprintf(_si_145, 4096, "%s %s = ((%s (*)(void*))%s)(&%s);", opt_t, next_var, opt_t, src_next, src_var);
            pact_emit_line(strdup(_si_145));
            char _si_146[4096];
            snprintf(_si_146, 4096, "if (%s.tag == 0) break;", next_var);
            pact_emit_line(strdup(_si_146));
            if ((elem_type == CT_INT)) {
                char _si_147[4096];
                snprintf(_si_147, 4096, "pact_list_push(%s, (void*)(intptr_t)%s.value);", result_list, next_var);
                pact_emit_line(strdup(_si_147));
            } else {
                char _si_148[4096];
                snprintf(_si_148, 4096, "pact_list_push(%s, (void*)%s.value);", result_list, next_var);
                pact_emit_line(strdup(_si_148));
            }
            cg_indent = (cg_indent - 1);
            pact_emit_line("}");
            pact_set_list_elem_type(result_list, elem_type);
            expr_result_str = result_list;
            expr_result_type = CT_LIST;
            expr_list_elem_type = elem_type;
            return;
        }
        if (pact_str_eq(method, "count")) {
            pact_iter_from_source(obj_str, obj_type);
            const char* src_var = ifs_iter_var;
            const char* src_next = ifs_next_fn;
            const char* opt_t = ifs_opt_type;
            const char* count_var = pact_fresh_temp("__count_");
            const char* next_var = pact_fresh_temp("__count_next_");
            char _si_149[4096];
            snprintf(_si_149, 4096, "int64_t %s = 0;", count_var);
            pact_emit_line(strdup(_si_149));
            pact_emit_line("while (1) {");
            cg_indent = (cg_indent + 1);
            char _si_150[4096];
            snprintf(_si_150, 4096, "%s %s = ((%s (*)(void*))%s)(&%s);", opt_t, next_var, opt_t, src_next, src_var);
            pact_emit_line(strdup(_si_150));
            char _si_151[4096];
            snprintf(_si_151, 4096, "if (%s.tag == 0) break;", next_var);
            pact_emit_line(strdup(_si_151));
            char _si_152[4096];
            snprintf(_si_152, 4096, "%s++;", count_var);
            pact_emit_line(strdup(_si_152));
            cg_indent = (cg_indent - 1);
            pact_emit_line("}");
            expr_result_str = count_var;
            expr_result_type = CT_INT;
            return;
        }
        if (pact_str_eq(method, "for_each")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* fn_str = expr_result_str;
            const char* fn_sig = expr_closure_sig;
            pact_iter_from_source(obj_str, obj_type);
            const char* src_var = ifs_iter_var;
            const char* src_next = ifs_next_fn;
            const int64_t elem_type = ifs_elem_type;
            const char* opt_t = ifs_opt_type;
            const char* c_inner = pact_c_type_str(elem_type);
            const char* next_var = pact_fresh_temp("__fe_next_");
            pact_emit_line("while (1) {");
            cg_indent = (cg_indent + 1);
            char _si_153[4096];
            snprintf(_si_153, 4096, "%s %s = ((%s (*)(void*))%s)(&%s);", opt_t, next_var, opt_t, src_next, src_var);
            pact_emit_line(strdup(_si_153));
            char _si_154[4096];
            snprintf(_si_154, 4096, "if (%s.tag == 0) break;", next_var);
            pact_emit_line(strdup(_si_154));
            char _si_155[4096];
            snprintf(_si_155, 4096, "((%s)%s->fn_ptr)(%s, %s.value);", fn_sig, fn_str, fn_str, next_var);
            pact_emit_line(strdup(_si_155));
            cg_indent = (cg_indent - 1);
            pact_emit_line("}");
            expr_result_str = "0";
            expr_result_type = CT_VOID;
            return;
        }
        if (pact_str_eq(method, "any")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* fn_str = expr_result_str;
            const char* fn_sig = expr_closure_sig;
            pact_iter_from_source(obj_str, obj_type);
            const char* src_var = ifs_iter_var;
            const char* src_next = ifs_next_fn;
            const int64_t elem_type = ifs_elem_type;
            const char* opt_t = ifs_opt_type;
            const char* c_inner = pact_c_type_str(elem_type);
            const char* result_var = pact_fresh_temp("__any_");
            const char* next_var = pact_fresh_temp("__any_next_");
            char _si_156[4096];
            snprintf(_si_156, 4096, "int %s = 0;", result_var);
            pact_emit_line(strdup(_si_156));
            pact_emit_line("while (1) {");
            cg_indent = (cg_indent + 1);
            char _si_157[4096];
            snprintf(_si_157, 4096, "%s %s = ((%s (*)(void*))%s)(&%s);", opt_t, next_var, opt_t, src_next, src_var);
            pact_emit_line(strdup(_si_157));
            char _si_158[4096];
            snprintf(_si_158, 4096, "if (%s.tag == 0) break;", next_var);
            pact_emit_line(strdup(_si_158));
            char _si_159[4096];
            snprintf(_si_159, 4096, "if (((%s)%s->fn_ptr)(%s, %s.value)) { %s = 1; break; }", fn_sig, fn_str, fn_str, next_var, result_var);
            pact_emit_line(strdup(_si_159));
            cg_indent = (cg_indent - 1);
            pact_emit_line("}");
            expr_result_str = result_var;
            expr_result_type = CT_BOOL;
            return;
        }
        if (pact_str_eq(method, "all")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* fn_str = expr_result_str;
            const char* fn_sig = expr_closure_sig;
            pact_iter_from_source(obj_str, obj_type);
            const char* src_var = ifs_iter_var;
            const char* src_next = ifs_next_fn;
            const int64_t elem_type = ifs_elem_type;
            const char* opt_t = ifs_opt_type;
            const char* c_inner = pact_c_type_str(elem_type);
            const char* result_var = pact_fresh_temp("__all_");
            const char* next_var = pact_fresh_temp("__all_next_");
            char _si_160[4096];
            snprintf(_si_160, 4096, "int %s = 1;", result_var);
            pact_emit_line(strdup(_si_160));
            pact_emit_line("while (1) {");
            cg_indent = (cg_indent + 1);
            char _si_161[4096];
            snprintf(_si_161, 4096, "%s %s = ((%s (*)(void*))%s)(&%s);", opt_t, next_var, opt_t, src_next, src_var);
            pact_emit_line(strdup(_si_161));
            char _si_162[4096];
            snprintf(_si_162, 4096, "if (%s.tag == 0) break;", next_var);
            pact_emit_line(strdup(_si_162));
            char _si_163[4096];
            snprintf(_si_163, 4096, "if (!((%s)%s->fn_ptr)(%s, %s.value)) { %s = 0; break; }", fn_sig, fn_str, fn_str, next_var, result_var);
            pact_emit_line(strdup(_si_163));
            cg_indent = (cg_indent - 1);
            pact_emit_line("}");
            expr_result_str = result_var;
            expr_result_type = CT_BOOL;
            return;
        }
        if (pact_str_eq(method, "find")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* fn_str = expr_result_str;
            const char* fn_sig = expr_closure_sig;
            pact_iter_from_source(obj_str, obj_type);
            const char* src_var = ifs_iter_var;
            const char* src_next = ifs_next_fn;
            const int64_t elem_type = ifs_elem_type;
            const char* opt_t = ifs_opt_type;
            pact_ensure_option_type(elem_type);
            const char* result_var = pact_fresh_temp("__find_");
            const char* next_var = pact_fresh_temp("__find_next_");
            char _si_164[4096];
            snprintf(_si_164, 4096, "%s %s = (%s){.tag = 0};", opt_t, result_var, opt_t);
            pact_emit_line(strdup(_si_164));
            pact_emit_line("while (1) {");
            cg_indent = (cg_indent + 1);
            char _si_165[4096];
            snprintf(_si_165, 4096, "%s %s = ((%s (*)(void*))%s)(&%s);", opt_t, next_var, opt_t, src_next, src_var);
            pact_emit_line(strdup(_si_165));
            char _si_166[4096];
            snprintf(_si_166, 4096, "if (%s.tag == 0) break;", next_var);
            pact_emit_line(strdup(_si_166));
            char _si_167[4096];
            snprintf(_si_167, 4096, "if (((%s)%s->fn_ptr)(%s, %s.value)) { %s = (%s){.tag = 1, .value = %s.value}; break; }", fn_sig, fn_str, fn_str, next_var, result_var, opt_t, next_var);
            pact_emit_line(strdup(_si_167));
            cg_indent = (cg_indent - 1);
            pact_emit_line("}");
            expr_result_str = result_var;
            expr_result_type = CT_OPTION;
            expr_option_inner = elem_type;
            return;
        }
        if (pact_str_eq(method, "fold")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* init_str = expr_result_str;
            const int64_t init_type = expr_result_type;
            pact_emit_expr(pact_sublist_get(args_sl, 1));
            const char* fn_str = expr_result_str;
            const char* fn_sig = expr_closure_sig;
            pact_iter_from_source(obj_str, obj_type);
            const char* src_var = ifs_iter_var;
            const char* src_next = ifs_next_fn;
            const int64_t elem_type = ifs_elem_type;
            const char* opt_t = ifs_opt_type;
            const char* acc_var = pact_fresh_temp("__fold_acc_");
            const char* next_var = pact_fresh_temp("__fold_next_");
            char _si_168[4096];
            snprintf(_si_168, 4096, "%s %s = %s;", pact_c_type_str(init_type), acc_var, init_str);
            pact_emit_line(strdup(_si_168));
            pact_emit_line("while (1) {");
            cg_indent = (cg_indent + 1);
            char _si_169[4096];
            snprintf(_si_169, 4096, "%s %s = ((%s (*)(void*))%s)(&%s);", opt_t, next_var, opt_t, src_next, src_var);
            pact_emit_line(strdup(_si_169));
            char _si_170[4096];
            snprintf(_si_170, 4096, "if (%s.tag == 0) break;", next_var);
            pact_emit_line(strdup(_si_170));
            char _si_171[4096];
            snprintf(_si_171, 4096, "%s = ((%s)%s->fn_ptr)(%s, %s, %s.value);", acc_var, fn_sig, fn_str, fn_str, acc_var, next_var);
            pact_emit_line(strdup(_si_171));
            cg_indent = (cg_indent - 1);
            pact_emit_line("}");
            expr_result_str = acc_var;
            expr_result_type = init_type;
            return;
        }
    }
    if ((obj_type == CT_CHANNEL)) {
        if (pact_str_eq(method, "send")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* val_str = expr_result_str;
            const int64_t val_type = expr_result_type;
            if ((val_type == CT_INT)) {
                char _si_172[4096];
                snprintf(_si_172, 4096, "pact_channel_send(%s, (void*)(intptr_t)%s);", obj_str, val_str);
                pact_emit_line(strdup(_si_172));
            } else {
                char _si_173[4096];
                snprintf(_si_173, 4096, "pact_channel_send(%s, (void*)%s);", obj_str, val_str);
                pact_emit_line(strdup(_si_173));
            }
            expr_result_str = "0";
            expr_result_type = CT_INT;
            return;
        }
        if (pact_str_eq(method, "recv")) {
            const char* recv_tmp = pact_fresh_temp("__recv_");
            const int64_t ch_inner = pact_get_var_channel_inner(obj_str);
            char _si_174[4096];
            snprintf(_si_174, 4096, "void* %s = pact_channel_recv(%s);", recv_tmp, obj_str);
            pact_emit_line(strdup(_si_174));
            if ((ch_inner == CT_STRING)) {
                char _si_175[4096];
                snprintf(_si_175, 4096, "(const char*)%s", recv_tmp);
                expr_result_str = strdup(_si_175);
                expr_result_type = CT_STRING;
            } else {
                char _si_176[4096];
                snprintf(_si_176, 4096, "(int64_t)(intptr_t)%s", recv_tmp);
                expr_result_str = strdup(_si_176);
                expr_result_type = CT_INT;
            }
            return;
        }
        if (pact_str_eq(method, "close")) {
            char _si_177[4096];
            snprintf(_si_177, 4096, "pact_channel_close(%s);", obj_str);
            pact_emit_line(strdup(_si_177));
            expr_result_str = "0";
            expr_result_type = CT_VOID;
            return;
        }
    }
    if ((obj_type == CT_MAP)) {
        if (pact_str_eq(method, "set")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* key_str = expr_result_str;
            pact_emit_expr(pact_sublist_get(args_sl, 1));
            const char* val_str2 = expr_result_str;
            const int64_t val_type2 = expr_result_type;
            if ((val_type2 == CT_INT)) {
                char _si_178[4096];
                snprintf(_si_178, 4096, "pact_map_set(%s, %s, (void*)(intptr_t)%s);", obj_str, key_str, val_str2);
                pact_emit_line(strdup(_si_178));
            } else if ((val_type2 == CT_FLOAT)) {
                const char* box_tmp = pact_fresh_temp("_fbox");
                char _si_179[4096];
                snprintf(_si_179, 4096, "double* %s = (double*)pact_alloc(sizeof(double));", box_tmp);
                pact_emit_line(strdup(_si_179));
                char _si_180[4096];
                snprintf(_si_180, 4096, "*%s = %s;", box_tmp, val_str2);
                pact_emit_line(strdup(_si_180));
                char _si_181[4096];
                snprintf(_si_181, 4096, "pact_map_set(%s, %s, (void*)%s);", obj_str, key_str, box_tmp);
                pact_emit_line(strdup(_si_181));
            } else {
                char _si_182[4096];
                snprintf(_si_182, 4096, "pact_map_set(%s, %s, (void*)%s);", obj_str, key_str, val_str2);
                pact_emit_line(strdup(_si_182));
            }
            pact_set_map_types(obj_str, CT_STRING, val_type2);
            expr_result_str = "0";
            expr_result_type = CT_VOID;
            return;
        }
        if (pact_str_eq(method, "get")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* key_str = expr_result_str;
            const int64_t vtype = pact_get_map_value_type(obj_str);
            if ((vtype == CT_STRING)) {
                char _si_183[4096];
                snprintf(_si_183, 4096, "(const char*)pact_map_get(%s, %s)", obj_str, key_str);
                expr_result_str = strdup(_si_183);
                expr_result_type = CT_STRING;
            } else if ((vtype == CT_LIST)) {
                char _si_184[4096];
                snprintf(_si_184, 4096, "(pact_list*)pact_map_get(%s, %s)", obj_str, key_str);
                expr_result_str = strdup(_si_184);
                expr_result_type = CT_LIST;
            } else {
                if ((vtype == CT_MAP)) {
                    char _si_185[4096];
                    snprintf(_si_185, 4096, "(pact_map*)pact_map_get(%s, %s)", obj_str, key_str);
                    expr_result_str = strdup(_si_185);
                    expr_result_type = CT_MAP;
                } else if ((vtype == CT_FLOAT)) {
                    char _si_186[4096];
                    snprintf(_si_186, 4096, "*(double*)pact_map_get(%s, %s)", obj_str, key_str);
                    expr_result_str = strdup(_si_186);
                    expr_result_type = CT_FLOAT;
                } else {
                    char _si_187[4096];
                    snprintf(_si_187, 4096, "(int64_t)(intptr_t)pact_map_get(%s, %s)", obj_str, key_str);
                    expr_result_str = strdup(_si_187);
                    expr_result_type = CT_INT;
                }
            }
            return;
        }
        if (pact_str_eq(method, "has")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* key_str = expr_result_str;
            char _si_188[4096];
            snprintf(_si_188, 4096, "pact_map_has(%s, %s)", obj_str, key_str);
            expr_result_str = strdup(_si_188);
            expr_result_type = CT_INT;
            return;
        }
        if (pact_str_eq(method, "remove")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* key_str = expr_result_str;
            char _si_189[4096];
            snprintf(_si_189, 4096, "pact_map_remove(%s, %s)", obj_str, key_str);
            expr_result_str = strdup(_si_189);
            expr_result_type = CT_INT;
            return;
        }
        if (pact_str_eq(method, "len")) {
            char _si_190[4096];
            snprintf(_si_190, 4096, "pact_map_len(%s)", obj_str);
            expr_result_str = strdup(_si_190);
            expr_result_type = CT_INT;
            return;
        }
        if (pact_str_eq(method, "keys")) {
            char _si_191[4096];
            snprintf(_si_191, 4096, "pact_map_keys(%s)", obj_str);
            expr_result_str = strdup(_si_191);
            expr_result_type = CT_LIST;
            expr_list_elem_type = CT_STRING;
            return;
        }
        if (pact_str_eq(method, "values")) {
            const int64_t vtype = pact_get_map_value_type(obj_str);
            char _si_192[4096];
            snprintf(_si_192, 4096, "pact_map_values(%s)", obj_str);
            expr_result_str = strdup(_si_192);
            expr_result_type = CT_LIST;
            expr_list_elem_type = vtype;
            return;
        }
    }
    const char* struct_type = pact_get_var_struct(obj_str);
    if (((!pact_str_eq(struct_type, "")) && (pact_lookup_impl_method(struct_type, method) != 0))) {
        char _si_193[4096];
        snprintf(_si_193, 4096, "%s_%s", struct_type, method);
        const char* mangled = strdup(_si_193);
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
        char _si_194[4096];
        snprintf(_si_194, 4096, "pact_%s(%s)", mangled, args_str);
        expr_result_str = strdup(_si_194);
        expr_result_type = pact_get_impl_method_ret(struct_type, method);
        return;
    }
    char _si_195[4096];
    snprintf(_si_195, 4096, "unresolved method '.%s' called on variable in '%s'", method, cg_current_fn_name);
    pact_diag_error_at("UnresolvedMethod", "E0505", strdup(_si_195), node, "");
    char _si_196[4096];
    snprintf(_si_196, 4096, "/* unresolved: .%s */", method);
    pact_emit_line(strdup(_si_196));
    expr_result_str = "0";
    expr_result_type = CT_INT;
}

int64_t pact_list_contains_str(pact_list* lst, const char* val) {
    int64_t i = 0;
    while ((i < pact_list_len(lst))) {
        if (pact_str_eq((const char*)pact_list_get(lst, i), val)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_is_in_scope(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(scope_vars))) {
        pact_ScopeVar _ub0 = *(pact_ScopeVar*)pact_list_get(scope_vars, i);
        if (pact_str_eq(_ub0.name, name)) {
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
        while ((fi < pact_list_len(fn_regs))) {
            pact_FnRegEntry _ub0 = *(pact_FnRegEntry*)pact_list_get(fn_regs, fi);
            if (pact_str_eq(_ub0.name, name)) {
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
        pact_list* _l1 = pact_list_new();
        pact_list* inner_locals = _l1;
        int64_t li = 0;
        while ((li < pact_list_len(locals))) {
            pact_list_push(inner_locals, (void*)(const char*)pact_list_get(locals, li));
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
        pact_list_push(block_locals, (void*)(const char*)pact_list_get(locals, li));
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

void pact_prescan_collect_muts(int64_t node) {
    if ((node == (-1))) {
        return;
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_LetBinding)) {
        if (((int64_t)(intptr_t)pact_list_get(np_is_mut, node) != 0)) {
            pact_list_push(prescan_mut_names, (void*)(const char*)pact_list_get(np_name, node));
        }
        return;
    }
    if ((kind == pact_NodeKind_Block)) {
        pact_prescan_collect_muts_block(node);
        return;
    }
    if ((kind == pact_NodeKind_IfExpr)) {
        pact_prescan_collect_muts_block((int64_t)(intptr_t)pact_list_get(np_then_body, node));
        pact_prescan_collect_muts_block((int64_t)(intptr_t)pact_list_get(np_else_body, node));
        return;
    }
    if ((kind == pact_NodeKind_WhileLoop)) {
        pact_prescan_collect_muts_block((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_ForIn)) {
        pact_prescan_collect_muts_block((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_LoopExpr)) {
        pact_prescan_collect_muts_block((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_WithBlock)) {
        pact_prescan_collect_muts_block((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
}

void pact_prescan_collect_muts_block(int64_t block) {
    if ((block == (-1))) {
        return;
    }
    const int64_t stmts_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, block);
    if ((stmts_sl == (-1))) {
        return;
    }
    int64_t i = 0;
    while ((i < pact_sublist_length(stmts_sl))) {
        pact_prescan_collect_muts(pact_sublist_get(stmts_sl, i));
        i = (i + 1);
    }
}

void pact_prescan_collect_closure_idents(int64_t node) {
    if ((node == (-1))) {
        return;
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_Ident)) {
        pact_list_push(prescan_closure_idents, (void*)(const char*)pact_list_get(np_name, node));
        return;
    }
    if ((kind == pact_NodeKind_BinOp)) {
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_left, node));
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_right, node));
        return;
    }
    if ((kind == pact_NodeKind_UnaryOp)) {
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_left, node));
        return;
    }
    if ((kind == pact_NodeKind_Call)) {
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_left, node));
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if ((args_sl != (-1))) {
            int64_t ai = 0;
            while ((ai < pact_sublist_length(args_sl))) {
                pact_prescan_collect_closure_idents(pact_sublist_get(args_sl, ai));
                ai = (ai + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_MethodCall)) {
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_obj, node));
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if ((args_sl != (-1))) {
            int64_t ai = 0;
            while ((ai < pact_sublist_length(args_sl))) {
                pact_prescan_collect_closure_idents(pact_sublist_get(args_sl, ai));
                ai = (ai + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_Assignment)) {
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_target, node));
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_value, node));
        return;
    }
    if ((kind == pact_NodeKind_CompoundAssign)) {
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_target, node));
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_value, node));
        return;
    }
    if ((kind == pact_NodeKind_LetBinding)) {
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_value, node));
        return;
    }
    if ((kind == pact_NodeKind_ExprStmt)) {
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_value, node));
        return;
    }
    if ((kind == pact_NodeKind_Return)) {
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_value, node));
        return;
    }
    if ((kind == pact_NodeKind_Block)) {
        pact_prescan_collect_closure_idents_block(node);
        return;
    }
    if ((kind == pact_NodeKind_IfExpr)) {
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_condition, node));
        pact_prescan_collect_closure_idents_block((int64_t)(intptr_t)pact_list_get(np_then_body, node));
        pact_prescan_collect_closure_idents_block((int64_t)(intptr_t)pact_list_get(np_else_body, node));
        return;
    }
    if ((kind == pact_NodeKind_WhileLoop)) {
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_condition, node));
        pact_prescan_collect_closure_idents_block((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_ForIn)) {
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_iterable, node));
        pact_prescan_collect_closure_idents_block((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_LoopExpr)) {
        pact_prescan_collect_closure_idents_block((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_InterpString)) {
        const int64_t parts_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        if ((parts_sl != (-1))) {
            int64_t pi = 0;
            while ((pi < pact_sublist_length(parts_sl))) {
                pact_prescan_collect_closure_idents(pact_sublist_get(parts_sl, pi));
                pi = (pi + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_FieldAccess)) {
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_obj, node));
        return;
    }
    if ((kind == pact_NodeKind_IndexExpr)) {
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_obj, node));
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_index, node));
        return;
    }
    if ((kind == pact_NodeKind_MatchExpr)) {
        pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_scrutinee, node));
        const int64_t arms_sl = (int64_t)(intptr_t)pact_list_get(np_arms, node);
        if ((arms_sl != (-1))) {
            int64_t ai = 0;
            while ((ai < pact_sublist_length(arms_sl))) {
                const int64_t arm = pact_sublist_get(arms_sl, ai);
                pact_prescan_collect_closure_idents((int64_t)(intptr_t)pact_list_get(np_body, arm));
                ai = (ai + 1);
            }
        }
        return;
    }
}

void pact_prescan_collect_closure_idents_block(int64_t block) {
    if ((block == (-1))) {
        return;
    }
    const int64_t stmts_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, block);
    if ((stmts_sl == (-1))) {
        return;
    }
    int64_t i = 0;
    while ((i < pact_sublist_length(stmts_sl))) {
        pact_prescan_collect_closure_idents(pact_sublist_get(stmts_sl, i));
        i = (i + 1);
    }
}

void pact_prescan_closures_in_node(int64_t node) {
    if ((node == (-1))) {
        return;
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_Closure)) {
        pact_prescan_collect_closure_idents_block((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_Block)) {
        pact_prescan_closures_in_block(node);
        return;
    }
    if ((kind == pact_NodeKind_LetBinding)) {
        pact_prescan_closures_in_node((int64_t)(intptr_t)pact_list_get(np_value, node));
        return;
    }
    if ((kind == pact_NodeKind_ExprStmt)) {
        pact_prescan_closures_in_node((int64_t)(intptr_t)pact_list_get(np_value, node));
        return;
    }
    if ((kind == pact_NodeKind_Assignment)) {
        pact_prescan_closures_in_node((int64_t)(intptr_t)pact_list_get(np_value, node));
        return;
    }
    if ((kind == pact_NodeKind_CompoundAssign)) {
        pact_prescan_closures_in_node((int64_t)(intptr_t)pact_list_get(np_value, node));
        return;
    }
    if ((kind == pact_NodeKind_IfExpr)) {
        pact_prescan_closures_in_node((int64_t)(intptr_t)pact_list_get(np_condition, node));
        pact_prescan_closures_in_block((int64_t)(intptr_t)pact_list_get(np_then_body, node));
        pact_prescan_closures_in_block((int64_t)(intptr_t)pact_list_get(np_else_body, node));
        return;
    }
    if ((kind == pact_NodeKind_WhileLoop)) {
        pact_prescan_closures_in_node((int64_t)(intptr_t)pact_list_get(np_condition, node));
        pact_prescan_closures_in_block((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_ForIn)) {
        pact_prescan_closures_in_node((int64_t)(intptr_t)pact_list_get(np_iterable, node));
        pact_prescan_closures_in_block((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_LoopExpr)) {
        pact_prescan_closures_in_block((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_Return)) {
        pact_prescan_closures_in_node((int64_t)(intptr_t)pact_list_get(np_value, node));
        return;
    }
    if ((kind == pact_NodeKind_Call)) {
        pact_prescan_closures_in_node((int64_t)(intptr_t)pact_list_get(np_left, node));
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if ((args_sl != (-1))) {
            int64_t ai = 0;
            while ((ai < pact_sublist_length(args_sl))) {
                pact_prescan_closures_in_node(pact_sublist_get(args_sl, ai));
                ai = (ai + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_MethodCall)) {
        pact_prescan_closures_in_node((int64_t)(intptr_t)pact_list_get(np_obj, node));
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if ((args_sl != (-1))) {
            int64_t ai = 0;
            while ((ai < pact_sublist_length(args_sl))) {
                pact_prescan_closures_in_node(pact_sublist_get(args_sl, ai));
                ai = (ai + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_BinOp)) {
        pact_prescan_closures_in_node((int64_t)(intptr_t)pact_list_get(np_left, node));
        pact_prescan_closures_in_node((int64_t)(intptr_t)pact_list_get(np_right, node));
        return;
    }
    if ((kind == pact_NodeKind_UnaryOp)) {
        pact_prescan_closures_in_node((int64_t)(intptr_t)pact_list_get(np_left, node));
        return;
    }
    if ((kind == pact_NodeKind_MatchExpr)) {
        pact_prescan_closures_in_node((int64_t)(intptr_t)pact_list_get(np_scrutinee, node));
        const int64_t arms_sl = (int64_t)(intptr_t)pact_list_get(np_arms, node);
        if ((arms_sl != (-1))) {
            int64_t ai = 0;
            while ((ai < pact_sublist_length(arms_sl))) {
                const int64_t arm = pact_sublist_get(arms_sl, ai);
                pact_prescan_closures_in_node((int64_t)(intptr_t)pact_list_get(np_body, arm));
                ai = (ai + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_WithBlock)) {
        pact_prescan_closures_in_block((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
}

void pact_prescan_closures_in_block(int64_t block) {
    if ((block == (-1))) {
        return;
    }
    const int64_t stmts_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, block);
    if ((stmts_sl == (-1))) {
        return;
    }
    int64_t i = 0;
    while ((i < pact_sublist_length(stmts_sl))) {
        pact_prescan_closures_in_node(pact_sublist_get(stmts_sl, i));
        i = (i + 1);
    }
}

void pact_prescan_mut_captures(int64_t block) {
    pact_list* _l0 = pact_list_new();
    prescan_mut_names = _l0;
    pact_list* _l1 = pact_list_new();
    prescan_closure_idents = _l1;
    pact_prescan_collect_muts_block(block);
    pact_prescan_closures_in_block(block);
    int64_t i = 0;
    while ((i < pact_list_len(prescan_mut_names))) {
        const char* mname = (const char*)pact_list_get(prescan_mut_names, i);
        int64_t j = 0;
        while ((j < pact_list_len(prescan_closure_idents))) {
            const char* cident = (const char*)pact_list_get(prescan_closure_idents, j);
            if (pact_str_eq(mname, cident)) {
                if ((pact_is_mut_captured(mname) == 0)) {
                    pact_list_push(mut_captured_vars, (void*)mname);
                }
            }
            j = (j + 1);
        }
        i = (i + 1);
    }
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
    pact_list* captures = pact_analyze_captures((int64_t)(intptr_t)pact_list_get(np_body, node), params_sl);
    const int64_t cap_start = pact_list_len(closure_captures);
    int64_t cap_i = 0;
    while ((cap_i < pact_list_len(captures))) {
        const char* cap_name = (const char*)pact_list_get(captures, cap_i);
        const int64_t cap_ct = pact_get_var_type(cap_name);
        int64_t _if_1;
        if ((pact_is_mut_captured(cap_name) != 0)) {
            _if_1 = 1;
        } else {
            _if_1 = 0;
        }
        const int64_t cap_mut = _if_1;
        pact_CaptureEntry _s2 = { .name = cap_name, .ctype = cap_ct, .is_mut = cap_mut };
        pact_CaptureEntry* _box3 = (pact_CaptureEntry*)pact_alloc(sizeof(pact_CaptureEntry));
        *_box3 = _s2;
        pact_list_push(closure_captures, (void*)_box3);
        cap_i = (cap_i + 1);
    }
    pact_ClosureCapInfo _s4 = { .start = cap_start, .count = pact_list_len(captures) };
    pact_ClosureCapInfo* _box5 = (pact_ClosureCapInfo*)pact_alloc(sizeof(pact_ClosureCapInfo));
    *_box5 = _s4;
    pact_list_push(closure_cap_infos, (void*)_box5);
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
                char _si_6[4096];
                snprintf(_si_6, 4096, "pact_closure* %s", pname);
                params_c = pact_str_concat(params_c, strdup(_si_6));
            } else if ((pact_is_enum_type(ptype) != 0)) {
                char _si_7[4096];
                snprintf(_si_7, 4096, "pact_%s %s", ptype, pname);
                params_c = pact_str_concat(params_c, strdup(_si_7));
            } else {
                if ((pact_is_struct_type(ptype) != 0)) {
                    char _si_8[4096];
                    snprintf(_si_8, 4096, "pact_%s %s", ptype, pname);
                    params_c = pact_str_concat(params_c, strdup(_si_8));
                } else {
                    const int64_t ct = pact_type_from_name(ptype);
                    char _si_9[4096];
                    snprintf(_si_9, 4096, "%s %s", pact_c_type_str(ct), pname);
                    params_c = pact_str_concat(params_c, strdup(_si_9));
                }
            }
            i = (i + 1);
        }
    }
    pact_list* saved_lines = cg_lines;
    const int64_t saved_indent = cg_indent;
    const int64_t saved_temp = cg_temp_counter;
    const int64_t saved_cap_start = cg_closure_cap_start;
    const int64_t saved_cap_count = cg_closure_cap_count;
    pact_list* _l10 = pact_list_new();
    cg_lines = _l10;
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
                    pact_VarEnumEntry _s11 = { .name = pname, .enum_type = ptype };
                    pact_VarEnumEntry* _box12 = (pact_VarEnumEntry*)pact_alloc(sizeof(pact_VarEnumEntry));
                    *_box12 = _s11;
                    pact_list_push(var_enums, (void*)_box12);
                }
            }
            i = (i + 1);
        }
    }
    char _si_13[4096];
    snprintf(_si_13, 4096, "static %s %s(%s) {", pact_c_type_str(ret_type), cname, params_c);
    pact_emit_line(strdup(_si_13));
    cg_indent = (cg_indent + 1);
    pact_list* _l14 = pact_list_new();
    pact_list* mc_done = _l14;
    int64_t mc_i = 0;
    while ((mc_i < pact_list_len(captures))) {
        pact_CaptureEntry _ub15 = *(pact_CaptureEntry*)pact_list_get(closure_captures, (cap_start + mc_i));
        const pact_CaptureEntry mc_e = _ub15;
        if ((mc_e.is_mut != 0)) {
            int64_t mc_dup = 0;
            int64_t mc_j = 0;
            while ((mc_j < mc_i)) {
                pact_CaptureEntry _ub16 = *(pact_CaptureEntry*)pact_list_get(closure_captures, (cap_start + mc_j));
                if (pact_str_eq(_ub16.name, mc_e.name)) {
                    mc_dup = 1;
                }
                mc_j = (mc_j + 1);
            }
            if ((mc_dup == 0)) {
                const char* mc_ts = pact_c_type_str(mc_e.ctype);
                char _si_17[4096];
                snprintf(_si_17, 4096, "%s* %s_cell = (%s*)pact_closure_get_capture(__self, %lld);", mc_ts, mc_e.name, mc_ts, (long long)mc_i);
                pact_emit_line(strdup(_si_17));
            }
        }
        mc_i = (mc_i + 1);
    }
    pact_emit_fn_body((int64_t)(intptr_t)pact_list_get(np_body, node), ret_type);
    cg_indent = (cg_indent - 1);
    pact_emit_line("}");
    pact_emit_line("");
    pact_pop_scope();
    pact_list* closure_lines = cg_lines;
    cg_lines = saved_lines;
    cg_indent = saved_indent;
    cg_temp_counter = saved_temp;
    cg_closure_cap_start = saved_cap_start;
    cg_closure_cap_count = saved_cap_count;
    int64_t ci = 0;
    while ((ci < pact_list_len(closure_lines))) {
        pact_list_push(cg_closure_defs, (void*)(const char*)pact_list_get(closure_lines, ci));
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
                char _si_18[4096];
                snprintf(_si_18, 4096, "pact_%s", sptype);
                sig_params = pact_str_concat(sig_params, strdup(_si_18));
            } else {
                if ((pact_is_struct_type(sptype) != 0)) {
                    char _si_19[4096];
                    snprintf(_si_19, 4096, "pact_%s", sptype);
                    sig_params = pact_str_concat(sig_params, strdup(_si_19));
                } else {
                    sig_params = pact_str_concat(sig_params, pact_c_type_str(pact_type_from_name(sptype)));
                }
            }
            si = (si + 1);
        }
    }
    char _si_20[4096];
    snprintf(_si_20, 4096, "%s(*)(%s)", pact_c_type_str(ret_type), sig_params);
    expr_closure_sig = strdup(_si_20);
    if ((pact_list_len(captures) > 0)) {
        char _si_21[4096];
        snprintf(_si_21, 4096, "__caps_%lld", (long long)closure_idx);
        const char* caps_var = strdup(_si_21);
        char _si_22[4096];
        snprintf(_si_22, 4096, "void** %s = (void**)pact_alloc(sizeof(void*) * %lld);", caps_var, (long long)pact_list_len(captures));
        pact_emit_line(strdup(_si_22));
        int64_t ci2 = 0;
        while ((ci2 < pact_list_len(captures))) {
            pact_CaptureEntry _ub23 = *(pact_CaptureEntry*)pact_list_get(closure_captures, (cap_start + ci2));
            const pact_CaptureEntry cap_e = _ub23;
            if ((cap_e.is_mut != 0)) {
                char _si_24[4096];
                snprintf(_si_24, 4096, "%s[%lld] = (void*)%s_cell;", caps_var, (long long)ci2, cap_e.name);
                pact_emit_line(strdup(_si_24));
            } else if ((cap_e.ctype == CT_INT)) {
                char _si_25[4096];
                snprintf(_si_25, 4096, "%s[%lld] = (void*)(intptr_t)%s;", caps_var, (long long)ci2, cap_e.name);
                pact_emit_line(strdup(_si_25));
            } else {
                if ((cap_e.ctype == CT_FLOAT)) {
                    char _si_26[4096];
                    snprintf(_si_26, 4096, "{double* __fp_%lld_%lld = (double*)pact_alloc(sizeof(double)); *__fp_%lld_%lld = %s; %s[%lld] = (void*)__fp_%lld_%lld;}", (long long)closure_idx, (long long)ci2, (long long)closure_idx, (long long)ci2, cap_e.name, caps_var, (long long)ci2, (long long)closure_idx, (long long)ci2);
                    pact_emit_line(strdup(_si_26));
                } else if ((cap_e.ctype == CT_BOOL)) {
                    char _si_27[4096];
                    snprintf(_si_27, 4096, "%s[%lld] = (void*)(intptr_t)%s;", caps_var, (long long)ci2, cap_e.name);
                    pact_emit_line(strdup(_si_27));
                } else {
                    char _si_28[4096];
                    snprintf(_si_28, 4096, "%s[%lld] = (void*)%s;", caps_var, (long long)ci2, cap_e.name);
                    pact_emit_line(strdup(_si_28));
                }
            }
            ci2 = (ci2 + 1);
        }
        char _si_29[4096];
        snprintf(_si_29, 4096, "pact_closure_new((void*)%s, %s, %lld)", cname, caps_var, (long long)pact_list_len(captures));
        expr_result_str = strdup(_si_29);
    } else {
        char _si_30[4096];
        snprintf(_si_30, 4096, "pact_closure_new((void*)%s, NULL, 0)", cname);
        expr_result_str = strdup(_si_30);
    }
    expr_result_type = CT_CLOSURE;
}

void pact_iter_from_source(const char* obj_str, int64_t obj_type) {
    if ((obj_type == CT_LIST)) {
        int64_t elem_type = pact_get_list_elem_type(obj_str);
        if ((elem_type == (-1))) {
            elem_type = CT_INT;
        }
        pact_ensure_iter_type(elem_type);
        const char* tag = pact_c_type_tag(elem_type);
        const char* li_type = pact_list_iter_c_type(elem_type);
        const char* iter_var = pact_fresh_temp("__src_iter_");
        char _si_0[4096];
        snprintf(_si_0, 4096, "%s %s = pact_list_into_iter_%s(%s);", li_type, iter_var, tag, obj_str);
        pact_emit_line(strdup(_si_0));
        ifs_iter_var = iter_var;
        char _si_1[4096];
        snprintf(_si_1, 4096, "%s_next", li_type);
        ifs_next_fn = strdup(_si_1);
        ifs_elem_type = elem_type;
        ifs_opt_type = pact_option_c_type(elem_type);
    } else {
        ifs_iter_var = obj_str;
        ifs_next_fn = pact_get_var_iter_next_fn(obj_str);
        ifs_elem_type = pact_get_var_iterator_inner(obj_str);
        ifs_opt_type = pact_option_c_type(ifs_elem_type);
    }
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
        const char* variant_enum2 = pact_resolve_variant(name);
        if ((!pact_str_eq(variant_enum2, ""))) {
            if ((pact_is_data_enum(variant_enum2) != 0)) {
                const int64_t tag = pact_get_variant_tag(variant_enum2, name);
                char _si_2[4096];
                snprintf(_si_2, 4096, "(pact_%s){.tag = %lld}", variant_enum2, (long long)tag);
                expr_result_str = strdup(_si_2);
                expr_result_type = CT_INT;
                return;
            }
            char _si_3[4096];
            snprintf(_si_3, 4096, "pact_%s_%s", variant_enum2, name);
            expr_result_str = strdup(_si_3);
            expr_result_type = CT_INT;
            return;
        }
        const int64_t cap_idx = pact_get_capture_index(name);
        if ((cap_idx >= 0)) {
            pact_CaptureEntry _ub4 = *(pact_CaptureEntry*)pact_list_get(closure_captures, (cg_closure_cap_start + cap_idx));
            const pact_CaptureEntry cap_entry = _ub4;
            if ((cap_entry.is_mut != 0)) {
                char _si_5[4096];
                snprintf(_si_5, 4096, "(*%s_cell)", name);
                expr_result_str = strdup(_si_5);
                expr_result_type = cap_entry.ctype;
                return;
            }
            expr_result_str = pact_capture_cast_expr(cap_idx);
            expr_result_type = cap_entry.ctype;
            return;
        }
        if ((pact_is_mut_captured(name) != 0)) {
            char _si_6[4096];
            snprintf(_si_6, 4096, "(*%s_cell)", name);
            expr_result_str = strdup(_si_6);
            expr_result_type = pact_get_var_type(name);
            return;
        }
        const char* alias = pact_get_var_alias(name);
        if ((!pact_str_eq(alias, ""))) {
            expr_result_str = alias;
        } else {
            expr_result_str = name;
        }
        expr_result_type = pact_get_var_type(name);
        if ((expr_result_type == CT_OPTION)) {
            expr_option_inner = pact_get_var_option_inner(name);
        }
        if ((expr_result_type == CT_RESULT)) {
            expr_result_ok_type = pact_get_var_result_ok(name);
            expr_result_err_type = pact_get_var_result_err(name);
        }
        if ((expr_result_type == CT_ITERATOR)) {
            expr_iter_next_fn = pact_get_var_iter_next_fn(name);
        }
        if ((expr_result_type == CT_LIST)) {
            expr_list_elem_type = pact_get_list_elem_type(name);
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
                if ((pact_is_data_enum(obj_name) != 0)) {
                    const int64_t tag = pact_get_variant_tag(obj_name, fa_field);
                    char _si_7[4096];
                    snprintf(_si_7, 4096, "(pact_%s){.tag = %lld}", obj_name, (long long)tag);
                    expr_result_str = strdup(_si_7);
                    expr_result_type = CT_INT;
                    return;
                }
                char _si_8[4096];
                snprintf(_si_8, 4096, "pact_%s_%s", obj_name, fa_field);
                expr_result_str = strdup(_si_8);
                expr_result_type = CT_INT;
                return;
            }
        }
        pact_emit_expr(fa_obj);
        const char* obj_str = expr_result_str;
        char _si_9[4096];
        snprintf(_si_9, 4096, "%s.%s", obj_str, fa_field);
        expr_result_str = strdup(_si_9);
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
            char _si_10[4096];
            snprintf(_si_10, 4096, "pact_str_char_at(%s, %s)", obj_str, idx_str);
            expr_result_str = strdup(_si_10);
            expr_result_type = CT_INT;
        } else {
            char _si_11[4096];
            snprintf(_si_11, 4096, "%s[%s]", obj_str, idx_str);
            expr_result_str = strdup(_si_11);
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
            char _si_12[4096];
            snprintf(_si_12, 4096, "return %s;", val_str);
            pact_emit_line(strdup(_si_12));
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
    if ((kind == pact_NodeKind_HandlerExpr)) {
        pact_emit_handler_expr(node);
        return;
    }
    if ((kind == pact_NodeKind_AwaitExpr)) {
        pact_emit_await_expr(node);
        return;
    }
    if ((kind == pact_NodeKind_AsyncScope)) {
        pact_emit_async_scope(node);
        return;
    }
    if ((kind == pact_NodeKind_ChannelNew)) {
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* cap_str = expr_result_str;
            char _si_13[4096];
            snprintf(_si_13, 4096, "pact_channel_new(%s)", cap_str);
            expr_result_str = strdup(_si_13);
        } else {
            expr_result_str = "pact_channel_new(16)";
        }
        expr_result_type = CT_CHANNEL;
        return;
    }
    expr_result_str = "0";
    expr_result_type = CT_VOID;
}

void pact_emit_handler_expr(int64_t node) {
    const char* effect_name = (const char*)pact_list_get(np_name, node);
    const int64_t methods_sl = (int64_t)(intptr_t)pact_list_get(np_methods, node);
    const int64_t handler_idx = cg_temp_counter;
    cg_temp_counter = (cg_temp_counter + 1);
    const char* vtable_type = "";
    const char* vtable_field = "";
    if (((pact_str_eq(effect_name, "IO") || pact_str_eq(effect_name, "IO.Print")) || pact_str_eq(effect_name, "IO.Log"))) {
        vtable_type = "pact_io_vtable";
        vtable_field = "io";
    } else if (((((pact_str_eq(effect_name, "FS") || pact_str_eq(effect_name, "FS.Read")) || pact_str_eq(effect_name, "FS.Write")) || pact_str_eq(effect_name, "FS.Delete")) || pact_str_eq(effect_name, "FS.Watch"))) {
        vtable_type = "pact_fs_vtable";
        vtable_field = "fs";
    } else {
        if ((((pact_str_eq(effect_name, "DB") || pact_str_eq(effect_name, "DB.Read")) || pact_str_eq(effect_name, "DB.Write")) || pact_str_eq(effect_name, "DB.Admin"))) {
            vtable_type = "pact_db_vtable";
            vtable_field = "db";
        } else if ((((pact_str_eq(effect_name, "Net") || pact_str_eq(effect_name, "Net.Connect")) || pact_str_eq(effect_name, "Net.Listen")) || pact_str_eq(effect_name, "Net.DNS"))) {
            vtable_type = "pact_net_vtable";
            vtable_field = "net";
        } else {
            if (((((pact_str_eq(effect_name, "Crypto") || pact_str_eq(effect_name, "Crypto.Hash")) || pact_str_eq(effect_name, "Crypto.Sign")) || pact_str_eq(effect_name, "Crypto.Encrypt")) || pact_str_eq(effect_name, "Crypto.Decrypt"))) {
                vtable_type = "pact_crypto_vtable";
                vtable_field = "crypto";
            } else if (pact_str_eq(effect_name, "Rand")) {
                vtable_type = "pact_rand_vtable";
                vtable_field = "rand";
            } else {
                if (((pact_str_eq(effect_name, "Time") || pact_str_eq(effect_name, "Time.Read")) || pact_str_eq(effect_name, "Time.Sleep"))) {
                    vtable_type = "pact_time_vtable";
                    vtable_field = "time";
                } else if (((pact_str_eq(effect_name, "Env") || pact_str_eq(effect_name, "Env.Read")) || pact_str_eq(effect_name, "Env.Write"))) {
                    vtable_type = "pact_env_vtable";
                    vtable_field = "env";
                } else {
                    if (((pact_str_eq(effect_name, "Process") || pact_str_eq(effect_name, "Process.Spawn")) || pact_str_eq(effect_name, "Process.Signal"))) {
                        vtable_type = "pact_process_vtable";
                        vtable_field = "process";
                    }
                }
            }
        }
    }
    int64_t is_user_effect = 0;
    if (pact_str_eq(vtable_type, "")) {
        int64_t uei = 0;
        while ((uei < pact_list_len(ue_effects))) {
            pact_UeEffect _ub0 = *(pact_UeEffect*)pact_list_get(ue_effects, uei);
            const pact_UeEffect ue = _ub0;
            char _si_1[4096];
            snprintf(_si_1, 4096, "%s.", ue.name);
            if ((pact_str_eq(effect_name, ue.name) || pact_str_starts_with(effect_name, strdup(_si_1)))) {
                char _si_2[4096];
                snprintf(_si_2, 4096, "pact_ue_%s_vtable", ue.handle);
                vtable_type = strdup(_si_2);
                vtable_field = ue.handle;
                is_user_effect = 1;
                break;
            }
            uei = (uei + 1);
        }
    }
    if (pact_str_eq(vtable_type, "")) {
        char _si_3[4096];
        snprintf(_si_3, 4096, "/* handler for unknown effect: %s */", effect_name);
        pact_emit_line(strdup(_si_3));
        expr_result_str = "0";
        expr_result_type = CT_VOID;
        return;
    }
    char _si_4[4096];
    snprintf(_si_4, 4096, "__handler_%lld_outer", (long long)handler_idx);
    const char* outer_ptr_name = strdup(_si_4);
    char _si_5[4096];
    snprintf(_si_5, 4096, "static %s* %s = NULL;", vtable_type, outer_ptr_name);
    pact_list_push(cg_closure_defs, (void*)strdup(_si_5));
    pact_list_push(cg_closure_defs, (void*)"");
    if (((methods_sl != (-1)) && (pact_sublist_length(methods_sl) > 0))) {
        int64_t mi = 0;
        while ((mi < pact_sublist_length(methods_sl))) {
            const int64_t m = pact_sublist_get(methods_sl, mi);
            const char* mname = (const char*)pact_list_get(np_name, m);
            char _si_6[4096];
            snprintf(_si_6, 4096, "__handler_%lld_%s", (long long)handler_idx, mname);
            const char* static_name = strdup(_si_6);
            const char* param_str = "";
            const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, m);
            if ((params_sl != (-1))) {
                int64_t pi = 0;
                while ((pi < pact_sublist_length(params_sl))) {
                    if ((pi > 0)) {
                        param_str = pact_str_concat(param_str, ", ");
                    }
                    const int64_t p = pact_sublist_get(params_sl, pi);
                    const char* pname = (const char*)pact_list_get(np_name, p);
                    const char* ptype = (const char*)pact_list_get(np_type_name, p);
                    const int64_t ct = pact_type_from_name(ptype);
                    char _si_7[4096];
                    snprintf(_si_7, 4096, "%s %s", pact_c_type_str(ct), pname);
                    param_str = pact_str_concat(param_str, strdup(_si_7));
                    pi = (pi + 1);
                }
            }
            if (pact_str_eq(param_str, "")) {
                param_str = "void";
            }
            const char* ret_str = (const char*)pact_list_get(np_return_type, m);
            const int64_t ret_type = pact_type_from_name(ret_str);
            const char* ret_c = pact_c_type_str(ret_type);
            char _si_8[4096];
            snprintf(_si_8, 4096, "static %s %s(%s) {", ret_c, static_name, param_str);
            const char* fn_line = strdup(_si_8);
            pact_list_push(cg_closure_defs, (void*)fn_line);
            pact_list* saved_lines = cg_lines;
            const int64_t saved_indent = cg_indent;
            const int64_t saved_in_handler = cg_in_handler_body;
            const char* saved_handler_vt = cg_handler_body_vtable_type;
            const char* saved_handler_field = cg_handler_body_field;
            const int64_t saved_handler_ue = cg_handler_body_is_ue;
            const int64_t saved_handler_hidx = cg_handler_body_idx;
            pact_list* _l9 = pact_list_new();
            cg_lines = _l9;
            cg_indent = 1;
            cg_in_handler_body = 1;
            cg_handler_body_vtable_type = vtable_type;
            cg_handler_body_field = vtable_field;
            cg_handler_body_is_ue = is_user_effect;
            cg_handler_body_idx = handler_idx;
            pact_push_scope();
            if ((params_sl != (-1))) {
                int64_t pi = 0;
                while ((pi < pact_sublist_length(params_sl))) {
                    const int64_t p = pact_sublist_get(params_sl, pi);
                    const char* pname = (const char*)pact_list_get(np_name, p);
                    const char* ptype = (const char*)pact_list_get(np_type_name, p);
                    pact_set_var(pname, pact_type_from_name(ptype), 0);
                    pi = (pi + 1);
                }
            }
            pact_emit_fn_body((int64_t)(intptr_t)pact_list_get(np_body, m), ret_type);
            pact_pop_scope();
            int64_t li = 0;
            while ((li < pact_list_len(cg_lines))) {
                pact_list_push(cg_closure_defs, (void*)(const char*)pact_list_get(cg_lines, li));
                li = (li + 1);
            }
            pact_list_push(cg_closure_defs, (void*)"}");
            pact_list_push(cg_closure_defs, (void*)"");
            cg_lines = saved_lines;
            cg_indent = saved_indent;
            cg_in_handler_body = saved_in_handler;
            cg_handler_body_vtable_type = saved_handler_vt;
            cg_handler_body_field = saved_handler_field;
            cg_handler_body_is_ue = saved_handler_ue;
            cg_handler_body_idx = saved_handler_hidx;
            mi = (mi + 1);
        }
    }
    char _si_10[4096];
    snprintf(_si_10, 4096, "__handler_vt_%lld", (long long)handler_idx);
    const char* vt_name = strdup(_si_10);
    if ((is_user_effect != 0)) {
        char _si_11[4096];
        snprintf(_si_11, 4096, "%s = __pact_ue_%s;", outer_ptr_name, vtable_field);
        pact_emit_line(strdup(_si_11));
    } else {
        char _si_12[4096];
        snprintf(_si_12, 4096, "%s = __pact_ctx.%s;", outer_ptr_name, vtable_field);
        pact_emit_line(strdup(_si_12));
    }
    char _si_13[4096];
    snprintf(_si_13, 4096, "%s %s = %s_default;", vtable_type, vt_name, vtable_type);
    pact_emit_line(strdup(_si_13));
    if ((methods_sl != (-1))) {
        int64_t mi = 0;
        while ((mi < pact_sublist_length(methods_sl))) {
            const int64_t m = pact_sublist_get(methods_sl, mi);
            const char* mname = (const char*)pact_list_get(np_name, m);
            char _si_14[4096];
            snprintf(_si_14, 4096, "__handler_%lld_%s", (long long)handler_idx, mname);
            const char* static_name = strdup(_si_14);
            char _si_15[4096];
            snprintf(_si_15, 4096, "%s.%s = %s;", vt_name, mname, static_name);
            pact_emit_line(strdup(_si_15));
            mi = (mi + 1);
        }
    }
    expr_result_str = vt_name;
    expr_result_type = CT_VOID;
    cg_handler_vtable_field = vtable_field;
    cg_handler_is_user_effect = is_user_effect;
}

void pact_emit_async_spawn_closure(int64_t closure_node, int64_t wrapper_idx, const char* wrapper_name, const char* task_fn_name) {
    const int64_t cl_params_sl = (int64_t)(intptr_t)pact_list_get(np_params, closure_node);
    pact_list* captures = pact_analyze_captures((int64_t)(intptr_t)pact_list_get(np_body, closure_node), cl_params_sl);
    const int64_t cap_start = pact_list_len(closure_captures);
    int64_t cap_i = 0;
    while ((cap_i < pact_list_len(captures))) {
        const int64_t cap_ct = pact_get_var_type((const char*)pact_list_get(captures, cap_i));
        int64_t _if_0;
        if ((pact_is_mut_captured((const char*)pact_list_get(captures, cap_i)) != 0)) {
            _if_0 = 1;
        } else {
            _if_0 = 0;
        }
        const int64_t cap_mut = _if_0;
        pact_CaptureEntry _s1 = { .name = (const char*)pact_list_get(captures, cap_i), .ctype = cap_ct, .is_mut = cap_mut };
        pact_CaptureEntry* _box2 = (pact_CaptureEntry*)pact_alloc(sizeof(pact_CaptureEntry));
        *_box2 = _s1;
        pact_list_push(closure_captures, (void*)_box2);
        cap_i = (cap_i + 1);
    }
    pact_ClosureCapInfo _s3 = { .start = cap_start, .count = pact_list_len(captures) };
    pact_ClosureCapInfo* _box4 = (pact_ClosureCapInfo*)pact_alloc(sizeof(pact_ClosureCapInfo));
    *_box4 = _s3;
    pact_list_push(closure_cap_infos, (void*)_box4);
    pact_list_push(cg_closure_defs, (void*)"typedef struct {");
    pact_list_push(cg_closure_defs, (void*)"    pact_handle* handle;");
    if ((pact_list_len(captures) > 0)) {
        pact_list_push(cg_closure_defs, (void*)"    void** captures;");
        pact_list_push(cg_closure_defs, (void*)"    int64_t capture_count;");
    }
    char _si_5[4096];
    snprintf(_si_5, 4096, "} __async_arg_%lld_t;", (long long)wrapper_idx);
    pact_list_push(cg_closure_defs, (void*)strdup(_si_5));
    pact_list_push(cg_closure_defs, (void*)"");
    pact_list* saved_lines = cg_lines;
    const int64_t saved_indent = cg_indent;
    const int64_t saved_temp = cg_temp_counter;
    const int64_t saved_cap_start = cg_closure_cap_start;
    const int64_t saved_cap_count = cg_closure_cap_count;
    pact_list* _l6 = pact_list_new();
    cg_lines = _l6;
    cg_indent = 0;
    cg_temp_counter = 0;
    cg_closure_cap_start = cap_start;
    cg_closure_cap_count = pact_list_len(captures);
    pact_push_scope();
    const char* task_params = "pact_closure* __self";
    char _si_7[4096];
    snprintf(_si_7, 4096, "static int64_t %s(%s) {", task_fn_name, task_params);
    pact_emit_line(strdup(_si_7));
    cg_indent = (cg_indent + 1);
    int64_t mc_i = 0;
    while ((mc_i < pact_list_len(captures))) {
        pact_CaptureEntry _ub8 = *(pact_CaptureEntry*)pact_list_get(closure_captures, (cap_start + mc_i));
        const pact_CaptureEntry mc_e = _ub8;
        if ((mc_e.is_mut != 0)) {
            const char* mc_ts = pact_c_type_str(mc_e.ctype);
            char _si_9[4096];
            snprintf(_si_9, 4096, "%s* %s_cell = (%s*)pact_closure_get_capture(__self, %lld);", mc_ts, mc_e.name, mc_ts, (long long)mc_i);
            pact_emit_line(strdup(_si_9));
        }
        mc_i = (mc_i + 1);
    }
    pact_emit_fn_body((int64_t)(intptr_t)pact_list_get(np_body, closure_node), CT_INT);
    cg_indent = (cg_indent - 1);
    pact_emit_line("}");
    pact_emit_line("");
    pact_pop_scope();
    pact_list* task_lines = cg_lines;
    cg_lines = saved_lines;
    cg_indent = saved_indent;
    cg_temp_counter = saved_temp;
    cg_closure_cap_start = saved_cap_start;
    cg_closure_cap_count = saved_cap_count;
    int64_t tli = 0;
    while ((tli < pact_list_len(task_lines))) {
        pact_list_push(cg_closure_defs, (void*)(const char*)pact_list_get(task_lines, tli));
        tli = (tli + 1);
    }
    char _si_10[4096];
    snprintf(_si_10, 4096, "static void %s(void* __arg) {", wrapper_name);
    pact_list_push(cg_closure_defs, (void*)strdup(_si_10));
    char _si_11[4096];
    snprintf(_si_11, 4096, "    __async_arg_%lld_t* __a = (__async_arg_%lld_t*)__arg;", (long long)wrapper_idx, (long long)wrapper_idx);
    pact_list_push(cg_closure_defs, (void*)strdup(_si_11));
    pact_list_push(cg_closure_defs, (void*)"    pact_handle* __h = __a->handle;");
    if ((pact_list_len(captures) > 0)) {
        pact_list_push(cg_closure_defs, (void*)"    pact_closure __self_data = {NULL, __a->captures, __a->capture_count};");
        char _si_12[4096];
        snprintf(_si_12, 4096, "    int64_t __r = %s(&__self_data);", task_fn_name);
        pact_list_push(cg_closure_defs, (void*)strdup(_si_12));
    } else {
        char _si_13[4096];
        snprintf(_si_13, 4096, "    int64_t __r = %s(NULL);", task_fn_name);
        pact_list_push(cg_closure_defs, (void*)strdup(_si_13));
    }
    pact_list_push(cg_closure_defs, (void*)"    pact_handle_set_result(__h, (void*)(intptr_t)__r);");
    pact_list_push(cg_closure_defs, (void*)"    free(__arg);");
    pact_list_push(cg_closure_defs, (void*)"}");
    pact_list_push(cg_closure_defs, (void*)"");
}

void pact_emit_await_expr(int64_t node) {
    pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_obj, node));
    const char* handle_str = expr_result_str;
    const int64_t handle_type = expr_result_type;
    const int64_t inner_type = pact_get_var_handle_inner(handle_str);
    const char* tmp = pact_fresh_temp("__await_");
    char _si_0[4096];
    snprintf(_si_0, 4096, "void* %s = pact_handle_await(%s);", tmp, handle_str);
    pact_emit_line(strdup(_si_0));
    if ((inner_type == CT_INT)) {
        char _si_1[4096];
        snprintf(_si_1, 4096, "(int64_t)(intptr_t)%s", tmp);
        expr_result_str = strdup(_si_1);
        expr_result_type = CT_INT;
    } else if ((inner_type == CT_STRING)) {
        char _si_2[4096];
        snprintf(_si_2, 4096, "(const char*)%s", tmp);
        expr_result_str = strdup(_si_2);
        expr_result_type = CT_STRING;
    } else {
        if ((inner_type == CT_FLOAT)) {
            char _si_3[4096];
            snprintf(_si_3, 4096, "*(double*)%s", tmp);
            expr_result_str = strdup(_si_3);
            expr_result_type = CT_FLOAT;
        } else if ((inner_type == CT_BOOL)) {
            char _si_4[4096];
            snprintf(_si_4, 4096, "(int)(intptr_t)%s", tmp);
            expr_result_str = strdup(_si_4);
            expr_result_type = CT_BOOL;
        } else {
            char _si_5[4096];
            snprintf(_si_5, 4096, "(int64_t)(intptr_t)%s", tmp);
            expr_result_str = strdup(_si_5);
            expr_result_type = CT_INT;
        }
    }
}

void pact_emit_async_scope(int64_t node) {
    cg_uses_async = 1;
    const int64_t scope_idx = cg_async_scope_counter;
    cg_async_scope_counter = (cg_async_scope_counter + 1);
    char _si_0[4096];
    snprintf(_si_0, 4096, "__scope_handles_%lld", (long long)scope_idx);
    const char* list_name = strdup(_si_0);
    char _si_1[4096];
    snprintf(_si_1, 4096, "pact_list* %s = pact_list_new();", list_name);
    pact_emit_line(strdup(_si_1));
    pact_list_push(cg_async_scope_stack, (void*)list_name);
    pact_emit_block_expr((int64_t)(intptr_t)pact_list_get(np_body, node));
    const char* saved_str = expr_result_str;
    const int64_t saved_type = expr_result_type;
    pact_list_pop(cg_async_scope_stack);
    const char* iter_var = pact_fresh_temp("__si_");
    char _si_2[4096];
    snprintf(_si_2, 4096, "for (int64_t %s = 0; %s < pact_list_len(%s); %s++) {", iter_var, iter_var, list_name, iter_var);
    pact_emit_line(strdup(_si_2));
    cg_indent = (cg_indent + 1);
    const char* handle_var = pact_fresh_temp("__sh_");
    char _si_3[4096];
    snprintf(_si_3, 4096, "pact_handle* %s = (pact_handle*)pact_list_get(%s, %s);", handle_var, list_name, iter_var);
    pact_emit_line(strdup(_si_3));
    char _si_4[4096];
    snprintf(_si_4, 4096, "if (%s->status == PACT_HANDLE_RUNNING) {", handle_var);
    pact_emit_line(strdup(_si_4));
    cg_indent = (cg_indent + 1);
    char _si_5[4096];
    snprintf(_si_5, 4096, "pact_handle_await(%s);", handle_var);
    pact_emit_line(strdup(_si_5));
    cg_indent = (cg_indent - 1);
    pact_emit_line("}");
    cg_indent = (cg_indent - 1);
    pact_emit_line("}");
    char _si_6[4096];
    snprintf(_si_6, 4096, "pact_list_free(%s);", list_name);
    pact_emit_line(strdup(_si_6));
    expr_result_str = saved_str;
    expr_result_type = saved_type;
}

void pact_emit_binop(int64_t node) {
    const char* op = (const char*)pact_list_get(np_op, node);
    if (pact_str_eq(op, "\?\?")) {
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_left, node));
        const char* left_str = expr_result_str;
        const int64_t left_type = expr_result_type;
        const int64_t opt_inner = expr_option_inner;
        if (((((((left_type == CT_BOOL) || (left_type == CT_FLOAT)) || (left_type == CT_STRING)) || (left_type == CT_LIST)) || (left_type == CT_RESULT)) || (left_type == CT_CLOSURE))) {
            char _si_0[4096];
            snprintf(_si_0, 4096, "the \?\? operator requires an Option value but got a non-Option type in function '%s'", cg_current_fn_name);
            pact_diag_error_at("CoalesceRequiresOption", "E0502", strdup(_si_0), node, "");
        }
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_right, node));
        const char* right_str = expr_result_str;
        const int64_t right_type = expr_result_type;
        const char* tmp = pact_fresh_temp("__opt");
        if ((opt_inner >= 0)) {
            const char* opt_c = pact_option_c_type(opt_inner);
            char _si_1[4096];
            snprintf(_si_1, 4096, "%s %s = %s;", opt_c, tmp, left_str);
            pact_emit_line(strdup(_si_1));
        } else {
            char _si_2[4096];
            snprintf(_si_2, 4096, "const int64_t %s = (int64_t)%s;", tmp, left_str);
            pact_emit_line(strdup(_si_2));
        }
        char _si_3[4096];
        snprintf(_si_3, 4096, "(%s.tag == 1 \? %s.value : %s)", tmp, tmp, right_str);
        expr_result_str = strdup(_si_3);
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
        char _si_4[4096];
        snprintf(_si_4, 4096, "pact_str_eq(%s, %s)", left_str, right_str);
        expr_result_str = strdup(_si_4);
        expr_result_type = CT_BOOL;
        return;
    }
    if (((pact_str_eq(op, "!=") && (left_type == CT_STRING)) && (right_type == CT_STRING))) {
        char _si_5[4096];
        snprintf(_si_5, 4096, "(!pact_str_eq(%s, %s))", left_str, right_str);
        expr_result_str = strdup(_si_5);
        expr_result_type = CT_BOOL;
        return;
    }
    if ((pact_str_eq(op, "+") && ((left_type == CT_STRING) || (right_type == CT_STRING)))) {
        char _si_6[4096];
        snprintf(_si_6, 4096, "pact_str_concat(%s, %s)", left_str, right_str);
        expr_result_str = strdup(_si_6);
        expr_result_type = CT_STRING;
        return;
    }
    char _si_7[4096];
    snprintf(_si_7, 4096, "(%s %s %s)", left_str, op, right_str);
    expr_result_str = strdup(_si_7);
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
        if (pact_str_eq(op, "\?")) {
            const char* tmp = pact_fresh_temp("__res");
            if ((operand_type == CT_RESULT)) {
                if ((cg_current_fn_ret != CT_RESULT)) {
                    char _si_2[4096];
                    snprintf(_si_2, 4096, "'\?' operator used in function '%s' which does not return Result", cg_current_fn_name);
                    pact_diag_error_at("QuestionMarkRequiresResult", "E0503", strdup(_si_2), node, "change the return type to Result");
                    expr_result_str = "0";
                    expr_result_type = CT_INT;
                } else {
                    const int64_t rok = expr_result_ok_type;
                    const int64_t rerr = expr_result_err_type;
                    const char* res_c = pact_result_c_type(rok, rerr);
                    char _si_3[4096];
                    snprintf(_si_3, 4096, "%s %s = %s;", res_c, tmp, operand_str);
                    pact_emit_line(strdup(_si_3));
                    char _si_4[4096];
                    snprintf(_si_4, 4096, "if (%s.tag == 1) return (%s){.tag = 1, .err = %s.err};", tmp, res_c, tmp);
                    pact_emit_line(strdup(_si_4));
                    char _si_5[4096];
                    snprintf(_si_5, 4096, "%s.ok", tmp);
                    expr_result_str = strdup(_si_5);
                    expr_result_type = rok;
                }
            } else {
                char _si_6[4096];
                snprintf(_si_6, 4096, "'\?' operator requires a Result value but got a non-Result type in function '%s'", cg_current_fn_name);
                pact_diag_error_at("QuestionMarkRequiresResult", "E0503", strdup(_si_6), node, "");
                expr_result_str = "0";
                expr_result_type = CT_INT;
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
        const int64_t call_line = (int64_t)(intptr_t)pact_list_get(np_line, func_node);
        if (pact_str_eq(fn_name, "assert")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
                pact_emit_expr(pact_sublist_get(args_sl, 0));
                const char* val_str = expr_result_str;
                pact_emit_line("{");
                cg_indent = (cg_indent + 1);
                char _si_0[4096];
                snprintf(_si_0, 4096, "int64_t _val = (int64_t)(%s);", val_str);
                pact_emit_line(strdup(_si_0));
                pact_emit_line("if (!_val) {");
                cg_indent = (cg_indent + 1);
                char _si_1[4096];
                snprintf(_si_1, 4096, "__pact_assert_fail(\"ASSERT FAILED: assertion failed\", %lld);", (long long)call_line);
                pact_emit_line(strdup(_si_1));
                cg_indent = (cg_indent - 1);
                pact_emit_line("}");
                cg_indent = (cg_indent - 1);
                pact_emit_line("}");
            }
            expr_result_str = "";
            expr_result_type = CT_VOID;
            return;
        }
        if (pact_str_eq(fn_name, "debug_assert")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            if ((cg_debug_mode == 0)) {
                expr_result_str = "";
                expr_result_type = CT_VOID;
                return;
            }
            if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
                pact_emit_expr(pact_sublist_get(args_sl, 0));
                const char* cond_str = expr_result_str;
                const char* msg_str = "\"debug assertion failed\"";
                if ((pact_sublist_length(args_sl) >= 2)) {
                    pact_emit_expr(pact_sublist_get(args_sl, 1));
                    msg_str = expr_result_str;
                }
                pact_emit_line("{");
                cg_indent = (cg_indent + 1);
                char _si_2[4096];
                snprintf(_si_2, 4096, "int64_t _dbg_val = (int64_t)(%s);", cond_str);
                pact_emit_line(strdup(_si_2));
                pact_emit_line("if (!_dbg_val) {");
                cg_indent = (cg_indent + 1);
                char _si_3[4096];
                snprintf(_si_3, 4096, "__pact_debug_assert_fail(\"%s\", %lld, \"%s\", \"%s\", %s);", diag_source_file, (long long)call_line, cg_current_fn_name, cond_str, msg_str);
                pact_emit_line(strdup(_si_3));
                cg_indent = (cg_indent - 1);
                pact_emit_line("}");
                cg_indent = (cg_indent - 1);
                pact_emit_line("}");
            }
            expr_result_str = "";
            expr_result_type = CT_VOID;
            return;
        }
        if (pact_str_eq(fn_name, "assert_eq")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            if (((args_sl != (-1)) && (pact_sublist_length(args_sl) >= 2))) {
                pact_emit_expr(pact_sublist_get(args_sl, 0));
                const char* left_str = expr_result_str;
                const int64_t left_type = expr_result_type;
                pact_emit_expr(pact_sublist_get(args_sl, 1));
                const char* right_str = expr_result_str;
                pact_emit_line("{");
                cg_indent = (cg_indent + 1);
                if ((left_type == CT_STRING)) {
                    char _si_4[4096];
                    snprintf(_si_4, 4096, "const char* _left = %s;", left_str);
                    pact_emit_line(strdup(_si_4));
                    char _si_5[4096];
                    snprintf(_si_5, 4096, "const char* _right = %s;", right_str);
                    pact_emit_line(strdup(_si_5));
                    pact_emit_line("if (!pact_str_eq(_left, _right)) {");
                    cg_indent = (cg_indent + 1);
                    const char* msg_tmp1 = pact_fresh_temp("_msg");
                    char _si_6[4096];
                    snprintf(_si_6, 4096, "char %s[512];", msg_tmp1);
                    pact_emit_line(strdup(_si_6));
                    char _si_7[4096];
                    snprintf(_si_7, 4096, "snprintf(%s, 512, \"ASSERT_EQ FAILED: \\\"%%s\\\" != \\\"%%s\\\"\", _left, _right);", msg_tmp1);
                    pact_emit_line(strdup(_si_7));
                    char _si_8[4096];
                    snprintf(_si_8, 4096, "__pact_assert_fail(%s, %lld);", msg_tmp1, (long long)call_line);
                    pact_emit_line(strdup(_si_8));
                    cg_indent = (cg_indent - 1);
                    pact_emit_line("}");
                } else if ((left_type == CT_FLOAT)) {
                    char _si_9[4096];
                    snprintf(_si_9, 4096, "double _left = (double)(%s);", left_str);
                    pact_emit_line(strdup(_si_9));
                    char _si_10[4096];
                    snprintf(_si_10, 4096, "double _right = (double)(%s);", right_str);
                    pact_emit_line(strdup(_si_10));
                    pact_emit_line("if (_left != _right) {");
                    cg_indent = (cg_indent + 1);
                    const char* msg_tmp3 = pact_fresh_temp("_msg");
                    char _si_11[4096];
                    snprintf(_si_11, 4096, "char %s[256];", msg_tmp3);
                    pact_emit_line(strdup(_si_11));
                    char _si_12[4096];
                    snprintf(_si_12, 4096, "snprintf(%s, 256, \"ASSERT_EQ FAILED: %%f != %%f\", _left, _right);", msg_tmp3);
                    pact_emit_line(strdup(_si_12));
                    char _si_13[4096];
                    snprintf(_si_13, 4096, "__pact_assert_fail(%s, %lld);", msg_tmp3, (long long)call_line);
                    pact_emit_line(strdup(_si_13));
                    cg_indent = (cg_indent - 1);
                    pact_emit_line("}");
                } else {
                    char _si_14[4096];
                    snprintf(_si_14, 4096, "int64_t _left = (int64_t)(%s);", left_str);
                    pact_emit_line(strdup(_si_14));
                    char _si_15[4096];
                    snprintf(_si_15, 4096, "int64_t _right = (int64_t)(%s);", right_str);
                    pact_emit_line(strdup(_si_15));
                    pact_emit_line("if (_left != _right) {");
                    cg_indent = (cg_indent + 1);
                    const char* msg_tmp2 = pact_fresh_temp("_msg");
                    char _si_16[4096];
                    snprintf(_si_16, 4096, "char %s[256];", msg_tmp2);
                    pact_emit_line(strdup(_si_16));
                    char _si_17[4096];
                    snprintf(_si_17, 4096, "snprintf(%s, 256, \"ASSERT_EQ FAILED: %%lld != %%lld\", (long long)_left, (long long)_right);", msg_tmp2);
                    pact_emit_line(strdup(_si_17));
                    char _si_18[4096];
                    snprintf(_si_18, 4096, "__pact_assert_fail(%s, %lld);", msg_tmp2, (long long)call_line);
                    pact_emit_line(strdup(_si_18));
                    cg_indent = (cg_indent - 1);
                    pact_emit_line("}");
                }
                cg_indent = (cg_indent - 1);
                pact_emit_line("}");
            }
            expr_result_str = "";
            expr_result_type = CT_VOID;
            return;
        }
        if (pact_str_eq(fn_name, "assert_ne")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            if (((args_sl != (-1)) && (pact_sublist_length(args_sl) >= 2))) {
                pact_emit_expr(pact_sublist_get(args_sl, 0));
                const char* left_str = expr_result_str;
                const int64_t left_type = expr_result_type;
                pact_emit_expr(pact_sublist_get(args_sl, 1));
                const char* right_str = expr_result_str;
                pact_emit_line("{");
                cg_indent = (cg_indent + 1);
                if ((left_type == CT_STRING)) {
                    char _si_19[4096];
                    snprintf(_si_19, 4096, "const char* _left = %s;", left_str);
                    pact_emit_line(strdup(_si_19));
                    char _si_20[4096];
                    snprintf(_si_20, 4096, "const char* _right = %s;", right_str);
                    pact_emit_line(strdup(_si_20));
                    pact_emit_line("if (pact_str_eq(_left, _right)) {");
                    cg_indent = (cg_indent + 1);
                    const char* msg_tmp1 = pact_fresh_temp("_msg");
                    char _si_21[4096];
                    snprintf(_si_21, 4096, "char %s[512];", msg_tmp1);
                    pact_emit_line(strdup(_si_21));
                    char _si_22[4096];
                    snprintf(_si_22, 4096, "snprintf(%s, 512, \"ASSERT_NE FAILED: \\\"%%s\\\" == \\\"%%s\\\"\", _left, _right);", msg_tmp1);
                    pact_emit_line(strdup(_si_22));
                    char _si_23[4096];
                    snprintf(_si_23, 4096, "__pact_assert_fail(%s, %lld);", msg_tmp1, (long long)call_line);
                    pact_emit_line(strdup(_si_23));
                    cg_indent = (cg_indent - 1);
                    pact_emit_line("}");
                } else if ((left_type == CT_FLOAT)) {
                    char _si_24[4096];
                    snprintf(_si_24, 4096, "double _left = (double)(%s);", left_str);
                    pact_emit_line(strdup(_si_24));
                    char _si_25[4096];
                    snprintf(_si_25, 4096, "double _right = (double)(%s);", right_str);
                    pact_emit_line(strdup(_si_25));
                    pact_emit_line("if (_left == _right) {");
                    cg_indent = (cg_indent + 1);
                    const char* msg_tmp3 = pact_fresh_temp("_msg");
                    char _si_26[4096];
                    snprintf(_si_26, 4096, "char %s[256];", msg_tmp3);
                    pact_emit_line(strdup(_si_26));
                    char _si_27[4096];
                    snprintf(_si_27, 4096, "snprintf(%s, 256, \"ASSERT_NE FAILED: %%f == %%f\", _left, _right);", msg_tmp3);
                    pact_emit_line(strdup(_si_27));
                    char _si_28[4096];
                    snprintf(_si_28, 4096, "__pact_assert_fail(%s, %lld);", msg_tmp3, (long long)call_line);
                    pact_emit_line(strdup(_si_28));
                    cg_indent = (cg_indent - 1);
                    pact_emit_line("}");
                } else {
                    char _si_29[4096];
                    snprintf(_si_29, 4096, "int64_t _left = (int64_t)(%s);", left_str);
                    pact_emit_line(strdup(_si_29));
                    char _si_30[4096];
                    snprintf(_si_30, 4096, "int64_t _right = (int64_t)(%s);", right_str);
                    pact_emit_line(strdup(_si_30));
                    pact_emit_line("if (_left == _right) {");
                    cg_indent = (cg_indent + 1);
                    const char* msg_tmp2 = pact_fresh_temp("_msg");
                    char _si_31[4096];
                    snprintf(_si_31, 4096, "char %s[256];", msg_tmp2);
                    pact_emit_line(strdup(_si_31));
                    char _si_32[4096];
                    snprintf(_si_32, 4096, "snprintf(%s, 256, \"ASSERT_NE FAILED: %%lld == %%lld\", (long long)_left, (long long)_right);", msg_tmp2);
                    pact_emit_line(strdup(_si_32));
                    char _si_33[4096];
                    snprintf(_si_33, 4096, "__pact_assert_fail(%s, %lld);", msg_tmp2, (long long)call_line);
                    pact_emit_line(strdup(_si_33));
                    cg_indent = (cg_indent - 1);
                    pact_emit_line("}");
                }
                cg_indent = (cg_indent - 1);
                pact_emit_line("}");
            }
            expr_result_str = "";
            expr_result_type = CT_VOID;
            return;
        }
        const char* variant_enum = pact_resolve_variant(fn_name);
        if (((!pact_str_eq(variant_enum, "")) && (pact_is_data_enum(variant_enum) != 0))) {
            const int64_t vidx = pact_get_variant_index(variant_enum, fn_name);
            const int64_t tag = pact_get_variant_tag(variant_enum, fn_name);
            const int64_t fcount = pact_get_variant_field_count(vidx);
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            char _si_34[4096];
            snprintf(_si_34, 4096, "(pact_%s){.tag = %lld", variant_enum, (long long)tag);
            const char* init_str = strdup(_si_34);
            if (((fcount > 0) && (args_sl != (-1)))) {
                char _si_35[4096];
                snprintf(_si_35, 4096, ", .data.%s = {", fn_name);
                init_str = pact_str_concat(init_str, strdup(_si_35));
                int64_t fi = 0;
                while (((fi < pact_sublist_length(args_sl)) && (fi < fcount))) {
                    if ((fi > 0)) {
                        init_str = pact_str_concat(init_str, ", ");
                    }
                    const char* field_name = pact_get_variant_field_name(vidx, fi);
                    pact_emit_expr(pact_sublist_get(args_sl, fi));
                    const char* arg_str = expr_result_str;
                    char _si_36[4096];
                    snprintf(_si_36, 4096, ".%s = %s", field_name, arg_str);
                    init_str = pact_str_concat(init_str, strdup(_si_36));
                    fi = (fi + 1);
                }
                init_str = pact_str_concat(init_str, "}");
            }
            init_str = pact_str_concat(init_str, "}");
            expr_result_str = init_str;
            expr_result_type = CT_INT;
            return;
        }
        if (pact_str_eq(fn_name, "Some")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
                pact_emit_expr(pact_sublist_get(args_sl, 0));
                const char* inner_str = expr_result_str;
                const int64_t inner_type = expr_result_type;
                pact_ensure_option_type(inner_type);
                const char* opt_type = pact_option_c_type(inner_type);
                char _si_37[4096];
                snprintf(_si_37, 4096, "(%s){.tag = 1, .value = %s}", opt_type, inner_str);
                expr_result_str = strdup(_si_37);
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
                char _si_38[4096];
                snprintf(_si_38, 4096, "(%s){.tag = 0, .ok = %s}", res_type, ok_str);
                expr_result_str = strdup(_si_38);
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
                char _si_39[4096];
                snprintf(_si_39, 4096, "(%s){.tag = 1, .err = %s}", res_type, err_str);
                expr_result_str = strdup(_si_39);
                expr_result_type = CT_RESULT;
                expr_result_ok_type = ok_type;
                expr_result_err_type = err_type;
                return;
            }
        }
        if (pact_str_eq(fn_name, "Map")) {
            expr_result_str = "pact_map_new()";
            expr_result_type = CT_MAP;
            return;
        }
        if (pact_str_eq(fn_name, "Channel")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
                pact_emit_expr(pact_sublist_get(args_sl, 0));
                const char* cap_str = expr_result_str;
                char _si_40[4096];
                snprintf(_si_40, 4096, "pact_channel_new(%s)", cap_str);
                expr_result_str = strdup(_si_40);
            } else {
                expr_result_str = "pact_channel_new(16)";
            }
            expr_result_type = CT_CHANNEL;
            return;
        }
        if (pact_str_eq(fn_name, "get_env")) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
            pact_emit_expr(pact_sublist_get(args_sl, 0));
            const char* arg_str = expr_result_str;
            pact_ensure_option_type(CT_STRING);
            const char* opt_type = pact_option_c_type(CT_STRING);
            const char* tmp = pact_fresh_temp("_env_");
            const char* res = pact_fresh_temp("_env_opt_");
            char _si_41[4096];
            snprintf(_si_41, 4096, "const char* %s = getenv(%s);", tmp, arg_str);
            pact_emit_line(strdup(_si_41));
            char _si_42[4096];
            snprintf(_si_42, 4096, "%s %s = %s \? (%s){.tag = 1, .value = %s} : (%s){.tag = 0};", opt_type, res, tmp, opt_type, tmp, opt_type);
            pact_emit_line(strdup(_si_42));
            expr_result_str = res;
            expr_result_type = CT_OPTION;
            expr_option_inner = CT_STRING;
            return;
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
            char _si_43[4096];
            snprintf(_si_43, 4096, "((%s)%s->fn_ptr)(%s)", closure_sig, fn_name, args_str);
            expr_result_str = strdup(_si_43);
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
        pact_list* _l44 = pact_list_new();
        pact_list* arg_types = _l44;
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
                char _si_45[4096];
                snprintf(_si_45, 4096, "pact_%s(%s)", mangled, args_str);
                expr_result_str = strdup(_si_45);
                expr_result_type = ret_type;
                return;
            }
        }
        if (((pact_is_fn_registered(fn_name) == 0) && (pact_is_generic_fn(fn_name) == 0))) {
            char _si_46[4096];
            snprintf(_si_46, 4096, "undefined function '%s' called in '%s'", fn_name, cg_current_fn_name);
            pact_diag_error_at("UndefinedFunction", "E0504", strdup(_si_46), node, "");
            char _si_47[4096];
            snprintf(_si_47, 4096, "/* undefined: %s */", fn_name);
            pact_emit_line(strdup(_si_47));
            expr_result_str = "0";
            expr_result_type = CT_INT;
            return;
        }
        char _si_48[4096];
        snprintf(_si_48, 4096, "pact_%s(%s)", fn_name, args_str);
        expr_result_str = strdup(_si_48);
        expr_result_type = pact_get_fn_ret(fn_name);
        if ((expr_result_type == CT_VOID)) {
            const char* fn_sret = pact_get_fn_ret_struct(fn_name);
            if ((!pact_str_eq(fn_sret, ""))) {
                const char* s_tmp = pact_fresh_temp("_sr");
                char _si_49[4096];
                snprintf(_si_49, 4096, "pact_%s %s = pact_%s(%s);", fn_sret, s_tmp, fn_name, args_str);
                pact_emit_line(strdup(_si_49));
                pact_set_var_struct(s_tmp, fn_sret);
                expr_result_str = s_tmp;
            }
        }
        pact_RetType _sr50 = pact_get_fn_ret_type(fn_name);
        const pact_RetType rt = _sr50;
        if ((expr_result_type == CT_RESULT)) {
            expr_result_ok_type = rt.inner1;
            expr_result_err_type = rt.inner2;
        }
        if ((expr_result_type == CT_OPTION)) {
            expr_option_inner = rt.inner1;
        }
        if ((expr_result_type == CT_LIST)) {
            expr_list_elem_type = rt.inner1;
        }
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
                        char _si_51[4096];
                        snprintf(_si_51, 4096, "%s_%s", type_name, method);
                        const char* mangled = strdup(_si_51);
                        const char* args_str = first_str;
                        int64_t i = 1;
                        while ((i < pact_sublist_length(args_sl))) {
                            args_str = pact_str_concat(args_str, ", ");
                            pact_emit_expr(pact_sublist_get(args_sl, i));
                            args_str = pact_str_concat(args_str, expr_result_str);
                            i = (i + 1);
                        }
                        char _si_52[4096];
                        snprintf(_si_52, 4096, "pact_%s(%s)", mangled, args_str);
                        expr_result_str = strdup(_si_52);
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
    char _si_53[4096];
    snprintf(_si_53, 4096, "%s(%s)", func_str, args_str);
    expr_result_str = strdup(_si_53);
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
                if ((ch == 63)) {
                    result = pact_str_concat(result, "\\\?");
                } else {
                    result = pact_str_concat(result, pact_str_substr(s, i, 1));
                }
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
                    args = pact_str_concat(args, " \? \"true\" : \"false\"");
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
    int64_t first_elem_type = (-1);
    const char* first_elem_struct = "";
    if ((elems_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(elems_sl))) {
            pact_emit_expr(pact_sublist_get(elems_sl, i));
            const char* e_str = expr_result_str;
            const int64_t e_type = expr_result_type;
            if ((i == 0)) {
                first_elem_type = e_type;
                first_elem_struct = pact_get_var_struct(e_str);
            }
            const char* e_struct = pact_get_var_struct(e_str);
            if (((e_type == CT_VOID) && (!pact_str_eq(e_struct, "")))) {
                const char* box_tmp = pact_fresh_temp("_box");
                char _si_1[4096];
                snprintf(_si_1, 4096, "pact_%s* %s = (pact_%s*)pact_alloc(sizeof(pact_%s));", e_struct, box_tmp, e_struct, e_struct);
                pact_emit_line(strdup(_si_1));
                char _si_2[4096];
                snprintf(_si_2, 4096, "*%s = %s;", box_tmp, e_str);
                pact_emit_line(strdup(_si_2));
                char _si_3[4096];
                snprintf(_si_3, 4096, "pact_list_push(%s, (void*)%s);", tmp, box_tmp);
                pact_emit_line(strdup(_si_3));
            } else if ((e_type == CT_INT)) {
                char _si_4[4096];
                snprintf(_si_4, 4096, "pact_list_push(%s, (void*)(intptr_t)%s);", tmp, e_str);
                pact_emit_line(strdup(_si_4));
            } else {
                if ((e_type == CT_FLOAT)) {
                    const char* box_tmp = pact_fresh_temp("_fbox");
                    char _si_5[4096];
                    snprintf(_si_5, 4096, "double* %s = (double*)pact_alloc(sizeof(double));", box_tmp);
                    pact_emit_line(strdup(_si_5));
                    char _si_6[4096];
                    snprintf(_si_6, 4096, "*%s = %s;", box_tmp, e_str);
                    pact_emit_line(strdup(_si_6));
                    char _si_7[4096];
                    snprintf(_si_7, 4096, "pact_list_push(%s, (void*)%s);", tmp, box_tmp);
                    pact_emit_line(strdup(_si_7));
                } else {
                    char _si_8[4096];
                    snprintf(_si_8, 4096, "pact_list_push(%s, (void*)%s);", tmp, e_str);
                    pact_emit_line(strdup(_si_8));
                }
            }
            i = (i + 1);
        }
    }
    if ((first_elem_type >= 0)) {
        expr_list_elem_type = first_elem_type;
    } else {
        expr_list_elem_type = (-1);
    }
    if ((!pact_str_eq(first_elem_struct, ""))) {
        pact_set_list_elem_type(tmp, CT_VOID);
        pact_set_list_elem_struct(tmp, first_elem_struct);
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

void pact_emit_if_expr(int64_t node) {
    const char* tmp = pact_fresh_temp("_if_");
    const int64_t then_type = pact_infer_block_type((int64_t)(intptr_t)pact_list_get(np_then_body, node));
    if ((then_type == CT_RESULT)) {
        pact_RetType _sr0 = pact_get_fn_ret_type(cg_current_fn_name);
        const pact_RetType rt = _sr0;
        if ((rt.inner1 >= 0)) {
            char _si_1[4096];
            snprintf(_si_1, 4096, "%s %s;", pact_result_c_type(rt.inner1, rt.inner2), tmp);
            pact_emit_line(strdup(_si_1));
        } else {
            char _si_2[4096];
            snprintf(_si_2, 4096, "%s %s;", pact_result_c_type(CT_INT, CT_STRING), tmp);
            pact_emit_line(strdup(_si_2));
        }
    } else if ((then_type == CT_OPTION)) {
        pact_RetType _sr3 = pact_get_fn_ret_type(cg_current_fn_name);
        const pact_RetType rt = _sr3;
        if ((rt.inner1 >= 0)) {
            char _si_4[4096];
            snprintf(_si_4, 4096, "%s %s;", pact_option_c_type(rt.inner1), tmp);
            pact_emit_line(strdup(_si_4));
        } else {
            char _si_5[4096];
            snprintf(_si_5, 4096, "%s %s;", pact_option_c_type(CT_INT), tmp);
            pact_emit_line(strdup(_si_5));
        }
    } else {
        char _si_6[4096];
        snprintf(_si_6, 4096, "%s %s;", pact_c_type_str(then_type), tmp);
        pact_emit_line(strdup(_si_6));
    }
    pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_condition, node));
    const char* cond_str = expr_result_str;
    char _si_7[4096];
    snprintf(_si_7, 4096, "if (%s) {", cond_str);
    pact_emit_line(strdup(_si_7));
    cg_indent = (cg_indent + 1);
    const char* then_val = pact_emit_block_value((int64_t)(intptr_t)pact_list_get(np_then_body, node));
    char _si_8[4096];
    snprintf(_si_8, 4096, "%s = %s;", tmp, then_val);
    pact_emit_line(strdup(_si_8));
    cg_indent = (cg_indent - 1);
    if (((int64_t)(intptr_t)pact_list_get(np_else_body, node) != (-1))) {
        pact_emit_line("} else {");
        cg_indent = (cg_indent + 1);
        const char* else_val = pact_emit_block_value((int64_t)(intptr_t)pact_list_get(np_else_body, node));
        char _si_9[4096];
        snprintf(_si_9, 4096, "%s = %s;", tmp, else_val);
        pact_emit_line(strdup(_si_9));
        cg_indent = (cg_indent - 1);
    }
    pact_emit_line("}");
    pact_set_var(tmp, then_type, 1);
    if ((then_type == CT_RESULT)) {
        pact_RetType _sr10 = pact_get_fn_ret_type(cg_current_fn_name);
        const pact_RetType rt2 = _sr10;
        pact_set_var_result(tmp, rt2.inner1, rt2.inner2);
        expr_result_ok_type = rt2.inner1;
        expr_result_err_type = rt2.inner2;
    }
    if ((then_type == CT_OPTION)) {
        pact_RetType _sr11 = pact_get_fn_ret_type(cg_current_fn_name);
        const pact_RetType rt3 = _sr11;
        pact_set_var_option(tmp, rt3.inner1);
        expr_option_inner = rt3.inner1;
    }
    expr_result_str = tmp;
    expr_result_type = then_type;
}

void pact_emit_match_expr(int64_t node) {
    const int64_t scrut = (int64_t)(intptr_t)pact_list_get(np_scrutinee, node);
    pact_list* _l0 = pact_list_new();
    match_scruts = _l0;
    match_scrut_enum = "";
    if (((int64_t)(intptr_t)pact_list_get(np_kind, scrut) == pact_NodeKind_TupleLit)) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, scrut);
        if ((elems_sl != (-1))) {
            int64_t ei = 0;
            while ((ei < pact_sublist_length(elems_sl))) {
                pact_emit_expr(pact_sublist_get(elems_sl, ei));
                const char* tmp = pact_fresh_temp("_tup_");
                char _si_1[4096];
                snprintf(_si_1, 4096, "%s %s = %s;", pact_c_type_str(expr_result_type), tmp, expr_result_str);
                pact_emit_line(strdup(_si_1));
                pact_set_var(tmp, expr_result_type, 1);
                pact_MatchScrutEntry _s2 = { .str_val = tmp, .scrut_type = expr_result_type };
                pact_MatchScrutEntry* _box3 = (pact_MatchScrutEntry*)pact_alloc(sizeof(pact_MatchScrutEntry));
                *_box3 = _s2;
                pact_list_push(match_scruts, (void*)_box3);
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
        if (((!pact_str_eq(match_scrut_enum, "")) && (pact_is_data_enum(match_scrut_enum) != 0))) {
            const char* scrut_tmp = pact_fresh_temp("_scrut_");
            char _si_4[4096];
            snprintf(_si_4, 4096, "pact_%s %s = %s;", match_scrut_enum, scrut_tmp, expr_result_str);
            pact_emit_line(strdup(_si_4));
            pact_set_var(scrut_tmp, CT_INT, 1);
            pact_MatchScrutEntry _s5 = { .str_val = scrut_tmp, .scrut_type = expr_result_type };
            pact_MatchScrutEntry* _box6 = (pact_MatchScrutEntry*)pact_alloc(sizeof(pact_MatchScrutEntry));
            *_box6 = _s5;
            pact_list_push(match_scruts, (void*)_box6);
        } else {
            pact_MatchScrutEntry _s7 = { .str_val = expr_result_str, .scrut_type = expr_result_type };
            pact_MatchScrutEntry* _box8 = (pact_MatchScrutEntry*)pact_alloc(sizeof(pact_MatchScrutEntry));
            *_box8 = _s7;
            pact_list_push(match_scruts, (void*)_box8);
        }
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
    char _si_9[4096];
    snprintf(_si_9, 4096, "%s %s;", pact_c_type_str(result_type), result_var);
    pact_emit_line(strdup(_si_9));
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
        const char* pat_cond = pact_pattern_condition(pat, 0, pact_list_len(match_scruts));
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
                char _si_10[4096];
                snprintf(_si_10, 4096, "if (!_mg_ && %s) {", pat_cond);
                pact_emit_line(strdup(_si_10));
            } else {
                char _si_11[4096];
                snprintf(_si_11, 4096, "} if (!_mg_ && %s) {", pat_cond);
                pact_emit_line(strdup(_si_11));
            }
            cg_indent = (cg_indent + 1);
            pact_bind_pattern_vars(pat, 0, pact_list_len(match_scruts));
            if ((guard_node != (-1))) {
                pact_emit_expr(guard_node);
                const char* guard_str = expr_result_str;
                char _si_12[4096];
                snprintf(_si_12, 4096, "if (%s) {", guard_str);
                pact_emit_line(strdup(_si_12));
                cg_indent = (cg_indent + 1);
                const char* arm_val = pact_emit_arm_value((int64_t)(intptr_t)pact_list_get(np_body, arm));
                char _si_13[4096];
                snprintf(_si_13, 4096, "%s = %s;", result_var, arm_val);
                pact_emit_line(strdup(_si_13));
                pact_emit_line("_mg_ = 1;");
                cg_indent = (cg_indent - 1);
                pact_emit_line("}");
            } else {
                const char* arm_val = pact_emit_arm_value((int64_t)(intptr_t)pact_list_get(np_body, arm));
                char _si_14[4096];
                snprintf(_si_14, 4096, "%s = %s;", result_var, arm_val);
                pact_emit_line(strdup(_si_14));
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
                char _si_15[4096];
                snprintf(_si_15, 4096, "if (%s) {", pat_cond);
                pact_emit_line(strdup(_si_15));
            } else {
                char _si_16[4096];
                snprintf(_si_16, 4096, "} else if (%s) {", pat_cond);
                pact_emit_line(strdup(_si_16));
            }
            cg_indent = (cg_indent + 1);
            pact_bind_pattern_vars(pat, 0, pact_list_len(match_scruts));
            const char* arm_val = pact_emit_arm_value((int64_t)(intptr_t)pact_list_get(np_body, arm));
            char _si_17[4096];
            snprintf(_si_17, 4096, "%s = %s;", result_var, arm_val);
            pact_emit_line(strdup(_si_17));
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
            if ((pact_is_data_enum(enum_name) != 0)) {
                const int64_t tag = pact_get_variant_tag(enum_name, pat_name);
                char _si_0[4096];
                pact_MatchScrutEntry _ub1 = *(pact_MatchScrutEntry*)pact_list_get(match_scruts, scrut_off);
                snprintf(_si_0, 4096, "(%s.tag == %lld)", _ub1.str_val, (long long)tag);
                return strdup(_si_0);
            }
            char _si_2[4096];
            pact_MatchScrutEntry _ub3 = *(pact_MatchScrutEntry*)pact_list_get(match_scruts, scrut_off);
            snprintf(_si_2, 4096, "(%s == pact_%s_%s)", _ub3.str_val, enum_name, pat_name);
            return strdup(_si_2);
        }
        return "";
    }
    if ((pk == pact_NodeKind_IntPattern)) {
        const char* pat_val = (const char*)pact_list_get(np_str_val, pat);
        char _si_4[4096];
        pact_MatchScrutEntry _ub5 = *(pact_MatchScrutEntry*)pact_list_get(match_scruts, scrut_off);
        snprintf(_si_4, 4096, "(%s == %s)", _ub5.str_val, pat_val);
        return strdup(_si_4);
    }
    if ((pk == pact_NodeKind_StringPattern)) {
        const char* pat_val = (const char*)pact_list_get(np_str_val, pat);
        char _si_6[4096];
        pact_MatchScrutEntry _ub7 = *(pact_MatchScrutEntry*)pact_list_get(match_scruts, scrut_off);
        snprintf(_si_6, 4096, "(pact_str_eq(%s, \"%s\"))", _ub7.str_val, pat_val);
        return strdup(_si_6);
    }
    if ((pk == pact_NodeKind_RangePattern)) {
        const char* lo = (const char*)pact_list_get(np_str_val, pat);
        const char* hi = (const char*)pact_list_get(np_name, pat);
        pact_MatchScrutEntry _ub8 = *(pact_MatchScrutEntry*)pact_list_get(match_scruts, scrut_off);
        const char* scrut = _ub8.str_val;
        if (((int64_t)(intptr_t)pact_list_get(np_inclusive, pat) != 0)) {
            char _si_9[4096];
            snprintf(_si_9, 4096, "(%s >= %s && %s <= %s)", scrut, lo, scrut, hi);
            return strdup(_si_9);
        }
        char _si_10[4096];
        snprintf(_si_10, 4096, "(%s >= %s && %s < %s)", scrut, lo, scrut, hi);
        return strdup(_si_10);
    }
    if ((pk == pact_NodeKind_EnumPattern)) {
        const char* enum_name = (const char*)pact_list_get(np_name, pat);
        const char* variant_name = (const char*)pact_list_get(np_type_name, pat);
        if ((!pact_str_eq(variant_name, ""))) {
            if ((pact_is_data_enum(enum_name) != 0)) {
                const int64_t tag = pact_get_variant_tag(enum_name, variant_name);
                char _si_11[4096];
                pact_MatchScrutEntry _ub12 = *(pact_MatchScrutEntry*)pact_list_get(match_scruts, scrut_off);
                snprintf(_si_11, 4096, "(%s.tag == %lld)", _ub12.str_val, (long long)tag);
                return strdup(_si_11);
            }
            char _si_13[4096];
            pact_MatchScrutEntry _ub14 = *(pact_MatchScrutEntry*)pact_list_get(match_scruts, scrut_off);
            snprintf(_si_13, 4096, "(%s == pact_%s_%s)", _ub14.str_val, enum_name, variant_name);
            return strdup(_si_13);
        }
        const char* pat_name = (const char*)pact_list_get(np_name, pat);
        const char* resolved = pact_resolve_variant(pat_name);
        if (((!pact_str_eq(resolved, "")) && (pact_is_data_enum(resolved) != 0))) {
            const int64_t tag = pact_get_variant_tag(resolved, pat_name);
            char _si_15[4096];
            pact_MatchScrutEntry _ub16 = *(pact_MatchScrutEntry*)pact_list_get(match_scruts, scrut_off);
            snprintf(_si_15, 4096, "(%s.tag == %lld)", _ub16.str_val, (long long)tag);
            return strdup(_si_15);
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
        pact_MatchScrutEntry _ub17 = *(pact_MatchScrutEntry*)pact_list_get(match_scruts, scrut_off);
        const char* scrut = _ub17.str_val;
        int64_t j = 0;
        while ((j < pact_sublist_length(flds_sl))) {
            const int64_t sf = pact_sublist_get(flds_sl, j);
            const char* fname = (const char*)pact_list_get(np_name, sf);
            const int64_t fpat = (int64_t)(intptr_t)pact_list_get(np_pattern, sf);
            if ((fpat != (-1))) {
                pact_list* saved_scruts = match_scruts;
                pact_list* _l18 = pact_list_new();
                char _si_20[4096];
                snprintf(_si_20, 4096, "%s.%s", scrut, fname);
                pact_MatchScrutEntry _s19 = { .str_val = strdup(_si_20), .scrut_type = CT_VOID };
                pact_MatchScrutEntry* _box21 = (pact_MatchScrutEntry*)pact_alloc(sizeof(pact_MatchScrutEntry));
                *_box21 = _s19;
                pact_list_push(_l18, (void*)_box21);
                match_scruts = _l18;
                const char* sub_cond = pact_pattern_condition(fpat, 0, 1);
                match_scruts = saved_scruts;
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
        const char* enum_name = (const char*)pact_list_get(np_name, pat);
        const char* variant_name = (const char*)pact_list_get(np_type_name, pat);
        const int64_t ep_flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, pat);
        const char* resolved_enum = enum_name;
        const char* resolved_variant = variant_name;
        if (pact_str_eq(variant_name, "")) {
            resolved_variant = enum_name;
            resolved_enum = pact_resolve_variant(enum_name);
        }
        if ((((!pact_str_eq(resolved_enum, "")) && (pact_is_data_enum(resolved_enum) != 0)) && (ep_flds_sl != (-1)))) {
            const int64_t vidx = pact_get_variant_index(resolved_enum, resolved_variant);
            if ((vidx >= 0)) {
                const int64_t fcount = pact_get_variant_field_count(vidx);
                pact_MatchScrutEntry _ub0 = *(pact_MatchScrutEntry*)pact_list_get(match_scruts, scrut_off);
                const char* scrut = _ub0.str_val;
                int64_t fi = 0;
                while (((fi < pact_sublist_length(ep_flds_sl)) && (fi < fcount))) {
                    const int64_t sub_pat = pact_sublist_get(ep_flds_sl, fi);
                    const int64_t sub_pk = (int64_t)(intptr_t)pact_list_get(np_kind, sub_pat);
                    const char* field_name = pact_get_variant_field_name(vidx, fi);
                    const char* field_type_name = pact_get_variant_field_type_str(vidx, fi);
                    const int64_t field_ct = pact_type_from_name(field_type_name);
                    if ((sub_pk == pact_NodeKind_IdentPattern)) {
                        const char* bind_name = (const char*)pact_list_get(np_name, sub_pat);
                        if ((!pact_str_eq(bind_name, "_"))) {
                            if ((pact_is_struct_type(field_type_name) != 0)) {
                                char _si_1[4096];
                                snprintf(_si_1, 4096, "pact_%s %s = %s.data.%s.%s;", field_type_name, bind_name, scrut, resolved_variant, field_name);
                                pact_emit_line(strdup(_si_1));
                                pact_set_var(bind_name, CT_VOID, 0);
                                pact_set_var_struct(bind_name, field_type_name);
                            } else if ((pact_is_enum_type(field_type_name) != 0)) {
                                char _si_2[4096];
                                snprintf(_si_2, 4096, "pact_%s %s = %s.data.%s.%s;", field_type_name, bind_name, scrut, resolved_variant, field_name);
                                pact_emit_line(strdup(_si_2));
                                pact_set_var(bind_name, CT_INT, 0);
                                pact_VarEnumEntry _s3 = { .name = bind_name, .enum_type = field_type_name };
                                pact_VarEnumEntry* _box4 = (pact_VarEnumEntry*)pact_alloc(sizeof(pact_VarEnumEntry));
                                *_box4 = _s3;
                                pact_list_push(var_enums, (void*)_box4);
                            } else {
                                char _si_5[4096];
                                snprintf(_si_5, 4096, "%s %s = %s.data.%s.%s;", pact_c_type_str(field_ct), bind_name, scrut, resolved_variant, field_name);
                                pact_emit_line(strdup(_si_5));
                                pact_set_var(bind_name, field_ct, 0);
                            }
                        }
                    } else if ((sub_pk == pact_NodeKind_WildcardPattern)) {
                        const int64_t _skip = 0;
                    } else {
                        pact_list* saved_scruts = match_scruts;
                        pact_list* _l6 = pact_list_new();
                        char _si_8[4096];
                        snprintf(_si_8, 4096, "%s.data.%s.%s", scrut, resolved_variant, field_name);
                        pact_MatchScrutEntry _s7 = { .str_val = strdup(_si_8), .scrut_type = field_ct };
                        pact_MatchScrutEntry* _box9 = (pact_MatchScrutEntry*)pact_alloc(sizeof(pact_MatchScrutEntry));
                        *_box9 = _s7;
                        pact_list_push(_l6, (void*)_box9);
                        match_scruts = _l6;
                        pact_bind_pattern_vars(sub_pat, 0, 1);
                        match_scruts = saved_scruts;
                    }
                    fi = (fi + 1);
                }
            }
        }
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
        pact_MatchScrutEntry _ub10 = *(pact_MatchScrutEntry*)pact_list_get(match_scruts, scrut_off);
        const char* scrut = _ub10.str_val;
        const char* stype_name = (const char*)pact_list_get(np_type_name, pat);
        int64_t j = 0;
        while ((j < pact_sublist_length(flds_sl))) {
            const int64_t sf = pact_sublist_get(flds_sl, j);
            const char* fname = (const char*)pact_list_get(np_name, sf);
            const int64_t fpat = (int64_t)(intptr_t)pact_list_get(np_pattern, sf);
            if ((fpat != (-1))) {
                pact_list* saved_scruts = match_scruts;
                pact_list* _l11 = pact_list_new();
                char _si_13[4096];
                snprintf(_si_13, 4096, "%s.%s", scrut, fname);
                pact_MatchScrutEntry _s12 = { .str_val = strdup(_si_13), .scrut_type = CT_VOID };
                pact_MatchScrutEntry* _box14 = (pact_MatchScrutEntry*)pact_alloc(sizeof(pact_MatchScrutEntry));
                *_box14 = _s12;
                pact_list_push(_l11, (void*)_box14);
                match_scruts = _l11;
                pact_bind_pattern_vars(fpat, 0, 1);
                match_scruts = saved_scruts;
            } else {
                char _si_15[4096];
                snprintf(_si_15, 4096, "__typeof__(%s.%s) %s = %s.%s;", scrut, fname, fname, scrut, fname);
                pact_emit_line(strdup(_si_15));
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
        pact_MatchScrutEntry _ub16 = *(pact_MatchScrutEntry*)pact_list_get(match_scruts, scrut_off);
        const int64_t st = _ub16.scrut_type;
        pact_MatchScrutEntry _ub17 = *(pact_MatchScrutEntry*)pact_list_get(match_scruts, scrut_off);
        const char* scrut_str = _ub17.str_val;
        if ((!pact_str_eq(match_scrut_enum, ""))) {
            char _si_18[4096];
            snprintf(_si_18, 4096, "pact_%s %s = %s;", match_scrut_enum, bind_name, scrut_str);
            pact_emit_line(strdup(_si_18));
            pact_set_var(bind_name, CT_INT, 1);
            pact_VarEnumEntry _s19 = { .name = bind_name, .enum_type = match_scrut_enum };
            pact_VarEnumEntry* _box20 = (pact_VarEnumEntry*)pact_alloc(sizeof(pact_VarEnumEntry));
            *_box20 = _s19;
            pact_list_push(var_enums, (void*)_box20);
        } else {
            char _si_21[4096];
            snprintf(_si_21, 4096, "%s %s = %s;", pact_c_type_str(st), bind_name, scrut_str);
            pact_emit_line(strdup(_si_21));
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
            pact_MatchScrutEntry _ub22 = *(pact_MatchScrutEntry*)pact_list_get(match_scruts, scrut_off);
            const int64_t st = _ub22.scrut_type;
            char _si_23[4096];
            pact_MatchScrutEntry _ub24 = *(pact_MatchScrutEntry*)pact_list_get(match_scruts, scrut_off);
            snprintf(_si_23, 4096, "%s %s = %s;", pact_c_type_str(st), bind_name, _ub24.str_val);
            pact_emit_line(strdup(_si_23));
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
        if (pact_str_eq(iname, "None")) {
            return CT_OPTION;
        }
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
            const char* call_name = (const char*)pact_list_get(np_name, func_node);
            if ((pact_str_eq(call_name, "Ok") || pact_str_eq(call_name, "Err"))) {
                return CT_RESULT;
            }
            if (pact_str_eq(call_name, "Some")) {
                return CT_OPTION;
            }
            return pact_get_fn_ret(call_name);
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
    if ((vk == pact_NodeKind_Call)) {
        const int64_t func = (int64_t)(intptr_t)pact_list_get(np_left, val_node);
        if (((int64_t)(intptr_t)pact_list_get(np_kind, func) == pact_NodeKind_Ident)) {
            const char* fn_name = (const char*)pact_list_get(np_name, func);
            const char* resolved = pact_resolve_variant(fn_name);
            if ((!pact_str_eq(resolved, ""))) {
                return resolved;
            }
        }
    }
    if ((vk == pact_NodeKind_MethodCall)) {
        const int64_t mc_obj = (int64_t)(intptr_t)pact_list_get(np_obj, val_node);
        if (((int64_t)(intptr_t)pact_list_get(np_kind, mc_obj) == pact_NodeKind_Ident)) {
            const char* mc_name = (const char*)pact_list_get(np_name, mc_obj);
            if ((pact_is_enum_type(mc_name) != 0)) {
                return mc_name;
            }
        }
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
    const char* saved_let_target_name = cg_let_target_name;
    if ((type_ann != (-1))) {
        cg_let_target_type = pact_type_from_name((const char*)pact_list_get(np_name, type_ann));
        cg_let_target_name = (const char*)pact_list_get(np_name, type_ann);
    } else {
        cg_let_target_type = 0;
        cg_let_target_name = "";
    }
    pact_emit_expr(val_node);
    cg_let_target_type = saved_let_target;
    cg_let_target_name = saved_let_target_name;
    const char* val_str = expr_result_str;
    const int64_t val_type = expr_result_type;
    const char* name = (const char*)pact_list_get(np_name, node);
    const int64_t is_mut = (int64_t)(intptr_t)pact_list_get(np_is_mut, node);
    pact_set_var(name, val_type, is_mut);
    if ((!pact_str_eq(enum_type, ""))) {
        pact_VarEnumEntry _s0 = { .name = name, .enum_type = enum_type };
        pact_VarEnumEntry* _box1 = (pact_VarEnumEntry*)pact_alloc(sizeof(pact_VarEnumEntry));
        *_box1 = _s0;
        pact_list_push(var_enums, (void*)_box1);
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
    if ((val_type == CT_HANDLE)) {
        const int64_t inner = pact_get_var_handle_inner(val_str);
        if ((inner >= 0)) {
            pact_set_var_handle(name, inner);
        } else {
            pact_set_var_handle(name, CT_INT);
        }
    }
    if ((val_type == CT_CHANNEL)) {
        const int64_t ch_inner = pact_get_var_channel_inner(val_str);
        if ((ch_inner >= 0)) {
            pact_set_var_channel(name, ch_inner);
        } else {
            pact_set_var_channel(name, CT_INT);
        }
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
                const int64_t elem_ct = pact_type_from_name(elem_name);
                pact_set_list_elem_type(name, elem_ct);
                if (((elem_ct == CT_VOID) && (pact_is_struct_type(elem_name) != 0))) {
                    pact_set_list_elem_struct(name, elem_name);
                }
            }
        }
    }
    if (((val_type == CT_MAP) && (type_ann != (-1)))) {
        const char* ann_name = (const char*)pact_list_get(np_name, type_ann);
        if (pact_str_eq(ann_name, "Map")) {
            const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, type_ann);
            if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) >= 2))) {
                const int64_t key_ann = pact_sublist_get(elems_sl, 0);
                const int64_t val_ann = pact_sublist_get(elems_sl, 1);
                const int64_t key_ct = pact_type_from_name((const char*)pact_list_get(np_name, key_ann));
                const int64_t val_ct = pact_type_from_name((const char*)pact_list_get(np_name, val_ann));
                pact_set_map_types(name, key_ct, val_ct);
            }
        }
    }
    if (((val_type == CT_LIST) && (expr_list_elem_type >= 0))) {
        pact_set_list_elem_type(name, expr_list_elem_type);
        expr_list_elem_type = (-1);
        const char* src_struct = pact_get_list_elem_struct(val_str);
        if ((!pact_str_eq(src_struct, ""))) {
            pact_set_list_elem_struct(name, src_struct);
        }
    }
    if ((val_type == CT_ITERATOR)) {
        pact_set_var_alias(name, val_str);
        const int64_t iter_inner = pact_get_var_iterator_inner(val_str);
        const char* iter_next = pact_get_var_iter_next_fn(val_str);
        if ((iter_inner >= 0)) {
            pact_set_var_iterator(name, iter_inner, iter_next);
        }
        return;
    }
    const char* struct_type = pact_get_var_struct(name);
    if ((val_type == CT_OPTION)) {
        const int64_t opt_inner = pact_get_var_option_inner(name);
        const char* opt_c = pact_option_c_type(opt_inner);
        if ((is_mut != 0)) {
            char _si_2[4096];
            snprintf(_si_2, 4096, "%s %s = %s;", opt_c, name, val_str);
            pact_emit_line(strdup(_si_2));
        } else {
            char _si_3[4096];
            snprintf(_si_3, 4096, "const %s %s = %s;", opt_c, name, val_str);
            pact_emit_line(strdup(_si_3));
        }
    } else if ((val_type == CT_RESULT)) {
        const int64_t rok = pact_get_var_result_ok(name);
        const int64_t rerr = pact_get_var_result_err(name);
        const char* res_c = pact_result_c_type(rok, rerr);
        if ((is_mut != 0)) {
            char _si_4[4096];
            snprintf(_si_4, 4096, "%s %s = %s;", res_c, name, val_str);
            pact_emit_line(strdup(_si_4));
        } else {
            char _si_5[4096];
            snprintf(_si_5, 4096, "const %s %s = %s;", res_c, name, val_str);
            pact_emit_line(strdup(_si_5));
        }
    } else {
        if ((!pact_str_eq(enum_type, ""))) {
            if ((is_mut != 0)) {
                char _si_6[4096];
                snprintf(_si_6, 4096, "pact_%s %s = %s;", enum_type, name, val_str);
                pact_emit_line(strdup(_si_6));
            } else {
                char _si_7[4096];
                snprintf(_si_7, 4096, "const pact_%s %s = %s;", enum_type, name, val_str);
                pact_emit_line(strdup(_si_7));
            }
        } else if ((!pact_str_eq(struct_type, ""))) {
            if ((is_mut != 0)) {
                char _si_8[4096];
                snprintf(_si_8, 4096, "pact_%s %s = %s;", struct_type, name, val_str);
                pact_emit_line(strdup(_si_8));
            } else {
                char _si_9[4096];
                snprintf(_si_9, 4096, "const pact_%s %s = %s;", struct_type, name, val_str);
                pact_emit_line(strdup(_si_9));
            }
        } else {
            const char* ts = pact_c_type_str(val_type);
            if (((((((((is_mut != 0) || (val_type == CT_STRING)) || (val_type == CT_LIST)) || (val_type == CT_MAP)) || (val_type == CT_CLOSURE)) || (val_type == CT_ITERATOR)) || (val_type == CT_HANDLE)) || (val_type == CT_CHANNEL))) {
                char _si_10[4096];
                snprintf(_si_10, 4096, "%s %s = %s;", ts, name, val_str);
                pact_emit_line(strdup(_si_10));
            } else {
                char _si_11[4096];
                snprintf(_si_11, 4096, "const %s %s = %s;", ts, name, val_str);
                pact_emit_line(strdup(_si_11));
            }
        }
    }
    if ((pact_is_mut_captured(name) != 0)) {
        const char* cell_type = pact_c_type_str(val_type);
        char _si_12[4096];
        snprintf(_si_12, 4096, "%s* %s_cell = (%s*)pact_alloc(sizeof(%s));", cell_type, name, cell_type, cell_type);
        pact_emit_line(strdup(_si_12));
        char _si_13[4096];
        snprintf(_si_13, 4096, "*%s_cell = %s;", name, name);
        pact_emit_line(strdup(_si_13));
    }
}

void pact_emit_for_in(int64_t node) {
    const char* var_name = (const char*)pact_list_get(np_var_name, node);
    const int64_t iter_node = (int64_t)(intptr_t)pact_list_get(np_iterable, node);
    const int64_t iter_kind = (int64_t)(intptr_t)pact_list_get(np_kind, iter_node);
    if ((iter_kind == pact_NodeKind_RangeLit)) {
        pact_ensure_range_iter();
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_start, iter_node));
        const char* start_str = expr_result_str;
        pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_end, iter_node));
        const char* end_str = expr_result_str;
        const char* incl_val = "0";
        if (((int64_t)(intptr_t)pact_list_get(np_inclusive, iter_node) != 0)) {
            incl_val = "1";
        }
        const char* iter_var = pact_fresh_temp("__iter_");
        const char* next_var = pact_fresh_temp("__next_");
        const char* opt_type = pact_option_c_type(CT_INT);
        char _si_0[4096];
        snprintf(_si_0, 4096, "pact_RangeIterator %s = { .current = %s, .end = %s, .is_inclusive = %s };", iter_var, start_str, end_str, incl_val);
        pact_emit_line(strdup(_si_0));
        pact_emit_line("while (1) {");
        cg_indent = (cg_indent + 1);
        char _si_1[4096];
        snprintf(_si_1, 4096, "%s %s = pact_RangeIterator_next(&%s);", opt_type, next_var, iter_var);
        pact_emit_line(strdup(_si_1));
        char _si_2[4096];
        snprintf(_si_2, 4096, "if (%s.tag == 0) break;", next_var);
        pact_emit_line(strdup(_si_2));
        char _si_3[4096];
        snprintf(_si_3, 4096, "int64_t %s = %s.value;", var_name, next_var);
        pact_emit_line(strdup(_si_3));
        pact_push_scope();
        pact_set_var(var_name, CT_INT, 1);
        pact_emit_block((int64_t)(intptr_t)pact_list_get(np_body, node));
        pact_pop_scope();
        cg_indent = (cg_indent - 1);
        pact_emit_line("}");
    } else {
        pact_emit_expr(iter_node);
        const char* iter_str = expr_result_str;
        const int64_t iter_type = expr_result_type;
        if ((iter_type == CT_LIST)) {
            int64_t elem_type = pact_get_list_elem_type(iter_str);
            if ((elem_type == (-1))) {
                elem_type = CT_INT;
            }
            pact_ensure_iter_type(elem_type);
            const char* tag = pact_c_type_tag(elem_type);
            const char* li_type = pact_list_iter_c_type(elem_type);
            const char* opt_type = pact_option_c_type(elem_type);
            const char* iter_var = pact_fresh_temp("__iter_");
            const char* next_var = pact_fresh_temp("__next_");
            char _si_4[4096];
            snprintf(_si_4, 4096, "%s %s = pact_list_into_iter_%s(%s);", li_type, iter_var, tag, iter_str);
            pact_emit_line(strdup(_si_4));
            pact_emit_line("while (1) {");
            cg_indent = (cg_indent + 1);
            char _si_5[4096];
            snprintf(_si_5, 4096, "%s %s = %s_next(&%s);", opt_type, next_var, li_type, iter_var);
            pact_emit_line(strdup(_si_5));
            char _si_6[4096];
            snprintf(_si_6, 4096, "if (%s.tag == 0) break;", next_var);
            pact_emit_line(strdup(_si_6));
            char _si_7[4096];
            snprintf(_si_7, 4096, "%s %s = %s.value;", pact_c_type_str(elem_type), var_name, next_var);
            pact_emit_line(strdup(_si_7));
            pact_push_scope();
            pact_set_var(var_name, elem_type, 0);
            pact_emit_block((int64_t)(intptr_t)pact_list_get(np_body, node));
            pact_pop_scope();
            cg_indent = (cg_indent - 1);
            pact_emit_line("}");
        } else if ((iter_type == CT_ITERATOR)) {
            const int64_t elem_type = pact_get_var_iterator_inner(iter_str);
            const char* next_fn = pact_get_var_iter_next_fn(iter_str);
            const char* opt_type = pact_option_c_type(elem_type);
            const char* iter_var = pact_fresh_temp("__iter_");
            const char* next_var = pact_fresh_temp("__next_");
            pact_emit_line("while (1) {");
            cg_indent = (cg_indent + 1);
            char _si_8[4096];
            snprintf(_si_8, 4096, "%s %s = ((%s (*)(void*))%s)(&%s);", opt_type, next_var, opt_type, next_fn, iter_str);
            pact_emit_line(strdup(_si_8));
            char _si_9[4096];
            snprintf(_si_9, 4096, "if (%s.tag == 0) break;", next_var);
            pact_emit_line(strdup(_si_9));
            char _si_10[4096];
            snprintf(_si_10, 4096, "%s %s = %s.value;", pact_c_type_str(elem_type), var_name, next_var);
            pact_emit_line(strdup(_si_10));
            pact_push_scope();
            pact_set_var(var_name, elem_type, 0);
            pact_emit_block((int64_t)(intptr_t)pact_list_get(np_body, node));
            pact_pop_scope();
            cg_indent = (cg_indent - 1);
            pact_emit_line("}");
        } else {
            if ((iter_type == CT_CHANNEL)) {
                const int64_t ch_inner = pact_get_var_channel_inner(iter_str);
                const char* recv_tmp = pact_fresh_temp("__chrecv_");
                pact_emit_line("while (1) {");
                cg_indent = (cg_indent + 1);
                char _si_11[4096];
                snprintf(_si_11, 4096, "void* %s = pact_channel_recv(%s);", recv_tmp, iter_str);
                pact_emit_line(strdup(_si_11));
                char _si_12[4096];
                snprintf(_si_12, 4096, "if (%s == NULL) break;", recv_tmp);
                pact_emit_line(strdup(_si_12));
                if ((ch_inner == CT_STRING)) {
                    char _si_13[4096];
                    snprintf(_si_13, 4096, "const char* %s = (const char*)%s;", var_name, recv_tmp);
                    pact_emit_line(strdup(_si_13));
                    pact_push_scope();
                    pact_set_var(var_name, CT_STRING, 0);
                } else {
                    char _si_14[4096];
                    snprintf(_si_14, 4096, "int64_t %s = (int64_t)(intptr_t)%s;", var_name, recv_tmp);
                    pact_emit_line(strdup(_si_14));
                    pact_push_scope();
                    pact_set_var(var_name, CT_INT, 0);
                }
                pact_emit_block((int64_t)(intptr_t)pact_list_get(np_body, node));
                pact_pop_scope();
                cg_indent = (cg_indent - 1);
                pact_emit_line("}");
            } else if ((iter_type == CT_STRING)) {
                pact_ensure_str_iter();
                const char* iter_var = pact_fresh_temp("__str_iter_");
                const char* next_var = pact_fresh_temp("__str_next_");
                const char* opt_type = pact_option_c_type(CT_INT);
                char _si_15[4096];
                snprintf(_si_15, 4096, "pact_StrIterator %s = { .str = %s, .index = 0, .len = pact_str_len(%s) };", iter_var, iter_str, iter_str);
                pact_emit_line(strdup(_si_15));
                pact_emit_line("while (1) {");
                cg_indent = (cg_indent + 1);
                char _si_16[4096];
                snprintf(_si_16, 4096, "%s %s = pact_StrIterator_next(&%s);", opt_type, next_var, iter_var);
                pact_emit_line(strdup(_si_16));
                char _si_17[4096];
                snprintf(_si_17, 4096, "if (%s.tag == 0) break;", next_var);
                pact_emit_line(strdup(_si_17));
                char _si_18[4096];
                snprintf(_si_18, 4096, "int64_t %s = %s.value;", var_name, next_var);
                pact_emit_line(strdup(_si_18));
                pact_push_scope();
                pact_set_var(var_name, CT_INT, 0);
                pact_emit_block((int64_t)(intptr_t)pact_list_get(np_body, node));
                pact_pop_scope();
                cg_indent = (cg_indent - 1);
                pact_emit_line("}");
            } else {
                pact_emit_line("/* unsupported iterable */");
            }
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
                pact_list* saved_lines2 = cg_lines;
                pact_list* _l1 = pact_list_new();
                cg_lines = _l1;
                pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_condition, inner));
                pact_list* hoisted_lines = cg_lines;
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
    pact_list* _l2 = pact_list_new();
    pact_list* saved_fields = _l2;
    pact_list* _l3 = pact_list_new();
    pact_list* saved_temps = _l3;
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
            char _si_4[4096];
            snprintf(_si_4, 4096, "int64_t %s = %s;", tmp, res_str);
            pact_emit_line(strdup(_si_4));
            pact_list_push(emitted_let_names, (void*)binding);
            pact_map_set(emitted_let_set, binding, (void*)(intptr_t)1);
            char _si_5[4096];
            snprintf(_si_5, 4096, "int64_t %s = %s;", binding, tmp);
            pact_emit_line(strdup(_si_5));
            pact_list_push(resource_names, (void*)binding);
            pact_list_push(resource_vars, (void*)tmp);
        } else {
            pact_emit_expr(item);
            const char* handler_str = expr_result_str;
            const char* vtable_field = cg_handler_vtable_field;
            const int64_t is_ue = cg_handler_is_user_effect;
            if ((!pact_str_eq(vtable_field, ""))) {
                const char* save_name = pact_fresh_temp("__saved_");
                if ((is_ue != 0)) {
                    char _si_6[4096];
                    snprintf(_si_6, 4096, "void* %s = (void*)__pact_ue_%s;", save_name, vtable_field);
                    pact_emit_line(strdup(_si_6));
                    char _si_7[4096];
                    snprintf(_si_7, 4096, "__pact_ue_%s = &%s;", vtable_field, handler_str);
                    pact_emit_line(strdup(_si_7));
                } else {
                    char _si_8[4096];
                    snprintf(_si_8, 4096, "void* %s = (void*)__pact_ctx.%s;", save_name, vtable_field);
                    pact_emit_line(strdup(_si_8));
                    char _si_9[4096];
                    snprintf(_si_9, 4096, "__pact_ctx.%s = &%s;", vtable_field, handler_str);
                    pact_emit_line(strdup(_si_9));
                }
                if ((is_ue != 0)) {
                    char _si_10[4096];
                    snprintf(_si_10, 4096, "ue:%s", vtable_field);
                    pact_list_push(saved_fields, (void*)strdup(_si_10));
                } else {
                    pact_list_push(saved_fields, (void*)vtable_field);
                }
                pact_list_push(saved_temps, (void*)save_name);
            } else if ((!pact_str_eq(handler_str, ""))) {
                char _si_11[4096];
                snprintf(_si_11, 4096, "%s;", handler_str);
                pact_emit_line(strdup(_si_11));
            }
        }
        i = (i + 1);
    }
    pact_emit_block(body);
    int64_t ri = (pact_list_len(saved_fields) - 1);
    while ((ri >= 0)) {
        const char* sf = (const char*)pact_list_get(saved_fields, ri);
        const char* st = (const char*)pact_list_get(saved_temps, ri);
        if (pact_str_starts_with(sf, "ue:")) {
            const char* ue_field = pact_str_substr(sf, 3, pact_str_len(sf));
            char _si_12[4096];
            snprintf(_si_12, 4096, "__pact_ue_%s = (void*)%s;", ue_field, st);
            pact_emit_line(strdup(_si_12));
        } else {
            char _si_13[4096];
            snprintf(_si_13, 4096, "__pact_ctx.%s = (void*)%s;", sf, st);
            pact_emit_line(strdup(_si_13));
        }
        ri = (ri - 1);
    }
    int64_t rri = (pact_list_len(resource_names) - 1);
    while ((rri >= 0)) {
        const char* rname = (const char*)pact_list_get(resource_names, rri);
        char _si_14[4096];
        snprintf(_si_14, 4096, "// close resource: %s", rname);
        pact_emit_line(strdup(_si_14));
        char _si_15[4096];
        snprintf(_si_15, 4096, "/* %s.close() -- Closeable trait call */", rname);
        pact_emit_line(strdup(_si_15));
        rri = (rri - 1);
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
    cg_current_fn_ret = ret_type;
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
        const char* resolved = pact_resolve_ret_type_from_ann(fn_node);
        if ((!pact_str_eq(resolved, ""))) {
            char _si_3[4096];
            snprintf(_si_3, 4096, "%s pact_%s(%s)", resolved, mangled, params);
            sig = strdup(_si_3);
        } else {
            char _si_4[4096];
            snprintf(_si_4, 4096, "%s pact_%s(%s)", pact_c_type_str(ret_type), mangled, params);
            sig = strdup(_si_4);
        }
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
                        pact_VarEnumEntry _s5 = { .name = pname, .enum_type = ptype };
                        pact_VarEnumEntry* _box6 = (pact_VarEnumEntry*)pact_alloc(sizeof(pact_VarEnumEntry));
                        *_box6 = _s5;
                        pact_list_push(var_enums, (void*)_box6);
                    }
                    if (pact_str_eq(ptype, "List")) {
                        const int64_t ta = (int64_t)(intptr_t)pact_list_get(np_type_ann, p);
                        if ((ta != (-1))) {
                            const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, ta);
                            if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) > 0))) {
                                const int64_t elem_ann = pact_sublist_get(elems_sl, 0);
                                const char* elem_name = (const char*)pact_list_get(np_name, elem_ann);
                                pact_set_list_elem_type(pname, pact_type_from_name(elem_name));
                            }
                        }
                    }
                    if (pact_str_eq(ptype, "Map")) {
                        const int64_t ta = (int64_t)(intptr_t)pact_list_get(np_type_ann, p);
                        if ((ta != (-1))) {
                            const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, ta);
                            if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) >= 2))) {
                                const int64_t key_ann = pact_sublist_get(elems_sl, 0);
                                const int64_t val_ann = pact_sublist_get(elems_sl, 1);
                                pact_set_map_types(pname, pact_type_from_name((const char*)pact_list_get(np_name, key_ann)), pact_type_from_name((const char*)pact_list_get(np_name, val_ann)));
                            }
                        }
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
    char _si_7[4096];
    snprintf(_si_7, 4096, "%s {", sig);
    pact_emit_line(strdup(_si_7));
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
        if ((pact_is_struct_type(ret_str) != 0)) {
            char _si_1[4096];
            snprintf(_si_1, 4096, "pact_%s pact_%s(%s);", ret_str, name, params);
            pact_emit_line(strdup(_si_1));
        } else {
            const char* resolved = pact_resolve_ret_type_from_ann(fn_node);
            if ((!pact_str_eq(resolved, ""))) {
                char _si_2[4096];
                snprintf(_si_2, 4096, "%s pact_%s(%s);", resolved, name, params);
                pact_emit_line(strdup(_si_2));
            } else {
                const int64_t ret_type = pact_type_from_name(ret_str);
                char _si_3[4096];
                snprintf(_si_3, 4096, "%s pact_%s(%s);", pact_c_type_str(ret_type), name, params);
                pact_emit_line(strdup(_si_3));
            }
        }
    }
}

void pact_emit_fn_def(int64_t fn_node) {
    pact_push_scope();
    cg_temp_counter = 0;
    const char* name = (const char*)pact_list_get(np_name, fn_node);
    cg_current_fn_name = name;
    const char* ret_str = (const char*)pact_list_get(np_return_type, fn_node);
    const int64_t ret_type = pact_type_from_name(ret_str);
    cg_current_fn_ret = ret_type;
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
        } else if ((pact_is_struct_type(ret_str) != 0)) {
            char _si_1[4096];
            snprintf(_si_1, 4096, "pact_%s pact_%s(%s)", ret_str, name, params);
            sig = strdup(_si_1);
        } else {
            const char* resolved = pact_resolve_ret_type_from_ann(fn_node);
            if ((!pact_str_eq(resolved, ""))) {
                char _si_2[4096];
                snprintf(_si_2, 4096, "%s pact_%s(%s)", resolved, name, params);
                sig = strdup(_si_2);
            } else {
                char _si_3[4096];
                snprintf(_si_3, 4096, "%s pact_%s(%s)", pact_c_type_str(ret_type), name, params);
                sig = strdup(_si_3);
            }
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
                    pact_VarEnumEntry _s4 = { .name = pname, .enum_type = ptype };
                    pact_VarEnumEntry* _box5 = (pact_VarEnumEntry*)pact_alloc(sizeof(pact_VarEnumEntry));
                    *_box5 = _s4;
                    pact_list_push(var_enums, (void*)_box5);
                }
                if (pact_str_eq(ptype, "List")) {
                    const int64_t ta = (int64_t)(intptr_t)pact_list_get(np_type_ann, p);
                    if ((ta != (-1))) {
                        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, ta);
                        if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) > 0))) {
                            const int64_t elem_ann = pact_sublist_get(elems_sl, 0);
                            const char* elem_name = (const char*)pact_list_get(np_name, elem_ann);
                            pact_set_list_elem_type(pname, pact_type_from_name(elem_name));
                        }
                    }
                }
                if (pact_str_eq(ptype, "Map")) {
                    const int64_t ta = (int64_t)(intptr_t)pact_list_get(np_type_ann, p);
                    if ((ta != (-1))) {
                        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, ta);
                        if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) >= 2))) {
                            const int64_t key_ann = pact_sublist_get(elems_sl, 0);
                            const int64_t val_ann = pact_sublist_get(elems_sl, 1);
                            pact_set_map_types(pname, pact_type_from_name((const char*)pact_list_get(np_name, key_ann)), pact_type_from_name((const char*)pact_list_get(np_name, val_ann)));
                        }
                    }
                }
            }
            i = (i + 1);
        }
    }
    pact_list* _l6 = pact_list_new();
    mut_captured_vars = _l6;
    pact_prescan_mut_captures((int64_t)(intptr_t)pact_list_get(np_body, fn_node));
    int64_t body_ret = ret_type;
    if ((pact_is_struct_type(ret_str) != 0)) {
        body_ret = CT_INT;
    }
    char _si_7[4096];
    snprintf(_si_7, 4096, "%s {", sig);
    pact_emit_line(strdup(_si_7));
    cg_indent = (cg_indent + 1);
    pact_emit_fn_body((int64_t)(intptr_t)pact_list_get(np_body, fn_node), body_ret);
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
    while ((check < pact_list_len(sf_entries))) {
        pact_StructFieldEntry _ub0 = *(pact_StructFieldEntry*)pact_list_get(sf_entries, check);
        if (pact_str_eq(_ub0.struct_name, mono_name)) {
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
                pact_StructFieldEntry _s1 = { .struct_name = mono_name, .field_name = fname, .field_type = CT_VOID, .stype = resolved };
                pact_StructFieldEntry* _box2 = (pact_StructFieldEntry*)pact_alloc(sizeof(pact_StructFieldEntry));
                *_box2 = _s1;
                pact_list_push(sf_entries, (void*)_box2);
            } else {
                const int64_t ct = pact_type_from_name(resolved);
                pact_StructFieldEntry _s3 = { .struct_name = mono_name, .field_name = fname, .field_type = ct, .stype = "" };
                pact_StructFieldEntry* _box4 = (pact_StructFieldEntry*)pact_alloc(sizeof(pact_StructFieldEntry));
                *_box4 = _s3;
                pact_list_push(sf_entries, (void*)_box4);
            }
        } else {
            pact_StructFieldEntry _s5 = { .struct_name = mono_name, .field_name = fname, .field_type = CT_INT, .stype = "" };
            pact_StructFieldEntry* _box6 = (pact_StructFieldEntry*)pact_alloc(sizeof(pact_StructFieldEntry));
            *_box6 = _s5;
            pact_list_push(sf_entries, (void*)_box6);
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
    pact_map_set(struct_reg_set, c_name, (void*)(intptr_t)1);
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
                pact_StructFieldEntry _s1 = { .struct_name = c_name, .field_name = fname, .field_type = CT_VOID, .stype = resolved };
                pact_StructFieldEntry* _box2 = (pact_StructFieldEntry*)pact_alloc(sizeof(pact_StructFieldEntry));
                *_box2 = _s1;
                pact_list_push(sf_entries, (void*)_box2);
            } else {
                const int64_t ct = pact_type_from_name(resolved);
                char _si_3[4096];
                snprintf(_si_3, 4096, "%s %s;", pact_c_type_str(ct), fname);
                pact_emit_line(strdup(_si_3));
                pact_StructFieldEntry _s4 = { .struct_name = c_name, .field_name = fname, .field_type = ct, .stype = "" };
                pact_StructFieldEntry* _box5 = (pact_StructFieldEntry*)pact_alloc(sizeof(pact_StructFieldEntry));
                *_box5 = _s4;
                pact_list_push(sf_entries, (void*)_box5);
            }
        } else {
            char _si_6[4096];
            snprintf(_si_6, 4096, "int64_t %s;", fname);
            pact_emit_line(strdup(_si_6));
            pact_StructFieldEntry _s7 = { .struct_name = c_name, .field_name = fname, .field_type = CT_INT, .stype = "" };
            pact_StructFieldEntry* _box8 = (pact_StructFieldEntry*)pact_alloc(sizeof(pact_StructFieldEntry));
            *_box8 = _s7;
            pact_list_push(sf_entries, (void*)_box8);
        }
        i = (i + 1);
    }
    cg_indent = (cg_indent - 1);
    char _si_9[4096];
    snprintf(_si_9, 4096, "} pact_%s;", c_name);
    pact_emit_line(strdup(_si_9));
    pact_emit_line("");
}

void pact_emit_all_mono_typedefs(void) {
    int64_t i = 0;
    while ((i < pact_list_len(mono_instances))) {
        pact_MonoInstance _ub0 = *(pact_MonoInstance*)pact_list_get(mono_instances, i);
        const pact_MonoInstance mi = _ub0;
        const int64_t td = pact_find_type_def(mi.base);
        if ((td != (-1))) {
            const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, td);
            if (((flds_sl != (-1)) && (pact_sublist_length(flds_sl) > 0))) {
                if (((int64_t)(intptr_t)pact_list_get(np_kind, pact_sublist_get(flds_sl, 0)) != pact_NodeKind_TypeVariant)) {
                    pact_emit_mono_struct_typedef(mi.base, mi.args);
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
                pact_VarEnumEntry _s4 = { .name = pname, .enum_type = resolved_ptype };
                pact_VarEnumEntry* _box5 = (pact_VarEnumEntry*)pact_alloc(sizeof(pact_VarEnumEntry));
                *_box5 = _s4;
                pact_list_push(var_enums, (void*)_box5);
            }
            if (pact_str_eq(resolved_ptype, "List")) {
                const int64_t ta = (int64_t)(intptr_t)pact_list_get(np_type_ann, p);
                if ((ta != (-1))) {
                    const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, ta);
                    if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) > 0))) {
                        const int64_t elem_ann = pact_sublist_get(elems_sl, 0);
                        const char* elem_name = (const char*)pact_list_get(np_name, elem_ann);
                        pact_set_list_elem_type(pname, pact_type_from_name(elem_name));
                    }
                }
            }
            if (pact_str_eq(resolved_ptype, "Map")) {
                const int64_t ta = (int64_t)(intptr_t)pact_list_get(np_type_ann, p);
                if ((ta != (-1))) {
                    const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, ta);
                    if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) >= 2))) {
                        const int64_t key_ann = pact_sublist_get(elems_sl, 0);
                        const int64_t val_ann = pact_sublist_get(elems_sl, 1);
                        pact_set_map_types(pname, pact_type_from_name((const char*)pact_list_get(np_name, key_ann)), pact_type_from_name((const char*)pact_list_get(np_name, val_ann)));
                    }
                }
            }
            i = (i + 1);
        }
    }
    char _si_6[4096];
    snprintf(_si_6, 4096, "%s pact_%s(%s) {", pact_c_type_str(ret_type), mangled, params_c);
    pact_emit_line(strdup(_si_6));
    cg_indent = (cg_indent + 1);
    pact_emit_fn_body((int64_t)(intptr_t)pact_list_get(np_body, fn_node), ret_type);
    cg_indent = (cg_indent - 1);
    pact_emit_line("}");
    pact_emit_line("");
    pact_pop_scope();
}

void pact_emit_all_mono_fns(void) {
    int64_t i = 0;
    while ((i < pact_list_len(mono_fns))) {
        pact_MonoFnInstance _ub0 = *(pact_MonoFnInstance*)pact_list_get(mono_fns, i);
        const pact_MonoFnInstance mf = _ub0;
        const int64_t fn_node = pact_get_generic_fn_node(mf.base);
        if ((fn_node != (-1))) {
            pact_emit_mono_fn_def(fn_node, mf.args);
        }
        i = (i + 1);
    }
}

void pact_emit_mono_typedefs_from(int64_t start) {
    int64_t i = start;
    while ((i < pact_list_len(mono_instances))) {
        pact_MonoInstance _ub0 = *(pact_MonoInstance*)pact_list_get(mono_instances, i);
        const pact_MonoInstance mi = _ub0;
        const int64_t td = pact_find_type_def(mi.base);
        if ((td != (-1))) {
            const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, td);
            if (((flds_sl != (-1)) && (pact_sublist_length(flds_sl) > 0))) {
                if (((int64_t)(intptr_t)pact_list_get(np_kind, pact_sublist_get(flds_sl, 0)) != pact_NodeKind_TypeVariant)) {
                    pact_emit_mono_struct_typedef(mi.base, mi.args);
                }
            }
        }
        i = (i + 1);
    }
}

void pact_emit_mono_fns_from(int64_t start) {
    int64_t i = start;
    while ((i < pact_list_len(mono_fns))) {
        pact_MonoFnInstance _ub0 = *(pact_MonoFnInstance*)pact_list_get(mono_fns, i);
        const pact_MonoFnInstance mf = _ub0;
        const int64_t fn_node = pact_get_generic_fn_node(mf.base);
        if ((fn_node != (-1))) {
            pact_emit_mono_fn_def(fn_node, mf.args);
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
                pact_StructFieldEntry _s1 = { .struct_name = name, .field_name = fname, .field_type = CT_INT, .stype = "" };
                pact_StructFieldEntry* _box2 = (pact_StructFieldEntry*)pact_alloc(sizeof(pact_StructFieldEntry));
                *_box2 = _s1;
                pact_list_push(sf_entries, (void*)_box2);
            } else if ((pact_is_struct_type(type_name) != 0)) {
                char _si_3[4096];
                snprintf(_si_3, 4096, "pact_%s %s;", type_name, fname);
                pact_emit_line(strdup(_si_3));
                pact_StructFieldEntry _s4 = { .struct_name = name, .field_name = fname, .field_type = CT_VOID, .stype = type_name };
                pact_StructFieldEntry* _box5 = (pact_StructFieldEntry*)pact_alloc(sizeof(pact_StructFieldEntry));
                *_box5 = _s4;
                pact_list_push(sf_entries, (void*)_box5);
            } else {
                const int64_t ct = pact_type_from_name(type_name);
                char _si_6[4096];
                snprintf(_si_6, 4096, "%s %s;", pact_c_type_str(ct), fname);
                pact_emit_line(strdup(_si_6));
                pact_StructFieldEntry _s7 = { .struct_name = name, .field_name = fname, .field_type = ct, .stype = "" };
                pact_StructFieldEntry* _box8 = (pact_StructFieldEntry*)pact_alloc(sizeof(pact_StructFieldEntry));
                *_box8 = _s7;
                pact_list_push(sf_entries, (void*)_box8);
            }
        } else {
            char _si_9[4096];
            snprintf(_si_9, 4096, "int64_t %s;", fname);
            pact_emit_line(strdup(_si_9));
            pact_StructFieldEntry _s10 = { .struct_name = name, .field_name = fname, .field_type = CT_INT, .stype = "" };
            pact_StructFieldEntry* _box11 = (pact_StructFieldEntry*)pact_alloc(sizeof(pact_StructFieldEntry));
            *_box11 = _s10;
            pact_list_push(sf_entries, (void*)_box11);
        }
        i = (i + 1);
    }
    cg_indent = (cg_indent - 1);
    char _si_12[4096];
    snprintf(_si_12, 4096, "} pact_%s;", name);
    pact_emit_line(strdup(_si_12));
    pact_emit_line("");
}

void pact_emit_enum_typedef(int64_t td_node) {
    const char* name = (const char*)pact_list_get(np_name, td_node);
    const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, td_node);
    if ((flds_sl == (-1))) {
        return;
    }
    const int64_t enum_idx = pact_list_len(enum_regs);
    int64_t has_data = 0;
    int64_t i = 0;
    while ((i < pact_sublist_length(flds_sl))) {
        const int64_t v = pact_sublist_get(flds_sl, i);
        const int64_t vflds = (int64_t)(intptr_t)pact_list_get(np_fields, v);
        if (((vflds != (-1)) && (pact_sublist_length(vflds) > 0))) {
            has_data = 1;
        }
        i = (i + 1);
    }
    pact_EnumReg _s0 = { .name = name, .has_data = has_data };
    pact_EnumReg* _box1 = (pact_EnumReg*)pact_alloc(sizeof(pact_EnumReg));
    *_box1 = _s0;
    pact_list_push(enum_regs, (void*)_box1);
    pact_map_set(enum_reg_set, name, (void*)(intptr_t)1);
    i = 0;
    while ((i < pact_sublist_length(flds_sl))) {
        const int64_t v = pact_sublist_get(flds_sl, i);
        const char* vname = (const char*)pact_list_get(np_name, v);
        const int64_t vflds = (int64_t)(intptr_t)pact_list_get(np_fields, v);
        if (((vflds != (-1)) && (pact_sublist_length(vflds) > 0))) {
            const char* field_names = "";
            const char* field_types = "";
            int64_t fi = 0;
            while ((fi < pact_sublist_length(vflds))) {
                const int64_t vf = pact_sublist_get(vflds, fi);
                const char* vf_name = (const char*)pact_list_get(np_name, vf);
                const int64_t vf_type_ann = (int64_t)(intptr_t)pact_list_get(np_value, vf);
                const char* vf_type_name = "Int";
                if ((vf_type_ann != (-1))) {
                    vf_type_name = (const char*)pact_list_get(np_name, vf_type_ann);
                }
                if ((fi > 0)) {
                    field_names = pact_str_concat(field_names, ",");
                    field_types = pact_str_concat(field_types, ",");
                }
                field_names = pact_str_concat(field_names, vf_name);
                field_types = pact_str_concat(field_types, vf_type_name);
                fi = (fi + 1);
            }
            pact_EnumVariant _s2 = { .name = vname, .enum_idx = enum_idx, .field_names = field_names, .field_types = field_types, .field_count = pact_sublist_length(vflds) };
            pact_EnumVariant* _box3 = (pact_EnumVariant*)pact_alloc(sizeof(pact_EnumVariant));
            *_box3 = _s2;
            pact_list_push(enum_variants, (void*)_box3);
        } else {
            pact_EnumVariant _s4 = { .name = vname, .enum_idx = enum_idx, .field_names = "", .field_types = "", .field_count = 0 };
            pact_EnumVariant* _box5 = (pact_EnumVariant*)pact_alloc(sizeof(pact_EnumVariant));
            *_box5 = _s4;
            pact_list_push(enum_variants, (void*)_box5);
        }
        i = (i + 1);
    }
    if ((has_data == 0)) {
        const char* variants_str = "";
        i = 0;
        while ((i < pact_sublist_length(flds_sl))) {
            const int64_t v = pact_sublist_get(flds_sl, i);
            const char* vname = (const char*)pact_list_get(np_name, v);
            if ((i > 0)) {
                variants_str = pact_str_concat(variants_str, ", ");
            }
            char _si_6[4096];
            snprintf(_si_6, 4096, "pact_%s_%s", name, vname);
            variants_str = pact_str_concat(variants_str, strdup(_si_6));
            i = (i + 1);
        }
        char _si_7[4096];
        snprintf(_si_7, 4096, "typedef enum { %s } pact_%s;", variants_str, name);
        pact_emit_line(strdup(_si_7));
        pact_emit_line("");
    } else {
        pact_emit_line("typedef struct {");
        cg_indent = (cg_indent + 1);
        pact_emit_line("int tag;");
        pact_emit_line("union {");
        cg_indent = (cg_indent + 1);
        i = 0;
        while ((i < pact_sublist_length(flds_sl))) {
            const int64_t v = pact_sublist_get(flds_sl, i);
            const char* vname = (const char*)pact_list_get(np_name, v);
            const int64_t vflds = (int64_t)(intptr_t)pact_list_get(np_fields, v);
            if (((vflds != (-1)) && (pact_sublist_length(vflds) > 0))) {
                pact_emit_line("struct {");
                cg_indent = (cg_indent + 1);
                int64_t fi = 0;
                while ((fi < pact_sublist_length(vflds))) {
                    const int64_t vf = pact_sublist_get(vflds, fi);
                    const char* vf_name = (const char*)pact_list_get(np_name, vf);
                    const int64_t vf_type_ann = (int64_t)(intptr_t)pact_list_get(np_value, vf);
                    const char* vf_c_type = "int64_t";
                    if ((vf_type_ann != (-1))) {
                        const char* vf_type_name = (const char*)pact_list_get(np_name, vf_type_ann);
                        if ((pact_is_struct_type(vf_type_name) != 0)) {
                            char _si_8[4096];
                            snprintf(_si_8, 4096, "pact_%s", vf_type_name);
                            vf_c_type = strdup(_si_8);
                        } else if ((pact_is_enum_type(vf_type_name) != 0)) {
                            if ((pact_is_data_enum(vf_type_name) != 0)) {
                                char _si_9[4096];
                                snprintf(_si_9, 4096, "pact_%s", vf_type_name);
                                vf_c_type = strdup(_si_9);
                            } else {
                                char _si_10[4096];
                                snprintf(_si_10, 4096, "pact_%s", vf_type_name);
                                vf_c_type = strdup(_si_10);
                            }
                        } else {
                            vf_c_type = pact_c_type_str(pact_type_from_name(vf_type_name));
                        }
                    }
                    char _si_11[4096];
                    snprintf(_si_11, 4096, "%s %s;", vf_c_type, vf_name);
                    pact_emit_line(strdup(_si_11));
                    fi = (fi + 1);
                }
                cg_indent = (cg_indent - 1);
                char _si_12[4096];
                snprintf(_si_12, 4096, "} %s;", vname);
                pact_emit_line(strdup(_si_12));
            }
            i = (i + 1);
        }
        cg_indent = (cg_indent - 1);
        pact_emit_line("} data;");
        cg_indent = (cg_indent - 1);
        char _si_13[4096];
        snprintf(_si_13, 4096, "} pact_%s;", name);
        pact_emit_line(strdup(_si_13));
        pact_emit_line("");
        i = 0;
        while ((i < pact_sublist_length(flds_sl))) {
            const int64_t v = pact_sublist_get(flds_sl, i);
            const char* vname = (const char*)pact_list_get(np_name, v);
            char _si_14[4096];
            snprintf(_si_14, 4096, "#define pact_%s_%s_TAG %lld", name, vname, (long long)i);
            pact_emit_line(strdup(_si_14));
            i = (i + 1);
        }
        pact_emit_line("");
    }
}

void pact_emit_top_level_let(int64_t node) {
    pact_list* saved_lines = cg_lines;
    pact_list* _l0 = pact_list_new();
    cg_lines = _l0;
    pact_emit_expr((int64_t)(intptr_t)pact_list_get(np_value, node));
    const char* val_str = expr_result_str;
    const int64_t val_type = expr_result_type;
    pact_list* helper_lines = cg_lines;
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
                const int64_t elem_ct = pact_type_from_name(elem_name);
                pact_set_list_elem_type(name, elem_ct);
                if (((elem_ct == CT_VOID) && (pact_is_struct_type(elem_name) != 0))) {
                    pact_set_list_elem_struct(name, elem_name);
                }
            }
        }
    }
    if (((val_type == CT_MAP) && (type_ann != (-1)))) {
        const char* ann_name = (const char*)pact_list_get(np_name, type_ann);
        if (pact_str_eq(ann_name, "Map")) {
            const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, type_ann);
            if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) >= 2))) {
                const int64_t key_ann = pact_sublist_get(elems_sl, 0);
                const int64_t val_ann = pact_sublist_get(elems_sl, 1);
                const int64_t key_ct = pact_type_from_name((const char*)pact_list_get(np_name, key_ann));
                const int64_t val_ct = pact_type_from_name((const char*)pact_list_get(np_name, val_ann));
                pact_set_map_types(name, key_ct, val_ct);
            }
        }
    }
    if (((val_type == CT_LIST) && (expr_list_elem_type >= 0))) {
        pact_set_list_elem_type(name, expr_list_elem_type);
        expr_list_elem_type = (-1);
        const char* src_struct = pact_get_list_elem_struct(val_str);
        if ((!pact_str_eq(src_struct, ""))) {
            pact_set_list_elem_struct(name, src_struct);
        }
    }
    const char* ts = pact_c_type_str(val_type);
    const int needs_init = (((pact_list_len(helper_lines) > 0) || (val_type == CT_LIST)) || (val_type == CT_MAP));
    if (needs_init) {
        char _si_1[4096];
        snprintf(_si_1, 4096, "static %s %s;", ts, name);
        pact_emit_line(strdup(_si_1));
        int64_t hi = 0;
        while ((hi < pact_list_len(helper_lines))) {
            pact_list_push(cg_global_inits, (void*)(const char*)pact_list_get(helper_lines, hi));
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
    scope_vars = _l1;
    pact_list* _l2 = pact_list_new();
    scope_frame_starts = _l2;
    pact_list* _l3 = pact_list_new();
    fn_regs = _l3;
    pact_list* _l4 = pact_list_new();
    fn_ret_structs = _l4;
    pact_list* _l5 = pact_list_new();
    fn_ret_types = _l5;
    pact_list* _l6 = pact_list_new();
    effect_entries = _l6;
    cg_current_fn_name = "";
    cg_current_fn_ret = 0;
    pact_list* _l7 = pact_list_new();
    cg_global_inits = _l7;
    pact_list* _l8 = pact_list_new();
    var_list_elems = _l8;
    pact_list* _l9 = pact_list_new();
    var_list_elem_frame_starts = _l9;
    pact_list* _l10 = pact_list_new();
    struct_reg_names = _l10;
    struct_reg_set = pact_map_new();
    pact_list* _l11 = pact_list_new();
    enum_regs = _l11;
    enum_reg_set = pact_map_new();
    pact_list* _l12 = pact_list_new();
    enum_variants = _l12;
    pact_list* _l13 = pact_list_new();
    var_enums = _l13;
    pact_list* _l14 = pact_list_new();
    fn_enum_rets = _l14;
    pact_list* _l15 = pact_list_new();
    emitted_let_names = _l15;
    emitted_let_set = pact_map_new();
    pact_list* _l16 = pact_list_new();
    emitted_fn_names = _l16;
    emitted_fn_set = pact_map_new();
    pact_list* _l17 = pact_list_new();
    trait_entries = _l17;
    pact_list* _l18 = pact_list_new();
    impl_entries = _l18;
    pact_list* _l19 = pact_list_new();
    from_entries = _l19;
    pact_list* _l20 = pact_list_new();
    tryfrom_entries = _l20;
    pact_list* _l21 = pact_list_new();
    var_structs = _l21;
    pact_list* _l22 = pact_list_new();
    var_struct_frame_starts = _l22;
    pact_list* _l23 = pact_list_new();
    sf_entries = _l23;
    pact_list* _l24 = pact_list_new();
    mono_instances = _l24;
    pact_list* _l25 = pact_list_new();
    cg_closure_defs = _l25;
    cg_closure_counter = 0;
    pact_list* _l26 = pact_list_new();
    var_closures = _l26;
    pact_list* _l27 = pact_list_new();
    var_closure_frame_starts = _l27;
    pact_list* _l28 = pact_list_new();
    generic_fns = _l28;
    pact_list* _l29 = pact_list_new();
    mono_fns = _l29;
    pact_list* _l30 = pact_list_new();
    var_options = _l30;
    pact_list* _l31 = pact_list_new();
    var_option_frame_starts = _l31;
    pact_list* _l32 = pact_list_new();
    var_results = _l32;
    pact_list* _l33 = pact_list_new();
    var_result_frame_starts = _l33;
    pact_list* _l34 = pact_list_new();
    emitted_option_types = _l34;
    emitted_option_set = pact_map_new();
    pact_list* _l35 = pact_list_new();
    emitted_result_types = _l35;
    emitted_result_set = pact_map_new();
    pact_list* _l36 = pact_list_new();
    emitted_iter_types = _l36;
    emitted_iter_set = pact_map_new();
    emitted_range_iter = 0;
    emitted_str_iter = 0;
    pact_list* _l37 = pact_list_new();
    emitted_map_iters = _l37;
    pact_list* _l38 = pact_list_new();
    emitted_filter_iters = _l38;
    pact_list* _l39 = pact_list_new();
    emitted_take_iters = _l39;
    pact_list* _l40 = pact_list_new();
    emitted_skip_iters = _l40;
    pact_list* _l41 = pact_list_new();
    emitted_chain_iters = _l41;
    pact_list* _l42 = pact_list_new();
    emitted_flat_map_iters = _l42;
    pact_list* _l43 = pact_list_new();
    var_iterators = _l43;
    pact_list* _l44 = pact_list_new();
    var_iterator_frame_starts = _l44;
    pact_list* _l45 = pact_list_new();
    var_aliases = _l45;
    pact_list* _l46 = pact_list_new();
    var_alias_frame_starts = _l46;
    pact_list* _l47 = pact_list_new();
    var_handles = _l47;
    pact_list* _l48 = pact_list_new();
    var_handle_frame_starts = _l48;
    pact_list* _l49 = pact_list_new();
    var_channels = _l49;
    pact_list* _l50 = pact_list_new();
    var_channel_frame_starts = _l50;
    cg_let_target_type = 0;
    cg_let_target_name = "";
    cg_handler_vtable_field = "";
    cg_handler_is_user_effect = 0;
    cg_in_handler_body = 0;
    cg_handler_body_vtable_type = "";
    cg_handler_body_field = "";
    cg_handler_body_is_ue = 0;
    cg_handler_body_idx = 0;
    cg_uses_async = 0;
    cg_async_wrapper_counter = 0;
    pact_list* _l51 = pact_list_new();
    cg_async_scope_stack = _l51;
    cg_async_scope_counter = 0;
    pact_list* _l52 = pact_list_new();
    cap_budget_names = _l52;
    cap_budget_active = 0;
    pact_list* _l53 = pact_list_new();
    ue_effects = _l53;
    pact_list* _l54 = pact_list_new();
    ue_methods = _l54;
    pact_push_scope();
    pact_reg_fn("arg_count", CT_INT);
    pact_reg_fn("get_arg", CT_STRING);
    pact_reg_fn("read_file", CT_STRING);
    pact_reg_fn("write_file", CT_VOID);
    pact_reg_fn("file_exists", CT_INT);
    pact_reg_fn("path_join", CT_STRING);
    pact_reg_fn("path_dirname", CT_STRING);
    pact_reg_fn("shell_exec", CT_INT);
    pact_reg_fn("exit", CT_VOID);
    pact_reg_fn("path_basename", CT_STRING);
    pact_reg_fn("is_dir", CT_INT);
    pact_reg_fn("get_env", CT_STRING);
    pact_reg_fn("time_ms", CT_INT);
    pact_reg_fn("unix_socket_listen", CT_INT);
    pact_reg_fn("unix_socket_connect", CT_INT);
    pact_reg_fn("unix_socket_accept", CT_INT);
    pact_reg_fn("unix_socket_close", CT_VOID);
    pact_reg_fn("socket_read_line", CT_STRING);
    pact_reg_fn("socket_write", CT_VOID);
    pact_reg_fn("file_mtime", CT_INT);
    pact_reg_fn("getpid", CT_INT);
    pact_list_push(struct_reg_names, (void*)"ConversionError");
    pact_map_set(struct_reg_set, "ConversionError", (void*)(intptr_t)1);
    pact_StructFieldEntry _s55 = { .struct_name = "ConversionError", .field_name = "message", .field_type = CT_STRING, .stype = "" };
    pact_StructFieldEntry* _box56 = (pact_StructFieldEntry*)pact_alloc(sizeof(pact_StructFieldEntry));
    *_box56 = _s55;
    pact_list_push(sf_entries, (void*)_box56);
    pact_StructFieldEntry _s57 = { .struct_name = "ConversionError", .field_name = "source_type", .field_type = CT_STRING, .stype = "" };
    pact_StructFieldEntry* _box58 = (pact_StructFieldEntry*)pact_alloc(sizeof(pact_StructFieldEntry));
    *_box58 = _s57;
    pact_list_push(sf_entries, (void*)_box58);
    pact_StructFieldEntry _s59 = { .struct_name = "ConversionError", .field_name = "target_type", .field_type = CT_STRING, .stype = "" };
    pact_StructFieldEntry* _box60 = (pact_StructFieldEntry*)pact_alloc(sizeof(pact_StructFieldEntry));
    *_box60 = _s59;
    pact_list_push(sf_entries, (void*)_box60);
    pact_init_builtin_effects();
    pact_TraitEntry _s61 = { .name = "Iterator", .method_sl = (-1) };
    pact_TraitEntry* _box62 = (pact_TraitEntry*)pact_alloc(sizeof(pact_TraitEntry));
    *_box62 = _s61;
    pact_list_push(trait_entries, (void*)_box62);
    pact_TraitEntry _s63 = { .name = "IntoIterator", .method_sl = (-1) };
    pact_TraitEntry* _box64 = (pact_TraitEntry*)pact_alloc(sizeof(pact_TraitEntry));
    *_box64 = _s63;
    pact_list_push(trait_entries, (void*)_box64);
    const int64_t effects_decl_sl = (int64_t)(intptr_t)pact_list_get(np_args, program);
    if ((effects_decl_sl != (-1))) {
        int64_t ei = 0;
        while ((ei < pact_sublist_length(effects_decl_sl))) {
            const int64_t ed = pact_sublist_get(effects_decl_sl, ei);
            const char* eff_name = (const char*)pact_list_get(np_name, ed);
            const int64_t parent_idx = pact_reg_effect(eff_name, (-1));
            const char* handle = "";
            int64_t hi = 0;
            while ((hi < pact_str_len(eff_name))) {
                const int64_t ch = pact_str_char_at(eff_name, hi);
                if ((ch == 65)) {
                    handle = pact_str_concat(handle, "a");
                } else if ((ch == 66)) {
                    handle = pact_str_concat(handle, "b");
                } else {
                    if ((ch == 67)) {
                        handle = pact_str_concat(handle, "c");
                    } else if ((ch == 68)) {
                        handle = pact_str_concat(handle, "d");
                    } else {
                        if ((ch == 69)) {
                            handle = pact_str_concat(handle, "e");
                        } else if ((ch == 70)) {
                            handle = pact_str_concat(handle, "f");
                        } else {
                            if ((ch == 71)) {
                                handle = pact_str_concat(handle, "g");
                            } else if ((ch == 72)) {
                                handle = pact_str_concat(handle, "h");
                            } else {
                                if ((ch == 73)) {
                                    handle = pact_str_concat(handle, "i");
                                } else if ((ch == 74)) {
                                    handle = pact_str_concat(handle, "j");
                                } else {
                                    if ((ch == 75)) {
                                        handle = pact_str_concat(handle, "k");
                                    } else if ((ch == 76)) {
                                        handle = pact_str_concat(handle, "l");
                                    } else {
                                        if ((ch == 77)) {
                                            handle = pact_str_concat(handle, "m");
                                        } else if ((ch == 78)) {
                                            handle = pact_str_concat(handle, "n");
                                        } else {
                                            if ((ch == 79)) {
                                                handle = pact_str_concat(handle, "o");
                                            } else if ((ch == 80)) {
                                                handle = pact_str_concat(handle, "p");
                                            } else {
                                                if ((ch == 81)) {
                                                    handle = pact_str_concat(handle, "q");
                                                } else if ((ch == 82)) {
                                                    handle = pact_str_concat(handle, "r");
                                                } else {
                                                    if ((ch == 83)) {
                                                        handle = pact_str_concat(handle, "s");
                                                    } else if ((ch == 84)) {
                                                        handle = pact_str_concat(handle, "t");
                                                    } else {
                                                        if ((ch == 85)) {
                                                            handle = pact_str_concat(handle, "u");
                                                        } else if ((ch == 86)) {
                                                            handle = pact_str_concat(handle, "v");
                                                        } else {
                                                            if ((ch == 87)) {
                                                                handle = pact_str_concat(handle, "w");
                                                            } else if ((ch == 88)) {
                                                                handle = pact_str_concat(handle, "x");
                                                            } else {
                                                                if ((ch == 89)) {
                                                                    handle = pact_str_concat(handle, "y");
                                                                } else if ((ch == 90)) {
                                                                    handle = pact_str_concat(handle, "z");
                                                                } else {
                                                                    handle = pact_str_concat(handle, pact_str_substr(eff_name, hi, 1));
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                hi = (hi + 1);
            }
            pact_UeEffect _s65 = { .name = eff_name, .handle = handle };
            pact_UeEffect* _box66 = (pact_UeEffect*)pact_alloc(sizeof(pact_UeEffect));
            *_box66 = _s65;
            pact_list_push(ue_effects, (void*)_box66);
            const int64_t children_sl = (int64_t)(intptr_t)pact_list_get(np_elements, ed);
            if ((children_sl != (-1))) {
                int64_t ci = 0;
                while ((ci < pact_sublist_length(children_sl))) {
                    const int64_t child = pact_sublist_get(children_sl, ci);
                    const char* child_name = (const char*)pact_list_get(np_name, child);
                    char _si_67[4096];
                    snprintf(_si_67, 4096, "%s.%s", eff_name, child_name);
                    pact_reg_effect(strdup(_si_67), parent_idx);
                    const int64_t child_ops = (int64_t)(intptr_t)pact_list_get(np_methods, child);
                    if ((child_ops != (-1))) {
                        int64_t oi = 0;
                        while ((oi < pact_sublist_length(child_ops))) {
                            const int64_t op = pact_sublist_get(child_ops, oi);
                            const char* op_name = (const char*)pact_list_get(np_name, op);
                            const char* op_ret = (const char*)pact_list_get(np_return_type, op);
                            const char* op_c_ret = "void";
                            if (pact_str_eq(op_ret, "Int")) {
                                op_c_ret = "int64_t";
                            } else if (pact_str_eq(op_ret, "Str")) {
                                op_c_ret = "const char*";
                            } else {
                                if (pact_str_eq(op_ret, "Float")) {
                                    op_c_ret = "double";
                                } else if (pact_str_eq(op_ret, "Bool")) {
                                    op_c_ret = "int";
                                } else {
                                    if ((!pact_str_eq(op_ret, ""))) {
                                        op_c_ret = "int64_t";
                                    }
                                }
                            }
                            const int64_t op_params_sl = (int64_t)(intptr_t)pact_list_get(np_params, op);
                            const char* op_c_params = "";
                            if ((op_params_sl != (-1))) {
                                int64_t pi = 0;
                                while ((pi < pact_sublist_length(op_params_sl))) {
                                    if ((pi > 0)) {
                                        op_c_params = pact_str_concat(op_c_params, ", ");
                                    }
                                    const int64_t p = pact_sublist_get(op_params_sl, pi);
                                    const char* ptype = (const char*)pact_list_get(np_type_name, p);
                                    const char* pname = (const char*)pact_list_get(np_name, p);
                                    const char* pc = "int64_t";
                                    if (pact_str_eq(ptype, "Str")) {
                                        pc = "const char*";
                                    } else if (pact_str_eq(ptype, "Float")) {
                                        pc = "double";
                                    } else {
                                        if (pact_str_eq(ptype, "Bool")) {
                                            pc = "int";
                                        } else if (pact_str_eq(ptype, "Int")) {
                                            pc = "int64_t";
                                        }
                                    }
                                    char _si_68[4096];
                                    snprintf(_si_68, 4096, "%s %s", pc, pname);
                                    op_c_params = pact_str_concat(op_c_params, strdup(_si_68));
                                    pi = (pi + 1);
                                }
                            }
                            if (pact_str_eq(op_c_params, "")) {
                                op_c_params = "void";
                            }
                            pact_UeMethod _s69 = { .name = op_name, .params = op_c_params, .ret = op_c_ret, .effect_handle = handle };
                            pact_UeMethod* _box70 = (pact_UeMethod*)pact_alloc(sizeof(pact_UeMethod));
                            *_box70 = _s69;
                            pact_list_push(ue_methods, (void*)_box70);
                            oi = (oi + 1);
                        }
                    }
                    ci = (ci + 1);
                }
            }
            ei = (ei + 1);
        }
    }
    const int64_t anns_sl = (int64_t)(intptr_t)pact_list_get(np_handlers, program);
    if ((anns_sl != (-1))) {
        int64_t ai = 0;
        while ((ai < pact_sublist_length(anns_sl))) {
            const int64_t ann = pact_sublist_get(anns_sl, ai);
            const char* ann_name = (const char*)pact_list_get(np_name, ann);
            if (pact_str_eq(ann_name, "capabilities")) {
                cap_budget_active = 1;
                const int64_t ann_args_sl = (int64_t)(intptr_t)pact_list_get(np_args, ann);
                if ((ann_args_sl != (-1))) {
                    int64_t aj = 0;
                    while ((aj < pact_sublist_length(ann_args_sl))) {
                        const int64_t arg_nd = pact_sublist_get(ann_args_sl, aj);
                        pact_list_push(cap_budget_names, (void*)(const char*)pact_list_get(np_name, arg_nd));
                        aj = (aj + 1);
                    }
                }
            }
            ai = (ai + 1);
        }
    }
    pact_list_push(cg_lines, (void*)"#include \"runtime.h\"");
    pact_list_push(cg_lines, (void*)"");
    pact_list_push(cg_lines, (void*)"static pact_ctx __pact_ctx;");
    pact_list_push(cg_lines, (void*)"");
    int64_t uei = 0;
    while ((uei < pact_list_len(ue_effects))) {
        pact_UeEffect _ub71 = *(pact_UeEffect*)pact_list_get(ue_effects, uei);
        const pact_UeEffect ue = _ub71;
        char _si_72[4096];
        snprintf(_si_72, 4096, "pact_ue_%s_vtable", ue.handle);
        const char* vt_type = strdup(_si_72);
        pact_list_push(cg_lines, (void*)"typedef struct {");
        int64_t mi = 0;
        while ((mi < pact_list_len(ue_methods))) {
            pact_UeMethod _ub73 = *(pact_UeMethod*)pact_list_get(ue_methods, mi);
            const pact_UeMethod uem = _ub73;
            if (pact_str_eq(uem.effect_handle, ue.handle)) {
                char _si_74[4096];
                snprintf(_si_74, 4096, "    %s (*%s)(%s);", uem.ret, uem.name, uem.params);
                pact_list_push(cg_lines, (void*)strdup(_si_74));
            }
            mi = (mi + 1);
        }
        char _si_75[4096];
        snprintf(_si_75, 4096, "} %s;", vt_type);
        pact_list_push(cg_lines, (void*)strdup(_si_75));
        pact_list_push(cg_lines, (void*)"");
        mi = 0;
        while ((mi < pact_list_len(ue_methods))) {
            pact_UeMethod _ub76 = *(pact_UeMethod*)pact_list_get(ue_methods, mi);
            const pact_UeMethod uem = _ub76;
            if (pact_str_eq(uem.effect_handle, ue.handle)) {
                char _si_77[4096];
                snprintf(_si_77, 4096, "pact_ue_%s_default_%s", ue.handle, uem.name);
                const char* dfn = strdup(_si_77);
                if (pact_str_eq(uem.ret, "void")) {
                    char _si_78[4096];
                    snprintf(_si_78, 4096, "static void %s(%s) {", dfn, uem.params);
                    pact_list_push(cg_lines, (void*)strdup(_si_78));
                    char _si_79[4096];
                    snprintf(_si_79, 4096, "    fprintf(stderr, \"pact: %s.%s not implemented\\n\");", ue.handle, uem.name);
                    pact_list_push(cg_lines, (void*)strdup(_si_79));
                    pact_list_push(cg_lines, (void*)"}");
                } else if (pact_str_eq(uem.ret, "const char*")) {
                    char _si_80[4096];
                    snprintf(_si_80, 4096, "static const char* %s(%s) {", dfn, uem.params);
                    pact_list_push(cg_lines, (void*)strdup(_si_80));
                    char _si_81[4096];
                    snprintf(_si_81, 4096, "    fprintf(stderr, \"pact: %s.%s not implemented\\n\");", ue.handle, uem.name);
                    pact_list_push(cg_lines, (void*)strdup(_si_81));
                    pact_list_push(cg_lines, (void*)"    return NULL;");
                    pact_list_push(cg_lines, (void*)"}");
                } else {
                    char _si_82[4096];
                    snprintf(_si_82, 4096, "static %s %s(%s) {", uem.ret, dfn, uem.params);
                    pact_list_push(cg_lines, (void*)strdup(_si_82));
                    char _si_83[4096];
                    snprintf(_si_83, 4096, "    fprintf(stderr, \"pact: %s.%s not implemented\\n\");", ue.handle, uem.name);
                    pact_list_push(cg_lines, (void*)strdup(_si_83));
                    pact_list_push(cg_lines, (void*)"    return 0;");
                    pact_list_push(cg_lines, (void*)"}");
                }
                pact_list_push(cg_lines, (void*)"");
            }
            mi = (mi + 1);
        }
        char _si_84[4096];
        snprintf(_si_84, 4096, "static %s %s_default = {", vt_type, vt_type);
        pact_list_push(cg_lines, (void*)strdup(_si_84));
        mi = 0;
        int64_t first_m = 1;
        while ((mi < pact_list_len(ue_methods))) {
            pact_UeMethod _ub85 = *(pact_UeMethod*)pact_list_get(ue_methods, mi);
            const pact_UeMethod uem = _ub85;
            if (pact_str_eq(uem.effect_handle, ue.handle)) {
                if ((first_m == 0)) {
                    pact_list_push(cg_lines, (void*)",");
                }
                char _si_86[4096];
                snprintf(_si_86, 4096, "    pact_ue_%s_default_%s", ue.handle, uem.name);
                pact_list_push(cg_lines, (void*)strdup(_si_86));
                first_m = 0;
            }
            mi = (mi + 1);
        }
        pact_list_push(cg_lines, (void*)"};");
        pact_list_push(cg_lines, (void*)"");
        char _si_87[4096];
        snprintf(_si_87, 4096, "static %s* __pact_ue_%s = &%s_default;", vt_type, ue.handle, vt_type);
        pact_list_push(cg_lines, (void*)strdup(_si_87));
        pact_list_push(cg_lines, (void*)"");
        uei = (uei + 1);
    }
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
                pact_map_set(struct_reg_set, (const char*)pact_list_get(np_name, td), (void*)(intptr_t)1);
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
                pact_map_set(emitted_let_set, let_name, (void*)(intptr_t)1);
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
                pact_GenericFnEntry _s88 = { .name = fn_name, .node = fn_node };
                pact_GenericFnEntry* _box89 = (pact_GenericFnEntry*)pact_alloc(sizeof(pact_GenericFnEntry));
                *_box89 = _s88;
                pact_list_push(generic_fns, (void*)_box89);
            } else if ((pact_is_emitted_fn(fn_name) == 0)) {
                const char* ret_str = (const char*)pact_list_get(np_return_type, fn_node);
                const int64_t fn_eff_sl = (int64_t)(intptr_t)pact_list_get(np_effects, fn_node);
                if ((pact_is_enum_type(ret_str) != 0)) {
                    pact_FnEnumRetEntry _s90 = { .name = fn_name, .enum_type = ret_str };
                    pact_FnEnumRetEntry* _box91 = (pact_FnEnumRetEntry*)pact_alloc(sizeof(pact_FnEnumRetEntry));
                    *_box91 = _s90;
                    pact_list_push(fn_enum_rets, (void*)_box91);
                    pact_reg_fn_with_effects(fn_name, CT_INT, fn_eff_sl);
                } else {
                    pact_reg_fn_with_effects(fn_name, pact_type_from_name(ret_str), fn_eff_sl);
                    if ((pact_is_struct_type(ret_str) != 0)) {
                        pact_reg_fn_struct_ret(fn_name, ret_str);
                    }
                }
                pact_reg_fn_ret_from_ann(fn_name, fn_node);
                pact_check_capabilities_budget(fn_name, fn_eff_sl);
                pact_list_push(emitted_fn_names, (void*)fn_name);
                pact_map_set(emitted_fn_set, fn_name, (void*)(intptr_t)1);
            }
            i = (i + 1);
        }
    }
    const int64_t traits_sl = (int64_t)(intptr_t)pact_list_get(np_arms, program);
    if ((traits_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(traits_sl))) {
            const int64_t tr = pact_sublist_get(traits_sl, i);
            pact_TraitEntry _s92 = { .name = (const char*)pact_list_get(np_name, tr), .method_sl = (int64_t)(intptr_t)pact_list_get(np_methods, tr) };
            pact_TraitEntry* _box93 = (pact_TraitEntry*)pact_alloc(sizeof(pact_TraitEntry));
            *_box93 = _s92;
            pact_list_push(trait_entries, (void*)_box93);
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
            pact_ImplEntry _s94 = { .trait_name = impl_trait, .type_name = impl_type, .methods_sl = (int64_t)(intptr_t)pact_list_get(np_methods, im) };
            pact_ImplEntry* _box95 = (pact_ImplEntry*)pact_alloc(sizeof(pact_ImplEntry));
            *_box95 = _s94;
            pact_list_push(impl_entries, (void*)_box95);
            if (pact_str_eq(impl_trait, "From")) {
                const int64_t trait_tparams = (int64_t)(intptr_t)pact_list_get(np_type_params, im);
                if (((trait_tparams != (-1)) && (pact_sublist_length(trait_tparams) > 0))) {
                    const int64_t src_node = pact_sublist_get(trait_tparams, 0);
                    const char* src_type = (const char*)pact_list_get(np_name, src_node);
                    pact_FromImplEntry _s96 = { .source = src_type, .target = impl_type, .method_sl = (int64_t)(intptr_t)pact_list_get(np_methods, im) };
                    pact_FromImplEntry* _box97 = (pact_FromImplEntry*)pact_alloc(sizeof(pact_FromImplEntry));
                    *_box97 = _s96;
                    pact_list_push(from_entries, (void*)_box97);
                }
            }
            if (pact_str_eq(impl_trait, "TryFrom")) {
                const int64_t trait_tparams = (int64_t)(intptr_t)pact_list_get(np_type_params, im);
                if (((trait_tparams != (-1)) && (pact_sublist_length(trait_tparams) > 0))) {
                    const int64_t src_node = pact_sublist_get(trait_tparams, 0);
                    const char* src_type = (const char*)pact_list_get(np_name, src_node);
                    pact_TryFromImplEntry _s98 = { .source = src_type, .target = impl_type, .method_sl = (int64_t)(intptr_t)pact_list_get(np_methods, im) };
                    pact_TryFromImplEntry* _box99 = (pact_TryFromImplEntry*)pact_alloc(sizeof(pact_TryFromImplEntry));
                    *_box99 = _s98;
                    pact_list_push(tryfrom_entries, (void*)_box99);
                }
            }
            const int64_t methods_sl = (int64_t)(intptr_t)pact_list_get(np_methods, im);
            if ((methods_sl != (-1))) {
                int64_t j = 0;
                while ((j < pact_sublist_length(methods_sl))) {
                    const int64_t m = pact_sublist_get(methods_sl, j);
                    const char* mname = (const char*)pact_list_get(np_name, m);
                    char _si_100[4096];
                    snprintf(_si_100, 4096, "%s_%s", impl_type, mname);
                    const char* mangled = strdup(_si_100);
                    const char* ret_str_raw = (const char*)pact_list_get(np_return_type, m);
                    const char* ret_str = pact_resolve_self_type(ret_str_raw, impl_type);
                    if ((pact_is_enum_type(ret_str) != 0)) {
                        pact_FnEnumRetEntry _s101 = { .name = mangled, .enum_type = ret_str };
                        pact_FnEnumRetEntry* _box102 = (pact_FnEnumRetEntry*)pact_alloc(sizeof(pact_FnEnumRetEntry));
                        *_box102 = _s101;
                        pact_list_push(fn_enum_rets, (void*)_box102);
                        pact_reg_fn(mangled, CT_INT);
                    } else if ((pact_is_struct_type(ret_str) != 0)) {
                        pact_reg_fn(mangled, CT_VOID);
                        pact_reg_fn_struct_ret(mangled, ret_str);
                    } else {
                        pact_reg_fn(mangled, pact_type_from_name(ret_str));
                    }
                    pact_reg_fn_ret_from_ann(mangled, m);
                    j = (j + 1);
                }
            }
            i = (i + 1);
        }
    }
    int64_t into_i = 0;
    while ((into_i < pact_list_len(from_entries))) {
        pact_FromImplEntry _ub103 = *(pact_FromImplEntry*)pact_list_get(from_entries, into_i);
        const pact_FromImplEntry fe = _ub103;
        pact_ImplEntry _s104 = { .trait_name = "Into", .type_name = fe.source, .methods_sl = fe.method_sl };
        pact_ImplEntry* _box105 = (pact_ImplEntry*)pact_alloc(sizeof(pact_ImplEntry));
        *_box105 = _s104;
        pact_list_push(impl_entries, (void*)_box105);
        into_i = (into_i + 1);
    }
    pact_emit_all_option_result_types();
    const int64_t early_option_count = pact_list_len(emitted_option_types);
    const int64_t early_result_count = pact_list_len(emitted_result_types);
    pact_list* _l106 = pact_list_new();
    emitted_fn_names = _l106;
    emitted_fn_set = pact_map_new();
    if ((fns_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(fns_sl))) {
            const int64_t fn_node = pact_sublist_get(fns_sl, i);
            const char* fn_name = (const char*)pact_list_get(np_name, fn_node);
            if (((pact_is_emitted_fn(fn_name) == 0) && (pact_is_generic_fn(fn_name) == 0))) {
                pact_emit_fn_decl(fn_node);
                pact_list_push(emitted_fn_names, (void*)fn_name);
                pact_map_set(emitted_fn_set, fn_name, (void*)(intptr_t)1);
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
                    char _si_107[4096];
                    snprintf(_si_107, 4096, "%s_%s", impl_type, mname);
                    const char* mangled = strdup(_si_107);
                    const char* params = pact_format_impl_params(m, impl_type);
                    const char* enum_ret = pact_get_fn_enum_ret(mangled);
                    if ((!pact_str_eq(enum_ret, ""))) {
                        char _si_108[4096];
                        snprintf(_si_108, 4096, "pact_%s pact_%s(%s);", enum_ret, mangled, params);
                        pact_emit_line(strdup(_si_108));
                    } else {
                        const char* ret_str_raw = (const char*)pact_list_get(np_return_type, m);
                        const char* ret_str = pact_resolve_self_type(ret_str_raw, impl_type);
                        if ((pact_is_struct_type(ret_str) != 0)) {
                            char _si_109[4096];
                            snprintf(_si_109, 4096, "pact_%s pact_%s(%s);", ret_str, mangled, params);
                            pact_emit_line(strdup(_si_109));
                        } else {
                            const char* resolved = pact_resolve_ret_type_from_ann(m);
                            if ((!pact_str_eq(resolved, ""))) {
                                char _si_110[4096];
                                snprintf(_si_110, 4096, "%s pact_%s(%s);", resolved, mangled, params);
                                pact_emit_line(strdup(_si_110));
                            } else {
                                const int64_t ret_type = pact_type_from_name(ret_str);
                                char _si_111[4096];
                                snprintf(_si_111, 4096, "%s pact_%s(%s);", pact_c_type_str(ret_type), mangled, params);
                                pact_emit_line(strdup(_si_111));
                            }
                        }
                    }
                    j = (j + 1);
                }
            }
            i = (i + 1);
        }
    }
    pact_emit_line("");
    pact_list* pre_fn_lines = cg_lines;
    pact_list* _l112 = pact_list_new();
    cg_lines = _l112;
    pact_list* _l113 = pact_list_new();
    emitted_fn_names = _l113;
    emitted_fn_set = pact_map_new();
    if ((fns_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(fns_sl))) {
            const int64_t fn_node = pact_sublist_get(fns_sl, i);
            const char* fn_name = (const char*)pact_list_get(np_name, fn_node);
            if (((pact_is_emitted_fn(fn_name) == 0) && (pact_is_generic_fn(fn_name) == 0))) {
                pact_emit_fn_def(fn_node);
                pact_emit_line("");
                pact_list_push(emitted_fn_names, (void*)fn_name);
                pact_map_set(emitted_fn_set, fn_name, (void*)(intptr_t)1);
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
    pact_list* fn_def_lines = cg_lines;
    cg_lines = pre_fn_lines;
    pact_emit_all_mono_typedefs();
    pact_emit_option_result_types_from(early_option_count, early_result_count);
    pact_emit_all_iter_types();
    pact_emit_all_mono_fns();
    if ((pact_list_len(cg_closure_defs) > 0)) {
        int64_t ci = 0;
        while ((ci < pact_list_len(cg_closure_defs))) {
            pact_list_push(cg_lines, (void*)(const char*)pact_list_get(cg_closure_defs, ci));
            ci = (ci + 1);
        }
    }
    if ((cg_uses_async != 0)) {
        pact_emit_line("static pact_threadpool* __pact_pool;");
        pact_emit_line("");
    }
    int64_t fi = 0;
    while ((fi < pact_list_len(fn_def_lines))) {
        pact_list_push(cg_lines, (void*)(const char*)pact_list_get(fn_def_lines, fi));
        fi = (fi + 1);
    }
    const int64_t tests_sl = (int64_t)(intptr_t)pact_list_get(np_captures, program);
    pact_list* _l114 = pact_list_new();
    pact_list* test_names = _l114;
    pact_list* _l115 = pact_list_new();
    pact_list* test_c_names = _l115;
    pact_list* _l116 = pact_list_new();
    pact_list* test_all_tags = _l116;
    pact_list* _l117 = pact_list_new();
    pact_list* test_tag_offsets = _l117;
    pact_list* _l118 = pact_list_new();
    pact_list* test_tag_counts = _l118;
    pact_list* pre_test_lines = cg_lines;
    const int64_t pre_test_closure_count = pact_list_len(cg_closure_defs);
    const int64_t pre_test_mono_td_count = pact_list_len(mono_instances);
    const int64_t pre_test_mono_fn_count = pact_list_len(mono_fns);
    const int64_t pre_test_option_count = pact_list_len(emitted_option_types);
    const int64_t pre_test_result_count = pact_list_len(emitted_result_types);
    const int64_t pre_test_iter_count = pact_list_len(emitted_iter_types);
    const int64_t pre_test_map_iter_count = pact_list_len(emitted_map_iters);
    const int64_t pre_test_filter_iter_count = pact_list_len(emitted_filter_iters);
    const int64_t pre_test_take_iter_count = pact_list_len(emitted_take_iters);
    const int64_t pre_test_skip_iter_count = pact_list_len(emitted_skip_iters);
    const int64_t pre_test_chain_iter_count = pact_list_len(emitted_chain_iters);
    const int64_t pre_test_flat_map_iter_count = pact_list_len(emitted_flat_map_iters);
    pact_list* _l119 = pact_list_new();
    cg_lines = _l119;
    if ((tests_sl != (-1))) {
        int64_t ti = 0;
        while ((ti < pact_sublist_length(tests_sl))) {
            const int64_t tb = pact_sublist_get(tests_sl, ti);
            const char* tname = (const char*)pact_list_get(np_name, tb);
            const int64_t tbody = (int64_t)(intptr_t)pact_list_get(np_body, tb);
            const char* sanitized = "";
            int64_t si = 0;
            while ((si < pact_str_len(tname))) {
                const int64_t ch = pact_str_char_at(tname, si);
                if ((ch == 32)) {
                    sanitized = pact_str_concat(sanitized, "_");
                } else if (((ch >= 48) && (ch <= 57))) {
                    sanitized = pact_str_concat(sanitized, pact_str_substr(tname, si, 1));
                } else {
                    if (((ch >= 65) && (ch <= 90))) {
                        sanitized = pact_str_concat(sanitized, pact_str_substr(tname, si, 1));
                    } else if (((ch >= 97) && (ch <= 122))) {
                        sanitized = pact_str_concat(sanitized, pact_str_substr(tname, si, 1));
                    } else {
                        if ((ch == 95)) {
                            sanitized = pact_str_concat(sanitized, "_");
                        }
                    }
                }
                si = (si + 1);
            }
            char _si_120[4096];
            snprintf(_si_120, 4096, "pact_test_%s", sanitized);
            const char* c_name = strdup(_si_120);
            pact_list_push(test_names, (void*)tname);
            pact_list_push(test_c_names, (void*)c_name);
            const int64_t tag_offset = pact_list_len(test_all_tags);
            const int64_t tb_anns = (int64_t)(intptr_t)pact_list_get(np_handlers, tb);
            if ((tb_anns != (-1))) {
                int64_t tai = 0;
                while ((tai < pact_sublist_length(tb_anns))) {
                    const int64_t ann = pact_sublist_get(tb_anns, tai);
                    if (pact_str_eq((const char*)pact_list_get(np_name, ann), "tags")) {
                        const int64_t tag_args_sl = (int64_t)(intptr_t)pact_list_get(np_args, ann);
                        if ((tag_args_sl != (-1))) {
                            int64_t tgi = 0;
                            while ((tgi < pact_sublist_length(tag_args_sl))) {
                                const int64_t tag_nd = pact_sublist_get(tag_args_sl, tgi);
                                pact_list_push(test_all_tags, (void*)(const char*)pact_list_get(np_name, tag_nd));
                                tgi = (tgi + 1);
                            }
                        }
                    }
                    tai = (tai + 1);
                }
            }
            pact_list_push(test_tag_offsets, (void*)(intptr_t)tag_offset);
            pact_list_push(test_tag_counts, (void*)(intptr_t)(pact_list_len(test_all_tags) - tag_offset));
            pact_push_scope();
            char _si_121[4096];
            snprintf(_si_121, 4096, "__test_%s", sanitized);
            cg_current_fn_name = strdup(_si_121);
            cg_current_fn_ret = CT_VOID;
            pact_list* _l122 = pact_list_new();
            mut_captured_vars = _l122;
            pact_prescan_mut_captures(tbody);
            char _si_123[4096];
            snprintf(_si_123, 4096, "static void %s(void) {", c_name);
            pact_emit_line(strdup(_si_123));
            cg_indent = (cg_indent + 1);
            pact_emit_block(tbody);
            cg_indent = (cg_indent - 1);
            pact_emit_line("}");
            pact_emit_line("");
            pact_pop_scope();
            ti = (ti + 1);
        }
    }
    pact_list* test_fn_lines = cg_lines;
    cg_lines = pre_test_lines;
    pact_emit_mono_typedefs_from(pre_test_mono_td_count);
    pact_emit_option_result_types_from(pre_test_option_count, pre_test_result_count);
    pact_emit_iter_types_from(pre_test_iter_count, pre_test_map_iter_count, pre_test_filter_iter_count, pre_test_take_iter_count, pre_test_skip_iter_count, pre_test_chain_iter_count, pre_test_flat_map_iter_count);
    pact_emit_mono_fns_from(pre_test_mono_fn_count);
    if ((pact_list_len(cg_closure_defs) > pre_test_closure_count)) {
        int64_t tci = pre_test_closure_count;
        while ((tci < pact_list_len(cg_closure_defs))) {
            pact_list_push(cg_lines, (void*)(const char*)pact_list_get(cg_closure_defs, tci));
            tci = (tci + 1);
        }
    }
    int64_t tfi = 0;
    while ((tfi < pact_list_len(test_fn_lines))) {
        pact_list_push(cg_lines, (void*)(const char*)pact_list_get(test_fn_lines, tfi));
        tfi = (tfi + 1);
    }
    const int64_t test_count = pact_list_len(test_names);
    if ((test_count > 0)) {
        int64_t tti = 0;
        while ((tti < test_count)) {
            const int64_t tag_count = (int64_t)(intptr_t)pact_list_get(test_tag_counts, tti);
            if ((tag_count > 0)) {
                const char* tcn = (const char*)pact_list_get(test_c_names, tti);
                char _si_124[4096];
                snprintf(_si_124, 4096, "static const char* %s_tags[] = {", tcn);
                const char* tag_arr = strdup(_si_124);
                int64_t tgi = 0;
                while ((tgi < tag_count)) {
                    if ((tgi > 0)) {
                        tag_arr = pact_str_concat(tag_arr, ", ");
                    }
                    const int64_t tag_idx = ((int64_t)(intptr_t)pact_list_get(test_tag_offsets, tti) + tgi);
                    const char* tag_val = (const char*)pact_list_get(test_all_tags, tag_idx);
                    tag_arr = pact_str_concat(pact_str_concat(pact_str_concat(tag_arr, "\""), tag_val), "\"");
                    tgi = (tgi + 1);
                }
                tag_arr = pact_str_concat(tag_arr, "};");
                pact_emit_line(tag_arr);
            }
            tti = (tti + 1);
        }
        pact_emit_line("static const pact_test_entry __pact_tests[] = {");
        cg_indent = (cg_indent + 1);
        int64_t tri = 0;
        while ((tri < test_count)) {
            const char* tn = (const char*)pact_list_get(test_names, tri);
            const char* tcn = (const char*)pact_list_get(test_c_names, tri);
            const char* _if_125;
            if ((tri < (test_count - 1))) {
                _if_125 = ",";
            } else {
                _if_125 = "";
            }
            const char* comma = _if_125;
            const int64_t tc = (int64_t)(intptr_t)pact_list_get(test_tag_counts, tri);
            if ((tc > 0)) {
                char _si_126[4096];
                snprintf(_si_126, 4096, "{\"%s\", %s, __FILE__, 0, 0, %s_tags, %lld}%s", tn, tcn, tcn, (long long)tc, comma);
                pact_emit_line(strdup(_si_126));
            } else {
                char _si_127[4096];
                snprintf(_si_127, 4096, "{\"%s\", %s, __FILE__, 0, 0, NULL, 0}%s", tn, tcn, comma);
                pact_emit_line(strdup(_si_127));
            }
            tri = (tri + 1);
        }
        cg_indent = (cg_indent - 1);
        pact_emit_line("};");
        pact_emit_line("");
        pact_emit_line("static void __pact_run_tests(int argc, const char** argv) {");
        cg_indent = (cg_indent + 1);
        char _si_128[4096];
        snprintf(_si_128, 4096, "pact_test_run(__pact_tests, %lld, argc, argv);", (long long)test_count);
        pact_emit_line(strdup(_si_128));
        cg_indent = (cg_indent - 1);
        pact_emit_line("}");
        pact_emit_line("");
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
    pact_emit_line("__pact_ctx = pact_ctx_default();");
    if ((cg_uses_async != 0)) {
        pact_emit_line("__pact_pool = pact_threadpool_init(4);");
    }
    if ((pact_list_len(cg_global_inits) > 0)) {
        pact_emit_line("__pact_init_globals();");
    }
    const int64_t has_main = pact_is_emitted_fn("main");
    if (((test_count > 0) && (has_main != 0))) {
        pact_emit_line("for (int i = 1; i < argc; i++) {");
        cg_indent = (cg_indent + 1);
        pact_emit_line("if (strcmp(argv[i], \"--test\") == 0) {");
        cg_indent = (cg_indent + 1);
        pact_emit_line("__pact_run_tests(argc, (const char**)argv);");
        if ((cg_uses_async != 0)) {
            pact_emit_line("pact_threadpool_shutdown(__pact_pool);");
        }
        pact_emit_line("return 0;");
        cg_indent = (cg_indent - 1);
        pact_emit_line("}");
        cg_indent = (cg_indent - 1);
        pact_emit_line("}");
    }
    if (((test_count > 0) && (has_main == 0))) {
        pact_emit_line("__pact_run_tests(argc, (const char**)argv);");
    } else {
        pact_emit_line("pact_main();");
    }
    if ((cg_uses_async != 0)) {
        pact_emit_line("pact_threadpool_shutdown(__pact_pool);");
    }
    pact_emit_line("return 0;");
    cg_indent = (cg_indent - 1);
    pact_emit_line("}");
    pact_pop_scope();
    return pact_join_lines();
}

void pact_fmt_emit(const char* line) {
    if (pact_str_eq(line, "")) {
        pact_list_push(fmt_lines, (void*)"");
    } else {
        const char* pad = "";
        int64_t i = 0;
        while ((i < fmt_indent)) {
            pad = pact_str_concat(pad, "    ");
            i = (i + 1);
        }
        pact_list_push(fmt_lines, (void*)pact_str_concat(pad, line));
    }
}

void pact_fmt_emit_raw(const char* line) {
    pact_list_push(fmt_lines, (void*)line);
}

int64_t pact_fmt_line_len(const char* line) {
    return ((fmt_indent * 4) + pact_str_len(line));
}

int64_t pact_fmt_needs_wrap(const char* line) {
    if ((pact_fmt_line_len(line) > fmt_max_line)) {
        return 1;
    }
    return 0;
}

const char* pact_fmt_join(void) {
    const char* result = "";
    int64_t i = 0;
    while ((i < pact_list_len(fmt_lines))) {
        if ((i > 0)) {
            result = pact_str_concat(result, "\n");
        }
        result = pact_str_concat(result, (const char*)pact_list_get(fmt_lines, i));
        i = (i + 1);
    }
    return result;
}

const char* pact_format_type_ann(int64_t node) {
    if ((node == (-1))) {
        return "";
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind != pact_NodeKind_TypeAnn)) {
        return (const char*)pact_list_get(np_name, node);
    }
    const char* name = (const char*)pact_list_get(np_name, node);
    const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
    if (pact_str_eq(name, "Fn")) {
        const char* result = "fn(";
        if ((elems_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(elems_sl))) {
                if ((i > 0)) {
                    result = pact_str_concat(result, ", ");
                }
                result = pact_str_concat(result, pact_format_type_ann(pact_sublist_get(elems_sl, i)));
                i = (i + 1);
            }
        }
        result = pact_str_concat(result, ")");
        const char* ret = (const char*)pact_list_get(np_return_type, node);
        if (((!pact_str_eq(ret, "")) && (!pact_str_eq(ret, "Void")))) {
            result = pact_str_concat(pact_str_concat(result, " -> "), ret);
        }
        return result;
    }
    if (((elems_sl != (-1)) && (pact_sublist_length(elems_sl) > 0))) {
        const char* result = pact_str_concat(name, "[");
        int64_t i = 0;
        while ((i < pact_sublist_length(elems_sl))) {
            if ((i > 0)) {
                result = pact_str_concat(result, ", ");
            }
            result = pact_str_concat(result, pact_format_type_ann(pact_sublist_get(elems_sl, i)));
            i = (i + 1);
        }
        result = pact_str_concat(result, "]");
        return result;
    }
    return name;
}

const char* pact_format_pattern(int64_t node) {
    if ((node == (-1))) {
        return "_";
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_WildcardPattern)) {
        return "_";
    }
    if ((kind == pact_NodeKind_IntPattern)) {
        return (const char*)pact_list_get(np_str_val, node);
    }
    if ((kind == pact_NodeKind_StringPattern)) {
        return pact_str_concat(pact_str_concat("\"", (const char*)pact_list_get(np_str_val, node)), "\"");
    }
    if ((kind == pact_NodeKind_IdentPattern)) {
        return (const char*)pact_list_get(np_name, node);
    }
    if ((kind == pact_NodeKind_Ident)) {
        return (const char*)pact_list_get(np_name, node);
    }
    if ((kind == pact_NodeKind_TuplePattern)) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        const char* result = "(";
        if ((elems_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(elems_sl))) {
                if ((i > 0)) {
                    result = pact_str_concat(result, ", ");
                }
                result = pact_str_concat(result, pact_format_pattern(pact_sublist_get(elems_sl, i)));
                i = (i + 1);
            }
        }
        return pact_str_concat(result, ")");
    }
    if ((kind == pact_NodeKind_OrPattern)) {
        const int64_t alts_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        const char* result = "";
        if ((alts_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(alts_sl))) {
                if ((i > 0)) {
                    result = pact_str_concat(result, " | ");
                }
                result = pact_str_concat(result, pact_format_pattern(pact_sublist_get(alts_sl, i)));
                i = (i + 1);
            }
        }
        return result;
    }
    if ((kind == pact_NodeKind_RangePattern)) {
        const char* lo = (const char*)pact_list_get(np_str_val, node);
        const char* hi = (const char*)pact_list_get(np_name, node);
        if (((int64_t)(intptr_t)pact_list_get(np_inclusive, node) != 0)) {
            char _si_0[4096];
            snprintf(_si_0, 4096, "%s..=%s", lo, hi);
            return strdup(_si_0);
        }
        char _si_1[4096];
        snprintf(_si_1, 4096, "%s..%s", lo, hi);
        return strdup(_si_1);
    }
    if ((kind == pact_NodeKind_EnumPattern)) {
        const char* ename = (const char*)pact_list_get(np_name, node);
        const char* vname = (const char*)pact_list_get(np_type_name, node);
        const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, node);
        const char* result = "";
        if ((!pact_str_eq(vname, ""))) {
            char _si_2[4096];
            snprintf(_si_2, 4096, "%s.%s", ename, vname);
            result = strdup(_si_2);
        } else {
            result = ename;
        }
        if ((flds_sl != (-1))) {
            result = pact_str_concat(result, "(");
            int64_t i = 0;
            while ((i < pact_sublist_length(flds_sl))) {
                if ((i > 0)) {
                    result = pact_str_concat(result, ", ");
                }
                result = pact_str_concat(result, pact_format_pattern(pact_sublist_get(flds_sl, i)));
                i = (i + 1);
            }
            result = pact_str_concat(result, ")");
        }
        return result;
    }
    if ((kind == pact_NodeKind_StructPattern)) {
        const char* sname = (const char*)pact_list_get(np_type_name, node);
        const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, node);
        const int64_t has_rest = (int64_t)(intptr_t)pact_list_get(np_inclusive, node);
        char _si_3[4096];
        snprintf(_si_3, 4096, "%s {", sname);
        const char* result = strdup(_si_3);
        if ((flds_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(flds_sl))) {
                if ((i > 0)) {
                    result = pact_str_concat(result, ", ");
                }
                const int64_t fld = pact_sublist_get(flds_sl, i);
                const char* fname = (const char*)pact_list_get(np_name, fld);
                const int64_t fpat = (int64_t)(intptr_t)pact_list_get(np_pattern, fld);
                if ((fpat != (-1))) {
                    result = pact_str_concat(pact_str_concat(pact_str_concat(result, fname), ": "), pact_format_pattern(fpat));
                } else {
                    result = pact_str_concat(result, fname);
                }
                i = (i + 1);
            }
        }
        if ((has_rest != 0)) {
            if (((flds_sl != (-1)) && (pact_sublist_length(flds_sl) > 0))) {
                result = pact_str_concat(result, ", ");
            }
            result = pact_str_concat(result, "..");
        }
        return pact_str_concat(result, "}");
    }
    if ((kind == pact_NodeKind_AsPattern)) {
        const char* name = (const char*)pact_list_get(np_name, node);
        const int64_t inner = (int64_t)(intptr_t)pact_list_get(np_pattern, node);
        char _si_4[4096];
        snprintf(_si_4, 4096, "%s as ", name);
        return pact_str_concat(strdup(_si_4), pact_format_pattern(inner));
    }
    return "_";
}

int64_t pact_op_precedence(const char* op) {
    if (pact_str_eq(op, "||")) {
        return 1;
    }
    if (pact_str_eq(op, "&&")) {
        return 2;
    }
    if ((pact_str_eq(op, "==") || pact_str_eq(op, "!="))) {
        return 3;
    }
    if ((((pact_str_eq(op, "<") || pact_str_eq(op, ">")) || pact_str_eq(op, "<=")) || pact_str_eq(op, ">="))) {
        return 4;
    }
    if (pact_str_eq(op, "\?\?")) {
        return 5;
    }
    if ((pact_str_eq(op, "+") || pact_str_eq(op, "-"))) {
        return 6;
    }
    if (((pact_str_eq(op, "*") || pact_str_eq(op, "/")) || pact_str_eq(op, "%"))) {
        return 7;
    }
    return 0;
}

int64_t pact_needs_parens(int64_t child, const char* parent_op, int64_t is_right) {
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, child);
    if ((kind != pact_NodeKind_BinOp)) {
        return 0;
    }
    const char* child_op = (const char*)pact_list_get(np_op, child);
    const int64_t parent_prec = pact_op_precedence(parent_op);
    const int64_t child_prec = pact_op_precedence(child_op);
    if ((child_prec < parent_prec)) {
        return 1;
    }
    if (((child_prec == parent_prec) && (is_right != 0))) {
        return 1;
    }
    return 0;
}

const char* pact_format_expr(int64_t node) {
    if ((node == (-1))) {
        return "";
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_IntLit)) {
        const char* s = (const char*)pact_list_get(np_str_val, node);
        if ((!pact_str_eq(s, ""))) {
            return s;
        }
        char _si_0[4096];
        snprintf(_si_0, 4096, "%lld", (long long)(int64_t)(intptr_t)pact_list_get(np_int_val, node));
        return strdup(_si_0);
    }
    if ((kind == pact_NodeKind_FloatLit)) {
        return (const char*)pact_list_get(np_str_val, node);
    }
    if ((kind == pact_NodeKind_BoolLit)) {
        if (((int64_t)(intptr_t)pact_list_get(np_int_val, node) != 0)) {
            return "true";
        }
        return "false";
    }
    if ((kind == pact_NodeKind_Ident)) {
        return (const char*)pact_list_get(np_name, node);
    }
    if ((kind == pact_NodeKind_InterpString)) {
        return pact_format_interp_string(node);
    }
    if ((kind == pact_NodeKind_BinOp)) {
        const char* op = (const char*)pact_list_get(np_op, node);
        const int64_t left = (int64_t)(intptr_t)pact_list_get(np_left, node);
        const int64_t right = (int64_t)(intptr_t)pact_list_get(np_right, node);
        const char* left_str = pact_format_expr(left);
        const char* right_str = pact_format_expr(right);
        if ((pact_needs_parens(left, op, 0) != 0)) {
            left_str = pact_str_concat(pact_str_concat("(", left_str), ")");
        }
        if ((pact_needs_parens(right, op, 1) != 0)) {
            right_str = pact_str_concat(pact_str_concat("(", right_str), ")");
        }
        char _si_1[4096];
        snprintf(_si_1, 4096, "%s %s %s", left_str, op, right_str);
        return strdup(_si_1);
    }
    if ((kind == pact_NodeKind_UnaryOp)) {
        const char* op = (const char*)pact_list_get(np_op, node);
        const int64_t operand = (int64_t)(intptr_t)pact_list_get(np_left, node);
        if (pact_str_eq(op, "\?")) {
            return pact_str_concat(pact_format_expr(operand), "\?");
        }
        const char* inner = pact_format_expr(operand);
        const int64_t inner_kind = (int64_t)(intptr_t)pact_list_get(np_kind, operand);
        if ((inner_kind == pact_NodeKind_BinOp)) {
            char _si_2[4096];
            snprintf(_si_2, 4096, "%s(", op);
            return pact_str_concat(pact_str_concat(strdup(_si_2), inner), ")");
        }
        return pact_str_concat(op, inner);
    }
    if ((kind == pact_NodeKind_Call)) {
        const int64_t func = (int64_t)(intptr_t)pact_list_get(np_left, node);
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        const char* func_str = pact_format_expr(func);
        const char* result = pact_str_concat(func_str, "(");
        if ((args_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(args_sl))) {
                if ((i > 0)) {
                    result = pact_str_concat(result, ", ");
                }
                result = pact_str_concat(result, pact_format_expr(pact_sublist_get(args_sl, i)));
                i = (i + 1);
            }
        }
        return pact_str_concat(result, ")");
    }
    if ((kind == pact_NodeKind_MethodCall)) {
        const int64_t obj = (int64_t)(intptr_t)pact_list_get(np_obj, node);
        const char* method = (const char*)pact_list_get(np_method, node);
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        const char* obj_str = pact_format_expr(obj);
        char _si_3[4096];
        snprintf(_si_3, 4096, "%s.%s(", obj_str, method);
        const char* result = strdup(_si_3);
        if ((args_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(args_sl))) {
                if ((i > 0)) {
                    result = pact_str_concat(result, ", ");
                }
                result = pact_str_concat(result, pact_format_expr(pact_sublist_get(args_sl, i)));
                i = (i + 1);
            }
        }
        return pact_str_concat(result, ")");
    }
    if ((kind == pact_NodeKind_FieldAccess)) {
        const int64_t obj = (int64_t)(intptr_t)pact_list_get(np_obj, node);
        const char* field = (const char*)pact_list_get(np_name, node);
        char _si_4[4096];
        snprintf(_si_4, 4096, "%s.%s", pact_format_expr(obj), field);
        return strdup(_si_4);
    }
    if ((kind == pact_NodeKind_IndexExpr)) {
        const int64_t obj = (int64_t)(intptr_t)pact_list_get(np_obj, node);
        const int64_t idx = (int64_t)(intptr_t)pact_list_get(np_index, node);
        char _si_5[4096];
        snprintf(_si_5, 4096, "%s[%s]", pact_format_expr(obj), pact_format_expr(idx));
        return strdup(_si_5);
    }
    if ((kind == pact_NodeKind_TupleLit)) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        const char* result = "(";
        if ((elems_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(elems_sl))) {
                if ((i > 0)) {
                    result = pact_str_concat(result, ", ");
                }
                result = pact_str_concat(result, pact_format_expr(pact_sublist_get(elems_sl, i)));
                i = (i + 1);
            }
        }
        return pact_str_concat(result, ")");
    }
    if ((kind == pact_NodeKind_ListLit)) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        const char* result = "[";
        if ((elems_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(elems_sl))) {
                if ((i > 0)) {
                    result = pact_str_concat(result, ", ");
                }
                result = pact_str_concat(result, pact_format_expr(pact_sublist_get(elems_sl, i)));
                i = (i + 1);
            }
        }
        return pact_str_concat(result, "]");
    }
    if ((kind == pact_NodeKind_StructLit)) {
        const char* tname = (const char*)pact_list_get(np_type_name, node);
        const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, node);
        char _si_6[4096];
        snprintf(_si_6, 4096, "%s { ", tname);
        const char* result = strdup(_si_6);
        if ((flds_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(flds_sl))) {
                if ((i > 0)) {
                    result = pact_str_concat(result, ", ");
                }
                const int64_t fld = pact_sublist_get(flds_sl, i);
                const char* fname = (const char*)pact_list_get(np_name, fld);
                const int64_t fval = (int64_t)(intptr_t)pact_list_get(np_value, fld);
                char _si_7[4096];
                snprintf(_si_7, 4096, "%s: %s", fname, pact_format_expr(fval));
                result = pact_str_concat(result, strdup(_si_7));
                i = (i + 1);
            }
        }
        return pact_str_concat(result, " }");
    }
    if ((kind == pact_NodeKind_RangeLit)) {
        const int64_t start = (int64_t)(intptr_t)pact_list_get(np_start, node);
        const int64_t end = (int64_t)(intptr_t)pact_list_get(np_end, node);
        if (((int64_t)(intptr_t)pact_list_get(np_inclusive, node) != 0)) {
            char _si_8[4096];
            snprintf(_si_8, 4096, "%s..=%s", pact_format_expr(start), pact_format_expr(end));
            return strdup(_si_8);
        }
        char _si_9[4096];
        snprintf(_si_9, 4096, "%s..%s", pact_format_expr(start), pact_format_expr(end));
        return strdup(_si_9);
    }
    if ((kind == pact_NodeKind_Closure)) {
        return pact_format_closure_inline(node);
    }
    if ((kind == pact_NodeKind_IfExpr)) {
        return pact_format_if_inline(node);
    }
    if ((kind == pact_NodeKind_MatchExpr)) {
        return pact_format_match_inline(node);
    }
    if ((kind == pact_NodeKind_Block)) {
        return pact_format_block_inline(node);
    }
    if ((kind == pact_NodeKind_AsyncScope)) {
        return pact_str_concat("async.scope ", pact_format_block_inline((int64_t)(intptr_t)pact_list_get(np_body, node)));
    }
    if ((kind == pact_NodeKind_AsyncSpawn)) {
        return pact_str_concat("async.spawn ", pact_format_block_inline((int64_t)(intptr_t)pact_list_get(np_body, node)));
    }
    if ((kind == pact_NodeKind_AwaitExpr)) {
        return pact_str_concat(pact_format_expr((int64_t)(intptr_t)pact_list_get(np_obj, node)), ".await");
    }
    if ((kind == pact_NodeKind_ChannelNew)) {
        const int64_t tparams = (int64_t)(intptr_t)pact_list_get(np_type_params, node);
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        const char* result = "channel.new";
        if (((tparams != (-1)) && (pact_sublist_length(tparams) > 0))) {
            result = pact_str_concat(result, "[");
            int64_t i = 0;
            while ((i < pact_sublist_length(tparams))) {
                if ((i > 0)) {
                    result = pact_str_concat(result, ", ");
                }
                result = pact_str_concat(result, (const char*)pact_list_get(np_name, pact_sublist_get(tparams, i)));
                i = (i + 1);
            }
            result = pact_str_concat(result, "]");
        }
        result = pact_str_concat(result, "(");
        if ((args_sl != (-1))) {
            int64_t i = 0;
            while ((i < pact_sublist_length(args_sl))) {
                if ((i > 0)) {
                    result = pact_str_concat(result, ", ");
                }
                result = pact_str_concat(result, pact_format_expr(pact_sublist_get(args_sl, i)));
                i = (i + 1);
            }
        }
        return pact_str_concat(result, ")");
    }
    if ((kind == pact_NodeKind_HandlerExpr)) {
        return pact_format_handler_inline(node);
    }
    return "";
}

const char* pact_fmt_escape_str_literal(const char* s) {
    const char* bs = "\\";
    const char* result = "";
    int64_t i = 0;
    while ((i < pact_str_len(s))) {
        const int64_t ch = pact_str_char_at(s, i);
        if ((ch == 92)) {
            result = pact_str_concat(pact_str_concat(result, bs), bs);
        } else if ((ch == 34)) {
            result = pact_str_concat(pact_str_concat(result, bs), "\"");
        } else {
            if ((ch == 10)) {
                result = pact_str_concat(pact_str_concat(result, bs), "n");
            } else if ((ch == 9)) {
                result = pact_str_concat(pact_str_concat(result, bs), "t");
            } else {
                if ((ch == 123)) {
                    result = pact_str_concat(pact_str_concat(result, bs), "{");
                } else if ((ch == 125)) {
                    result = pact_str_concat(pact_str_concat(result, bs), "}");
                } else {
                    result = pact_str_concat(result, pact_str_substr(s, i, 1));
                }
            }
        }
        i = (i + 1);
    }
    return result;
}

const char* pact_format_interp_string(int64_t node) {
    const int64_t parts_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
    if ((parts_sl == (-1))) {
        return "\"\"";
    }
    const char* result = "\"";
    int64_t i = 0;
    while ((i < pact_sublist_length(parts_sl))) {
        const int64_t part = pact_sublist_get(parts_sl, i);
        const int64_t pk = (int64_t)(intptr_t)pact_list_get(np_kind, part);
        if (((pk == pact_NodeKind_Ident) && pact_str_eq((const char*)pact_list_get(np_str_val, part), (const char*)pact_list_get(np_name, part)))) {
            result = pact_str_concat(result, pact_fmt_escape_str_literal((const char*)pact_list_get(np_str_val, part)));
        } else {
            result = pact_str_concat(pact_str_concat(pact_str_concat(result, "{"), pact_format_expr(part)), "}");
        }
        i = (i + 1);
    }
    return pact_str_concat(result, "\"");
}

const char* pact_format_closure_inline(int64_t node) {
    const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, node);
    const int64_t body = (int64_t)(intptr_t)pact_list_get(np_body, node);
    const char* ret = (const char*)pact_list_get(np_return_type, node);
    const char* result = "fn(";
    if ((params_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(params_sl))) {
            if ((i > 0)) {
                result = pact_str_concat(result, ", ");
            }
            result = pact_str_concat(result, pact_format_param(pact_sublist_get(params_sl, i)));
            i = (i + 1);
        }
    }
    result = pact_str_concat(result, ")");
    if ((!pact_str_eq(ret, ""))) {
        result = pact_str_concat(pact_str_concat(result, " -> "), ret);
    }
    result = pact_str_concat(pact_str_concat(result, " "), pact_format_block_inline(body));
    return result;
}

const char* pact_format_param(int64_t node) {
    const char* name = (const char*)pact_list_get(np_name, node);
    const char* type_name = (const char*)pact_list_get(np_type_name, node);
    const int64_t is_mut = (int64_t)(intptr_t)pact_list_get(np_is_mut, node);
    const int64_t type_ann = (int64_t)(intptr_t)pact_list_get(np_type_ann, node);
    const char* result = "";
    if ((is_mut != 0)) {
        result = "mut ";
    }
    result = pact_str_concat(result, name);
    if ((type_ann != (-1))) {
        result = pact_str_concat(pact_str_concat(result, ": "), pact_format_type_ann(type_ann));
    } else if ((!pact_str_eq(type_name, ""))) {
        result = pact_str_concat(pact_str_concat(result, ": "), type_name);
    }
    return result;
}

const char* pact_format_block_inline(int64_t node) {
    if ((node == (-1))) {
        return "{ }";
    }
    const int64_t stmts_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, node);
    if (((stmts_sl == (-1)) || (pact_sublist_length(stmts_sl) == 0))) {
        return "{ }";
    }
    if ((pact_sublist_length(stmts_sl) == 1)) {
        const int64_t stmt = pact_sublist_get(stmts_sl, 0);
        const int64_t sk = (int64_t)(intptr_t)pact_list_get(np_kind, stmt);
        if ((sk == pact_NodeKind_ExprStmt)) {
            const int64_t inner = (int64_t)(intptr_t)pact_list_get(np_value, stmt);
            return pact_str_concat(pact_str_concat("{ ", pact_format_expr(inner)), " }");
        }
        if ((sk == pact_NodeKind_Return)) {
            const int64_t val = (int64_t)(intptr_t)pact_list_get(np_value, stmt);
            if ((val != (-1))) {
                return pact_str_concat(pact_str_concat("{ return ", pact_format_expr(val)), " }");
            }
            return "{ return }";
        }
        if (pact_is_simple_expr_kind(sk)) {
            return pact_str_concat(pact_str_concat("{ ", pact_format_expr(stmt)), " }");
        }
    }
    return "{ ... }";
}

int64_t pact_is_simple_expr_kind(int64_t kind) {
    if ((kind == pact_NodeKind_IntLit)) {
        return 1;
    }
    if ((kind == pact_NodeKind_FloatLit)) {
        return 1;
    }
    if ((kind == pact_NodeKind_BoolLit)) {
        return 1;
    }
    if ((kind == pact_NodeKind_Ident)) {
        return 1;
    }
    if ((kind == pact_NodeKind_BinOp)) {
        return 1;
    }
    if ((kind == pact_NodeKind_UnaryOp)) {
        return 1;
    }
    if ((kind == pact_NodeKind_Call)) {
        return 1;
    }
    if ((kind == pact_NodeKind_MethodCall)) {
        return 1;
    }
    if ((kind == pact_NodeKind_FieldAccess)) {
        return 1;
    }
    if ((kind == pact_NodeKind_InterpString)) {
        return 1;
    }
    return 0;
}

const char* pact_format_if_inline(int64_t node) {
    const int64_t cond = (int64_t)(intptr_t)pact_list_get(np_condition, node);
    const int64_t then_b = (int64_t)(intptr_t)pact_list_get(np_then_body, node);
    const int64_t else_b = (int64_t)(intptr_t)pact_list_get(np_else_body, node);
    const char* result = pact_str_concat(pact_str_concat(pact_str_concat("if ", pact_format_expr(cond)), " "), pact_format_block_inline(then_b));
    if ((else_b != (-1))) {
        const int64_t else_stmts = (int64_t)(intptr_t)pact_list_get(np_stmts, else_b);
        if (((else_stmts != (-1)) && (pact_sublist_length(else_stmts) == 1))) {
            const int64_t inner = pact_sublist_get(else_stmts, 0);
            if (((int64_t)(intptr_t)pact_list_get(np_kind, inner) == pact_NodeKind_IfExpr)) {
                result = pact_str_concat(pact_str_concat(result, " else "), pact_format_if_inline(inner));
                return result;
            }
        }
        result = pact_str_concat(pact_str_concat(result, " else "), pact_format_block_inline(else_b));
    }
    return result;
}

const char* pact_format_match_inline(int64_t node) {
    return pact_str_concat(pact_str_concat("match ", pact_format_expr((int64_t)(intptr_t)pact_list_get(np_scrutinee, node))), " { ... }");
}

const char* pact_format_handler_inline(int64_t node) {
    const char* name = (const char*)pact_list_get(np_name, node);
    char _si_0[4096];
    snprintf(_si_0, 4096, "handler %s { ... }", name);
    return strdup(_si_0);
}

void pact_emit_call_wrapped(int64_t node, const char* prefix) {
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_Call)) {
        const int64_t func = (int64_t)(intptr_t)pact_list_get(np_left, node);
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        const char* func_str = pact_format_expr(func);
        const char* open = pact_str_concat(pact_str_concat(prefix, func_str), "(");
        if (((args_sl == (-1)) || (pact_sublist_length(args_sl) == 0))) {
            pact_fmt_emit(pact_str_concat(open, ")"));
            return;
        }
        pact_fmt_emit(open);
        fmt_indent = (fmt_indent + 1);
        int64_t i = 0;
        while ((i < pact_sublist_length(args_sl))) {
            const char* arg_str = pact_format_expr(pact_sublist_get(args_sl, i));
            if ((i < (pact_sublist_length(args_sl) - 1))) {
                pact_fmt_emit(pact_str_concat(arg_str, ","));
            } else {
                pact_fmt_emit(arg_str);
            }
            i = (i + 1);
        }
        fmt_indent = (fmt_indent - 1);
        pact_fmt_emit(")");
        return;
    }
    if ((kind == pact_NodeKind_MethodCall)) {
        const int64_t obj = (int64_t)(intptr_t)pact_list_get(np_obj, node);
        const char* method = (const char*)pact_list_get(np_method, node);
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        const char* obj_str = pact_format_expr(obj);
        const char* open = pact_str_concat(pact_str_concat(pact_str_concat(pact_str_concat(prefix, obj_str), "."), method), "(");
        if (((args_sl == (-1)) || (pact_sublist_length(args_sl) == 0))) {
            pact_fmt_emit(pact_str_concat(open, ")"));
            return;
        }
        pact_fmt_emit(open);
        fmt_indent = (fmt_indent + 1);
        int64_t i = 0;
        while ((i < pact_sublist_length(args_sl))) {
            const char* arg_str = pact_format_expr(pact_sublist_get(args_sl, i));
            if ((i < (pact_sublist_length(args_sl) - 1))) {
                pact_fmt_emit(pact_str_concat(arg_str, ","));
            } else {
                pact_fmt_emit(arg_str);
            }
            i = (i + 1);
        }
        fmt_indent = (fmt_indent - 1);
        pact_fmt_emit(")");
        return;
    }
    pact_fmt_emit(pact_str_concat(prefix, pact_format_expr(node)));
}

void pact_emit_list_wrapped(int64_t node, const char* prefix) {
    const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
    if (((elems_sl == (-1)) || (pact_sublist_length(elems_sl) == 0))) {
        pact_fmt_emit(pact_str_concat(prefix, "[]"));
        return;
    }
    pact_fmt_emit(pact_str_concat(prefix, "["));
    fmt_indent = (fmt_indent + 1);
    int64_t i = 0;
    while ((i < pact_sublist_length(elems_sl))) {
        const char* elem_str = pact_format_expr(pact_sublist_get(elems_sl, i));
        if ((i < (pact_sublist_length(elems_sl) - 1))) {
            pact_fmt_emit(pact_str_concat(elem_str, ","));
        } else {
            pact_fmt_emit(elem_str);
        }
        i = (i + 1);
    }
    fmt_indent = (fmt_indent - 1);
    pact_fmt_emit("]");
}

void pact_emit_struct_lit_wrapped(int64_t node, const char* prefix) {
    const char* tname = (const char*)pact_list_get(np_type_name, node);
    const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, node);
    if (((flds_sl == (-1)) || (pact_sublist_length(flds_sl) == 0))) {
        pact_fmt_emit(pact_str_concat(pact_str_concat(prefix, tname), " { }"));
        return;
    }
    pact_fmt_emit(pact_str_concat(pact_str_concat(prefix, tname), " {"));
    fmt_indent = (fmt_indent + 1);
    int64_t i = 0;
    while ((i < pact_sublist_length(flds_sl))) {
        const int64_t fld = pact_sublist_get(flds_sl, i);
        const char* fname = (const char*)pact_list_get(np_name, fld);
        const int64_t fval = (int64_t)(intptr_t)pact_list_get(np_value, fld);
        char _si_0[4096];
        snprintf(_si_0, 4096, "%s: %s", fname, pact_format_expr(fval));
        const char* fld_str = strdup(_si_0);
        if ((i < (pact_sublist_length(flds_sl) - 1))) {
            pact_fmt_emit(pact_str_concat(fld_str, ","));
        } else {
            pact_fmt_emit(fld_str);
        }
        i = (i + 1);
    }
    fmt_indent = (fmt_indent - 1);
    pact_fmt_emit("}");
}

void pact_emit_binop_wrapped(int64_t node, const char* prefix) {
    pact_list* _l0 = pact_list_new();
    binop_parts = _l0;
    pact_list* _l1 = pact_list_new();
    binop_ops = _l1;
    pact_flatten_binop_chain(node);
    if ((pact_list_len(binop_parts) == 0)) {
        pact_fmt_emit(pact_str_concat(prefix, pact_format_expr(node)));
        return;
    }
    pact_fmt_emit(pact_str_concat(prefix, (const char*)pact_list_get(binop_parts, 0)));
    fmt_indent = (fmt_indent + 1);
    int64_t i = 0;
    while ((i < pact_list_len(binop_ops))) {
        char _si_2[4096];
        snprintf(_si_2, 4096, "%s %s", (const char*)pact_list_get(binop_ops, i), (const char*)pact_list_get(binop_parts, (i + 1)));
        pact_fmt_emit(strdup(_si_2));
        i = (i + 1);
    }
    fmt_indent = (fmt_indent - 1);
}

void pact_flatten_binop_chain(int64_t node) {
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind != pact_NodeKind_BinOp)) {
        pact_list_push(binop_parts, (void*)pact_format_expr(node));
        return;
    }
    const char* op = (const char*)pact_list_get(np_op, node);
    const int64_t left = (int64_t)(intptr_t)pact_list_get(np_left, node);
    const int64_t right = (int64_t)(intptr_t)pact_list_get(np_right, node);
    const int64_t left_kind = (int64_t)(intptr_t)pact_list_get(np_kind, left);
    if (((left_kind == pact_NodeKind_BinOp) && pact_str_eq((const char*)pact_list_get(np_op, left), op))) {
        pact_flatten_binop_chain(left);
    } else {
        const char* left_str = pact_format_expr(left);
        if ((pact_needs_parens(left, op, 0) != 0)) {
            left_str = pact_str_concat(pact_str_concat("(", left_str), ")");
        }
        pact_list_push(binop_parts, (void*)left_str);
    }
    pact_list_push(binop_ops, (void*)op);
    const char* right_str = pact_format_expr(right);
    if ((pact_needs_parens(right, op, 1) != 0)) {
        right_str = pact_str_concat(pact_str_concat("(", right_str), ")");
    }
    pact_list_push(binop_parts, (void*)right_str);
}

void pact_emit_method_chain_wrapped(int64_t node, const char* prefix) {
    pact_list* _l0 = pact_list_new();
    pact_list* chain = _l0;
    int64_t cur = node;
    while (((int64_t)(intptr_t)pact_list_get(np_kind, cur) == pact_NodeKind_MethodCall)) {
        pact_list_push(chain, (void*)(intptr_t)cur);
        cur = (int64_t)(intptr_t)pact_list_get(np_obj, cur);
    }
    const char* base_str = pact_format_expr(cur);
    pact_fmt_emit(pact_str_concat(prefix, base_str));
    fmt_indent = (fmt_indent + 1);
    int64_t i = (pact_list_len(chain) - 1);
    while ((i >= 0)) {
        const int64_t mc = (int64_t)(intptr_t)pact_list_get(chain, i);
        const char* method = (const char*)pact_list_get(np_method, mc);
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, mc);
        const char* call_str = pact_str_concat(pact_str_concat(".", method), "(");
        if ((args_sl != (-1))) {
            int64_t j = 0;
            while ((j < pact_sublist_length(args_sl))) {
                if ((j > 0)) {
                    call_str = pact_str_concat(call_str, ", ");
                }
                call_str = pact_str_concat(call_str, pact_format_expr(pact_sublist_get(args_sl, j)));
                j = (j + 1);
            }
        }
        call_str = pact_str_concat(call_str, ")");
        pact_fmt_emit(call_str);
        i = (i - 1);
    }
    fmt_indent = (fmt_indent - 1);
}

int64_t pact_is_method_chain(int64_t node) {
    if (((int64_t)(intptr_t)pact_list_get(np_kind, node) != pact_NodeKind_MethodCall)) {
        return 0;
    }
    const int64_t obj = (int64_t)(intptr_t)pact_list_get(np_obj, node);
    if (((int64_t)(intptr_t)pact_list_get(np_kind, obj) == pact_NodeKind_MethodCall)) {
        return 1;
    }
    return 0;
}

int64_t pact_chain_depth(int64_t node) {
    int64_t depth = 0;
    int64_t cur = node;
    while (((int64_t)(intptr_t)pact_list_get(np_kind, cur) == pact_NodeKind_MethodCall)) {
        depth = (depth + 1);
        cur = (int64_t)(intptr_t)pact_list_get(np_obj, cur);
    }
    return depth;
}

void pact_emit_expr_wrapped(int64_t node, const char* prefix, const char* suffix) {
    const char* expr_str = pact_format_expr(node);
    const char* full = pact_str_concat(pact_str_concat(prefix, expr_str), suffix);
    if ((pact_fmt_needs_wrap(full) == 0)) {
        pact_fmt_emit(full);
        return;
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if (((kind == pact_NodeKind_Call) || (kind == pact_NodeKind_MethodCall))) {
        if (((pact_is_method_chain(node) != 0) && (pact_chain_depth(node) >= 2))) {
            if ((!pact_str_eq(suffix, ""))) {
                pact_emit_method_chain_wrapped(node, prefix);
                return;
            }
            pact_emit_method_chain_wrapped(node, prefix);
            return;
        }
        if ((!pact_str_eq(suffix, ""))) {
            const char* inner = pact_format_expr(node);
            const char* with_suffix = pact_str_concat(pact_str_concat(prefix, inner), suffix);
            if ((pact_fmt_needs_wrap(with_suffix) == 0)) {
                pact_fmt_emit(with_suffix);
                return;
            }
        }
        pact_emit_call_wrapped(node, prefix);
        return;
    }
    if ((kind == pact_NodeKind_ListLit)) {
        pact_emit_list_wrapped(node, prefix);
        return;
    }
    if ((kind == pact_NodeKind_StructLit)) {
        pact_emit_struct_lit_wrapped(node, prefix);
        return;
    }
    if ((kind == pact_NodeKind_BinOp)) {
        if ((!pact_str_eq(suffix, ""))) {
            pact_fmt_emit(full);
            return;
        }
        pact_emit_binop_wrapped(node, prefix);
        return;
    }
    pact_fmt_emit(full);
}

void pact_emit_comments(int64_t node) {
    const char* doc = (const char*)pact_list_get(np_doc_comment, node);
    if ((!pact_str_eq(doc, ""))) {
        int64_t i = 0;
        int64_t line_start = 0;
        while ((i <= pact_str_len(doc))) {
            if (((i == pact_str_len(doc)) || (pact_str_char_at(doc, i) == 10))) {
                const char* line = pact_str_substr(doc, line_start, (i - line_start));
                pact_fmt_emit(pact_str_concat("///", line));
                line_start = (i + 1);
            }
            i = (i + 1);
        }
    }
    const char* leading = (const char*)pact_list_get(np_leading_comments, node);
    if ((!pact_str_eq(leading, ""))) {
        int64_t i = 0;
        int64_t line_start = 0;
        while ((i <= pact_str_len(leading))) {
            if (((i == pact_str_len(leading)) || (pact_str_char_at(leading, i) == 10))) {
                const char* line = pact_str_substr(leading, line_start, (i - line_start));
                pact_fmt_emit(pact_str_concat("//", line));
                line_start = (i + 1);
            }
            i = (i + 1);
        }
    }
}

void pact_format_stmt(int64_t node) {
    if ((node == (-1))) {
        return;
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    pact_emit_comments(node);
    if ((kind == pact_NodeKind_LetBinding)) {
        const char* name = (const char*)pact_list_get(np_name, node);
        const int64_t is_mut = (int64_t)(intptr_t)pact_list_get(np_is_mut, node);
        const int64_t is_pub = (int64_t)(intptr_t)pact_list_get(np_is_pub, node);
        const int64_t val = (int64_t)(intptr_t)pact_list_get(np_value, node);
        const int64_t type_ann = (int64_t)(intptr_t)pact_list_get(np_target, node);
        const char* prefix = "";
        if ((is_pub != 0)) {
            prefix = "pub ";
        }
        prefix = pact_str_concat(prefix, "let ");
        if ((is_mut != 0)) {
            prefix = pact_str_concat(prefix, "mut ");
        }
        prefix = pact_str_concat(prefix, name);
        if ((type_ann != (-1))) {
            prefix = pact_str_concat(pact_str_concat(prefix, ": "), pact_format_type_ann(type_ann));
        }
        prefix = pact_str_concat(prefix, " = ");
        pact_emit_expr_wrapped(val, prefix, "");
        return;
    }
    if ((kind == pact_NodeKind_Assignment)) {
        const int64_t target = (int64_t)(intptr_t)pact_list_get(np_target, node);
        const int64_t val = (int64_t)(intptr_t)pact_list_get(np_value, node);
        const char* assign_prefix = pact_str_concat(pact_format_expr(target), " = ");
        pact_emit_expr_wrapped(val, assign_prefix, "");
        return;
    }
    if ((kind == pact_NodeKind_CompoundAssign)) {
        const char* op = (const char*)pact_list_get(np_op, node);
        const int64_t target = (int64_t)(intptr_t)pact_list_get(np_target, node);
        const int64_t val = (int64_t)(intptr_t)pact_list_get(np_value, node);
        char _si_0[4096];
        snprintf(_si_0, 4096, "%s %s= ", pact_format_expr(target), op);
        const char* comp_prefix = strdup(_si_0);
        pact_emit_expr_wrapped(val, comp_prefix, "");
        return;
    }
    if ((kind == pact_NodeKind_ExprStmt)) {
        const int64_t val = (int64_t)(intptr_t)pact_list_get(np_value, node);
        const int64_t val_kind = (int64_t)(intptr_t)pact_list_get(np_kind, val);
        if ((val_kind == pact_NodeKind_IfExpr)) {
            pact_format_if_stmt(val);
            return;
        }
        if ((val_kind == pact_NodeKind_MatchExpr)) {
            pact_format_match_stmt(val);
            return;
        }
        pact_emit_expr_wrapped(val, "", "");
        return;
    }
    if ((kind == pact_NodeKind_Return)) {
        const int64_t val = (int64_t)(intptr_t)pact_list_get(np_value, node);
        if ((val != (-1))) {
            pact_emit_expr_wrapped(val, "return ", "");
        } else {
            pact_fmt_emit("return");
        }
        return;
    }
    if ((kind == pact_NodeKind_Break)) {
        const int64_t val = (int64_t)(intptr_t)pact_list_get(np_value, node);
        if ((val != (-1))) {
            char _si_1[4096];
            snprintf(_si_1, 4096, "break %s", pact_format_expr(val));
            pact_fmt_emit(strdup(_si_1));
        } else {
            pact_fmt_emit("break");
        }
        return;
    }
    if ((kind == pact_NodeKind_Continue)) {
        pact_fmt_emit("continue");
        return;
    }
    if ((kind == pact_NodeKind_IfExpr)) {
        pact_format_if_stmt(node);
        return;
    }
    if ((kind == pact_NodeKind_MatchExpr)) {
        pact_format_match_stmt(node);
        return;
    }
    if ((kind == pact_NodeKind_ForIn)) {
        const char* var_name = (const char*)pact_list_get(np_var_name, node);
        const int64_t iterable = (int64_t)(intptr_t)pact_list_get(np_iterable, node);
        const int64_t body = (int64_t)(intptr_t)pact_list_get(np_body, node);
        char _si_2[4096];
        snprintf(_si_2, 4096, "for %s in %s {", var_name, pact_format_expr(iterable));
        const char* for_line = strdup(_si_2);
        if ((pact_fmt_needs_wrap(for_line) != 0)) {
            char _si_3[4096];
            snprintf(_si_3, 4096, "for %s in ", var_name);
            pact_emit_expr_wrapped(iterable, strdup(_si_3), " {");
        } else {
            pact_fmt_emit(for_line);
        }
        fmt_indent = (fmt_indent + 1);
        pact_format_block_body(body);
        fmt_indent = (fmt_indent - 1);
        pact_fmt_emit("}");
        return;
    }
    if ((kind == pact_NodeKind_WhileLoop)) {
        const int64_t cond = (int64_t)(intptr_t)pact_list_get(np_condition, node);
        const int64_t body = (int64_t)(intptr_t)pact_list_get(np_body, node);
        char _si_4[4096];
        snprintf(_si_4, 4096, "while %s {", pact_format_expr(cond));
        const char* while_line = strdup(_si_4);
        if (((pact_fmt_needs_wrap(while_line) != 0) && ((int64_t)(intptr_t)pact_list_get(np_kind, cond) == pact_NodeKind_BinOp))) {
            pact_fmt_emit("while");
            fmt_indent = (fmt_indent + 1);
            pact_emit_binop_wrapped(cond, "");
            fmt_indent = (fmt_indent - 1);
            pact_fmt_emit("{");
        } else {
            pact_fmt_emit(while_line);
        }
        fmt_indent = (fmt_indent + 1);
        pact_format_block_body(body);
        fmt_indent = (fmt_indent - 1);
        pact_fmt_emit("}");
        return;
    }
    if ((kind == pact_NodeKind_LoopExpr)) {
        const int64_t body = (int64_t)(intptr_t)pact_list_get(np_body, node);
        pact_fmt_emit("loop {");
        fmt_indent = (fmt_indent + 1);
        pact_format_block_body(body);
        fmt_indent = (fmt_indent - 1);
        pact_fmt_emit("}");
        return;
    }
    if ((kind == pact_NodeKind_WithBlock)) {
        pact_format_with_block(node);
        return;
    }
    if ((kind == pact_NodeKind_Block)) {
        pact_format_block_body(node);
        return;
    }
    pact_fmt_emit(pact_format_expr(node));
}

void pact_format_if_stmt(int64_t node) {
    pact_format_if_chain(node, "if");
}

void pact_format_if_chain(int64_t node, const char* prefix) {
    const int64_t cond = (int64_t)(intptr_t)pact_list_get(np_condition, node);
    const int64_t then_b = (int64_t)(intptr_t)pact_list_get(np_then_body, node);
    const int64_t else_b = (int64_t)(intptr_t)pact_list_get(np_else_body, node);
    const char* cond_str = pact_format_expr(cond);
    char _si_0[4096];
    snprintf(_si_0, 4096, "%s %s {", prefix, cond_str);
    const char* if_line = strdup(_si_0);
    if (((pact_fmt_needs_wrap(if_line) != 0) && ((int64_t)(intptr_t)pact_list_get(np_kind, cond) == pact_NodeKind_BinOp))) {
        char _si_1[4096];
        snprintf(_si_1, 4096, "%s", prefix);
        pact_fmt_emit(strdup(_si_1));
        fmt_indent = (fmt_indent + 1);
        pact_emit_binop_wrapped(cond, "");
        fmt_indent = (fmt_indent - 1);
        pact_fmt_emit("{");
    } else {
        pact_fmt_emit(if_line);
    }
    fmt_indent = (fmt_indent + 1);
    pact_format_block_body(then_b);
    fmt_indent = (fmt_indent - 1);
    if ((else_b != (-1))) {
        const int64_t else_stmts = (int64_t)(intptr_t)pact_list_get(np_stmts, else_b);
        if (((else_stmts != (-1)) && (pact_sublist_length(else_stmts) == 1))) {
            const int64_t inner = pact_sublist_get(else_stmts, 0);
            if (((int64_t)(intptr_t)pact_list_get(np_kind, inner) == pact_NodeKind_IfExpr)) {
                pact_format_if_chain(inner, "} else if");
                return;
            }
        }
        pact_fmt_emit("} else {");
        fmt_indent = (fmt_indent + 1);
        pact_format_block_body(else_b);
        fmt_indent = (fmt_indent - 1);
        pact_fmt_emit("}");
    } else {
        pact_fmt_emit("}");
    }
}

const char* pact_format_else_if(int64_t node) {
    return "";
}

void pact_format_match_stmt(int64_t node) {
    const int64_t scrut = (int64_t)(intptr_t)pact_list_get(np_scrutinee, node);
    const int64_t arms_sl = (int64_t)(intptr_t)pact_list_get(np_arms, node);
    char _si_0[4096];
    snprintf(_si_0, 4096, "match %s {", pact_format_expr(scrut));
    pact_fmt_emit(strdup(_si_0));
    fmt_indent = (fmt_indent + 1);
    if ((arms_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(arms_sl))) {
            pact_format_match_arm(pact_sublist_get(arms_sl, i));
            i = (i + 1);
        }
    }
    fmt_indent = (fmt_indent - 1);
    pact_fmt_emit("}");
}

void pact_format_match_arm(int64_t node) {
    const int64_t pat = (int64_t)(intptr_t)pact_list_get(np_pattern, node);
    const int64_t guard = (int64_t)(intptr_t)pact_list_get(np_guard, node);
    const int64_t body = (int64_t)(intptr_t)pact_list_get(np_body, node);
    const char* line = pact_format_pattern(pat);
    if ((guard != (-1))) {
        line = pact_str_concat(pact_str_concat(line, " if "), pact_format_expr(guard));
    }
    line = pact_str_concat(line, " => ");
    const int64_t body_kind = (int64_t)(intptr_t)pact_list_get(np_kind, body);
    if ((body_kind == pact_NodeKind_Block)) {
        const int64_t stmts_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, body);
        if (((stmts_sl != (-1)) && (pact_sublist_length(stmts_sl) == 1))) {
            const int64_t inner = pact_sublist_get(stmts_sl, 0);
            const int64_t ik = (int64_t)(intptr_t)pact_list_get(np_kind, inner);
            if ((ik == pact_NodeKind_ExprStmt)) {
                pact_fmt_emit(pact_str_concat(line, pact_format_expr((int64_t)(intptr_t)pact_list_get(np_value, inner))));
                return;
            }
            if (pact_is_simple_expr_kind(ik)) {
                pact_fmt_emit(pact_str_concat(line, pact_format_expr(inner)));
                return;
            }
        }
        pact_fmt_emit(pact_str_concat(line, "{"));
        fmt_indent = (fmt_indent + 1);
        pact_format_block_body(body);
        fmt_indent = (fmt_indent - 1);
        pact_fmt_emit("}");
    } else if ((body_kind == pact_NodeKind_ExprStmt)) {
        pact_fmt_emit(pact_str_concat(line, pact_format_expr((int64_t)(intptr_t)pact_list_get(np_value, body))));
    } else {
        if (pact_is_simple_expr_kind(body_kind)) {
            pact_fmt_emit(pact_str_concat(line, pact_format_expr(body)));
        } else {
            pact_fmt_emit(pact_str_concat(line, "{"));
            fmt_indent = (fmt_indent + 1);
            pact_format_stmt(body);
            fmt_indent = (fmt_indent - 1);
            pact_fmt_emit("}");
        }
    }
}

void pact_format_with_block(int64_t node) {
    const int64_t handlers_sl = (int64_t)(intptr_t)pact_list_get(np_handlers, node);
    const int64_t body = (int64_t)(intptr_t)pact_list_get(np_body, node);
    const char* line = "with ";
    if ((handlers_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(handlers_sl))) {
            if ((i > 0)) {
                line = pact_str_concat(line, ", ");
            }
            const int64_t h = pact_sublist_get(handlers_sl, i);
            const int64_t hk = (int64_t)(intptr_t)pact_list_get(np_kind, h);
            if ((hk == pact_NodeKind_WithResource)) {
                const int64_t val = (int64_t)(intptr_t)pact_list_get(np_value, h);
                const char* binding = (const char*)pact_list_get(np_name, h);
                line = pact_str_concat(pact_str_concat(pact_str_concat(line, pact_format_expr(val)), " as "), binding);
            } else {
                line = pact_str_concat(line, pact_format_expr(h));
            }
            i = (i + 1);
        }
    }
    pact_fmt_emit(pact_str_concat(line, " {"));
    fmt_indent = (fmt_indent + 1);
    pact_format_block_body(body);
    fmt_indent = (fmt_indent - 1);
    pact_fmt_emit("}");
}

void pact_format_block_body(int64_t node) {
    if ((node == (-1))) {
        return;
    }
    const int64_t stmts_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, node);
    if ((stmts_sl == (-1))) {
        return;
    }
    int64_t i = 0;
    while ((i < pact_sublist_length(stmts_sl))) {
        pact_format_stmt(pact_sublist_get(stmts_sl, i));
        i = (i + 1);
    }
}

const char* pact_format_fn_sig_suffix(const char* ret, int64_t ret_ann, int64_t effects_sl) {
    const char* suffix = "";
    if ((!pact_str_eq(ret, ""))) {
        if ((ret_ann != (-1))) {
            suffix = pact_str_concat(pact_str_concat(suffix, " -> "), pact_format_type_ann(ret_ann));
        } else {
            suffix = pact_str_concat(pact_str_concat(suffix, " -> "), ret);
        }
    }
    if (((effects_sl != (-1)) && (pact_sublist_length(effects_sl) > 0))) {
        suffix = pact_str_concat(suffix, " ! ");
        int64_t i = 0;
        while ((i < pact_sublist_length(effects_sl))) {
            if ((i > 0)) {
                suffix = pact_str_concat(suffix, ", ");
            }
            suffix = pact_str_concat(suffix, (const char*)pact_list_get(np_name, pact_sublist_get(effects_sl, i)));
            i = (i + 1);
        }
    }
    return suffix;
}

void pact_format_fn_def(int64_t node) {
    pact_emit_comments(node);
    const char* name = (const char*)pact_list_get(np_name, node);
    const int64_t is_pub = (int64_t)(intptr_t)pact_list_get(np_is_pub, node);
    const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, node);
    const char* ret = (const char*)pact_list_get(np_return_type, node);
    const int64_t ret_ann = (int64_t)(intptr_t)pact_list_get(np_type_ann, node);
    const int64_t body = (int64_t)(intptr_t)pact_list_get(np_body, node);
    const int64_t effects_sl = (int64_t)(intptr_t)pact_list_get(np_effects, node);
    const int64_t tparams = (int64_t)(intptr_t)pact_list_get(np_type_params, node);
    const char* line = "";
    if ((is_pub != 0)) {
        line = "pub ";
    }
    line = pact_str_concat(pact_str_concat(line, "fn "), name);
    if (((tparams != (-1)) && (pact_sublist_length(tparams) > 0))) {
        line = pact_str_concat(line, "[");
        int64_t i = 0;
        while ((i < pact_sublist_length(tparams))) {
            if ((i > 0)) {
                line = pact_str_concat(line, ", ");
            }
            const int64_t tp = pact_sublist_get(tparams, i);
            line = pact_str_concat(line, (const char*)pact_list_get(np_name, tp));
            i = (i + 1);
        }
        line = pact_str_concat(line, "]");
    }
    line = pact_str_concat(line, "(");
    if ((params_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(params_sl))) {
            if ((i > 0)) {
                line = pact_str_concat(line, ", ");
            }
            line = pact_str_concat(line, pact_format_param(pact_sublist_get(params_sl, i)));
            i = (i + 1);
        }
    }
    line = pact_str_concat(line, ")");
    const char* suffix = pact_format_fn_sig_suffix(ret, ret_ann, effects_sl);
    line = pact_str_concat(line, suffix);
    if ((body != (-1))) {
        const char* full_line = pact_str_concat(line, " {");
        if ((((pact_fmt_needs_wrap(full_line) != 0) && (params_sl != (-1))) && (pact_sublist_length(params_sl) > 0))) {
            const char* fn_prefix = "";
            if ((is_pub != 0)) {
                fn_prefix = "pub ";
            }
            fn_prefix = pact_str_concat(pact_str_concat(fn_prefix, "fn "), name);
            if (((tparams != (-1)) && (pact_sublist_length(tparams) > 0))) {
                fn_prefix = pact_str_concat(fn_prefix, "[");
                int64_t ti = 0;
                while ((ti < pact_sublist_length(tparams))) {
                    if ((ti > 0)) {
                        fn_prefix = pact_str_concat(fn_prefix, ", ");
                    }
                    fn_prefix = pact_str_concat(fn_prefix, (const char*)pact_list_get(np_name, pact_sublist_get(tparams, ti)));
                    ti = (ti + 1);
                }
                fn_prefix = pact_str_concat(fn_prefix, "]");
            }
            pact_fmt_emit(pact_str_concat(fn_prefix, "("));
            fmt_indent = (fmt_indent + 1);
            int64_t pi = 0;
            while ((pi < pact_sublist_length(params_sl))) {
                const char* p_str = pact_format_param(pact_sublist_get(params_sl, pi));
                if ((pi < (pact_sublist_length(params_sl) - 1))) {
                    pact_fmt_emit(pact_str_concat(p_str, ","));
                } else {
                    pact_fmt_emit(p_str);
                }
                pi = (pi + 1);
            }
            fmt_indent = (fmt_indent - 1);
            pact_fmt_emit(pact_str_concat(pact_str_concat(")", suffix), " {"));
        } else {
            pact_fmt_emit(full_line);
        }
        fmt_indent = (fmt_indent + 1);
        pact_format_block_body(body);
        fmt_indent = (fmt_indent - 1);
        pact_fmt_emit("}");
    } else if ((((pact_fmt_needs_wrap(line) != 0) && (params_sl != (-1))) && (pact_sublist_length(params_sl) > 0))) {
        const char* fn_prefix = "";
        if ((is_pub != 0)) {
            fn_prefix = "pub ";
        }
        fn_prefix = pact_str_concat(pact_str_concat(fn_prefix, "fn "), name);
        if (((tparams != (-1)) && (pact_sublist_length(tparams) > 0))) {
            fn_prefix = pact_str_concat(fn_prefix, "[");
            int64_t ti = 0;
            while ((ti < pact_sublist_length(tparams))) {
                if ((ti > 0)) {
                    fn_prefix = pact_str_concat(fn_prefix, ", ");
                }
                fn_prefix = pact_str_concat(fn_prefix, (const char*)pact_list_get(np_name, pact_sublist_get(tparams, ti)));
                ti = (ti + 1);
            }
            fn_prefix = pact_str_concat(fn_prefix, "]");
        }
        pact_fmt_emit(pact_str_concat(fn_prefix, "("));
        fmt_indent = (fmt_indent + 1);
        int64_t pi = 0;
        while ((pi < pact_sublist_length(params_sl))) {
            const char* p_str = pact_format_param(pact_sublist_get(params_sl, pi));
            if ((pi < (pact_sublist_length(params_sl) - 1))) {
                pact_fmt_emit(pact_str_concat(p_str, ","));
            } else {
                pact_fmt_emit(p_str);
            }
            pi = (pi + 1);
        }
        fmt_indent = (fmt_indent - 1);
        pact_fmt_emit(pact_str_concat(")", suffix));
    } else {
        pact_fmt_emit(line);
    }
}

void pact_format_type_def(int64_t node) {
    pact_emit_comments(node);
    const char* name = (const char*)pact_list_get(np_name, node);
    const int64_t is_pub = (int64_t)(intptr_t)pact_list_get(np_is_pub, node);
    const int64_t flds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, node);
    const int64_t tparams = (int64_t)(intptr_t)pact_list_get(np_type_params, node);
    const char* line = "";
    if ((is_pub != 0)) {
        line = "pub ";
    }
    line = pact_str_concat(pact_str_concat(line, "type "), name);
    if (((tparams != (-1)) && (pact_sublist_length(tparams) > 0))) {
        line = pact_str_concat(line, "[");
        int64_t i = 0;
        while ((i < pact_sublist_length(tparams))) {
            if ((i > 0)) {
                line = pact_str_concat(line, ", ");
            }
            const int64_t tp = pact_sublist_get(tparams, i);
            line = pact_str_concat(line, (const char*)pact_list_get(np_name, tp));
            i = (i + 1);
        }
        line = pact_str_concat(line, "]");
    }
    if (((flds_sl == (-1)) || (pact_sublist_length(flds_sl) == 0))) {
        pact_fmt_emit(line);
        return;
    }
    const int64_t first = pact_sublist_get(flds_sl, 0);
    const int64_t first_kind = (int64_t)(intptr_t)pact_list_get(np_kind, first);
    if ((first_kind == pact_NodeKind_TypeVariant)) {
        pact_fmt_emit(pact_str_concat(line, " {"));
        fmt_indent = (fmt_indent + 1);
        int64_t i = 0;
        while ((i < pact_sublist_length(flds_sl))) {
            const int64_t v = pact_sublist_get(flds_sl, i);
            const char* vname = (const char*)pact_list_get(np_name, v);
            const int64_t vflds_sl = (int64_t)(intptr_t)pact_list_get(np_fields, v);
            if (((vflds_sl != (-1)) && (pact_sublist_length(vflds_sl) > 0))) {
                const char* vline = pact_str_concat(vname, "(");
                int64_t j = 0;
                while ((j < pact_sublist_length(vflds_sl))) {
                    if ((j > 0)) {
                        vline = pact_str_concat(vline, ", ");
                    }
                    const int64_t vf = pact_sublist_get(vflds_sl, j);
                    const char* vfn = (const char*)pact_list_get(np_name, vf);
                    const int64_t vft = (int64_t)(intptr_t)pact_list_get(np_value, vf);
                    vline = pact_str_concat(pact_str_concat(pact_str_concat(vline, vfn), ": "), pact_format_type_ann(vft));
                    j = (j + 1);
                }
                vline = pact_str_concat(vline, ")");
                if ((i < (pact_sublist_length(flds_sl) - 1))) {
                    vline = pact_str_concat(vline, ",");
                }
                pact_fmt_emit(vline);
            } else {
                const char* vline = vname;
                if ((i < (pact_sublist_length(flds_sl) - 1))) {
                    vline = pact_str_concat(vline, ",");
                }
                pact_fmt_emit(vline);
            }
            i = (i + 1);
        }
        fmt_indent = (fmt_indent - 1);
        pact_fmt_emit("}");
    } else if ((first_kind == pact_NodeKind_TypeField)) {
        pact_fmt_emit(pact_str_concat(line, " {"));
        fmt_indent = (fmt_indent + 1);
        int64_t i = 0;
        while ((i < pact_sublist_length(flds_sl))) {
            const int64_t f = pact_sublist_get(flds_sl, i);
            const char* fname = (const char*)pact_list_get(np_name, f);
            const int64_t ftype = (int64_t)(intptr_t)pact_list_get(np_value, f);
            char _si_0[4096];
            snprintf(_si_0, 4096, "%s: %s", fname, pact_format_type_ann(ftype));
            pact_fmt_emit(strdup(_si_0));
            i = (i + 1);
        }
        fmt_indent = (fmt_indent - 1);
        pact_fmt_emit("}");
    } else {
        pact_fmt_emit(line);
    }
}

void pact_format_trait_def(int64_t node) {
    pact_emit_comments(node);
    const char* name = (const char*)pact_list_get(np_name, node);
    const int64_t is_pub = (int64_t)(intptr_t)pact_list_get(np_is_pub, node);
    const int64_t methods_sl = (int64_t)(intptr_t)pact_list_get(np_methods, node);
    const int64_t tparams = (int64_t)(intptr_t)pact_list_get(np_type_params, node);
    const char* line = "";
    if ((is_pub != 0)) {
        line = "pub ";
    }
    line = pact_str_concat(pact_str_concat(line, "trait "), name);
    if (((tparams != (-1)) && (pact_sublist_length(tparams) > 0))) {
        line = pact_str_concat(line, "[");
        int64_t i = 0;
        while ((i < pact_sublist_length(tparams))) {
            if ((i > 0)) {
                line = pact_str_concat(line, ", ");
            }
            line = pact_str_concat(line, pact_format_type_ann(pact_sublist_get(tparams, i)));
            i = (i + 1);
        }
        line = pact_str_concat(line, "]");
    }
    line = pact_str_concat(line, " {");
    pact_fmt_emit(line);
    fmt_indent = (fmt_indent + 1);
    if ((methods_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(methods_sl))) {
            if ((i > 0)) {
                pact_fmt_emit("");
            }
            pact_format_fn_def(pact_sublist_get(methods_sl, i));
            i = (i + 1);
        }
    }
    fmt_indent = (fmt_indent - 1);
    pact_fmt_emit("}");
}

void pact_format_impl_block(int64_t node) {
    pact_emit_comments(node);
    const char* trait_name = (const char*)pact_list_get(np_trait_name, node);
    const char* type_name = (const char*)pact_list_get(np_name, node);
    const int64_t methods_sl = (int64_t)(intptr_t)pact_list_get(np_methods, node);
    const int64_t tparams = (int64_t)(intptr_t)pact_list_get(np_type_params, node);
    const char* line = pact_str_concat("impl ", trait_name);
    if (((tparams != (-1)) && (pact_sublist_length(tparams) > 0))) {
        line = pact_str_concat(line, "[");
        int64_t i = 0;
        while ((i < pact_sublist_length(tparams))) {
            if ((i > 0)) {
                line = pact_str_concat(line, ", ");
            }
            line = pact_str_concat(line, pact_format_type_ann(pact_sublist_get(tparams, i)));
            i = (i + 1);
        }
        line = pact_str_concat(line, "]");
    }
    if ((!pact_str_eq(type_name, ""))) {
        line = pact_str_concat(pact_str_concat(line, " for "), type_name);
    }
    line = pact_str_concat(line, " {");
    pact_fmt_emit(line);
    fmt_indent = (fmt_indent + 1);
    if ((methods_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(methods_sl))) {
            if ((i > 0)) {
                pact_fmt_emit("");
            }
            pact_format_fn_def(pact_sublist_get(methods_sl, i));
            i = (i + 1);
        }
    }
    fmt_indent = (fmt_indent - 1);
    pact_fmt_emit("}");
}

void pact_format_test_block(int64_t node) {
    pact_emit_comments(node);
    const char* name = (const char*)pact_list_get(np_name, node);
    const int64_t body = (int64_t)(intptr_t)pact_list_get(np_body, node);
    char _si_0[4096];
    snprintf(_si_0, 4096, "test \"%s\" {", name);
    pact_fmt_emit(strdup(_si_0));
    fmt_indent = (fmt_indent + 1);
    pact_format_block_body(body);
    fmt_indent = (fmt_indent - 1);
    pact_fmt_emit("}");
}

int64_t pact_annotation_order(const char* name) {
    if (pact_str_eq(name, "mod")) {
        return 0;
    }
    if (pact_str_eq(name, "capabilities")) {
        return 1;
    }
    if (pact_str_eq(name, "derive")) {
        return 2;
    }
    if (pact_str_eq(name, "src")) {
        return 3;
    }
    if (pact_str_eq(name, "requires")) {
        return 4;
    }
    if (pact_str_eq(name, "ensures")) {
        return 5;
    }
    if (pact_str_eq(name, "where")) {
        return 6;
    }
    if (pact_str_eq(name, "invariant")) {
        return 7;
    }
    if (pact_str_eq(name, "perf")) {
        return 8;
    }
    if (pact_str_eq(name, "ffi")) {
        return 9;
    }
    if (pact_str_eq(name, "trusted")) {
        return 10;
    }
    if (pact_str_eq(name, "effects")) {
        return 11;
    }
    if (pact_str_eq(name, "alt")) {
        return 12;
    }
    if (pact_str_eq(name, "verify")) {
        return 13;
    }
    if (pact_str_eq(name, "deprecated")) {
        return 14;
    }
    return 99;
}

void pact_format_annotation(int64_t node) {
    const char* name = (const char*)pact_list_get(np_name, node);
    const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
    const char* line = pact_str_concat("@", name);
    if (((args_sl != (-1)) && (pact_sublist_length(args_sl) > 0))) {
        line = pact_str_concat(line, "(");
        int64_t i = 0;
        while ((i < pact_sublist_length(args_sl))) {
            if ((i > 0)) {
                line = pact_str_concat(line, ", ");
            }
            line = pact_str_concat(line, (const char*)pact_list_get(np_name, pact_sublist_get(args_sl, i)));
            i = (i + 1);
        }
        line = pact_str_concat(line, ")");
    }
    pact_fmt_emit(line);
}

void pact_format_import(int64_t node) {
    pact_emit_comments(node);
    const char* path = (const char*)pact_list_get(np_str_val, node);
    const int64_t names_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
    const char* line = pact_str_concat("import ", path);
    if (((names_sl != (-1)) && (pact_sublist_length(names_sl) > 0))) {
        line = pact_str_concat(line, " { ");
        int64_t i = 0;
        while ((i < pact_sublist_length(names_sl))) {
            if ((i > 0)) {
                line = pact_str_concat(line, ", ");
            }
            line = pact_str_concat(line, (const char*)pact_list_get(np_name, pact_sublist_get(names_sl, i)));
            i = (i + 1);
        }
        line = pact_str_concat(line, " }");
    }
    pact_fmt_emit(line);
}

void pact_format_effect_decl(int64_t node) {
    pact_emit_comments(node);
    const char* name = (const char*)pact_list_get(np_name, node);
    const int64_t is_pub = (int64_t)(intptr_t)pact_list_get(np_is_pub, node);
    const int64_t children_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
    const char* line = "";
    if ((is_pub != 0)) {
        line = "pub ";
    }
    line = pact_str_concat(pact_str_concat(line, "effect "), name);
    if (((children_sl == (-1)) || (pact_sublist_length(children_sl) == 0))) {
        pact_fmt_emit(line);
        return;
    }
    pact_fmt_emit(pact_str_concat(line, " {"));
    fmt_indent = (fmt_indent + 1);
    int64_t i = 0;
    while ((i < pact_sublist_length(children_sl))) {
        const int64_t child = pact_sublist_get(children_sl, i);
        const char* child_name = (const char*)pact_list_get(np_name, child);
        const int64_t child_ops = (int64_t)(intptr_t)pact_list_get(np_methods, child);
        if (((child_ops != (-1)) && (pact_sublist_length(child_ops) > 0))) {
            char _si_0[4096];
            snprintf(_si_0, 4096, "effect %s {", child_name);
            pact_fmt_emit(strdup(_si_0));
            fmt_indent = (fmt_indent + 1);
            int64_t j = 0;
            while ((j < pact_sublist_length(child_ops))) {
                const int64_t op = pact_sublist_get(child_ops, j);
                pact_format_effect_op_sig(op);
                j = (j + 1);
            }
            fmt_indent = (fmt_indent - 1);
            pact_fmt_emit("}");
        } else {
            char _si_1[4096];
            snprintf(_si_1, 4096, "effect %s", child_name);
            pact_fmt_emit(strdup(_si_1));
        }
        i = (i + 1);
    }
    fmt_indent = (fmt_indent - 1);
    pact_fmt_emit("}");
}

void pact_format_effect_op_sig(int64_t node) {
    const char* name = (const char*)pact_list_get(np_name, node);
    const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, node);
    const char* ret = (const char*)pact_list_get(np_return_type, node);
    const char* line = pact_str_concat(pact_str_concat("fn ", name), "(");
    if ((params_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(params_sl))) {
            if ((i > 0)) {
                line = pact_str_concat(line, ", ");
            }
            line = pact_str_concat(line, pact_format_param(pact_sublist_get(params_sl, i)));
            i = (i + 1);
        }
    }
    line = pact_str_concat(line, ")");
    if ((!pact_str_eq(ret, ""))) {
        line = pact_str_concat(pact_str_concat(line, " -> "), ret);
    }
    pact_fmt_emit(line);
}

const char* pact_format(int64_t program) {
    pact_list* _l0 = pact_list_new();
    fmt_lines = _l0;
    fmt_indent = 0;
    const int64_t imports_sl = (int64_t)(intptr_t)pact_list_get(np_elements, program);
    if (((imports_sl != (-1)) && (pact_sublist_length(imports_sl) > 0))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(imports_sl))) {
            pact_format_import(pact_sublist_get(imports_sl, i));
            i = (i + 1);
        }
        pact_fmt_emit("");
    }
    const int64_t anns_sl = (int64_t)(intptr_t)pact_list_get(np_handlers, program);
    if (((anns_sl != (-1)) && (pact_sublist_length(anns_sl) > 0))) {
        const int64_t ann_count = pact_sublist_length(anns_sl);
        pact_list* _l1 = pact_list_new();
        pact_list* sorted_anns = _l1;
        int64_t i = 0;
        while ((i < ann_count)) {
            pact_list_push(sorted_anns, (void*)(intptr_t)pact_sublist_get(anns_sl, i));
            i = (i + 1);
        }
        int64_t si = 0;
        while ((si < (ann_count - 1))) {
            int64_t min_idx = si;
            int64_t sj = (si + 1);
            while ((sj < ann_count)) {
                if ((pact_annotation_order((const char*)pact_list_get(np_name, (int64_t)(intptr_t)pact_list_get(sorted_anns, sj))) < pact_annotation_order((const char*)pact_list_get(np_name, (int64_t)(intptr_t)pact_list_get(sorted_anns, min_idx))))) {
                    min_idx = sj;
                }
                sj = (sj + 1);
            }
            if ((min_idx != si)) {
                const int64_t tmp = (int64_t)(intptr_t)pact_list_get(sorted_anns, si);
                pact_list_set(sorted_anns, si, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(sorted_anns, min_idx));
                pact_list_set(sorted_anns, min_idx, (void*)(intptr_t)tmp);
            }
            si = (si + 1);
        }
        i = 0;
        while ((i < ann_count)) {
            pact_format_annotation((int64_t)(intptr_t)pact_list_get(sorted_anns, i));
            i = (i + 1);
        }
        pact_fmt_emit("");
    }
    const int64_t effects_sl = (int64_t)(intptr_t)pact_list_get(np_args, program);
    if (((effects_sl != (-1)) && (pact_sublist_length(effects_sl) > 0))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(effects_sl))) {
            pact_format_effect_decl(pact_sublist_get(effects_sl, i));
            pact_fmt_emit("");
            i = (i + 1);
        }
    }
    const int64_t types_sl = (int64_t)(intptr_t)pact_list_get(np_fields, program);
    if (((types_sl != (-1)) && (pact_sublist_length(types_sl) > 0))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(types_sl))) {
            pact_format_type_def(pact_sublist_get(types_sl, i));
            pact_fmt_emit("");
            i = (i + 1);
        }
    }
    const int64_t lets_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, program);
    if (((lets_sl != (-1)) && (pact_sublist_length(lets_sl) > 0))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(lets_sl))) {
            pact_format_stmt(pact_sublist_get(lets_sl, i));
            i = (i + 1);
        }
        pact_fmt_emit("");
    }
    const int64_t traits_sl = (int64_t)(intptr_t)pact_list_get(np_arms, program);
    if (((traits_sl != (-1)) && (pact_sublist_length(traits_sl) > 0))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(traits_sl))) {
            pact_format_trait_def(pact_sublist_get(traits_sl, i));
            pact_fmt_emit("");
            i = (i + 1);
        }
    }
    const int64_t impls_sl = (int64_t)(intptr_t)pact_list_get(np_methods, program);
    if (((impls_sl != (-1)) && (pact_sublist_length(impls_sl) > 0))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(impls_sl))) {
            pact_format_impl_block(pact_sublist_get(impls_sl, i));
            pact_fmt_emit("");
            i = (i + 1);
        }
    }
    const int64_t fns_sl = (int64_t)(intptr_t)pact_list_get(np_params, program);
    if (((fns_sl != (-1)) && (pact_sublist_length(fns_sl) > 0))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(fns_sl))) {
            pact_format_fn_def(pact_sublist_get(fns_sl, i));
            pact_fmt_emit("");
            i = (i + 1);
        }
    }
    const int64_t tests_sl = (int64_t)(intptr_t)pact_list_get(np_captures, program);
    if (((tests_sl != (-1)) && (pact_sublist_length(tests_sl) > 0))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(tests_sl))) {
            pact_format_test_block(pact_sublist_get(tests_sl, i));
            pact_fmt_emit("");
            i = (i + 1);
        }
    }
    while (((pact_list_len(fmt_lines) > 0) && pact_str_eq((const char*)pact_list_get(fmt_lines, (pact_list_len(fmt_lines) - 1)), ""))) {
        pact_list_pop(fmt_lines);
    }
    pact_list_push(fmt_lines, (void*)"");
    return pact_fmt_join();
}

void pact_init_mutating_methods(void) {
    if ((pact_map_len(mutating_method_set) > 0)) {
        return;
    }
    pact_map_set(mutating_method_set, "push", (void*)(intptr_t)1);
    pact_map_set(mutating_method_set, "pop", (void*)(intptr_t)1);
    pact_map_set(mutating_method_set, "append", (void*)(intptr_t)1);
    pact_map_set(mutating_method_set, "clear", (void*)(intptr_t)1);
    pact_map_set(mutating_method_set, "insert", (void*)(intptr_t)1);
    pact_map_set(mutating_method_set, "remove", (void*)(intptr_t)1);
    pact_map_set(mutating_method_set, "set", (void*)(intptr_t)1);
}

int64_t pact_is_mutating_method(const char* name) {
    return pact_map_has(mutating_method_set, name);
}

int64_t pact_is_global(const char* name) {
    return pact_map_has(global_set, name);
}

int64_t pact_fn_index(const char* name) {
    if ((pact_map_has(fn_name_map, name) != 0)) {
        return (int64_t)(intptr_t)pact_map_get(fn_name_map, name);
    }
    return (-1);
}

int64_t pact_global_index(const char* name) {
    if ((pact_map_has(global_idx_map, name) != 0)) {
        return (int64_t)(intptr_t)pact_map_get(global_idx_map, name);
    }
    return (-1);
}

int64_t pact_mat_has_write(int64_t fn_idx, int64_t gi) {
    return (int64_t)(intptr_t)pact_list_get(writes_mat, ((fn_idx * writes_mat_cols) + gi));
}

void pact_mat_set_write(int64_t fn_idx, int64_t gi) {
    pact_list_set(writes_mat, ((fn_idx * writes_mat_cols) + gi), (void*)(intptr_t)1);
}

int64_t pact_fn_has_write(int64_t fn_idx, const char* global_name) {
    const int64_t gi = pact_global_index(global_name);
    if ((gi < 0)) {
        return 0;
    }
    return pact_mat_has_write(fn_idx, gi);
}

void pact_add_write(int64_t fn_idx, const char* global_name) {
    const int64_t gi = pact_global_index(global_name);
    if ((gi < 0)) {
        return;
    }
    if ((pact_mat_has_write(fn_idx, gi) != 0)) {
        return;
    }
    pact_mat_set_write(fn_idx, gi);
    pact_list_push(ma_write_items, (void*)global_name);
    pact_list_set(ma_write_counts, fn_idx, (void*)(intptr_t)((int64_t)(intptr_t)pact_list_get(ma_write_counts, fn_idx) + 1));
}

const char* pact_extract_ident_name(int64_t node) {
    if ((node == (-1))) {
        return "";
    }
    if (((int64_t)(intptr_t)pact_list_get(np_kind, node) == pact_NodeKind_Ident)) {
        return (const char*)pact_list_get(np_name, node);
    }
    return "";
}

void pact_walk_expr(int64_t node, int64_t fn_idx) {
    if ((node == (-1))) {
        return;
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if (((kind == pact_NodeKind_Assignment) || (kind == pact_NodeKind_CompoundAssign))) {
        const int64_t target = (int64_t)(intptr_t)pact_list_get(np_target, node);
        if ((target != (-1))) {
            const int64_t tk = (int64_t)(intptr_t)pact_list_get(np_kind, target);
            if ((tk == pact_NodeKind_Ident)) {
                const char* tname = (const char*)pact_list_get(np_name, target);
                if ((pact_is_global(tname) != 0)) {
                    pact_add_write(fn_idx, tname);
                }
            }
            if ((tk == pact_NodeKind_FieldAccess)) {
                const int64_t obj = (int64_t)(intptr_t)pact_list_get(np_obj, target);
                if (((obj != (-1)) && ((int64_t)(intptr_t)pact_list_get(np_kind, obj) == pact_NodeKind_Ident))) {
                    const char* oname = (const char*)pact_list_get(np_name, obj);
                    if ((pact_is_global(oname) != 0)) {
                        pact_add_write(fn_idx, oname);
                    }
                }
            }
            if ((tk == pact_NodeKind_IndexExpr)) {
                const int64_t obj = (int64_t)(intptr_t)pact_list_get(np_obj, target);
                if (((obj != (-1)) && ((int64_t)(intptr_t)pact_list_get(np_kind, obj) == pact_NodeKind_Ident))) {
                    const char* oname = (const char*)pact_list_get(np_name, obj);
                    if ((pact_is_global(oname) != 0)) {
                        pact_add_write(fn_idx, oname);
                    }
                }
            }
        }
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_value, node), fn_idx);
        return;
    }
    if ((kind == pact_NodeKind_MethodCall)) {
        const int64_t obj = (int64_t)(intptr_t)pact_list_get(np_obj, node);
        const char* method = (const char*)pact_list_get(np_method, node);
        if (((obj != (-1)) && ((int64_t)(intptr_t)pact_list_get(np_kind, obj) == pact_NodeKind_Ident))) {
            const char* oname = (const char*)pact_list_get(np_name, obj);
            if (((pact_is_global(oname) != 0) && (pact_is_mutating_method(method) != 0))) {
                pact_add_write(fn_idx, oname);
            }
        }
        pact_walk_expr(obj, fn_idx);
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if ((args_sl != (-1))) {
            int64_t ai = 0;
            while ((ai < pact_sublist_length(args_sl))) {
                pact_walk_expr(pact_sublist_get(args_sl, ai), fn_idx);
                ai = (ai + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_Call)) {
        const int64_t callee = (int64_t)(intptr_t)pact_list_get(np_left, node);
        const char* callee_name = pact_extract_ident_name(callee);
        if ((!pact_str_eq(callee_name, ""))) {
            const int64_t callee_idx = pact_fn_index(callee_name);
            if ((callee_idx >= 0)) {
                pact_list_push(ma_call_edges_from, (void*)(intptr_t)fn_idx);
                pact_list_push(ma_call_edges_to, (void*)(intptr_t)callee_idx);
            }
        }
        pact_walk_expr(callee, fn_idx);
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if ((args_sl != (-1))) {
            int64_t ai = 0;
            while ((ai < pact_sublist_length(args_sl))) {
                pact_walk_expr(pact_sublist_get(args_sl, ai), fn_idx);
                ai = (ai + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_BinOp)) {
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_left, node), fn_idx);
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_right, node), fn_idx);
        return;
    }
    if ((kind == pact_NodeKind_UnaryOp)) {
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_left, node), fn_idx);
        return;
    }
    if ((kind == pact_NodeKind_IfExpr)) {
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_condition, node), fn_idx);
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_then_body, node), fn_idx);
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_else_body, node), fn_idx);
        return;
    }
    if ((kind == pact_NodeKind_Block)) {
        pact_walk_stmts((int64_t)(intptr_t)pact_list_get(np_stmts, node), fn_idx);
        return;
    }
    if ((kind == pact_NodeKind_LetBinding)) {
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_value, node), fn_idx);
        return;
    }
    if ((kind == pact_NodeKind_ExprStmt)) {
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_value, node), fn_idx);
        return;
    }
    if ((kind == pact_NodeKind_Return)) {
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_value, node), fn_idx);
        return;
    }
    if ((kind == pact_NodeKind_ForIn)) {
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_iterable, node), fn_idx);
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_body, node), fn_idx);
        return;
    }
    if ((kind == pact_NodeKind_WhileLoop)) {
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_condition, node), fn_idx);
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_body, node), fn_idx);
        return;
    }
    if ((kind == pact_NodeKind_LoopExpr)) {
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_body, node), fn_idx);
        return;
    }
    if ((kind == pact_NodeKind_MatchExpr)) {
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_scrutinee, node), fn_idx);
        const int64_t arms_sl = (int64_t)(intptr_t)pact_list_get(np_arms, node);
        if ((arms_sl != (-1))) {
            int64_t ai = 0;
            while ((ai < pact_sublist_length(arms_sl))) {
                const int64_t arm = pact_sublist_get(arms_sl, ai);
                pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_guard, arm), fn_idx);
                pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_body, arm), fn_idx);
                ai = (ai + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_FieldAccess)) {
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_obj, node), fn_idx);
        return;
    }
    if ((kind == pact_NodeKind_IndexExpr)) {
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_obj, node), fn_idx);
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_index, node), fn_idx);
        return;
    }
    if (((kind == pact_NodeKind_TupleLit) || (kind == pact_NodeKind_ListLit))) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        if ((elems_sl != (-1))) {
            int64_t ei = 0;
            while ((ei < pact_sublist_length(elems_sl))) {
                pact_walk_expr(pact_sublist_get(elems_sl, ei), fn_idx);
                ei = (ei + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_StructLit)) {
        const int64_t fields_sl = (int64_t)(intptr_t)pact_list_get(np_fields, node);
        if ((fields_sl != (-1))) {
            int64_t fi = 0;
            while ((fi < pact_sublist_length(fields_sl))) {
                const int64_t fld = pact_sublist_get(fields_sl, fi);
                pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_value, fld), fn_idx);
                fi = (fi + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_Closure)) {
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_body, node), fn_idx);
        return;
    }
    if ((kind == pact_NodeKind_InterpString)) {
        const int64_t parts_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        if ((parts_sl != (-1))) {
            int64_t pi = 0;
            while ((pi < pact_sublist_length(parts_sl))) {
                pact_walk_expr(pact_sublist_get(parts_sl, pi), fn_idx);
                pi = (pi + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_RangeLit)) {
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_start, node), fn_idx);
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_end, node), fn_idx);
        return;
    }
    if ((kind == pact_NodeKind_WithBlock)) {
        pact_walk_expr((int64_t)(intptr_t)pact_list_get(np_body, node), fn_idx);
        return;
    }
}

void pact_walk_stmts(int64_t stmts_sl, int64_t fn_idx) {
    if ((stmts_sl == (-1))) {
        return;
    }
    int64_t i = 0;
    while ((i < pact_sublist_length(stmts_sl))) {
        pact_walk_expr(pact_sublist_get(stmts_sl, i), fn_idx);
        i = (i + 1);
    }
}

int64_t pact_propagate_writes(void) {
    int64_t changed = 0;
    const int64_t num_globals = pact_list_len(ma_globals);
    int64_t ei = 0;
    while ((ei < pact_list_len(ma_call_edges_from))) {
        const int64_t caller_idx = (int64_t)(intptr_t)pact_list_get(ma_call_edges_from, ei);
        const int64_t callee_idx = (int64_t)(intptr_t)pact_list_get(ma_call_edges_to, ei);
        int64_t gi = 0;
        while ((gi < num_globals)) {
            if (((pact_mat_has_write(callee_idx, gi) != 0) && (pact_mat_has_write(caller_idx, gi) == 0))) {
                pact_mat_set_write(caller_idx, gi);
                changed = 1;
            }
            gi = (gi + 1);
        }
        ei = (ei + 1);
    }
    return changed;
}

void pact_rebuild_write_lists(void) {
    pact_list* _l0 = pact_list_new();
    ma_write_items = _l0;
    pact_list* _l1 = pact_list_new();
    ma_write_starts = _l1;
    pact_list* _l2 = pact_list_new();
    ma_write_counts = _l2;
    const int64_t num_globals = pact_list_len(ma_globals);
    int64_t fi = 0;
    while ((fi < pact_list_len(ma_fn_names))) {
        const int64_t start = pact_list_len(ma_write_items);
        pact_list_push(ma_write_starts, (void*)(intptr_t)start);
        int64_t count = 0;
        int64_t gi = 0;
        while ((gi < num_globals)) {
            if ((pact_mat_has_write(fi, gi) != 0)) {
                pact_list_push(ma_write_items, (void*)(const char*)pact_list_get(ma_globals, gi));
                count = (count + 1);
            }
            gi = (gi + 1);
        }
        pact_list_push(ma_write_counts, (void*)(intptr_t)count);
        fi = (fi + 1);
    }
}

void pact_analyze_mutations(int64_t program) {
    pact_init_mutating_methods();
    pact_list* _l0 = pact_list_new();
    ma_fn_names = _l0;
    pact_list* _l1 = pact_list_new();
    ma_write_items = _l1;
    pact_list* _l2 = pact_list_new();
    ma_write_starts = _l2;
    pact_list* _l3 = pact_list_new();
    ma_write_counts = _l3;
    pact_list* _l4 = pact_list_new();
    ma_globals = _l4;
    pact_list* _l5 = pact_list_new();
    ma_call_edges_from = _l5;
    pact_list* _l6 = pact_list_new();
    ma_call_edges_to = _l6;
    fn_name_map = pact_map_new();
    global_set = pact_map_new();
    global_idx_map = pact_map_new();
    const int64_t lets_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, program);
    if ((lets_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(lets_sl))) {
            const int64_t let_node = pact_sublist_get(lets_sl, i);
            if ((((int64_t)(intptr_t)pact_list_get(np_kind, let_node) == pact_NodeKind_LetBinding) && ((int64_t)(intptr_t)pact_list_get(np_is_mut, let_node) != 0))) {
                const char* gname = (const char*)pact_list_get(np_name, let_node);
                pact_list_push(ma_globals, (void*)gname);
                pact_map_set(global_set, gname, (void*)(intptr_t)1);
                pact_map_set(global_idx_map, gname, (void*)(intptr_t)(pact_list_len(ma_globals) - 1));
            }
            i = (i + 1);
        }
    }
    const int64_t fns_sl = (int64_t)(intptr_t)pact_list_get(np_params, program);
    if ((fns_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(fns_sl))) {
            const int64_t fn_node = pact_sublist_get(fns_sl, i);
            const char* fname = (const char*)pact_list_get(np_name, fn_node);
            pact_list_push(ma_fn_names, (void*)fname);
            pact_map_set(fn_name_map, fname, (void*)(intptr_t)i);
            pact_list_push(ma_write_starts, (void*)(intptr_t)0);
            pact_list_push(ma_write_counts, (void*)(intptr_t)0);
            i = (i + 1);
        }
    }
    writes_mat_cols = pact_list_len(ma_globals);
    pact_list* _l7 = pact_list_new();
    writes_mat = _l7;
    const int64_t mat_size = (pact_list_len(ma_fn_names) * writes_mat_cols);
    int64_t mi = 0;
    while ((mi < mat_size)) {
        pact_list_push(writes_mat, (void*)(intptr_t)0);
        mi = (mi + 1);
    }
    if ((fns_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(fns_sl))) {
            const int64_t fn_node = pact_sublist_get(fns_sl, i);
            const int64_t body = (int64_t)(intptr_t)pact_list_get(np_body, fn_node);
            pact_walk_expr(body, i);
            i = (i + 1);
        }
    }
    int64_t max_iters = (pact_list_len(ma_fn_names) + 1);
    int64_t iter = 0;
    while ((iter < max_iters)) {
        if ((pact_propagate_writes() == 0)) {
            iter = max_iters;
        }
        iter = (iter + 1);
    }
    pact_rebuild_write_lists();
}

int64_t pact_get_fn_write_count(const char* name) {
    const int64_t idx = pact_fn_index(name);
    if ((idx >= 0)) {
        return (int64_t)(intptr_t)pact_list_get(ma_write_counts, idx);
    }
    return 0;
}

const char* pact_get_fn_write_at(const char* name, int64_t wi) {
    const int64_t idx = pact_fn_index(name);
    if ((idx >= 0)) {
        const int64_t start = (int64_t)(intptr_t)pact_list_get(ma_write_starts, idx);
        return (const char*)pact_list_get(ma_write_items, (start + wi));
    }
    return "";
}

pact_list* pact_get_all_globals(void) {
    return ma_globals;
}

int64_t pact_fn_writes_to(const char* fn_name, const char* global_name) {
    const int64_t idx = pact_fn_index(fn_name);
    if ((idx >= 0)) {
        return pact_fn_has_write(idx, global_name);
    }
    return 0;
}

void pact_sr_reset(void) {
    pact_list* _l0 = pact_list_new();
    sr_save_local = _l0;
    pact_list* _l1 = pact_list_new();
    sr_save_global = _l1;
    sr_restore_globals = pact_map_new();
}

void pact_sr_add_save(const char* local_name, const char* global_name) {
    pact_list_push(sr_save_local, (void*)local_name);
    pact_list_push(sr_save_global, (void*)global_name);
}

const char* pact_sr_is_save_local(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(sr_save_local))) {
        if (pact_str_eq((const char*)pact_list_get(sr_save_local, i), name)) {
            return (const char*)pact_list_get(sr_save_global, i);
        }
        i = (i + 1);
    }
    return "";
}

int64_t pact_sr_is_saved_global(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(sr_save_global))) {
        if (pact_str_eq((const char*)pact_list_get(sr_save_global, i), name)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

void pact_sr_check_call(int64_t call_node, const char* callee_name) {
    const int64_t callee_idx = pact_fn_index(callee_name);
    if ((callee_idx < 0)) {
        return;
    }
    const int64_t wcount = (int64_t)(intptr_t)pact_list_get(ma_write_counts, callee_idx);
    if ((wcount == 0)) {
        return;
    }
    const int64_t wstart = (int64_t)(intptr_t)pact_list_get(ma_write_starts, callee_idx);
    int64_t saved_count = 0;
    int64_t total_in_ws = wcount;
    pact_list* _l0 = pact_list_new();
    pact_list* unsaved = _l0;
    int64_t wi = 0;
    while ((wi < wcount)) {
        const char* gname = (const char*)pact_list_get(ma_write_items, (wstart + wi));
        if ((pact_sr_is_saved_global(gname) != 0)) {
            saved_count = (saved_count + 1);
        } else {
            pact_list_push(unsaved, (void*)gname);
        }
        wi = (wi + 1);
    }
    if (((saved_count > 0) && (pact_list_len(unsaved) > 0))) {
        const char* missing = "";
        int64_t ui = 0;
        while ((ui < pact_list_len(unsaved))) {
            if ((ui > 0)) {
                missing = pact_str_concat(missing, ", ");
            }
            missing = pact_str_concat(missing, (const char*)pact_list_get(unsaved, ui));
            ui = (ui + 1);
        }
        char _si_1[4096];
        snprintf(_si_1, 4096, "call to '%s' in '%s' mutates [%s] which are not saved/restored (write-set: %lld globals, saved: %lld)", callee_name, sr_current_fn, missing, (long long)wcount, (long long)saved_count);
        char _si_2[4096];
        snprintf(_si_2, 4096, "save and restore [%s] around this call, or verify the mutation is intentional", missing);
        pact_diag_warn_at("IncompleteStateRestore", "W0550", strdup(_si_1), call_node, strdup(_si_2));
    }
    if (((saved_count == 0) && (total_in_ws >= 3))) {
        const char* all_writes = "";
        wi = 0;
        while ((wi < wcount)) {
            if ((wi > 0)) {
                all_writes = pact_str_concat(all_writes, ", ");
            }
            all_writes = pact_str_concat(all_writes, (const char*)pact_list_get(ma_write_items, (wstart + wi)));
            wi = (wi + 1);
        }
        char _si_3[4096];
        snprintf(_si_3, 4096, "call to '%s' in '%s' mutates [%s] with no save/restore pattern", callee_name, sr_current_fn, all_writes);
        pact_diag_warn_at("UnrestoredMutation", "W0551", strdup(_si_3), call_node, "if this call is speculative, save/restore affected globals");
    }
}

void pact_sr_scan_stmts(int64_t stmts_sl) {
    if ((stmts_sl == (-1))) {
        return;
    }
    const int64_t num_stmts = pact_sublist_length(stmts_sl);
    int64_t i = 0;
    while ((i < num_stmts)) {
        const int64_t stmt = pact_sublist_get(stmts_sl, i);
        const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, stmt);
        if ((kind == pact_NodeKind_LetBinding)) {
            const char* local_name = (const char*)pact_list_get(np_name, stmt);
            const int64_t val = (int64_t)(intptr_t)pact_list_get(np_value, stmt);
            if (((val != (-1)) && ((int64_t)(intptr_t)pact_list_get(np_kind, val) == pact_NodeKind_Ident))) {
                const char* val_name = (const char*)pact_list_get(np_name, val);
                if ((pact_is_global(val_name) != 0)) {
                    pact_sr_add_save(local_name, val_name);
                }
            }
        }
        if ((kind == pact_NodeKind_Assignment)) {
            const int64_t target = (int64_t)(intptr_t)pact_list_get(np_target, stmt);
            const int64_t val = (int64_t)(intptr_t)pact_list_get(np_value, stmt);
            if (((target != (-1)) && (val != (-1)))) {
                if ((((int64_t)(intptr_t)pact_list_get(np_kind, target) == pact_NodeKind_Ident) && ((int64_t)(intptr_t)pact_list_get(np_kind, val) == pact_NodeKind_Ident))) {
                    const char* tname = (const char*)pact_list_get(np_name, target);
                    const char* vname = (const char*)pact_list_get(np_name, val);
                    const char* mapped = pact_sr_is_save_local(vname);
                    if (((!pact_str_eq(mapped, "")) && pact_str_eq(mapped, tname))) {
                        pact_map_set(sr_restore_globals, tname, (void*)(intptr_t)1);
                    }
                }
            }
        }
        i = (i + 1);
    }
    i = 0;
    while ((i < num_stmts)) {
        const int64_t stmt = pact_sublist_get(stmts_sl, i);
        const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, stmt);
        if ((kind == pact_NodeKind_ExprStmt)) {
            const int64_t inner = (int64_t)(intptr_t)pact_list_get(np_value, stmt);
            if ((inner != (-1))) {
                const int64_t ik = (int64_t)(intptr_t)pact_list_get(np_kind, inner);
                if ((ik == pact_NodeKind_Call)) {
                    const int64_t callee = (int64_t)(intptr_t)pact_list_get(np_left, inner);
                    const char* cname = pact_extract_ident_name(callee);
                    if ((!pact_str_eq(cname, ""))) {
                        pact_sr_check_call(inner, cname);
                    }
                }
            }
        }
        if ((kind == pact_NodeKind_Call)) {
            const int64_t callee = (int64_t)(intptr_t)pact_list_get(np_left, stmt);
            const char* cname = pact_extract_ident_name(callee);
            if ((!pact_str_eq(cname, ""))) {
                pact_sr_check_call(stmt, cname);
            }
        }
        i = (i + 1);
    }
    i = 0;
    while ((i < num_stmts)) {
        const int64_t stmt = pact_sublist_get(stmts_sl, i);
        pact_sr_scan_node(stmt);
        i = (i + 1);
    }
}

void pact_sr_scan_node(int64_t node) {
    if ((node == (-1))) {
        return;
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_Block)) {
        pact_list* outer_saves_l = sr_save_local;
        pact_list* outer_saves_g = sr_save_global;
        pact_map* outer_restores = sr_restore_globals;
        pact_list* _l0 = pact_list_new();
        sr_save_local = _l0;
        pact_list* _l1 = pact_list_new();
        sr_save_global = _l1;
        sr_restore_globals = pact_map_new();
        pact_sr_scan_stmts((int64_t)(intptr_t)pact_list_get(np_stmts, node));
        sr_save_local = outer_saves_l;
        sr_save_global = outer_saves_g;
        sr_restore_globals = outer_restores;
        return;
    }
    if ((kind == pact_NodeKind_IfExpr)) {
        pact_sr_scan_node((int64_t)(intptr_t)pact_list_get(np_then_body, node));
        pact_sr_scan_node((int64_t)(intptr_t)pact_list_get(np_else_body, node));
        return;
    }
    if ((kind == pact_NodeKind_WhileLoop)) {
        pact_sr_scan_node((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_ForIn)) {
        pact_sr_scan_node((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_LoopExpr)) {
        pact_sr_scan_node((int64_t)(intptr_t)pact_list_get(np_body, node));
        return;
    }
    if ((kind == pact_NodeKind_MatchExpr)) {
        const int64_t arms_sl = (int64_t)(intptr_t)pact_list_get(np_arms, node);
        if ((arms_sl != (-1))) {
            int64_t ai = 0;
            while ((ai < pact_sublist_length(arms_sl))) {
                const int64_t arm = pact_sublist_get(arms_sl, ai);
                pact_sr_scan_node((int64_t)(intptr_t)pact_list_get(np_body, arm));
                ai = (ai + 1);
            }
        }
        return;
    }
}

void pact_sr_analyze_fn(int64_t fn_node) {
    sr_current_fn = (const char*)pact_list_get(np_name, fn_node);
    pact_sr_reset();
    const int64_t body = (int64_t)(intptr_t)pact_list_get(np_body, fn_node);
    if ((body == (-1))) {
        return;
    }
    const int64_t body_kind = (int64_t)(intptr_t)pact_list_get(np_kind, body);
    if ((body_kind == pact_NodeKind_Block)) {
        pact_sr_scan_stmts((int64_t)(intptr_t)pact_list_get(np_stmts, body));
    }
}

void pact_analyze_save_restore(int64_t program) {
    const int64_t fns_sl = (int64_t)(intptr_t)pact_list_get(np_params, program);
    if ((fns_sl == (-1))) {
        return;
    }
    int64_t i = 0;
    while ((i < pact_sublist_length(fns_sl))) {
        pact_sr_analyze_fn(pact_sublist_get(fns_sl, i));
        i = (i + 1);
    }
}

const char* pact_extract_intent(const char* doc) {
    if (pact_str_eq(doc, "")) {
        return "";
    }
    int64_t i = 0;
    while ((i < pact_str_len(doc))) {
        if ((pact_str_char_at(doc, i) == 10)) {
            return pact_str_substr(doc, 0, i);
        }
        i = (i + 1);
    }
    return doc;
}

const char* pact_extract_annotation_args(int64_t node, const char* ann_name) {
    const int64_t anns_sl = (int64_t)(intptr_t)pact_list_get(np_handlers, node);
    if ((anns_sl == (-1))) {
        return "";
    }
    const char* result = "";
    int64_t i = 0;
    while ((i < pact_sublist_length(anns_sl))) {
        const int64_t ann = pact_sublist_get(anns_sl, i);
        if (pact_str_eq((const char*)pact_list_get(np_name, ann), ann_name)) {
            const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, ann);
            if ((args_sl != (-1))) {
                int64_t j = 0;
                while ((j < pact_sublist_length(args_sl))) {
                    if ((!pact_str_eq(result, ""))) {
                        result = pact_str_concat(result, ",");
                    }
                    result = pact_str_concat(result, (const char*)pact_list_get(np_name, pact_sublist_get(args_sl, j)));
                    j = (j + 1);
                }
            }
        }
        i = (i + 1);
    }
    return result;
}

int64_t pact_add_symbol(const char* name, int64_t kind, const char* module, const char* file, int64_t line, int64_t vis, const char* effects, const char* sig, const char* ret_type, const char* param_types) {
    const int64_t idx = si_sym_count;
    pact_list_push(si_sym_name, (void*)name);
    pact_list_push(si_sym_kind, (void*)(intptr_t)kind);
    pact_list_push(si_sym_module, (void*)module);
    pact_list_push(si_sym_file, (void*)file);
    pact_list_push(si_sym_line, (void*)(intptr_t)line);
    pact_list_push(si_sym_vis, (void*)(intptr_t)vis);
    pact_list_push(si_sym_effects, (void*)effects);
    pact_list_push(si_sym_sig, (void*)sig);
    pact_list_push(si_sym_ret_type, (void*)ret_type);
    pact_list_push(si_sym_param_types, (void*)param_types);
    pact_map_set(sym_name_map, name, (void*)(intptr_t)idx);
    si_sym_count = (si_sym_count + 1);
    return idx;
}

void pact_si_add_dep(int64_t from_idx, int64_t to_idx, int64_t kind) {
    pact_list_push(si_dep_from, (void*)(intptr_t)from_idx);
    pact_list_push(si_dep_to, (void*)(intptr_t)to_idx);
    pact_list_push(si_dep_kind, (void*)(intptr_t)kind);
    si_dep_count = (si_dep_count + 1);
}

void pact_add_rdep(int64_t from_idx, int64_t to_idx) {
    pact_list_push(si_rdep_from, (void*)(intptr_t)from_idx);
    pact_list_push(si_rdep_to, (void*)(intptr_t)to_idx);
    si_rdep_count = (si_rdep_count + 1);
}

int64_t pact_register_file(const char* path, int64_t mtime, int64_t sym_start) {
    const int64_t idx = si_file_count;
    pact_list_push(si_file_path, (void*)path);
    pact_list_push(si_file_mtime, (void*)(intptr_t)mtime);
    pact_list_push(si_file_sym_start, (void*)(intptr_t)sym_start);
    pact_list_push(si_file_sym_end, (void*)(intptr_t)sym_start);
    pact_map_set(file_path_map, path, (void*)(intptr_t)idx);
    si_file_count = (si_file_count + 1);
    return idx;
}

int64_t pact_sym_index(const char* name) {
    if ((pact_map_has(sym_name_map, name) != 0)) {
        return (int64_t)(intptr_t)pact_map_get(sym_name_map, name);
    }
    return (-1);
}

const char* pact_collect_param_types(int64_t fn_node) {
    const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, fn_node);
    if ((params_sl == (-1))) {
        return "";
    }
    const char* result = "";
    int64_t i = 0;
    while ((i < pact_sublist_length(params_sl))) {
        const int64_t p = pact_sublist_get(params_sl, i);
        if ((i > 0)) {
            result = pact_str_concat(result, ",");
        }
        result = pact_str_concat(result, (const char*)pact_list_get(np_type_name, p));
        i = (i + 1);
    }
    return result;
}

const char* pact_collect_effects(int64_t fn_node) {
    const int64_t eff_sl = (int64_t)(intptr_t)pact_list_get(np_effects, fn_node);
    if ((eff_sl == (-1))) {
        return "";
    }
    const char* result = "";
    int64_t i = 0;
    while ((i < pact_sublist_length(eff_sl))) {
        const int64_t e = pact_sublist_get(eff_sl, i);
        if ((i > 0)) {
            result = pact_str_concat(result, ",");
        }
        result = pact_str_concat(result, (const char*)pact_list_get(np_name, e));
        i = (i + 1);
    }
    return result;
}

void pact_walk_deps(int64_t node, int64_t from_idx) {
    if ((node == (-1))) {
        return;
    }
    const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, node);
    if ((kind == pact_NodeKind_Call)) {
        const int64_t callee = (int64_t)(intptr_t)pact_list_get(np_left, node);
        if (((callee != (-1)) && ((int64_t)(intptr_t)pact_list_get(np_kind, callee) == pact_NodeKind_Ident))) {
            const char* callee_name = (const char*)pact_list_get(np_name, callee);
            const int64_t callee_idx = pact_sym_index(callee_name);
            if ((callee_idx >= 0)) {
                pact_si_add_dep(from_idx, callee_idx, DK_CALLS);
            }
        }
        pact_walk_deps(callee, from_idx);
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if ((args_sl != (-1))) {
            int64_t ai = 0;
            while ((ai < pact_sublist_length(args_sl))) {
                pact_walk_deps(pact_sublist_get(args_sl, ai), from_idx);
                ai = (ai + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_MethodCall)) {
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_obj, node), from_idx);
        const int64_t args_sl = (int64_t)(intptr_t)pact_list_get(np_args, node);
        if ((args_sl != (-1))) {
            int64_t ai = 0;
            while ((ai < pact_sublist_length(args_sl))) {
                pact_walk_deps(pact_sublist_get(args_sl, ai), from_idx);
                ai = (ai + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_FieldAccess)) {
        const int64_t obj = (int64_t)(intptr_t)pact_list_get(np_obj, node);
        if (((obj != (-1)) && ((int64_t)(intptr_t)pact_list_get(np_kind, obj) == pact_NodeKind_Ident))) {
            const char* obj_name = (const char*)pact_list_get(np_name, obj);
            const int64_t obj_idx = pact_sym_index(obj_name);
            if ((obj_idx >= 0)) {
                pact_si_add_dep(from_idx, obj_idx, DK_FIELD_ACCESS);
            }
        }
        pact_walk_deps(obj, from_idx);
        return;
    }
    if ((kind == pact_NodeKind_Ident)) {
        const char* ref_name = (const char*)pact_list_get(np_name, node);
        const int64_t ref_idx = pact_sym_index(ref_name);
        if (((ref_idx >= 0) && (ref_idx != from_idx))) {
            pact_si_add_dep(from_idx, ref_idx, DK_USES_TYPE);
        }
        return;
    }
    if ((kind == pact_NodeKind_BinOp)) {
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_left, node), from_idx);
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_right, node), from_idx);
        return;
    }
    if ((kind == pact_NodeKind_UnaryOp)) {
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_left, node), from_idx);
        return;
    }
    if ((kind == pact_NodeKind_IfExpr)) {
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_condition, node), from_idx);
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_then_body, node), from_idx);
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_else_body, node), from_idx);
        return;
    }
    if ((kind == pact_NodeKind_Block)) {
        pact_walk_dep_stmts((int64_t)(intptr_t)pact_list_get(np_stmts, node), from_idx);
        return;
    }
    if ((kind == pact_NodeKind_LetBinding)) {
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_value, node), from_idx);
        return;
    }
    if ((kind == pact_NodeKind_ExprStmt)) {
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_value, node), from_idx);
        return;
    }
    if ((kind == pact_NodeKind_Return)) {
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_value, node), from_idx);
        return;
    }
    if (((kind == pact_NodeKind_Assignment) || (kind == pact_NodeKind_CompoundAssign))) {
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_target, node), from_idx);
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_value, node), from_idx);
        return;
    }
    if ((kind == pact_NodeKind_ForIn)) {
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_iterable, node), from_idx);
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_body, node), from_idx);
        return;
    }
    if ((kind == pact_NodeKind_WhileLoop)) {
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_condition, node), from_idx);
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_body, node), from_idx);
        return;
    }
    if ((kind == pact_NodeKind_LoopExpr)) {
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_body, node), from_idx);
        return;
    }
    if ((kind == pact_NodeKind_MatchExpr)) {
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_scrutinee, node), from_idx);
        const int64_t arms_sl = (int64_t)(intptr_t)pact_list_get(np_arms, node);
        if ((arms_sl != (-1))) {
            int64_t ai = 0;
            while ((ai < pact_sublist_length(arms_sl))) {
                const int64_t arm = pact_sublist_get(arms_sl, ai);
                pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_guard, arm), from_idx);
                pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_body, arm), from_idx);
                ai = (ai + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_IndexExpr)) {
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_obj, node), from_idx);
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_index, node), from_idx);
        return;
    }
    if (((kind == pact_NodeKind_TupleLit) || (kind == pact_NodeKind_ListLit))) {
        const int64_t elems_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        if ((elems_sl != (-1))) {
            int64_t ei = 0;
            while ((ei < pact_sublist_length(elems_sl))) {
                pact_walk_deps(pact_sublist_get(elems_sl, ei), from_idx);
                ei = (ei + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_StructLit)) {
        const char* type_name = (const char*)pact_list_get(np_type_name, node);
        const int64_t type_idx = pact_sym_index(type_name);
        if ((type_idx >= 0)) {
            pact_si_add_dep(from_idx, type_idx, DK_USES_TYPE);
        }
        const int64_t fields_sl = (int64_t)(intptr_t)pact_list_get(np_fields, node);
        if ((fields_sl != (-1))) {
            int64_t fi = 0;
            while ((fi < pact_sublist_length(fields_sl))) {
                const int64_t fld = pact_sublist_get(fields_sl, fi);
                pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_value, fld), from_idx);
                fi = (fi + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_Closure)) {
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_body, node), from_idx);
        return;
    }
    if ((kind == pact_NodeKind_InterpString)) {
        const int64_t parts_sl = (int64_t)(intptr_t)pact_list_get(np_elements, node);
        if ((parts_sl != (-1))) {
            int64_t pi = 0;
            while ((pi < pact_sublist_length(parts_sl))) {
                pact_walk_deps(pact_sublist_get(parts_sl, pi), from_idx);
                pi = (pi + 1);
            }
        }
        return;
    }
    if ((kind == pact_NodeKind_RangeLit)) {
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_start, node), from_idx);
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_end, node), from_idx);
        return;
    }
    if ((kind == pact_NodeKind_WithBlock)) {
        pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_body, node), from_idx);
        return;
    }
}

void pact_walk_dep_stmts(int64_t stmts_sl, int64_t from_idx) {
    if ((stmts_sl == (-1))) {
        return;
    }
    int64_t i = 0;
    while ((i < pact_sublist_length(stmts_sl))) {
        pact_walk_deps(pact_sublist_get(stmts_sl, i), from_idx);
        i = (i + 1);
    }
}

void pact_register_type_dep(int64_t from_idx, const char* type_name) {
    if ((((((pact_str_eq(type_name, "") || pact_str_eq(type_name, "Int")) || pact_str_eq(type_name, "Str")) || pact_str_eq(type_name, "Float")) || pact_str_eq(type_name, "Bool")) || pact_str_eq(type_name, "Void"))) {
        return;
    }
    const int64_t type_idx = pact_sym_index(type_name);
    if ((type_idx >= 0)) {
        pact_si_add_dep(from_idx, type_idx, DK_USES_TYPE);
    }
}

void pact_build_reverse_deps(void) {
    int64_t i = 0;
    while ((i < si_dep_count)) {
        pact_add_rdep((int64_t)(intptr_t)pact_list_get(si_dep_to, i), (int64_t)(intptr_t)pact_list_get(si_dep_from, i));
        i = (i + 1);
    }
}

void pact_si_build(int64_t program, const char* file_path, const char* module_name) {
    const int64_t file_sym_start = si_sym_count;
    const int64_t file_idx = pact_register_file(file_path, 0, file_sym_start);
    const int64_t fns_sl = (int64_t)(intptr_t)pact_list_get(np_params, program);
    if ((fns_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(fns_sl))) {
            const int64_t fn_node = pact_sublist_get(fns_sl, i);
            const char* name = (const char*)pact_list_get(np_name, fn_node);
            int64_t _if_0;
            if (((int64_t)(intptr_t)pact_list_get(np_is_pub, fn_node) != 0)) {
                _if_0 = VIS_PUB;
            } else {
                _if_0 = VIS_PRIVATE;
            }
            const int64_t vis = _if_0;
            const char* ret = (const char*)pact_list_get(np_return_type, fn_node);
            const char* ptypes = pact_collect_param_types(fn_node);
            const char* effs = pact_collect_effects(fn_node);
            const char* sig = pact_str_concat(pact_str_concat(pact_str_concat(pact_str_concat(name, "("), ptypes), ") -> "), ret);
            pact_add_symbol(name, SK_FN, module_name, file_path, (int64_t)(intptr_t)pact_list_get(np_line, fn_node), vis, effs, sig, ret, ptypes);
            const char* fn_doc = (const char*)pact_list_get(np_doc_comment, fn_node);
            pact_list_push(si_sym_doc, (void*)fn_doc);
            pact_list_push(si_sym_intent, (void*)pact_extract_intent(fn_doc));
            pact_list_push(si_sym_requires, (void*)pact_extract_annotation_args(fn_node, "requires"));
            pact_list_push(si_sym_ensures, (void*)pact_extract_annotation_args(fn_node, "ensures"));
            pact_list_push(si_sym_end_line, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(np_end_line, fn_node));
            i = (i + 1);
        }
    }
    const int64_t types_sl = (int64_t)(intptr_t)pact_list_get(np_fields, program);
    if ((types_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(types_sl))) {
            const int64_t type_node = pact_sublist_get(types_sl, i);
            const char* name = (const char*)pact_list_get(np_name, type_node);
            int64_t _if_1;
            if (((int64_t)(intptr_t)pact_list_get(np_is_pub, type_node) != 0)) {
                _if_1 = VIS_PUB;
            } else {
                _if_1 = VIS_PRIVATE;
            }
            const int64_t vis = _if_1;
            const int64_t kind = (int64_t)(intptr_t)pact_list_get(np_kind, type_node);
            int64_t _if_2;
            if ((kind == pact_NodeKind_TypeDef)) {
                _if_2 = SK_STRUCT;
            } else {
                _if_2 = SK_ENUM;
            }
            const int64_t sym_kind = _if_2;
            pact_add_symbol(name, sym_kind, module_name, file_path, (int64_t)(intptr_t)pact_list_get(np_line, type_node), vis, "", "", "", "");
            const char* type_doc = (const char*)pact_list_get(np_doc_comment, type_node);
            pact_list_push(si_sym_doc, (void*)type_doc);
            pact_list_push(si_sym_intent, (void*)pact_extract_intent(type_doc));
            pact_list_push(si_sym_requires, (void*)"");
            pact_list_push(si_sym_ensures, (void*)"");
            pact_list_push(si_sym_end_line, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(np_end_line, type_node));
            i = (i + 1);
        }
    }
    const int64_t traits_sl = (int64_t)(intptr_t)pact_list_get(np_arms, program);
    if ((traits_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(traits_sl))) {
            const int64_t trait_node = pact_sublist_get(traits_sl, i);
            const char* name = (const char*)pact_list_get(np_name, trait_node);
            int64_t _if_3;
            if (((int64_t)(intptr_t)pact_list_get(np_is_pub, trait_node) != 0)) {
                _if_3 = VIS_PUB;
            } else {
                _if_3 = VIS_PRIVATE;
            }
            const int64_t vis = _if_3;
            pact_add_symbol(name, SK_TRAIT, module_name, file_path, (int64_t)(intptr_t)pact_list_get(np_line, trait_node), vis, "", "", "", "");
            const char* trait_doc = (const char*)pact_list_get(np_doc_comment, trait_node);
            pact_list_push(si_sym_doc, (void*)trait_doc);
            pact_list_push(si_sym_intent, (void*)pact_extract_intent(trait_doc));
            pact_list_push(si_sym_requires, (void*)"");
            pact_list_push(si_sym_ensures, (void*)"");
            pact_list_push(si_sym_end_line, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(np_end_line, trait_node));
            i = (i + 1);
        }
    }
    const int64_t lets_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, program);
    if ((lets_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(lets_sl))) {
            const int64_t let_node = pact_sublist_get(lets_sl, i);
            if (((int64_t)(intptr_t)pact_list_get(np_kind, let_node) == pact_NodeKind_LetBinding)) {
                const char* name = (const char*)pact_list_get(np_name, let_node);
                int64_t _if_4;
                if (((int64_t)(intptr_t)pact_list_get(np_is_pub, let_node) != 0)) {
                    _if_4 = VIS_PUB;
                } else {
                    _if_4 = VIS_PRIVATE;
                }
                const int64_t vis = _if_4;
                pact_add_symbol(name, SK_LET, module_name, file_path, (int64_t)(intptr_t)pact_list_get(np_line, let_node), vis, "", "", "", "");
                const char* let_doc = (const char*)pact_list_get(np_doc_comment, let_node);
                pact_list_push(si_sym_doc, (void*)let_doc);
                pact_list_push(si_sym_intent, (void*)pact_extract_intent(let_doc));
                pact_list_push(si_sym_requires, (void*)"");
                pact_list_push(si_sym_ensures, (void*)"");
                pact_list_push(si_sym_end_line, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(np_line, let_node));
            }
            i = (i + 1);
        }
    }
    pact_list_set(si_file_sym_end, file_idx, (void*)(intptr_t)si_sym_count);
    if ((fns_sl != (-1))) {
        int64_t i = 0;
        while ((i < pact_sublist_length(fns_sl))) {
            const int64_t fn_node = pact_sublist_get(fns_sl, i);
            const char* fn_name = (const char*)pact_list_get(np_name, fn_node);
            const int64_t fn_idx = pact_sym_index(fn_name);
            if ((fn_idx >= 0)) {
                pact_register_type_dep(fn_idx, (const char*)pact_list_get(np_return_type, fn_node));
                const int64_t params_sl = (int64_t)(intptr_t)pact_list_get(np_params, fn_node);
                if ((params_sl != (-1))) {
                    int64_t pi = 0;
                    while ((pi < pact_sublist_length(params_sl))) {
                        const int64_t p = pact_sublist_get(params_sl, pi);
                        pact_register_type_dep(fn_idx, (const char*)pact_list_get(np_type_name, p));
                        pi = (pi + 1);
                    }
                }
                pact_walk_deps((int64_t)(intptr_t)pact_list_get(np_body, fn_node), fn_idx);
            }
            i = (i + 1);
        }
    }
    pact_build_reverse_deps();
}

pact_list* pact_si_get_rdeps(int64_t sym_idx) {
    pact_list* _l0 = pact_list_new();
    pact_list* result = _l0;
    int64_t i = 0;
    while ((i < si_rdep_count)) {
        if (((int64_t)(intptr_t)pact_list_get(si_rdep_from, i) == sym_idx)) {
            pact_list_push(result, (void*)(intptr_t)(int64_t)(intptr_t)pact_list_get(si_rdep_to, i));
        }
        i = (i + 1);
    }
    return result;
}

int64_t pact_si_find_sym(const char* name) {
    if ((pact_map_has(sym_name_map, name) != 0)) {
        return (int64_t)(intptr_t)pact_map_get(sym_name_map, name);
    }
    return (-1);
}

pact_list* pact_si_file_symbols(const char* path) {
    pact_list* _l0 = pact_list_new();
    pact_list* result = _l0;
    if ((pact_map_has(file_path_map, path) == 0)) {
        return result;
    }
    const int64_t file_idx = (int64_t)(intptr_t)pact_map_get(file_path_map, path);
    const int64_t start = (int64_t)(intptr_t)pact_list_get(si_file_sym_start, file_idx);
    const int64_t end = (int64_t)(intptr_t)pact_list_get(si_file_sym_end, file_idx);
    int64_t i = start;
    while ((i < end)) {
        pact_list_push(result, (void*)(intptr_t)i);
        i = (i + 1);
    }
    return result;
}

void pact_si_reset(void) {
    pact_list* _l0 = pact_list_new();
    si_sym_name = _l0;
    pact_list* _l1 = pact_list_new();
    si_sym_kind = _l1;
    pact_list* _l2 = pact_list_new();
    si_sym_module = _l2;
    pact_list* _l3 = pact_list_new();
    si_sym_file = _l3;
    pact_list* _l4 = pact_list_new();
    si_sym_line = _l4;
    pact_list* _l5 = pact_list_new();
    si_sym_vis = _l5;
    pact_list* _l6 = pact_list_new();
    si_sym_effects = _l6;
    pact_list* _l7 = pact_list_new();
    si_sym_sig = _l7;
    pact_list* _l8 = pact_list_new();
    si_sym_ret_type = _l8;
    pact_list* _l9 = pact_list_new();
    si_sym_param_types = _l9;
    pact_list* _l10 = pact_list_new();
    si_sym_doc = _l10;
    pact_list* _l11 = pact_list_new();
    si_sym_intent = _l11;
    pact_list* _l12 = pact_list_new();
    si_sym_requires = _l12;
    pact_list* _l13 = pact_list_new();
    si_sym_ensures = _l13;
    pact_list* _l14 = pact_list_new();
    si_sym_end_line = _l14;
    si_sym_count = 0;
    pact_list* _l15 = pact_list_new();
    si_dep_from = _l15;
    pact_list* _l16 = pact_list_new();
    si_dep_to = _l16;
    pact_list* _l17 = pact_list_new();
    si_dep_kind = _l17;
    si_dep_count = 0;
    pact_list* _l18 = pact_list_new();
    si_rdep_from = _l18;
    pact_list* _l19 = pact_list_new();
    si_rdep_to = _l19;
    si_rdep_count = 0;
    pact_list* _l20 = pact_list_new();
    si_file_path = _l20;
    pact_list* _l21 = pact_list_new();
    si_file_mtime = _l21;
    pact_list* _l22 = pact_list_new();
    si_file_sym_start = _l22;
    pact_list* _l23 = pact_list_new();
    si_file_sym_end = _l23;
    si_file_count = 0;
    sym_name_map = pact_map_new();
    file_path_map = pact_map_new();
}

const char* pact_sym_kind_name(int64_t kind) {
    if ((kind == SK_FN)) {
        return "fn";
    }
    if ((kind == SK_STRUCT)) {
        return "struct";
    }
    if ((kind == SK_ENUM)) {
        return "enum";
    }
    if ((kind == SK_TRAIT)) {
        return "trait";
    }
    if ((kind == SK_LET)) {
        return "let";
    }
    return "unknown";
}

const char* pact_dep_kind_name(int64_t kind) {
    if ((kind == DK_CALLS)) {
        return "calls";
    }
    if ((kind == DK_USES_TYPE)) {
        return "uses_type";
    }
    if ((kind == DK_FIELD_ACCESS)) {
        return "field_access";
    }
    return "unknown";
}

void pact_fw_init(void) {
    pact_list* _l0 = pact_list_new();
    fw_path = _l0;
    pact_list* _l1 = pact_list_new();
    fw_mtime = _l1;
    fw_count = 0;
    pact_list* _l2 = pact_list_new();
    fw_dirty_path = _l2;
    fw_dirty_count = 0;
    path_map = pact_map_new();
    int64_t i = 0;
    while ((i < si_file_count)) {
        const char* p = (const char*)pact_list_get(si_file_path, i);
        const int64_t mt = pact_file_mtime(p);
        pact_list_push(fw_path, (void*)p);
        pact_list_push(fw_mtime, (void*)(intptr_t)mt);
        pact_map_set(path_map, p, (void*)(intptr_t)fw_count);
        fw_count = (fw_count + 1);
        i = (i + 1);
    }
}

int64_t pact_fw_poll(void) {
    pact_list* _l0 = pact_list_new();
    fw_dirty_path = _l0;
    fw_dirty_count = 0;
    int64_t i = 0;
    while ((i < fw_count)) {
        const char* p = (const char*)pact_list_get(fw_path, i);
        const int64_t old_mt = (int64_t)(intptr_t)pact_list_get(fw_mtime, i);
        const int64_t cur_mt = pact_file_mtime(p);
        if ((cur_mt != old_mt)) {
            pact_list_set(fw_mtime, i, (void*)(intptr_t)cur_mt);
            pact_list_push(fw_dirty_path, (void*)p);
            fw_dirty_count = (fw_dirty_count + 1);
        }
        i = (i + 1);
    }
    i = 0;
    while ((i < si_file_count)) {
        const char* p = (const char*)pact_list_get(si_file_path, i);
        if ((pact_map_has(path_map, p) == 0)) {
            const int64_t mt = pact_file_mtime(p);
            pact_list_push(fw_path, (void*)p);
            pact_list_push(fw_mtime, (void*)(intptr_t)mt);
            pact_map_set(path_map, p, (void*)(intptr_t)fw_count);
            fw_count = (fw_count + 1);
            pact_list_push(fw_dirty_path, (void*)p);
            fw_dirty_count = (fw_dirty_count + 1);
        }
        i = (i + 1);
    }
    return fw_dirty_count;
}

pact_list* pact_fw_get_dirty(void) {
    return fw_dirty_path;
}

void pact_fw_clear_dirty(void) {
    pact_list* _l0 = pact_list_new();
    fw_dirty_path = _l0;
    fw_dirty_count = 0;
}

void pact_fw_add_file(const char* path) {
    if ((pact_map_has(path_map, path) != 0)) {
        return;
    }
    const int64_t mt = pact_file_mtime(path);
    pact_list_push(fw_path, (void*)path);
    pact_list_push(fw_mtime, (void*)(intptr_t)mt);
    pact_map_set(path_map, path, (void*)(intptr_t)fw_count);
    fw_count = (fw_count + 1);
}

void pact_fw_reset(void) {
    pact_list* _l0 = pact_list_new();
    fw_path = _l0;
    pact_list* _l1 = pact_list_new();
    fw_mtime = _l1;
    fw_count = 0;
    pact_list* _l2 = pact_list_new();
    fw_dirty_path = _l2;
    fw_dirty_count = 0;
    path_map = pact_map_new();
}

const char* pact_escape_str(const char* s) {
    const char* result = "";
    int64_t i = 0;
    while ((i < pact_str_len(s))) {
        const int64_t c = pact_str_char_at(s, i);
        if ((c == 34)) {
            result = pact_str_concat(result, "\\\"");
        } else if ((c == 92)) {
            result = pact_str_concat(result, "\\\\");
        } else {
            if ((c == 10)) {
                result = pact_str_concat(result, "\\n");
            } else if ((c == 9)) {
                result = pact_str_concat(result, "\\t");
            } else {
                if ((c == 13)) {
                    result = pact_str_concat(result, "\\r");
                } else {
                    result = pact_str_concat(result, pact_str_substr(s, i, 1));
                }
            }
        }
        i = (i + 1);
    }
    return result;
}

const char* pact_effects_to_json_array(const char* effects) {
    if (pact_str_eq(effects, "")) {
        return "[]";
    }
    const char* result = "[";
    int64_t start = 0;
    int64_t i = 0;
    int64_t first = 1;
    while ((i <= pact_str_len(effects))) {
        if (((i == pact_str_len(effects)) || (pact_str_char_at(effects, i) == 44))) {
            const char* part = pact_str_substr(effects, start, (i - start));
            if ((first == 0)) {
                result = pact_str_concat(result, ",");
            }
            result = pact_str_concat(pact_str_concat(pact_str_concat(result, "\""), pact_escape_str(part)), "\"");
            first = 0;
            start = (i + 1);
        }
        i = (i + 1);
    }
    result = pact_str_concat(result, "]");
    return result;
}

const char* pact_vis_name(int64_t vis) {
    if ((vis == VIS_PUB)) {
        return "pub";
    }
    return "private";
}

const char* pact_symbol_to_json(int64_t idx) {
    const char* name = pact_escape_str((const char*)pact_list_get(si_sym_name, idx));
    const char* kind = pact_sym_kind_name((int64_t)(intptr_t)pact_list_get(si_sym_kind, idx));
    const char* module = pact_escape_str((const char*)pact_list_get(si_sym_module, idx));
    const char* sig = pact_escape_str((const char*)pact_list_get(si_sym_sig, idx));
    const char* effects = (const char*)pact_list_get(si_sym_effects, idx);
    const char* vis = pact_vis_name((int64_t)(intptr_t)pact_list_get(si_sym_vis, idx));
    const char* eff_arr = pact_effects_to_json_array(effects);
    const char* r = "{\"name\":\"";
    r = pact_str_concat(r, name);
    r = pact_str_concat(r, "\",\"kind\":\"");
    r = pact_str_concat(r, kind);
    r = pact_str_concat(r, "\",\"module\":\"");
    r = pact_str_concat(r, module);
    r = pact_str_concat(r, "\",\"signature\":\"");
    r = pact_str_concat(r, sig);
    r = pact_str_concat(r, "\",\"effects\":");
    r = pact_str_concat(r, eff_arr);
    r = pact_str_concat(r, ",\"visibility\":\"");
    r = pact_str_concat(r, vis);
    r = pact_str_concat(r, "\"");
    const char* intent = (const char*)pact_list_get(si_sym_intent, idx);
    if ((!pact_str_eq(intent, ""))) {
        r = pact_str_concat(pact_str_concat(pact_str_concat(r, ",\"intent\":\""), pact_escape_str(intent)), "\"");
    }
    const char* doc = (const char*)pact_list_get(si_sym_doc, idx);
    if ((!pact_str_eq(doc, ""))) {
        r = pact_str_concat(pact_str_concat(pact_str_concat(r, ",\"doc\":\""), pact_escape_str(doc)), "\"");
    }
    const char* req = (const char*)pact_list_get(si_sym_requires, idx);
    if ((!pact_str_eq(req, ""))) {
        r = pact_str_concat(pact_str_concat(pact_str_concat(r, ",\"requires\":\""), pact_escape_str(req)), "\"");
    }
    const char* ens = (const char*)pact_list_get(si_sym_ensures, idx);
    if ((!pact_str_eq(ens, ""))) {
        r = pact_str_concat(pact_str_concat(pact_str_concat(r, ",\"ensures\":\""), pact_escape_str(ens)), "\"");
    }
    const int64_t el = (int64_t)(intptr_t)pact_list_get(si_sym_end_line, idx);
    if ((el > 0)) {
        char _si_0[4096];
        snprintf(_si_0, 4096, ",\"end_line\":%lld", (long long)el);
        r = pact_str_concat(r, strdup(_si_0));
    }
    r = pact_str_concat(r, "}");
    return r;
}

const char* pact_wrap_results(const char* items) {
    return pact_str_concat(pact_str_concat("{\"results\":[", items), "]}");
}

int64_t pact_effects_contain(const char* effects, const char* target) {
    if (pact_str_eq(effects, "")) {
        return 0;
    }
    int64_t start = 0;
    int64_t i = 0;
    while ((i <= pact_str_len(effects))) {
        if (((i == pact_str_len(effects)) || (pact_str_char_at(effects, i) == 44))) {
            const char* part = pact_str_substr(effects, start, (i - start));
            if (pact_str_eq(part, target)) {
                return 1;
            }
            start = (i + 1);
        }
        i = (i + 1);
    }
    return 0;
}

const char* pact_query_by_signature(const char* module) {
    const char* items = "";
    int64_t first = 1;
    int64_t i = 0;
    while ((i < si_sym_count)) {
        if ((pact_str_eq((const char*)pact_list_get(si_sym_module, i), module) && ((int64_t)(intptr_t)pact_list_get(si_sym_kind, i) == SK_FN))) {
            if ((first == 0)) {
                items = pact_str_concat(items, ",");
            }
            items = pact_str_concat(items, pact_symbol_to_json(i));
            first = 0;
        }
        i = (i + 1);
    }
    return pact_wrap_results(items);
}

const char* pact_query_by_effect(const char* effect_name) {
    const char* items = "";
    int64_t first = 1;
    int64_t i = 0;
    while ((i < si_sym_count)) {
        if (((int64_t)(intptr_t)pact_list_get(si_sym_kind, i) == SK_FN)) {
            if ((pact_effects_contain((const char*)pact_list_get(si_sym_effects, i), effect_name) == 1)) {
                if ((first == 0)) {
                    items = pact_str_concat(items, ",");
                }
                items = pact_str_concat(items, pact_symbol_to_json(i));
                first = 0;
            }
        }
        i = (i + 1);
    }
    return pact_wrap_results(items);
}

const char* pact_query_pub_pure(void) {
    const char* items = "";
    int64_t first = 1;
    int64_t i = 0;
    while ((i < si_sym_count)) {
        if (((((int64_t)(intptr_t)pact_list_get(si_sym_kind, i) == SK_FN) && ((int64_t)(intptr_t)pact_list_get(si_sym_vis, i) == VIS_PUB)) && pact_str_eq((const char*)pact_list_get(si_sym_effects, i), ""))) {
            if ((first == 0)) {
                items = pact_str_concat(items, ",");
            }
            items = pact_str_concat(items, pact_symbol_to_json(i));
            first = 0;
        }
        i = (i + 1);
    }
    return pact_wrap_results(items);
}

const char* pact_query_by_name(const char* name) {
    const int64_t idx = pact_si_find_sym(name);
    if ((idx < 0)) {
        return pact_wrap_results("");
    }
    return pact_wrap_results(pact_symbol_to_json(idx));
}

const char* pact_query_filtered(int64_t vis_filter, const char* module_filter, const char* effect_filter, int64_t pure_only, const char* name_filter) {
    const char* items = "";
    int64_t first = 1;
    int64_t i = 0;
    while ((i < si_sym_count)) {
        if (((int64_t)(intptr_t)pact_list_get(si_sym_kind, i) != SK_FN)) {
            i = (i + 1);
            continue;
        }
        if (((vis_filter == VIS_PUB) && ((int64_t)(intptr_t)pact_list_get(si_sym_vis, i) != VIS_PUB))) {
            i = (i + 1);
            continue;
        }
        if (((!pact_str_eq(module_filter, "")) && (!pact_str_eq((const char*)pact_list_get(si_sym_module, i), module_filter)))) {
            i = (i + 1);
            continue;
        }
        if (((!pact_str_eq(effect_filter, "")) && (pact_effects_contain((const char*)pact_list_get(si_sym_effects, i), effect_filter) == 0))) {
            i = (i + 1);
            continue;
        }
        if (((pure_only != 0) && (!pact_str_eq((const char*)pact_list_get(si_sym_effects, i), "")))) {
            i = (i + 1);
            continue;
        }
        if (((!pact_str_eq(name_filter, "")) && (!pact_str_eq((const char*)pact_list_get(si_sym_name, i), name_filter)))) {
            i = (i + 1);
            continue;
        }
        if ((first == 0)) {
            items = pact_str_concat(items, ",");
        }
        items = pact_str_concat(items, pact_symbol_to_json(i));
        first = 0;
        i = (i + 1);
    }
    return pact_wrap_results(items);
}

const char* pact_symbol_to_intent_json(int64_t idx) {
    const char* name = pact_escape_str((const char*)pact_list_get(si_sym_name, idx));
    const char* intent = pact_escape_str((const char*)pact_list_get(si_sym_intent, idx));
    const char* r = "{\"name\":\"";
    r = pact_str_concat(r, name);
    r = pact_str_concat(r, "\",\"intent\":\"");
    r = pact_str_concat(r, intent);
    r = pact_str_concat(r, "\"}");
    return r;
}

const char* pact_symbol_to_contract_json(int64_t idx) {
    const char* name = pact_escape_str((const char*)pact_list_get(si_sym_name, idx));
    const char* sig = pact_escape_str((const char*)pact_list_get(si_sym_sig, idx));
    const char* effects = (const char*)pact_list_get(si_sym_effects, idx);
    const char* vis = pact_vis_name((int64_t)(intptr_t)pact_list_get(si_sym_vis, idx));
    const char* eff_arr = pact_effects_to_json_array(effects);
    const char* r = "{\"name\":\"";
    r = pact_str_concat(r, name);
    r = pact_str_concat(r, "\",\"signature\":\"");
    r = pact_str_concat(r, sig);
    r = pact_str_concat(r, "\",\"effects\":");
    r = pact_str_concat(r, eff_arr);
    r = pact_str_concat(r, ",\"visibility\":\"");
    r = pact_str_concat(r, vis);
    r = pact_str_concat(r, "\"");
    const char* req = (const char*)pact_list_get(si_sym_requires, idx);
    if ((!pact_str_eq(req, ""))) {
        r = pact_str_concat(pact_str_concat(pact_str_concat(r, ",\"requires\":\""), pact_escape_str(req)), "\"");
    }
    const char* ens = (const char*)pact_list_get(si_sym_ensures, idx);
    if ((!pact_str_eq(ens, ""))) {
        r = pact_str_concat(pact_str_concat(pact_str_concat(r, ",\"ensures\":\""), pact_escape_str(ens)), "\"");
    }
    r = pact_str_concat(r, "}");
    return r;
}

const char* pact_extract_lines(const char* content, int64_t start_line, int64_t end_line) {
    int64_t line_num = 1;
    int64_t line_start = 0;
    int64_t capture_start = (-1);
    int64_t i = 0;
    while ((i <= pact_str_len(content))) {
        if (((i == pact_str_len(content)) || (pact_str_char_at(content, i) == 10))) {
            if ((line_num == start_line)) {
                capture_start = line_start;
            }
            if ((line_num == end_line)) {
                const int64_t capture_end = i;
                if ((capture_start < 0)) {
                    capture_start = line_start;
                }
                return pact_str_substr(content, capture_start, (capture_end - capture_start));
            }
            line_num = (line_num + 1);
            line_start = (i + 1);
        }
        i = (i + 1);
    }
    if ((capture_start >= 0)) {
        return pact_str_substr(content, capture_start, (pact_str_len(content) - capture_start));
    }
    return "";
}

const char* pact_symbol_to_full_json(int64_t idx) {
    const char* name = pact_escape_str((const char*)pact_list_get(si_sym_name, idx));
    const char* kind = pact_sym_kind_name((int64_t)(intptr_t)pact_list_get(si_sym_kind, idx));
    const char* module = pact_escape_str((const char*)pact_list_get(si_sym_module, idx));
    const char* sig = pact_escape_str((const char*)pact_list_get(si_sym_sig, idx));
    const char* effects = (const char*)pact_list_get(si_sym_effects, idx);
    const char* vis = pact_vis_name((int64_t)(intptr_t)pact_list_get(si_sym_vis, idx));
    const char* eff_arr = pact_effects_to_json_array(effects);
    const char* r = "{\"name\":\"";
    r = pact_str_concat(r, name);
    r = pact_str_concat(r, "\",\"kind\":\"");
    r = pact_str_concat(r, kind);
    r = pact_str_concat(r, "\",\"module\":\"");
    r = pact_str_concat(r, module);
    r = pact_str_concat(r, "\",\"signature\":\"");
    r = pact_str_concat(r, sig);
    r = pact_str_concat(r, "\",\"effects\":");
    r = pact_str_concat(r, eff_arr);
    r = pact_str_concat(r, ",\"visibility\":\"");
    r = pact_str_concat(r, vis);
    r = pact_str_concat(r, "\"");
    const char* intent = (const char*)pact_list_get(si_sym_intent, idx);
    if ((!pact_str_eq(intent, ""))) {
        r = pact_str_concat(pact_str_concat(pact_str_concat(r, ",\"intent\":\""), pact_escape_str(intent)), "\"");
    }
    const char* doc = (const char*)pact_list_get(si_sym_doc, idx);
    if ((!pact_str_eq(doc, ""))) {
        r = pact_str_concat(pact_str_concat(pact_str_concat(r, ",\"doc\":\""), pact_escape_str(doc)), "\"");
    }
    const char* req = (const char*)pact_list_get(si_sym_requires, idx);
    if ((!pact_str_eq(req, ""))) {
        r = pact_str_concat(pact_str_concat(pact_str_concat(r, ",\"requires\":\""), pact_escape_str(req)), "\"");
    }
    const char* ens = (const char*)pact_list_get(si_sym_ensures, idx);
    if ((!pact_str_eq(ens, ""))) {
        r = pact_str_concat(pact_str_concat(pact_str_concat(r, ",\"ensures\":\""), pact_escape_str(ens)), "\"");
    }
    const int64_t line = (int64_t)(intptr_t)pact_list_get(si_sym_line, idx);
    char _si_0[4096];
    snprintf(_si_0, 4096, ",\"line\":%lld", (long long)line);
    r = pact_str_concat(r, strdup(_si_0));
    const int64_t el = (int64_t)(intptr_t)pact_list_get(si_sym_end_line, idx);
    if ((el > 0)) {
        char _si_1[4096];
        snprintf(_si_1, 4096, ",\"end_line\":%lld", (long long)el);
        r = pact_str_concat(r, strdup(_si_1));
        const char* file_path = (const char*)pact_list_get(si_sym_file, idx);
        if ((!pact_str_eq(file_path, ""))) {
            const char* file_content = pact_read_file(file_path);
            if ((!pact_str_eq(file_content, ""))) {
                const char* source = pact_extract_lines(file_content, line, el);
                if ((!pact_str_eq(source, ""))) {
                    r = pact_str_concat(pact_str_concat(pact_str_concat(r, ",\"source\":\""), pact_escape_str(source)), "\"");
                }
            }
        }
    }
    r = pact_str_concat(r, "}");
    return r;
}

const char* pact_format_symbol_for_layer(const char* layer, int64_t idx) {
    if (pact_str_eq(layer, "intent")) {
        return pact_symbol_to_intent_json(idx);
    }
    if (pact_str_eq(layer, "contract")) {
        return pact_symbol_to_contract_json(idx);
    }
    if (pact_str_eq(layer, "full")) {
        return pact_symbol_to_full_json(idx);
    }
    return pact_symbol_to_json(idx);
}

const char* pact_query_filtered_layer(const char* layer, int64_t vis_filter, const char* module_filter, const char* effect_filter, int64_t pure_only, const char* name_filter) {
    const char* items = "";
    int64_t first = 1;
    int64_t i = 0;
    while ((i < si_sym_count)) {
        if (((int64_t)(intptr_t)pact_list_get(si_sym_kind, i) != SK_FN)) {
            i = (i + 1);
            continue;
        }
        if (((vis_filter == VIS_PUB) && ((int64_t)(intptr_t)pact_list_get(si_sym_vis, i) != VIS_PUB))) {
            i = (i + 1);
            continue;
        }
        if (((!pact_str_eq(module_filter, "")) && (!pact_str_eq((const char*)pact_list_get(si_sym_module, i), module_filter)))) {
            i = (i + 1);
            continue;
        }
        if (((!pact_str_eq(effect_filter, "")) && (pact_effects_contain((const char*)pact_list_get(si_sym_effects, i), effect_filter) == 0))) {
            i = (i + 1);
            continue;
        }
        if (((pure_only != 0) && (!pact_str_eq((const char*)pact_list_get(si_sym_effects, i), "")))) {
            i = (i + 1);
            continue;
        }
        if (((!pact_str_eq(name_filter, "")) && (!pact_str_eq((const char*)pact_list_get(si_sym_name, i), name_filter)))) {
            i = (i + 1);
            continue;
        }
        if ((first == 0)) {
            items = pact_str_concat(items, ",");
        }
        items = pact_str_concat(items, pact_format_symbol_for_layer(layer, i));
        first = 0;
        i = (i + 1);
    }
    return pact_wrap_results(items);
}

int64_t pact_qr_skip_ws(const char* s, int64_t pos) {
    int64_t p = pos;
    while ((p < pact_str_len(s))) {
        const int64_t c = pact_str_char_at(s, p);
        if (((((c == 32) || (c == 9)) || (c == 10)) || (c == 13))) {
            p = (p + 1);
        } else {
            return p;
        }
    }
    return p;
}

const char* pact_qr_parse_string(const char* s, int64_t pos) {
    if (((pos >= pact_str_len(s)) || (pact_str_char_at(s, pos) != 34))) {
        return "";
    }
    int64_t p = (pos + 1);
    const char* result = "";
    while ((p < pact_str_len(s))) {
        const int64_t c = pact_str_char_at(s, p);
        if ((c == 34)) {
            return result;
        }
        if (((c == 92) && ((p + 1) < pact_str_len(s)))) {
            const int64_t next = pact_str_char_at(s, (p + 1));
            if ((next == 34)) {
                result = pact_str_concat(result, "\"");
                p = (p + 2);
            } else if ((next == 92)) {
                result = pact_str_concat(result, "\\");
                p = (p + 2);
            } else {
                if ((next == 110)) {
                    result = pact_str_concat(result, "\n");
                    p = (p + 2);
                } else {
                    result = pact_str_concat(result, pact_str_substr(s, p, 1));
                    p = (p + 1);
                }
            }
        } else {
            result = pact_str_concat(result, pact_str_substr(s, p, 1));
            p = (p + 1);
        }
    }
    return result;
}

int64_t pact_qr_end_of_string(const char* s, int64_t pos) {
    if (((pos >= pact_str_len(s)) || (pact_str_char_at(s, pos) != 34))) {
        return pos;
    }
    int64_t p = (pos + 1);
    while ((p < pact_str_len(s))) {
        const int64_t c = pact_str_char_at(s, p);
        if ((c == 34)) {
            return (p + 1);
        }
        if ((c == 92)) {
            p = (p + 2);
        } else {
            p = (p + 1);
        }
    }
    return p;
}

int64_t pact_qr_parse_request(const char* s) {
    pact_list* _l0 = pact_list_new();
    qr_keys = _l0;
    pact_list* _l1 = pact_list_new();
    qr_vals = _l1;
    int64_t p = pact_qr_skip_ws(s, 0);
    if (((p >= pact_str_len(s)) || (pact_str_char_at(s, p) != 123))) {
        return 0;
    }
    p = (p + 1);
    p = pact_qr_skip_ws(s, p);
    while (((p < pact_str_len(s)) && (pact_str_char_at(s, p) != 125))) {
        if ((pact_list_len(qr_keys) > 0)) {
            if (((p < pact_str_len(s)) && (pact_str_char_at(s, p) == 44))) {
                p = (p + 1);
                p = pact_qr_skip_ws(s, p);
            }
        }
        const char* key = pact_qr_parse_string(s, p);
        p = pact_qr_end_of_string(s, p);
        p = pact_qr_skip_ws(s, p);
        if (((p < pact_str_len(s)) && (pact_str_char_at(s, p) == 58))) {
            p = (p + 1);
        }
        p = pact_qr_skip_ws(s, p);
        const char* val = pact_qr_parse_string(s, p);
        p = pact_qr_end_of_string(s, p);
        p = pact_qr_skip_ws(s, p);
        pact_list_push(qr_keys, (void*)key);
        pact_list_push(qr_vals, (void*)val);
    }
    return 1;
}

const char* pact_qr_get(const char* key) {
    int64_t i = 0;
    while ((i < pact_list_len(qr_keys))) {
        if (pact_str_eq((const char*)pact_list_get(qr_keys, i), key)) {
            return (const char*)pact_list_get(qr_vals, i);
        }
        i = (i + 1);
    }
    return "";
}

const char* pact_query_dispatch(const char* request) {
    if ((pact_qr_parse_request(request) == 0)) {
        return "{\"error\":\"invalid JSON request\"}";
    }
    const char* qtype = pact_qr_get("type");
    if (pact_str_eq(qtype, "")) {
        return "{\"error\":\"missing 'type' field\"}";
    }
    if (pact_str_eq(qtype, "signature")) {
        const char* module = pact_qr_get("module");
        if (pact_str_eq(module, "")) {
            return "{\"error\":\"missing 'module' field for signature query\"}";
        }
        return pact_query_by_signature(module);
    }
    if (pact_str_eq(qtype, "effect")) {
        const char* eff_name = pact_qr_get("effect");
        if (pact_str_eq(eff_name, "")) {
            return "{\"error\":\"missing 'effect' field for effect query\"}";
        }
        return pact_query_by_effect(eff_name);
    }
    if (pact_str_eq(qtype, "pub_pure")) {
        return pact_query_pub_pure();
    }
    if (pact_str_eq(qtype, "fn")) {
        const char* name = pact_qr_get("name");
        if (pact_str_eq(name, "")) {
            return "{\"error\":\"missing 'name' field for fn query\"}";
        }
        return pact_query_by_name(name);
    }
    char _si_0[4096];
    snprintf(_si_0, 4096, "{\"error\":\"unknown query type: %s\"}", qtype);
    return strdup(_si_0);
}

void pact_inc_snapshot(void) {
    pact_list* _l0 = pact_list_new();
    inc_snap_path = _l0;
    pact_list* _l1 = pact_list_new();
    inc_snap_mtime = _l1;
    inc_snap_count = 0;
    snap_path_map = pact_map_new();
    int64_t i = 0;
    while ((i < si_file_count)) {
        const char* path = (const char*)pact_list_get(si_file_path, i);
        const int64_t mtime = pact_file_mtime(path);
        pact_list_push(inc_snap_path, (void*)path);
        pact_list_push(inc_snap_mtime, (void*)(intptr_t)mtime);
        pact_map_set(snap_path_map, path, (void*)(intptr_t)i);
        inc_snap_count = (inc_snap_count + 1);
        i = (i + 1);
    }
}

void pact_inc_detect_changes(void) {
    pact_list* _l0 = pact_list_new();
    inc_dirty_path = _l0;
    inc_dirty_count = 0;
    int64_t i = 0;
    while ((i < inc_snap_count)) {
        const char* path = (const char*)pact_list_get(inc_snap_path, i);
        const int64_t old_mtime = (int64_t)(intptr_t)pact_list_get(inc_snap_mtime, i);
        const int64_t cur_mtime = pact_file_mtime(path);
        if ((cur_mtime != old_mtime)) {
            pact_list_push(inc_dirty_path, (void*)path);
            inc_dirty_count = (inc_dirty_count + 1);
        }
        i = (i + 1);
    }
    i = 0;
    while ((i < si_file_count)) {
        const char* path = (const char*)pact_list_get(si_file_path, i);
        if ((pact_map_has(snap_path_map, path) == 0)) {
            pact_list_push(inc_dirty_path, (void*)path);
            inc_dirty_count = (inc_dirty_count + 1);
        }
        i = (i + 1);
    }
}

void pact_mark_affected(int64_t sym_idx) {
    char _si_0[4096];
    snprintf(_si_0, 4096, "%lld", (long long)sym_idx);
    const char* key = strdup(_si_0);
    if ((pact_map_has(affected_map, key) != 0)) {
        return;
    }
    pact_map_set(affected_map, key, (void*)(intptr_t)1);
    pact_list_push(inc_affected, (void*)(intptr_t)sym_idx);
    inc_affected_count = (inc_affected_count + 1);
    pact_list* rdeps = pact_si_get_rdeps(sym_idx);
    int64_t i = 0;
    while ((i < pact_list_len(rdeps))) {
        pact_mark_affected((int64_t)(intptr_t)pact_list_get(rdeps, i));
        i = (i + 1);
    }
}

void pact_inc_compute_affected(void) {
    pact_list* _l0 = pact_list_new();
    inc_affected = _l0;
    inc_affected_count = 0;
    affected_map = pact_map_new();
    int64_t di = 0;
    while ((di < inc_dirty_count)) {
        const char* path = (const char*)pact_list_get(inc_dirty_path, di);
        pact_list* syms = pact_si_file_symbols(path);
        int64_t si = 0;
        while ((si < pact_list_len(syms))) {
            pact_mark_affected((int64_t)(intptr_t)pact_list_get(syms, si));
            si = (si + 1);
        }
        di = (di + 1);
    }
}

int64_t pact_inc_needs_recheck(int64_t sym_idx) {
    if ((inc_affected_count == 0)) {
        return 1;
    }
    char _si_0[4096];
    snprintf(_si_0, 4096, "%lld", (long long)sym_idx);
    return pact_map_has(affected_map, strdup(_si_0));
}

void pact_inc_reset(void) {
    pact_list* _l0 = pact_list_new();
    inc_snap_path = _l0;
    pact_list* _l1 = pact_list_new();
    inc_snap_mtime = _l1;
    inc_snap_count = 0;
    pact_list* _l2 = pact_list_new();
    inc_dirty_path = _l2;
    inc_dirty_count = 0;
    pact_list* _l3 = pact_list_new();
    inc_affected = _l3;
    inc_affected_count = 0;
    affected_map = pact_map_new();
    snap_path_map = pact_map_new();
}

const char* pact_dj_escape(const char* s) {
    const char* result = "";
    int64_t i = 0;
    while ((i < pact_str_len(s))) {
        const int64_t c = pact_str_char_at(s, i);
        if ((c == 34)) {
            result = pact_str_concat(result, "\\\"");
        } else if ((c == 92)) {
            result = pact_str_concat(result, "\\\\");
        } else {
            if ((c == 10)) {
                result = pact_str_concat(result, "\\n");
            } else if ((c == 9)) {
                result = pact_str_concat(result, "\\t");
            } else {
                if ((c == 13)) {
                    result = pact_str_concat(result, "\\r");
                } else {
                    result = pact_str_concat(result, pact_str_substr(s, i, 1));
                }
            }
        }
        i = (i + 1);
    }
    return result;
}

int64_t pact_dr_skip_ws(const char* s, int64_t p) {
    int64_t i = p;
    while ((i < pact_str_len(s))) {
        const int64_t c = pact_str_char_at(s, i);
        if (((((c == 32) || (c == 9)) || (c == 10)) || (c == 13))) {
            i = (i + 1);
        } else {
            return i;
        }
    }
    return i;
}

const char* pact_dr_parse_string(const char* s, int64_t p) {
    if (((p >= pact_str_len(s)) || (pact_str_char_at(s, p) != 34))) {
        return "";
    }
    int64_t i = (p + 1);
    const char* result = "";
    while ((i < pact_str_len(s))) {
        const int64_t c = pact_str_char_at(s, i);
        if ((c == 34)) {
            return result;
        }
        if (((c == 92) && ((i + 1) < pact_str_len(s)))) {
            const int64_t next = pact_str_char_at(s, (i + 1));
            if ((next == 34)) {
                result = pact_str_concat(result, "\"");
                i = (i + 2);
            } else if ((next == 92)) {
                result = pact_str_concat(result, "\\");
                i = (i + 2);
            } else {
                if ((next == 110)) {
                    result = pact_str_concat(result, "\n");
                    i = (i + 2);
                } else {
                    result = pact_str_concat(result, pact_str_substr(s, i, 1));
                    i = (i + 1);
                }
            }
        } else {
            result = pact_str_concat(result, pact_str_substr(s, i, 1));
            i = (i + 1);
        }
    }
    return result;
}

int64_t pact_dr_end_of_string(const char* s, int64_t p) {
    if (((p >= pact_str_len(s)) || (pact_str_char_at(s, p) != 34))) {
        return p;
    }
    int64_t i = (p + 1);
    while ((i < pact_str_len(s))) {
        const int64_t c = pact_str_char_at(s, i);
        if ((c == 34)) {
            return (i + 1);
        }
        if ((c == 92)) {
            i = (i + 2);
        } else {
            i = (i + 1);
        }
    }
    return i;
}

int64_t pact_dr_parse_request(const char* s) {
    pact_list* _l0 = pact_list_new();
    dr_keys = _l0;
    pact_list* _l1 = pact_list_new();
    dr_vals = _l1;
    int64_t p = pact_dr_skip_ws(s, 0);
    if (((p >= pact_str_len(s)) || (pact_str_char_at(s, p) != 123))) {
        return 0;
    }
    p = (p + 1);
    p = pact_dr_skip_ws(s, p);
    while (((p < pact_str_len(s)) && (pact_str_char_at(s, p) != 125))) {
        if ((pact_list_len(dr_keys) > 0)) {
            if (((p < pact_str_len(s)) && (pact_str_char_at(s, p) == 44))) {
                p = (p + 1);
                p = pact_dr_skip_ws(s, p);
            }
        }
        const char* key = pact_dr_parse_string(s, p);
        p = pact_dr_end_of_string(s, p);
        p = pact_dr_skip_ws(s, p);
        if (((p < pact_str_len(s)) && (pact_str_char_at(s, p) == 58))) {
            p = (p + 1);
        }
        p = pact_dr_skip_ws(s, p);
        const char* val = pact_dr_parse_string(s, p);
        p = pact_dr_end_of_string(s, p);
        p = pact_dr_skip_ws(s, p);
        pact_list_push(dr_keys, (void*)key);
        pact_list_push(dr_vals, (void*)val);
    }
    return 1;
}

const char* pact_dr_get(const char* key) {
    int64_t i = 0;
    while ((i < pact_list_len(dr_keys))) {
        if (pact_str_eq((const char*)pact_list_get(dr_keys, i), key)) {
            return (const char*)pact_list_get(dr_vals, i);
        }
        i = (i + 1);
    }
    return "";
}

const char* pact_daemon_extract_type(const char* request) {
    if ((pact_dr_parse_request(request) == 0)) {
        return "";
    }
    return pact_dr_get("type");
}

const char* pact_daemon_diags_to_json(void) {
    const char* result = "[";
    int64_t i = 0;
    while ((i < pact_list_len(diag_severity))) {
        if ((i > 0)) {
            result = pact_str_concat(result, ",");
        }
        const char* sev = pact_dj_escape((const char*)pact_list_get(diag_severity, i));
        const char* name = pact_dj_escape((const char*)pact_list_get(diag_name, i));
        const char* code = pact_dj_escape((const char*)pact_list_get(diag_code, i));
        const char* msg = pact_dj_escape((const char*)pact_list_get(diag_message, i));
        const char* file = pact_dj_escape((const char*)pact_list_get(diag_file, i));
        const int64_t line = (int64_t)(intptr_t)pact_list_get(diag_line, i);
        const int64_t col = (int64_t)(intptr_t)pact_list_get(diag_col, i);
        const char* help = (const char*)pact_list_get(diag_help, i);
        char _si_0[4096];
        snprintf(_si_0, 4096, "{\"severity\":\"%s\",\"name\":\"%s\",\"code\":\"%s\",\"message\":\"%s\",\"file\":\"%s\",\"line\":%lld,\"col\":%lld", sev, name, code, msg, file, (long long)line, (long long)col);
        const char* entry = strdup(_si_0);
        if ((!pact_str_eq(help, ""))) {
            entry = pact_str_concat(pact_str_concat(pact_str_concat(entry, ",\"help\":\""), pact_dj_escape(help)), "\"");
        }
        entry = pact_str_concat(entry, "}");
        result = pact_str_concat(result, entry);
        i = (i + 1);
    }
    result = pact_str_concat(result, "]");
    return result;
}

const char* pact_daemon_handle_check(void) {
    daemon_check_count = (daemon_check_count + 1);
    const int64_t changed = pact_fw_poll();
    if ((changed == 0)) {
        return "{\"ok\":true,\"changed\":0,\"diagnostics\":[]}";
    }
    pact_inc_detect_changes();
    pact_inc_compute_affected();
    pact_list* _l0 = pact_list_new();
    pact_list* affected_names = _l0;
    int64_t i = 0;
    while ((i < inc_affected_count)) {
        const int64_t sym_idx = (int64_t)(intptr_t)pact_list_get(inc_affected, i);
        pact_list_push(affected_names, (void*)(const char*)pact_list_get(si_sym_name, sym_idx));
        i = (i + 1);
    }
    pact_diag_reset();
    const char* source = pact_read_file(daemon_source_path);
    pact_lex(source);
    pos = 0;
    const int64_t program = pact_parse_program();
    daemon_program = program;
    pact_tc_set_incremental_filter(affected_names);
    pact_check_types(program);
    pact_tc_clear_incremental_filter();
    pact_si_reset();
    pact_si_build(program, daemon_source_path, "main");
    pact_inc_snapshot();
    pact_fw_clear_dirty();
    const char* diags_json = pact_daemon_diags_to_json();
    const int64_t err_count = diag_count;
    char _si_1[4096];
    snprintf(_si_1, 4096, "{\"ok\":true,\"changed\":%lld,\"errors\":%lld,\"diagnostics\":%s}", (long long)changed, (long long)err_count, diags_json);
    return strdup(_si_1);
}

const char* pact_daemon_handle_query(const char* request) {
    return pact_query_dispatch(request);
}

const char* pact_daemon_handle_status(void) {
    const int64_t now = pact_time_ms();
    const int64_t uptime = (now - daemon_start_time);
    const int64_t sym_count = si_sym_count;
    const int64_t file_count = si_file_count;
    const int64_t checks = daemon_check_count;
    char _si_0[4096];
    snprintf(_si_0, 4096, "{\"ok\":true,\"uptime_ms\":%lld,\"symbols\":%lld,\"files\":%lld,\"checks\":%lld}", (long long)uptime, (long long)sym_count, (long long)file_count, (long long)checks);
    return strdup(_si_0);
}

const char* pact_daemon_handle_stop(void) {
    daemon_running = 0;
    return "{\"ok\":true,\"message\":\"daemon stopping\"}";
}

void pact_daemon_loop(void) {
    while ((daemon_running == 1)) {
        const int64_t client_fd = pact_unix_socket_accept(daemon_socket_fd);
        if ((client_fd < 0)) {
            continue;
        }
        const char* request = pact_socket_read_line(client_fd);
        const char* req_type = pact_daemon_extract_type(request);
        const char* response = "";
        if (pact_str_eq(req_type, "check")) {
            response = pact_daemon_handle_check();
        } else if (pact_str_eq(req_type, "query")) {
            response = pact_daemon_handle_query(request);
        } else {
            if (pact_str_eq(req_type, "status")) {
                response = pact_daemon_handle_status();
            } else if (pact_str_eq(req_type, "stop")) {
                response = pact_daemon_handle_stop();
            } else {
                char _si_0[4096];
                snprintf(_si_0, 4096, "{\"ok\":false,\"error\":\"unknown request type: %s\"}", req_type);
                response = strdup(_si_0);
            }
        }
        pact_socket_write(client_fd, pact_str_concat(response, "\n"));
        pact_unix_socket_close(client_fd);
        if ((daemon_running == 1)) {
            pact_fw_poll();
        }
    }
}

void pact_daemon_stop(void) {
    if ((daemon_socket_fd >= 0)) {
        pact_unix_socket_close(daemon_socket_fd);
        daemon_socket_fd = (-1);
    }
    if ((!pact_str_eq(daemon_pid_path, ""))) {
        char _si_0[4096];
        snprintf(_si_0, 4096, "rm -f %s", daemon_pid_path);
        pact_shell_exec(strdup(_si_0));
    }
    if ((!pact_str_eq(daemon_sock_path, ""))) {
        char _si_1[4096];
        snprintf(_si_1, 4096, "rm -f %s", daemon_sock_path);
        pact_shell_exec(strdup(_si_1));
    }
    pact_si_reset();
    pact_inc_reset();
    pact_fw_reset();
    daemon_running = 0;
}

void pact_daemon_start(const char* root, const char* source) {
    daemon_project_root = root;
    daemon_source_path = source;
    daemon_start_time = pact_time_ms();
    const char* pact_dir = pact_path_join(root, ".pact");
    char _si_0[4096];
    snprintf(_si_0, 4096, "mkdir -p %s", pact_dir);
    pact_shell_exec(strdup(_si_0));
    daemon_pid_path = pact_path_join(pact_dir, "daemon.pid");
    const int64_t pid = pact_getpid();
    char _si_1[4096];
    snprintf(_si_1, 4096, "%lld", (long long)pid);
    pact_write_file(daemon_pid_path, strdup(_si_1));
    daemon_sock_path = pact_path_join(pact_dir, "daemon.sock");
    daemon_socket_fd = pact_unix_socket_listen(daemon_sock_path);
    if ((daemon_socket_fd < 0)) {
        char _si_2[4096];
        snprintf(_si_2, 4096, "daemon: failed to create socket at %s", daemon_sock_path);
        fprintf(stderr, "%s\n", strdup(_si_2));
        return;
    }
    const char* src = pact_read_file(source);
    pact_lex(src);
    pos = 0;
    const int64_t program = pact_parse_program();
    daemon_program = program;
    pact_check_types(program);
    pact_si_build(program, source, "main");
    pact_fw_init();
    pact_inc_snapshot();
    char _si_3[4096];
    snprintf(_si_3, 4096, "daemon: listening on %s (pid %lld)", daemon_sock_path, (long long)pid);
    fprintf(stderr, "%s\n", strdup(_si_3));
    daemon_running = 1;
    pact_daemon_loop();
    pact_daemon_stop();
}

int64_t pact_is_ws(int64_t c) {
    return ((c == CH_SPACE) || (c == CH_TAB));
}

int64_t pact_is_newline(int64_t c) {
    return ((c == CH_NEWLINE) || (c == CH_CR));
}

int64_t pact_is_bare_key_char(int64_t c) {
    return ((((pact_is_alpha(c) || pact_is_digit(c)) || (c == CH_UNDERSCORE)) || (c == CH_MINUS)) || (c == CH_SLASH));
}

int64_t pact_skip_ws(const char* content, int64_t pos) {
    int64_t p = pos;
    while (((p < pact_str_len(content)) && pact_is_ws(pact_peek(content, p)))) {
        p = (p + 1);
    }
    return p;
}

int64_t pact_skip_to_newline(const char* content, int64_t pos) {
    int64_t p = pos;
    while (((p < pact_str_len(content)) && (pact_peek(content, p) != CH_NEWLINE))) {
        p = (p + 1);
    }
    return p;
}

int64_t pact_skip_ws_and_newlines(const char* content, int64_t pos) {
    int64_t p = pos;
    while ((p < pact_str_len(content))) {
        const int64_t c = pact_peek(content, p);
        if ((pact_is_ws(c) || pact_is_newline(c))) {
            p = (p + 1);
        } else {
            return p;
        }
    }
    return p;
}

void pact_store_entry(const char* key, const char* value, int64_t vtype) {
    pact_list_push(toml_keys, (void*)key);
    pact_list_push(toml_values, (void*)value);
    pact_list_push(toml_types, (void*)(intptr_t)vtype);
}

int64_t pact_find_key_index(const char* key) {
    int64_t i = 0;
    while ((i < pact_list_len(toml_keys))) {
        if (pact_str_eq((const char*)pact_list_get(toml_keys, i), key)) {
            return i;
        }
        i = (i + 1);
    }
    return (-1);
}

int64_t pact_get_arr_table_count(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(arr_table_names))) {
        if (pact_str_eq((const char*)pact_list_get(arr_table_names, i), name)) {
            return (int64_t)(intptr_t)pact_list_get(arr_table_counts, i);
        }
        i = (i + 1);
    }
    return 0;
}

int64_t pact_inc_arr_table_count(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(arr_table_names))) {
        if (pact_str_eq((const char*)pact_list_get(arr_table_names, i), name)) {
            const int64_t count = (int64_t)(intptr_t)pact_list_get(arr_table_counts, i);
            pact_list_set(arr_table_counts, i, (void*)(intptr_t)(count + 1));
            return count;
        }
        i = (i + 1);
    }
    pact_list_push(arr_table_names, (void*)name);
    pact_list_push(arr_table_counts, (void*)(intptr_t)1);
    return 0;
}

void pact_parse_quoted_string(const char* content, int64_t pos) {
    int64_t p = (pos + 1);
    const char* result = "";
    while ((p < pact_str_len(content))) {
        const int64_t c = pact_peek(content, p);
        if ((c == CH_DQUOTE)) {
            tmp_str = result;
            tmp_pos = (p + 1);
            return;
        }
        if (((c == CH_BACKSLASH) && ((p + 1) < pact_str_len(content)))) {
            const int64_t next = pact_peek(content, (p + 1));
            if ((next == CH_n)) {
                result = pact_str_concat(result, "\n");
                p = (p + 2);
                continue;
            }
            if ((next == CH_t)) {
                result = pact_str_concat(result, "\t");
                p = (p + 2);
                continue;
            }
            if ((next == CH_BACKSLASH)) {
                result = pact_str_concat(result, "\\");
                p = (p + 2);
                continue;
            }
            if ((next == CH_DQUOTE)) {
                result = pact_str_concat(result, "\"");
                p = (p + 2);
                continue;
            }
            result = pact_str_concat(result, pact_str_substr(content, p, 1));
            p = (p + 1);
            continue;
        }
        result = pact_str_concat(result, pact_str_substr(content, p, 1));
        p = (p + 1);
    }
    tmp_str = result;
    tmp_pos = p;
}

void pact_parse_bare_key(const char* content, int64_t pos) {
    int64_t p = pos;
    while (((p < pact_str_len(content)) && pact_is_bare_key_char(pact_peek(content, p)))) {
        p = (p + 1);
    }
    tmp_str = pact_str_substr(content, pos, (p - pos));
    tmp_pos = p;
}

void pact_parse_key(const char* content, int64_t pos) {
    const int64_t c = pact_peek(content, pos);
    if ((c == CH_DQUOTE)) {
        pact_parse_quoted_string(content, pos);
    } else {
        pact_parse_bare_key(content, pos);
    }
}

void pact_parse_dotted_key(const char* content, int64_t pos) {
    pact_parse_key(content, pos);
    const char* result = tmp_str;
    int64_t p = tmp_pos;
    while ((p < pact_str_len(content))) {
        const int64_t pp = pact_skip_ws(content, p);
        if ((pact_peek(content, pp) == CH_DOT)) {
            const int64_t after_dot = pact_skip_ws(content, (pp + 1));
            pact_parse_key(content, after_dot);
            result = pact_str_concat(pact_str_concat(result, "."), tmp_str);
            p = tmp_pos;
        } else {
            tmp_str = result;
            tmp_pos = p;
            return;
        }
    }
    tmp_str = result;
    tmp_pos = p;
}

void pact_parse_integer(const char* content, int64_t pos) {
    int64_t p = pos;
    if (((p < pact_str_len(content)) && ((pact_peek(content, p) == CH_PLUS) || (pact_peek(content, p) == CH_MINUS)))) {
        p = (p + 1);
    }
    while (((p < pact_str_len(content)) && pact_is_digit(pact_peek(content, p)))) {
        p = (p + 1);
    }
    tmp_str = pact_str_substr(content, pos, (p - pos));
    tmp_pos = p;
}

void pact_parse_array_value(const char* content, int64_t pos, const char* full_key) {
    int64_t p = (pos + 1);
    int64_t count = 0;
    p = pact_skip_ws_and_newlines(content, p);
    while (((p < pact_str_len(content)) && (pact_peek(content, p) != CH_RBRACKET))) {
        p = pact_skip_ws_and_newlines(content, p);
        if ((pact_peek(content, p) == CH_RBRACKET)) {
            p = (p + 1);
            char _si_0[4096];
            snprintf(_si_0, 4096, "%lld", (long long)count);
            pact_store_entry(full_key, strdup(_si_0), TOML_ARRAY);
            tmp_pos = p;
            return;
        }
        const int64_t c = pact_peek(content, p);
        if ((c == CH_DQUOTE)) {
            pact_parse_quoted_string(content, p);
            char _si_1[4096];
            snprintf(_si_1, 4096, "%s[%lld]", full_key, (long long)count);
            const char* item_key = strdup(_si_1);
            pact_store_entry(item_key, tmp_str, TOML_STRING);
            p = tmp_pos;
            count = (count + 1);
        } else if (((pact_is_digit(c) || (c == CH_MINUS)) || (c == CH_PLUS))) {
            pact_parse_integer(content, p);
            char _si_2[4096];
            snprintf(_si_2, 4096, "%s[%lld]", full_key, (long long)count);
            const char* item_key = strdup(_si_2);
            pact_store_entry(item_key, tmp_str, TOML_INT);
            p = tmp_pos;
            count = (count + 1);
        } else {
            p = (p + 1);
        }
        p = pact_skip_ws_and_newlines(content, p);
        if ((pact_peek(content, p) == CH_COMMA)) {
            p = (p + 1);
        }
    }
    if (((p < pact_str_len(content)) && (pact_peek(content, p) == CH_RBRACKET))) {
        p = (p + 1);
    }
    char _si_3[4096];
    snprintf(_si_3, 4096, "%lld", (long long)count);
    pact_store_entry(full_key, strdup(_si_3), TOML_ARRAY);
    tmp_pos = p;
}

void pact_parse_inline_table(const char* content, int64_t pos, const char* prefix) {
    int64_t p = (pos + 1);
    p = pact_skip_ws(content, p);
    while (((p < pact_str_len(content)) && (pact_peek(content, p) != CH_RBRACE))) {
        p = pact_skip_ws(content, p);
        if ((pact_peek(content, p) == CH_RBRACE)) {
            p = (p + 1);
            tmp_pos = p;
            return;
        }
        pact_parse_dotted_key(content, p);
        const char* key = tmp_str;
        p = tmp_pos;
        p = pact_skip_ws(content, p);
        if ((pact_peek(content, p) == CH_EQUALS)) {
            p = (p + 1);
        }
        p = pact_skip_ws(content, p);
        char _si_0[4096];
        snprintf(_si_0, 4096, "%s.%s", prefix, key);
        const char* full_key = strdup(_si_0);
        const int64_t vc = pact_peek(content, p);
        if ((vc == CH_DQUOTE)) {
            pact_parse_quoted_string(content, p);
            pact_store_entry(full_key, tmp_str, TOML_STRING);
            p = tmp_pos;
        } else if ((vc == CH_LBRACKET)) {
            pact_parse_array_value(content, p, full_key);
            p = tmp_pos;
        } else {
            if ((vc == CH_LBRACE)) {
                pact_parse_inline_table(content, p, full_key);
                pact_store_entry(full_key, "", TOML_INLINE_TABLE);
                p = tmp_pos;
            } else if (((pact_is_digit(vc) || (vc == CH_MINUS)) || (vc == CH_PLUS))) {
                pact_parse_integer(content, p);
                pact_store_entry(full_key, tmp_str, TOML_INT);
                p = tmp_pos;
            } else {
                if ((((p + 4) <= pact_str_len(content)) && pact_str_eq(pact_str_substr(content, p, 4), "true"))) {
                    pact_store_entry(full_key, "1", TOML_BOOL);
                    p = (p + 4);
                } else if ((((p + 5) <= pact_str_len(content)) && pact_str_eq(pact_str_substr(content, p, 5), "false"))) {
                    pact_store_entry(full_key, "0", TOML_BOOL);
                    p = (p + 5);
                } else {
                    p = (p + 1);
                }
            }
        }
        p = pact_skip_ws(content, p);
        if ((pact_peek(content, p) == CH_COMMA)) {
            p = (p + 1);
        }
    }
    if (((p < pact_str_len(content)) && (pact_peek(content, p) == CH_RBRACE))) {
        p = (p + 1);
    }
    tmp_pos = p;
}

void pact_parse_value(const char* content, int64_t pos, const char* full_key) {
    const int64_t c = pact_peek(content, pos);
    if ((c == CH_DQUOTE)) {
        pact_parse_quoted_string(content, pos);
        pact_store_entry(full_key, tmp_str, TOML_STRING);
        return;
    }
    if ((c == CH_LBRACKET)) {
        pact_parse_array_value(content, pos, full_key);
        return;
    }
    if ((c == CH_LBRACE)) {
        pact_parse_inline_table(content, pos, full_key);
        pact_store_entry(full_key, "", TOML_INLINE_TABLE);
        return;
    }
    if (((pact_is_digit(c) || (c == CH_MINUS)) || (c == CH_PLUS))) {
        pact_parse_integer(content, pos);
        pact_store_entry(full_key, tmp_str, TOML_INT);
        return;
    }
    if ((((pos + 4) <= pact_str_len(content)) && pact_str_eq(pact_str_substr(content, pos, 4), "true"))) {
        pact_store_entry(full_key, "1", TOML_BOOL);
        tmp_pos = (pos + 4);
        return;
    }
    if ((((pos + 5) <= pact_str_len(content)) && pact_str_eq(pact_str_substr(content, pos, 5), "false"))) {
        pact_store_entry(full_key, "0", TOML_BOOL);
        tmp_pos = (pos + 5);
        return;
    }
    tmp_pos = pact_skip_to_newline(content, pos);
}

void pact_parse_section_header(const char* content, int64_t pos) {
    int64_t p = (pos + 1);
    p = pact_skip_ws(content, p);
    pact_parse_dotted_key(content, p);
    const char* name = tmp_str;
    p = tmp_pos;
    p = pact_skip_ws(content, p);
    if (((p < pact_str_len(content)) && (pact_peek(content, p) == CH_RBRACKET))) {
        p = (p + 1);
    }
    tmp_str = name;
    tmp_pos = p;
}

void pact_parse_array_table_header(const char* content, int64_t pos) {
    int64_t p = (pos + 2);
    p = pact_skip_ws(content, p);
    pact_parse_dotted_key(content, p);
    const char* name = tmp_str;
    p = tmp_pos;
    p = pact_skip_ws(content, p);
    if (((p < pact_str_len(content)) && (pact_peek(content, p) == CH_RBRACKET))) {
        p = (p + 1);
    }
    if (((p < pact_str_len(content)) && (pact_peek(content, p) == CH_RBRACKET))) {
        p = (p + 1);
    }
    tmp_str = name;
    tmp_pos = p;
}

int64_t pact_toml_parse(const char* content) {
    int64_t pos = 0;
    const char* current_section = "";
    int64_t in_array_table = 0;
    const char* array_table_name = "";
    int64_t array_table_index = 0;
    while ((pos < pact_str_len(content))) {
        pos = pact_skip_ws(content, pos);
        if ((pos >= pact_str_len(content))) {
            return 0;
        }
        const int64_t c = pact_peek(content, pos);
        if (pact_is_newline(c)) {
            pos = (pos + 1);
            continue;
        }
        if ((c == CH_HASH)) {
            pos = pact_skip_to_newline(content, pos);
            if ((pos < pact_str_len(content))) {
                pos = (pos + 1);
            }
            continue;
        }
        if ((((c == CH_LBRACKET) && ((pos + 1) < pact_str_len(content))) && (pact_peek(content, (pos + 1)) == CH_LBRACKET))) {
            pact_parse_array_table_header(content, pos);
            array_table_name = tmp_str;
            pos = tmp_pos;
            in_array_table = 1;
            array_table_index = pact_inc_arr_table_count(array_table_name);
            char _si_0[4096];
            snprintf(_si_0, 4096, "%s[%lld]", array_table_name, (long long)array_table_index);
            current_section = strdup(_si_0);
            pos = pact_skip_to_newline(content, pos);
            if ((pos < pact_str_len(content))) {
                pos = (pos + 1);
            }
            continue;
        }
        if ((c == CH_LBRACKET)) {
            pact_parse_section_header(content, pos);
            current_section = tmp_str;
            pos = tmp_pos;
            in_array_table = 0;
            pos = pact_skip_to_newline(content, pos);
            if ((pos < pact_str_len(content))) {
                pos = (pos + 1);
            }
            continue;
        }
        pact_parse_dotted_key(content, pos);
        const char* key = tmp_str;
        pos = tmp_pos;
        pos = pact_skip_ws(content, pos);
        if ((pact_peek(content, pos) == CH_EQUALS)) {
            pos = (pos + 1);
        }
        pos = pact_skip_ws(content, pos);
        const char* full_key = key;
        if ((!pact_str_eq(current_section, ""))) {
            char _si_1[4096];
            snprintf(_si_1, 4096, "%s.%s", current_section, key);
            full_key = strdup(_si_1);
        }
        pact_parse_value(content, pos, full_key);
        pos = tmp_pos;
        pos = pact_skip_to_newline(content, pos);
        if ((pos < pact_str_len(content))) {
            pos = (pos + 1);
        }
    }
    return 0;
}

const char* pact_toml_get(const char* key) {
    const int64_t idx = pact_find_key_index(key);
    if ((idx == (-1))) {
        return "";
    }
    return (const char*)pact_list_get(toml_values, idx);
}

int64_t pact_toml_get_int(const char* key) {
    const char* val = pact_toml_get(key);
    if (pact_str_eq(val, "")) {
        return 0;
    }
    int64_t result = 0;
    int64_t i = 0;
    int64_t negative = 0;
    if (((i < pact_str_len(val)) && (pact_str_char_at(val, i) == CH_MINUS))) {
        negative = 1;
        i = (i + 1);
    }
    if (((i < pact_str_len(val)) && (pact_str_char_at(val, i) == CH_PLUS))) {
        i = (i + 1);
    }
    while ((i < pact_str_len(val))) {
        const int64_t c = pact_str_char_at(val, i);
        if (((c >= CH_0) && (c <= CH_9))) {
            result = ((result * 10) + (c - CH_0));
        }
        i = (i + 1);
    }
    if ((negative == 1)) {
        return (0 - result);
    }
    return result;
}

int64_t pact_toml_has(const char* key) {
    if ((pact_find_key_index(key) != (-1))) {
        return 1;
    }
    return 0;
}

int64_t pact_toml_array_len(const char* key) {
    return pact_get_arr_table_count(key);
}

const char* pact_toml_get_array_item(const char* key, int64_t index) {
    char _si_0[4096];
    snprintf(_si_0, 4096, "%s[%lld]", key, (long long)index);
    const char* item_key = strdup(_si_0);
    return pact_toml_get(item_key);
}

int64_t pact_toml_get_array_len(const char* key) {
    const char* val = pact_toml_get(key);
    if (pact_str_eq(val, "")) {
        return 0;
    }
    return pact_toml_get_int(key);
}

int64_t pact_toml_clear(void) {
    pact_list* _l0 = pact_list_new();
    toml_keys = _l0;
    pact_list* _l1 = pact_list_new();
    toml_values = _l1;
    pact_list* _l2 = pact_list_new();
    toml_types = _l2;
    pact_list* _l3 = pact_list_new();
    arr_table_names = _l3;
    pact_list* _l4 = pact_list_new();
    arr_table_counts = _l4;
    tmp_str = "";
    tmp_pos = 0;
    return 0;
}

void pact_lockfile_clear(void) {
    lock_version = 0;
    lock_pact_version = "";
    lock_generated = "";
    pact_list* _l0 = pact_list_new();
    lock_pkg_names = _l0;
    pact_list* _l1 = pact_list_new();
    lock_pkg_versions = _l1;
    pact_list* _l2 = pact_list_new();
    lock_pkg_sources = _l2;
    pact_list* _l3 = pact_list_new();
    lock_pkg_hashes = _l3;
    pact_list* _l4 = pact_list_new();
    lock_pkg_caps = _l4;
}

int64_t pact_lockfile_pkg_count(void) {
    return pact_list_len(lock_pkg_names);
}

int64_t pact_lockfile_find_pkg(const char* name) {
    int64_t i = 0;
    while ((i < pact_list_len(lock_pkg_names))) {
        if (pact_str_eq((const char*)pact_list_get(lock_pkg_names, i), name)) {
            return i;
        }
        i = (i + 1);
    }
    return (-1);
}

const char* pact_lockfile_get_pkg_hash(const char* name) {
    const int64_t idx = pact_lockfile_find_pkg(name);
    if ((idx == (-1))) {
        return "";
    }
    return (const char*)pact_list_get(lock_pkg_hashes, idx);
}

int64_t pact_lockfile_verify_hash(const char* name, const char* expected_hash) {
    const char* actual = pact_lockfile_get_pkg_hash(name);
    if (pact_str_eq(actual, "")) {
        return 0;
    }
    if (pact_str_eq(actual, expected_hash)) {
        return 1;
    }
    return 0;
}

void pact_lockfile_add_pkg(const char* name, const char* version, const char* source, const char* hash, const char* caps) {
    pact_list_push(lock_pkg_names, (void*)name);
    pact_list_push(lock_pkg_versions, (void*)version);
    pact_list_push(lock_pkg_sources, (void*)source);
    pact_list_push(lock_pkg_hashes, (void*)hash);
    pact_list_push(lock_pkg_caps, (void*)caps);
}

void pact_lockfile_set_metadata(const char* pact_version, const char* generated) {
    lock_version = 1;
    lock_pact_version = pact_version;
    lock_generated = generated;
}

int64_t pact_str_compare(const char* a, const char* b) {
    int64_t i = 0;
    const int64_t a_len = pact_str_len(a);
    const int64_t b_len = pact_str_len(b);
    while (((i < a_len) && (i < b_len))) {
        const int64_t ca = pact_str_char_at(a, i);
        const int64_t cb = pact_str_char_at(b, i);
        if ((ca < cb)) {
            return (-1);
        }
        if ((ca > cb)) {
            return 1;
        }
        i = (i + 1);
    }
    if ((a_len < b_len)) {
        return (-1);
    }
    if ((a_len > b_len)) {
        return 1;
    }
    return 0;
}

void pact_sort_packages(void) {
    const int64_t n = pact_list_len(lock_pkg_names);
    int64_t i = 1;
    while ((i < n)) {
        const char* key_name = (const char*)pact_list_get(lock_pkg_names, i);
        const char* key_ver = (const char*)pact_list_get(lock_pkg_versions, i);
        const char* key_src = (const char*)pact_list_get(lock_pkg_sources, i);
        const char* key_hash = (const char*)pact_list_get(lock_pkg_hashes, i);
        const char* key_caps = (const char*)pact_list_get(lock_pkg_caps, i);
        int64_t j = (i - 1);
        while (((j >= 0) && (pact_str_compare((const char*)pact_list_get(lock_pkg_names, j), key_name) > 0))) {
            pact_list_set(lock_pkg_names, (j + 1), (void*)(const char*)pact_list_get(lock_pkg_names, j));
            pact_list_set(lock_pkg_versions, (j + 1), (void*)(const char*)pact_list_get(lock_pkg_versions, j));
            pact_list_set(lock_pkg_sources, (j + 1), (void*)(const char*)pact_list_get(lock_pkg_sources, j));
            pact_list_set(lock_pkg_hashes, (j + 1), (void*)(const char*)pact_list_get(lock_pkg_hashes, j));
            pact_list_set(lock_pkg_caps, (j + 1), (void*)(const char*)pact_list_get(lock_pkg_caps, j));
            j = (j - 1);
        }
        pact_list_set(lock_pkg_names, (j + 1), (void*)key_name);
        pact_list_set(lock_pkg_versions, (j + 1), (void*)key_ver);
        pact_list_set(lock_pkg_sources, (j + 1), (void*)key_src);
        pact_list_set(lock_pkg_hashes, (j + 1), (void*)key_hash);
        pact_list_set(lock_pkg_caps, (j + 1), (void*)key_caps);
        i = (i + 1);
    }
}

const char* pact_format_caps_toml(const char* caps) {
    if (pact_str_eq(caps, "")) {
        return "[]";
    }
    const char* result = "[";
    int64_t start = 0;
    int64_t i = 0;
    int64_t first = 1;
    while ((i < pact_str_len(caps))) {
        if ((pact_str_char_at(caps, i) == 44)) {
            if ((first == 0)) {
                result = pact_str_concat(result, ", ");
            }
            result = pact_str_concat(pact_str_concat(pact_str_concat(result, "\""), pact_str_substr(caps, start, (i - start))), "\"");
            first = 0;
            start = (i + 1);
        }
        i = (i + 1);
    }
    if ((start < pact_str_len(caps))) {
        if ((first == 0)) {
            result = pact_str_concat(result, ", ");
        }
        result = pact_str_concat(pact_str_concat(pact_str_concat(result, "\""), pact_str_substr(caps, start, (pact_str_len(caps) - start))), "\"");
    }
    return pact_str_concat(result, "]");
}

int64_t pact_lockfile_write(const char* path) {
    pact_sort_packages();
    const char* out = "[metadata]\n";
    out = pact_str_concat(out, "lockfile-version = 1\n");
    out = pact_str_concat(pact_str_concat(pact_str_concat(out, "pact-version = \""), lock_pact_version), "\"\n");
    out = pact_str_concat(pact_str_concat(pact_str_concat(out, "generated = \""), lock_generated), "\"\n");
    int64_t i = 0;
    while ((i < pact_list_len(lock_pkg_names))) {
        out = pact_str_concat(out, "\n[[package]]\n");
        out = pact_str_concat(pact_str_concat(pact_str_concat(out, "name = \""), (const char*)pact_list_get(lock_pkg_names, i)), "\"\n");
        out = pact_str_concat(pact_str_concat(pact_str_concat(out, "version = \""), (const char*)pact_list_get(lock_pkg_versions, i)), "\"\n");
        out = pact_str_concat(pact_str_concat(pact_str_concat(out, "source = \""), (const char*)pact_list_get(lock_pkg_sources, i)), "\"\n");
        out = pact_str_concat(pact_str_concat(pact_str_concat(out, "hash = \""), (const char*)pact_list_get(lock_pkg_hashes, i)), "\"\n");
        out = pact_str_concat(pact_str_concat(pact_str_concat(out, "capabilities = "), pact_format_caps_toml((const char*)pact_list_get(lock_pkg_caps, i))), "\n");
        i = (i + 1);
    }
    pact_write_file(path, out);
    return 0;
}

const char* pact_parse_caps_for_pkg(const char* prefix) {
    const char* caps_key = pact_str_concat(prefix, ".capabilities");
    if ((pact_toml_has(caps_key) == 0)) {
        return "";
    }
    const int64_t count = pact_toml_get_array_len(caps_key);
    if ((count == 0)) {
        return "";
    }
    const char* result = "";
    int64_t i = 0;
    while ((i < count)) {
        if ((i > 0)) {
            result = pact_str_concat(result, ",");
        }
        result = pact_str_concat(result, pact_toml_get_array_item(caps_key, i));
        i = (i + 1);
    }
    return result;
}

int64_t pact_lockfile_load(const char* path) {
    pact_lockfile_clear();
    if ((pact_file_exists(path) == 0)) {
        return 1;
    }
    const char* content = pact_read_file(path);
    pact_toml_clear();
    pact_toml_parse(content);
    if ((pact_toml_has("metadata.lockfile-version") == 0)) {
        return 1;
    }
    const int64_t ver = pact_toml_get_int("metadata.lockfile-version");
    if ((ver != 1)) {
        return 1;
    }
    lock_version = ver;
    if ((pact_toml_has("metadata.pact-version") == 1)) {
        lock_pact_version = pact_toml_get("metadata.pact-version");
    }
    if ((pact_toml_has("metadata.generated") == 1)) {
        lock_generated = pact_toml_get("metadata.generated");
    }
    const int64_t pkg_count = pact_toml_array_len("package");
    int64_t i = 0;
    while ((i < pkg_count)) {
        char _si_0[4096];
        snprintf(_si_0, 4096, "package[%lld]", (long long)i);
        const char* prefix = strdup(_si_0);
        const char* name_key = pact_str_concat(prefix, ".name");
        const char* ver_key = pact_str_concat(prefix, ".version");
        const char* src_key = pact_str_concat(prefix, ".source");
        const char* hash_key = pact_str_concat(prefix, ".hash");
        if ((pact_toml_has(name_key) == 0)) {
            return 1;
        }
        if ((pact_toml_has(ver_key) == 0)) {
            return 1;
        }
        if ((pact_toml_has(src_key) == 0)) {
            return 1;
        }
        if ((pact_toml_has(hash_key) == 0)) {
            return 1;
        }
        const char* pkg_name = pact_toml_get(name_key);
        const char* pkg_ver = pact_toml_get(ver_key);
        const char* pkg_src = pact_toml_get(src_key);
        const char* pkg_hash = pact_toml_get(hash_key);
        const char* pkg_caps = pact_parse_caps_for_pkg(prefix);
        pact_list_push(lock_pkg_names, (void*)pkg_name);
        pact_list_push(lock_pkg_versions, (void*)pkg_ver);
        pact_list_push(lock_pkg_sources, (void*)pkg_src);
        pact_list_push(lock_pkg_hashes, (void*)pkg_hash);
        pact_list_push(lock_pkg_caps, (void*)pkg_caps);
        i = (i + 1);
    }
    return 0;
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

void pact_ensure_lockfile_loaded(const char* src_root) {
    if ((lockfile_loaded == 1)) {
        return;
    }
    lockfile_loaded = 1;
    const char* project_root = src_root;
    if (pact_str_ends_with(src_root, "src/")) {
        project_root = pact_str_substr(src_root, 0, (pact_str_len(src_root) - 4));
    }
    const char* lock_path = pact_path_join(project_root, "pact.lock");
    if ((pact_file_exists(lock_path) == 1)) {
        pact_lockfile_load(lock_path);
    }
}

const char* pact_compiler_get_home(void) {
    pact_shell_exec("printf '%s' $HOME > /tmp/_pact_home");
    const char* raw = pact_read_file("/tmp/_pact_home");
    int64_t end = pact_str_len(raw);
    while ((end > 0)) {
        const int64_t ch = pact_str_char_at(raw, (end - 1));
        if ((((ch == 10) || (ch == 13)) || (ch == 32))) {
            end = (end - 1);
        } else {
            return pact_str_substr(raw, 0, end);
        }
    }
    return "";
}

const char* pact_resolve_from_lockfile(const char* dotted_path, const char* src_root) {
    if ((pact_lockfile_pkg_count() == 0)) {
        return "";
    }
    const char* pkg_name = "";
    const char* sub_path = "";
    const char* full_pkg = pact_dots_to_slashes(dotted_path);
    const int64_t idx_full = pact_lockfile_find_pkg(full_pkg);
    if ((idx_full >= 0)) {
        pkg_name = full_pkg;
        sub_path = "";
    }
    if (pact_str_eq(pkg_name, "")) {
        int64_t dot_pos = (-1);
        int64_t i = 0;
        while ((i < pact_str_len(dotted_path))) {
            if ((pact_str_char_at(dotted_path, i) == 46)) {
                dot_pos = i;
                i = pact_str_len(dotted_path);
            }
            i = (i + 1);
        }
        if ((dot_pos > 0)) {
            const char* first = pact_str_substr(dotted_path, 0, dot_pos);
            const char* rest = pact_str_substr(dotted_path, (dot_pos + 1), ((pact_str_len(dotted_path) - dot_pos) - 1));
            const int64_t idx_first = pact_lockfile_find_pkg(first);
            if ((idx_first >= 0)) {
                pkg_name = first;
                sub_path = rest;
            }
        } else {
            const int64_t idx_single = pact_lockfile_find_pkg(dotted_path);
            if ((idx_single >= 0)) {
                pkg_name = dotted_path;
                sub_path = "";
            }
        }
    }
    if (pact_str_eq(pkg_name, "")) {
        int64_t first_dot = (-1);
        int64_t second_dot = (-1);
        int64_t i = 0;
        while ((i < pact_str_len(dotted_path))) {
            if ((pact_str_char_at(dotted_path, i) == 46)) {
                if ((first_dot == (-1))) {
                    first_dot = i;
                } else if ((second_dot == (-1))) {
                    second_dot = i;
                }
            }
            i = (i + 1);
        }
        if ((second_dot > 0)) {
            const char* two_seg = pact_str_substr(dotted_path, 0, second_dot);
            const char* two_pkg = pact_dots_to_slashes(two_seg);
            const char* rest = pact_str_substr(dotted_path, (second_dot + 1), ((pact_str_len(dotted_path) - second_dot) - 1));
            const int64_t idx_two = pact_lockfile_find_pkg(two_pkg);
            if ((idx_two >= 0)) {
                pkg_name = two_pkg;
                sub_path = rest;
            }
        }
    }
    if (pact_str_eq(pkg_name, "")) {
        return "";
    }
    const int64_t pkg_idx = pact_lockfile_find_pkg(pkg_name);
    const char* source = (const char*)pact_list_get(lock_pkg_sources, pkg_idx);
    const char* base_dir = "";
    if (pact_str_starts_with(source, "path:")) {
        base_dir = pact_str_substr(source, 5, (pact_str_len(source) - 5));
    } else if (pact_str_starts_with(source, "git:")) {
        const char* home = pact_compiler_get_home();
        const char* url_part = pact_str_substr(source, 4, (pact_str_len(source) - 4));
        int64_t hash_pos = (-1);
        int64_t i = 0;
        while ((i < pact_str_len(url_part))) {
            if ((pact_str_char_at(url_part, i) == 35)) {
                hash_pos = i;
            }
            i = (i + 1);
        }
        if ((hash_pos > 0)) {
            url_part = pact_str_substr(url_part, 0, hash_pos);
        }
        const char* cache_name = "";
        i = 0;
        while ((i < pact_str_len(url_part))) {
            const int64_t ch = pact_str_char_at(url_part, i);
            if (((((ch >= 97) && (ch <= 122)) || ((ch >= 65) && (ch <= 90))) || ((ch >= 48) && (ch <= 57)))) {
                cache_name = pact_str_concat(cache_name, pact_str_substr(url_part, i, 1));
            } else {
                cache_name = pact_str_concat(cache_name, "_");
            }
            i = (i + 1);
        }
        base_dir = pact_path_join(home, pact_path_join(".pact/cache/git", pact_path_join(cache_name, "checkout")));
    }
    if (pact_str_eq(base_dir, "")) {
        return "";
    }
    if (pact_str_eq(sub_path, "")) {
        const char* lib_path = pact_path_join(base_dir, "src/lib.pact");
        if ((pact_file_exists(lib_path) == 1)) {
            return lib_path;
        }
        return "";
    }
    const char* sub_rel = pact_dots_to_slashes(sub_path);
    const char* resolved = pact_path_join(base_dir, pact_path_join("src", pact_str_concat(sub_rel, ".pact")));
    if ((pact_file_exists(resolved) == 1)) {
        return resolved;
    }
    return "";
}

const char* pact_resolve_module_path(const char* dotted_path, const char* src_root) {
    const char* rel = pact_dots_to_slashes(dotted_path);
    const char* full = pact_path_join(src_root, pact_str_concat(rel, ".pact"));
    const int local_exists = (pact_file_exists(full) == 1);
    pact_ensure_lockfile_loaded(src_root);
    const char* dep_path = pact_resolve_from_lockfile(dotted_path, src_root);
    if (local_exists) {
        if ((!pact_str_eq(dep_path, ""))) {
            printf("%s\n", "warning[W1000]: local module shadows dependency");
            char _si_0[4096];
            snprintf(_si_0, 4096, " --> %s", full);
            printf("%s\n", strdup(_si_0));
            char _si_1[4096];
            snprintf(_si_1, 4096, "  = note: import '%s' matches both local file and a dependency", dotted_path);
            printf("%s\n", strdup(_si_1));
            printf("%s\n", "  = help: this is allowed but may confuse consumers expecting the library");
        }
        return full;
    }
    if ((!pact_str_eq(dep_path, ""))) {
        return dep_path;
    }
    if (pact_str_starts_with(dotted_path, "std.")) {
        const char* compiler_dir = pact_path_dirname(pact_get_arg(0));
        const char* std_rel = pact_dots_to_slashes(pact_str_substr(dotted_path, 4, (pact_str_len(dotted_path) - 4)));
        const char* std_full = pact_path_join(compiler_dir, pact_path_join("lib/std", pact_str_concat(std_rel, ".pact")));
        if ((pact_file_exists(std_full) == 1)) {
            return std_full;
        }
    }
    char _si_2[4096];
    snprintf(_si_2, 4096, "module not found: %s (looked at: %s)", dotted_path, full);
    pact_diag_error_no_loc("ModuleNotFound", "E1200", strdup(_si_2), "");
    return "";
}

int64_t pact_should_import_item(int64_t item, int64_t import_node) {
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
    pact_list* _l5 = pact_list_new();
    pact_list* all_effects = _l5;
    int64_t pi = 0;
    while ((pi < pact_list_len(imported))) {
        const int64_t prog = (int64_t)(intptr_t)pact_list_get(imported, pi);
        const int64_t fns_sl = (int64_t)(intptr_t)pact_list_get(np_params, prog);
        int64_t fi = 0;
        while ((fi < pact_sublist_length(fns_sl))) {
            pact_list_push(all_fns, (void*)(intptr_t)pact_sublist_get(fns_sl, fi));
            fi = (fi + 1);
        }
        const int64_t types_sl = (int64_t)(intptr_t)pact_list_get(np_fields, prog);
        int64_t ti = 0;
        while ((ti < pact_sublist_length(types_sl))) {
            pact_list_push(all_types, (void*)(intptr_t)pact_sublist_get(types_sl, ti));
            ti = (ti + 1);
        }
        const int64_t lets_sl = (int64_t)(intptr_t)pact_list_get(np_stmts, prog);
        int64_t li = 0;
        while ((li < pact_sublist_length(lets_sl))) {
            pact_list_push(all_lets, (void*)(intptr_t)pact_sublist_get(lets_sl, li));
            li = (li + 1);
        }
        const int64_t traits_sl = (int64_t)(intptr_t)pact_list_get(np_arms, prog);
        int64_t tri = 0;
        while ((tri < pact_sublist_length(traits_sl))) {
            pact_list_push(all_traits, (void*)(intptr_t)pact_sublist_get(traits_sl, tri));
            tri = (tri + 1);
        }
        const int64_t impls_sl = (int64_t)(intptr_t)pact_list_get(np_methods, prog);
        int64_t ii = 0;
        while ((ii < pact_sublist_length(impls_sl))) {
            pact_list_push(all_impls, (void*)(intptr_t)pact_sublist_get(impls_sl, ii));
            ii = (ii + 1);
        }
        const int64_t effects_sl = (int64_t)(intptr_t)pact_list_get(np_args, prog);
        if ((effects_sl != (-1))) {
            int64_t edi = 0;
            while ((edi < pact_sublist_length(effects_sl))) {
                pact_list_push(all_effects, (void*)(intptr_t)pact_sublist_get(effects_sl, edi));
                edi = (edi + 1);
            }
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
    const int64_t main_effects = (int64_t)(intptr_t)pact_list_get(np_args, main_prog);
    if ((main_effects != (-1))) {
        int64_t edi = 0;
        while ((edi < pact_sublist_length(main_effects))) {
            pact_list_push(all_effects, (void*)(intptr_t)pact_sublist_get(main_effects, edi));
            edi = (edi + 1);
        }
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
    int64_t merged_effects = (-1);
    if ((pact_list_len(all_effects) > 0)) {
        merged_effects = pact_new_sublist();
        int64_t edi = 0;
        while ((edi < pact_list_len(all_effects))) {
            pact_sublist_push(merged_effects, (int64_t)(intptr_t)pact_list_get(all_effects, edi));
            edi = (edi + 1);
        }
        pact_finalize_sublist(merged_effects);
    }
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
    pact_list_pop(np_args);
    pact_list_push(np_args, (void*)(intptr_t)merged_effects);
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
        printf("%s\n", "Usage: pactc <source.pact> [output.c] [--format json] [--json] [--emit pact] [--stats] [--debug]");
        printf("%s\n", "  Compiles a Pact source file to C.");
        return;
    }
    const char* source_path = pact_get_arg(1);
    const char* out_path = "";
    const char* emit_mode = "";
    int64_t stats_mode = 0;
    int64_t check_only = 0;
    int64_t i = 2;
    while ((i < pact_arg_count())) {
        const char* arg = pact_get_arg(i);
        if (pact_str_eq(arg, "--format")) {
            if (((i + 1) < pact_arg_count())) {
                i = (i + 1);
                const char* fmt = pact_get_arg(i);
                if (pact_str_eq(fmt, "json")) {
                    diag_format = 1;
                }
            }
        } else if (pact_str_eq(arg, "--json")) {
            diag_format = 1;
        } else {
            if (pact_str_eq(arg, "--emit")) {
                if (((i + 1) < pact_arg_count())) {
                    i = (i + 1);
                    emit_mode = pact_get_arg(i);
                }
            } else if (pact_str_eq(arg, "--debug")) {
                cg_debug_mode = 1;
            } else {
                if (pact_str_eq(arg, "--stats")) {
                    stats_mode = 1;
                } else if (pact_str_eq(arg, "--check-only")) {
                    check_only = 1;
                } else {
                    out_path = arg;
                }
            }
        }
        i = (i + 1);
    }
    diag_source_file = source_path;
    const char* source = pact_read_file(source_path);
    const int64_t t_lex_start = pact_time_ms();
    pact_lex(source);
    const int64_t t_lex_end = pact_time_ms();
    pos = 0;
    const int64_t t_parse_start = pact_time_ms();
    const int64_t program_node = pact_parse_program();
    const int64_t t_parse_end = pact_time_ms();
    pact_list_push(loaded_files, (void*)source_path);
    const char* src_root = pact_find_src_root(source_path);
    const int64_t t_import_start = pact_time_ms();
    pact_list* _l0 = pact_list_new();
    pact_list* imported_programs = _l0;
    pact_collect_imports(program_node, src_root, imported_programs);
    int64_t final_program = program_node;
    if ((pact_list_len(imported_programs) > 0)) {
        final_program = pact_merge_programs(program_node, imported_programs, import_map_nodes);
    }
    const int64_t t_import_end = pact_time_ms();
    if (pact_str_eq(emit_mode, "pact")) {
        const char* pact_output = pact_format(final_program);
        if ((!pact_str_eq(out_path, ""))) {
            pact_write_file(out_path, pact_output);
        } else {
            printf("%s\n", pact_output);
        }
        return;
    }
    const int64_t t_tc_start = pact_time_ms();
    const int64_t tc_err_count = pact_check_types(final_program);
    const int64_t t_tc_end = pact_time_ms();
    if ((diag_count > 0)) {
        pact_diag_flush();
        return;
    }
    if ((check_only != 0)) {
        pact_diag_flush();
        return;
    }
    const int64_t t_mut_start = pact_time_ms();
    pact_analyze_mutations(final_program);
    pact_analyze_save_restore(final_program);
    const int64_t t_mut_end = pact_time_ms();
    const int64_t t_cg_start = pact_time_ms();
    const char* c_output = pact_generate(final_program);
    const int64_t t_cg_end = pact_time_ms();
    if ((diag_count > 0)) {
        pact_diag_flush();
        return;
    }
    if ((!pact_str_eq(out_path, ""))) {
        pact_write_file(out_path, c_output);
    } else {
        printf("%s\n", c_output);
    }
    if ((stats_mode == 1)) {
        const int64_t lex_ms = (t_lex_end - t_lex_start);
        const int64_t parse_ms = (t_parse_end - t_parse_start);
        const int64_t import_ms = (t_import_end - t_import_start);
        const int64_t typecheck_ms = (t_tc_end - t_tc_start);
        const int64_t mutation_ms = (t_mut_end - t_mut_start);
        const int64_t codegen_ms = (t_cg_end - t_cg_start);
        const int64_t total_ms = (t_cg_end - t_lex_start);
        const char* q = "\"";
        char _si_1[4096];
        snprintf(_si_1, 4096, "{%slex_ms%s:%lld,%sparse_ms%s:%lld,%simport_ms%s:%lld,%stypecheck_ms%s:%lld,%smutation_ms%s:%lld,%scodegen_ms%s:%lld,%stotal_ms%s:%lld}", q, q, (long long)lex_ms, q, q, (long long)parse_ms, q, q, (long long)import_ms, q, q, (long long)typecheck_ms, q, q, (long long)mutation_ms, q, q, (long long)codegen_ms, q, q, (long long)total_ms);
        fprintf(stderr, "%s\n", strdup(_si_1));
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
    diag_severity = _l4;
pact_list* _l5 = pact_list_new();
    diag_name = _l5;
pact_list* _l6 = pact_list_new();
    diag_code = _l6;
pact_list* _l7 = pact_list_new();
    diag_message = _l7;
pact_list* _l8 = pact_list_new();
    diag_file = _l8;
pact_list* _l9 = pact_list_new();
    diag_line = _l9;
pact_list* _l10 = pact_list_new();
    diag_col = _l10;
pact_list* _l11 = pact_list_new();
    diag_help = _l11;
pact_list* _l12 = pact_list_new();
    diag_end_line = _l12;
pact_list* _l13 = pact_list_new();
    diag_end_col = _l13;
pact_list* _l14 = pact_list_new();
    np_kind = _l14;
pact_list* _l15 = pact_list_new();
    np_int_val = _l15;
pact_list* _l16 = pact_list_new();
    np_str_val = _l16;
pact_list* _l17 = pact_list_new();
    np_name = _l17;
pact_list* _l18 = pact_list_new();
    np_op = _l18;
pact_list* _l19 = pact_list_new();
    np_left = _l19;
pact_list* _l20 = pact_list_new();
    np_right = _l20;
pact_list* _l21 = pact_list_new();
    np_body = _l21;
pact_list* _l22 = pact_list_new();
    np_condition = _l22;
pact_list* _l23 = pact_list_new();
    np_then_body = _l23;
pact_list* _l24 = pact_list_new();
    np_else_body = _l24;
pact_list* _l25 = pact_list_new();
    np_scrutinee = _l25;
pact_list* _l26 = pact_list_new();
    np_pattern = _l26;
pact_list* _l27 = pact_list_new();
    np_guard = _l27;
pact_list* _l28 = pact_list_new();
    np_value = _l28;
pact_list* _l29 = pact_list_new();
    np_target = _l29;
pact_list* _l30 = pact_list_new();
    np_iterable = _l30;
pact_list* _l31 = pact_list_new();
    np_var_name = _l31;
pact_list* _l32 = pact_list_new();
    np_is_mut = _l32;
pact_list* _l33 = pact_list_new();
    np_is_pub = _l33;
pact_list* _l34 = pact_list_new();
    np_inclusive = _l34;
pact_list* _l35 = pact_list_new();
    np_start = _l35;
pact_list* _l36 = pact_list_new();
    np_end = _l36;
pact_list* _l37 = pact_list_new();
    np_obj = _l37;
pact_list* _l38 = pact_list_new();
    np_method = _l38;
pact_list* _l39 = pact_list_new();
    np_index = _l39;
pact_list* _l40 = pact_list_new();
    np_return_type = _l40;
pact_list* _l41 = pact_list_new();
    np_type_name = _l41;
pact_list* _l42 = pact_list_new();
    np_trait_name = _l42;
pact_list* _l43 = pact_list_new();
    sl_items = _l43;
pact_list* _l44 = pact_list_new();
    sl_start = _l44;
pact_list* _l45 = pact_list_new();
    sl_len = _l45;
pact_list* _l46 = pact_list_new();
    np_params = _l46;
pact_list* _l47 = pact_list_new();
    np_args = _l47;
pact_list* _l48 = pact_list_new();
    np_stmts = _l48;
pact_list* _l49 = pact_list_new();
    np_arms = _l49;
pact_list* _l50 = pact_list_new();
    np_fields = _l50;
pact_list* _l51 = pact_list_new();
    np_elements = _l51;
pact_list* _l52 = pact_list_new();
    np_methods = _l52;
pact_list* _l53 = pact_list_new();
    np_type_params = _l53;
pact_list* _l54 = pact_list_new();
    np_effects = _l54;
pact_list* _l55 = pact_list_new();
    np_captures = _l55;
pact_list* _l56 = pact_list_new();
    np_type_ann = _l56;
pact_list* _l57 = pact_list_new();
    np_handlers = _l57;
pact_list* _l58 = pact_list_new();
    np_leading_comments = _l58;
pact_list* _l59 = pact_list_new();
    np_doc_comment = _l59;
pact_list* _l60 = pact_list_new();
    np_line = _l60;
pact_list* _l61 = pact_list_new();
    np_col = _l61;
pact_list* _l62 = pact_list_new();
    np_end_line = _l62;
pact_list* _l63 = pact_list_new();
    np_end_col = _l63;
pact_list* _l64 = pact_list_new();
    pending_comments = _l64;
pact_list* _l65 = pact_list_new();
    annotation_nodes = _l65;
pact_list* _l66 = pact_list_new();
    ty_kind = _l66;
pact_list* _l67 = pact_list_new();
    ty_name = _l67;
pact_list* _l68 = pact_list_new();
    ty_inner1 = _l68;
pact_list* _l69 = pact_list_new();
    ty_inner2 = _l69;
pact_list* _l70 = pact_list_new();
    ty_params_start = _l70;
pact_list* _l71 = pact_list_new();
    ty_params_count = _l71;
pact_list* _l72 = pact_list_new();
    ty_param_list = _l72;
pact_list* _l73 = pact_list_new();
    named_type_names = _l73;
pact_list* _l74 = pact_list_new();
    named_type_ids = _l74;
pact_list* _l75 = pact_list_new();
    sfield_struct_id = _l75;
pact_list* _l76 = pact_list_new();
    sfield_name = _l76;
pact_list* _l77 = pact_list_new();
    sfield_type_id = _l77;
pact_list* _l78 = pact_list_new();
    evar_enum_id = _l78;
pact_list* _l79 = pact_list_new();
    evar_name = _l79;
pact_list* _l80 = pact_list_new();
    evar_tag = _l80;
pact_list* _l81 = pact_list_new();
    evar_has_data = _l81;
pact_list* _l82 = pact_list_new();
    evfield_var_idx = _l82;
pact_list* _l83 = pact_list_new();
    evfield_name = _l83;
pact_list* _l84 = pact_list_new();
    evfield_type_id = _l84;
    named_type_map = pact_map_new();
    fnsig_map = pact_map_new();
pact_list* _l85 = pact_list_new();
    fnsig_name = _l85;
pact_list* _l86 = pact_list_new();
    fnsig_ret = _l86;
pact_list* _l87 = pact_list_new();
    fnsig_params_start = _l87;
pact_list* _l88 = pact_list_new();
    fnsig_params_count = _l88;
pact_list* _l89 = pact_list_new();
    fnsig_param_list = _l89;
pact_list* _l90 = pact_list_new();
    fnsig_type_params_start = _l90;
pact_list* _l91 = pact_list_new();
    fnsig_type_params_count = _l91;
pact_list* _l92 = pact_list_new();
    fnsig_type_param_names = _l92;
pact_list* _l93 = pact_list_new();
    tc_trait_names = _l93;
pact_list* _l94 = pact_list_new();
    tc_trait_method_names = _l94;
pact_list* _l95 = pact_list_new();
    tc_fn_effects = _l95;
pact_list* _l96 = pact_list_new();
    tc_errors = _l96;
pact_list* _l97 = pact_list_new();
    tc_warnings = _l97;
    tc_inc_filter = pact_map_new();
pact_list* _l98 = pact_list_new();
    nr_scope_names = _l98;
pact_list* _l99 = pact_list_new();
    nr_scope_muts = _l99;
pact_list* _l100 = pact_list_new();
    nr_scope_types = _l100;
pact_list* _l101 = pact_list_new();
    nr_scope_frames = _l101;
pact_list* _l102 = pact_list_new();
    nr_impl_type_names = _l102;
pact_list* _l103 = pact_list_new();
    nr_impl_method_names = _l103;
pact_list* _l104 = pact_list_new();
    cg_lines = _l104;
pact_list* _l105 = pact_list_new();
    cg_global_inits = _l105;
pact_list* _l106 = pact_list_new();
    struct_reg_names = _l106;
pact_list* _l107 = pact_list_new();
    enum_regs = _l107;
pact_list* _l108 = pact_list_new();
    enum_variants = _l108;
pact_list* _l109 = pact_list_new();
    var_enums = _l109;
pact_list* _l110 = pact_list_new();
    fn_enum_rets = _l110;
pact_list* _l111 = pact_list_new();
    emitted_let_names = _l111;
pact_list* _l112 = pact_list_new();
    emitted_fn_names = _l112;
    struct_reg_set = pact_map_new();
    enum_reg_set = pact_map_new();
    emitted_fn_set = pact_map_new();
    emitted_let_set = pact_map_new();
    emitted_option_set = pact_map_new();
    emitted_result_set = pact_map_new();
    emitted_iter_set = pact_map_new();
pact_list* _l113 = pact_list_new();
    cg_closure_defs = _l113;
pact_list* _l114 = pact_list_new();
    closure_captures = _l114;
pact_list* _l115 = pact_list_new();
    closure_cap_infos = _l115;
pact_list* _l116 = pact_list_new();
    mut_captured_vars = _l116;
pact_list* _l117 = pact_list_new();
    trait_entries = _l117;
pact_list* _l118 = pact_list_new();
    impl_entries = _l118;
pact_list* _l119 = pact_list_new();
    from_entries = _l119;
pact_list* _l120 = pact_list_new();
    tryfrom_entries = _l120;
pact_list* _l121 = pact_list_new();
    var_structs = _l121;
pact_list* _l122 = pact_list_new();
    var_struct_frame_starts = _l122;
pact_list* _l123 = pact_list_new();
    sf_entries = _l123;
pact_list* _l124 = pact_list_new();
    var_closures = _l124;
pact_list* _l125 = pact_list_new();
    var_closure_frame_starts = _l125;
pact_list* _l126 = pact_list_new();
    generic_fns = _l126;
pact_list* _l127 = pact_list_new();
    mono_fns = _l127;
pact_list* _l128 = pact_list_new();
    mono_instances = _l128;
pact_list* _l129 = pact_list_new();
    var_options = _l129;
pact_list* _l130 = pact_list_new();
    var_option_frame_starts = _l130;
pact_list* _l131 = pact_list_new();
    var_results = _l131;
pact_list* _l132 = pact_list_new();
    var_result_frame_starts = _l132;
pact_list* _l133 = pact_list_new();
    emitted_option_types = _l133;
pact_list* _l134 = pact_list_new();
    emitted_result_types = _l134;
pact_list* _l135 = pact_list_new();
    emitted_iter_types = _l135;
pact_list* _l136 = pact_list_new();
    var_iterators = _l136;
pact_list* _l137 = pact_list_new();
    var_iterator_frame_starts = _l137;
pact_list* _l138 = pact_list_new();
    var_aliases = _l138;
pact_list* _l139 = pact_list_new();
    var_alias_frame_starts = _l139;
pact_list* _l140 = pact_list_new();
    emitted_map_iters = _l140;
pact_list* _l141 = pact_list_new();
    emitted_filter_iters = _l141;
pact_list* _l142 = pact_list_new();
    emitted_take_iters = _l142;
pact_list* _l143 = pact_list_new();
    emitted_skip_iters = _l143;
pact_list* _l144 = pact_list_new();
    emitted_chain_iters = _l144;
pact_list* _l145 = pact_list_new();
    emitted_flat_map_iters = _l145;
pact_list* _l146 = pact_list_new();
    var_handles = _l146;
pact_list* _l147 = pact_list_new();
    var_handle_frame_starts = _l147;
pact_list* _l148 = pact_list_new();
    var_channels = _l148;
pact_list* _l149 = pact_list_new();
    var_channel_frame_starts = _l149;
pact_list* _l150 = pact_list_new();
    scope_vars = _l150;
pact_list* _l151 = pact_list_new();
    scope_frame_starts = _l151;
pact_list* _l152 = pact_list_new();
    fn_regs = _l152;
pact_list* _l153 = pact_list_new();
    fn_ret_structs = _l153;
pact_list* _l154 = pact_list_new();
    fn_ret_types = _l154;
pact_list* _l155 = pact_list_new();
    effect_entries = _l155;
pact_list* _l156 = pact_list_new();
    ue_effects = _l156;
pact_list* _l157 = pact_list_new();
    ue_methods = _l157;
pact_list* _l158 = pact_list_new();
    cap_budget_names = _l158;
pact_list* _l159 = pact_list_new();
    var_list_elems = _l159;
pact_list* _l160 = pact_list_new();
    var_list_elem_frame_starts = _l160;
pact_list* _l161 = pact_list_new();
    var_maps = _l161;
pact_list* _l162 = pact_list_new();
    var_map_frame_starts = _l162;
pact_list* _l163 = pact_list_new();
    cg_async_scope_stack = _l163;
pact_list* _l164 = pact_list_new();
    match_scruts = _l164;
pact_list* _l165 = pact_list_new();
    prescan_mut_names = _l165;
pact_list* _l166 = pact_list_new();
    prescan_closure_idents = _l166;
pact_list* _l167 = pact_list_new();
    fmt_lines = _l167;
pact_list* _l168 = pact_list_new();
    binop_parts = _l168;
pact_list* _l169 = pact_list_new();
    binop_ops = _l169;
pact_list* _l170 = pact_list_new();
    ma_fn_names = _l170;
pact_list* _l171 = pact_list_new();
    ma_write_items = _l171;
pact_list* _l172 = pact_list_new();
    ma_write_starts = _l172;
pact_list* _l173 = pact_list_new();
    ma_write_counts = _l173;
pact_list* _l174 = pact_list_new();
    ma_globals = _l174;
pact_list* _l175 = pact_list_new();
    ma_call_edges_from = _l175;
pact_list* _l176 = pact_list_new();
    ma_call_edges_to = _l176;
    fn_name_map = pact_map_new();
    global_set = pact_map_new();
    global_idx_map = pact_map_new();
    mutating_method_set = pact_map_new();
pact_list* _l177 = pact_list_new();
    writes_mat = _l177;
pact_list* _l178 = pact_list_new();
    sr_save_local = _l178;
pact_list* _l179 = pact_list_new();
    sr_save_global = _l179;
    sr_restore_globals = pact_map_new();
pact_list* _l180 = pact_list_new();
    si_sym_name = _l180;
pact_list* _l181 = pact_list_new();
    si_sym_kind = _l181;
pact_list* _l182 = pact_list_new();
    si_sym_module = _l182;
pact_list* _l183 = pact_list_new();
    si_sym_file = _l183;
pact_list* _l184 = pact_list_new();
    si_sym_line = _l184;
pact_list* _l185 = pact_list_new();
    si_sym_vis = _l185;
pact_list* _l186 = pact_list_new();
    si_sym_effects = _l186;
pact_list* _l187 = pact_list_new();
    si_sym_sig = _l187;
pact_list* _l188 = pact_list_new();
    si_sym_ret_type = _l188;
pact_list* _l189 = pact_list_new();
    si_sym_param_types = _l189;
pact_list* _l190 = pact_list_new();
    si_sym_doc = _l190;
pact_list* _l191 = pact_list_new();
    si_sym_intent = _l191;
pact_list* _l192 = pact_list_new();
    si_sym_requires = _l192;
pact_list* _l193 = pact_list_new();
    si_sym_ensures = _l193;
pact_list* _l194 = pact_list_new();
    si_sym_end_line = _l194;
pact_list* _l195 = pact_list_new();
    si_dep_from = _l195;
pact_list* _l196 = pact_list_new();
    si_dep_to = _l196;
pact_list* _l197 = pact_list_new();
    si_dep_kind = _l197;
pact_list* _l198 = pact_list_new();
    si_rdep_from = _l198;
pact_list* _l199 = pact_list_new();
    si_rdep_to = _l199;
pact_list* _l200 = pact_list_new();
    si_file_path = _l200;
pact_list* _l201 = pact_list_new();
    si_file_mtime = _l201;
pact_list* _l202 = pact_list_new();
    si_file_sym_start = _l202;
pact_list* _l203 = pact_list_new();
    si_file_sym_end = _l203;
    sym_name_map = pact_map_new();
    file_path_map = pact_map_new();
pact_list* _l204 = pact_list_new();
    fw_path = _l204;
pact_list* _l205 = pact_list_new();
    fw_mtime = _l205;
pact_list* _l206 = pact_list_new();
    fw_dirty_path = _l206;
    path_map = pact_map_new();
pact_list* _l207 = pact_list_new();
    qr_keys = _l207;
pact_list* _l208 = pact_list_new();
    qr_vals = _l208;
pact_list* _l209 = pact_list_new();
    inc_snap_path = _l209;
pact_list* _l210 = pact_list_new();
    inc_snap_mtime = _l210;
pact_list* _l211 = pact_list_new();
    inc_dirty_path = _l211;
pact_list* _l212 = pact_list_new();
    inc_affected = _l212;
    affected_map = pact_map_new();
    snap_path_map = pact_map_new();
pact_list* _l213 = pact_list_new();
    dr_keys = _l213;
pact_list* _l214 = pact_list_new();
    dr_vals = _l214;
pact_list* _l215 = pact_list_new();
    toml_keys = _l215;
pact_list* _l216 = pact_list_new();
    toml_values = _l216;
pact_list* _l217 = pact_list_new();
    toml_types = _l217;
pact_list* _l218 = pact_list_new();
    arr_table_names = _l218;
pact_list* _l219 = pact_list_new();
    arr_table_counts = _l219;
pact_list* _l220 = pact_list_new();
    lock_pkg_names = _l220;
pact_list* _l221 = pact_list_new();
    lock_pkg_versions = _l221;
pact_list* _l222 = pact_list_new();
    lock_pkg_sources = _l222;
pact_list* _l223 = pact_list_new();
    lock_pkg_hashes = _l223;
pact_list* _l224 = pact_list_new();
    lock_pkg_caps = _l224;
pact_list* _l225 = pact_list_new();
    loaded_files = _l225;
pact_list* _l226 = pact_list_new();
    import_map_paths = _l226;
pact_list* _l227 = pact_list_new();
    import_map_nodes = _l227;
}

int main(int argc, char** argv) {
    pact_g_argc = argc;
    pact_g_argv = (const char**)argv;
    __pact_ctx = pact_ctx_default();
    __pact_init_globals();
    pact_main();
    return 0;
}