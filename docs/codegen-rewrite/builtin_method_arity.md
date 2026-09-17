# Builtin method arity

A builtin method has no `fnsig`. Its arity is implicit in which `if method ==`
arm runs inside `infer_type_uncached`, so nothing counts the arguments a caller
wrote: `xs.len(1, 2, 3)` type-checks and runs, and `sb.write()` reaches codegen
with an argument that is not there.

This table is the survey of what each arm actually reads. It is the input to the
arity check, and it is a fact about the code as it stands, not a proposal.

## How to read it

`args` is the number of arguments the arm reads, counted from the highest
argument index it asks about. `reads` says how the arm asks:

| `reads` | meaning |
|---|---|
| `typed` | `check_builtin_arg(method, i, ...)` — validates the type of argument `i` when it is present |
| `arity` | the arm already calls `check_builtin_arity`, so a wrong count is reported today |
| `closure` | `closure_arg_at(args_sl, i)` — a HOF argument, position read, type not checked here |
| `raw` | `sublist_get` / `infer_type` on a position, guarded by an explicit length test |
| `none` | the arm reads no argument at all |

An arm with `reads = none` and `args = 0` is a method that takes nothing. Those
are the rows the MVCEs on the ticket land in, and they are the rows a counter
built out of `check_builtin_arg` can never see: the arm asks about no index, so
there is no index to count.

## Optional arguments

**None. Every builtin method takes a fixed number of arguments.** Blink has no
default parameter values and no variadic parameters, so a method cannot have an
optional index, and no survey of these arms will find one. Every row below is an
exact count: one method, one arity, always. Do not go looking for optionals.

Three arms *tolerate* a missing argument rather than allow it, which is a
different thing: `StringBuilder.write`, `StringBuilder.write_char`, `Ptr.write`
and `Bytes.with_ptr` guard with `sublist_length` and return a type instead of
reporting. The argument is still required — codegen reads it — so the guard is
a declined report, not an optional parameter, and enforcing the count makes
those calls errors rather than silent nonsense.

## One arm is not one arity

Three arms cover methods whose counts differ, so the unit of the table is the
method name and never the arm:

| arm | methods | args |
|---|---|---|
| `Int`: `abs \|\| min \|\| max` | `abs` | 0 |
| | `min`, `max` | 1 |
| sized int: `wrapping_add \|\| ... \|\| wrapping_neg` | `wrapping_add`, `wrapping_sub`, `wrapping_mul`, `wrapping_div`, `wrapping_rem` | 1 |
| | `wrapping_neg` | 0 |
| scalar: `display` / `fmt` | `display` | 0 |
| | `fmt` | 1 |

`sections/03_types.md:860-862` pins the first of those: `abs` is `fn(self) -> Self`,
`min` and `max` are `fn(self, Self) -> Self`.

## The table

### Any receiver

| method | args | reads | note |
|---|---|---|---|
| `display` | 0 | none | Int/Float/Bool/Str/Char |
| `fmt` | 1 | none | takes the StringBuilder; the argument is not read here |
| `into_iter` | 0 | none | List/Set/Iterator |

### Iterator

| method | args | reads |
|---|---|---|
| `map`, `flat_map`, `filter`, `for_each`, `any`, `all`, `find` | 1 | closure |
| `take`, `skip`, `chain` | 1 | typed |
| `zip` | 1 | arity |
| `fold` | 2 | arity |
| `enumerate`, `collect`, `count` | 0 | none |

### List

| method | args | reads |
|---|---|---|
| `get`, `push`, `take`, `skip`, `chain`, `append`, `join`, `contains` | 1 | typed |
| `map`, `flat_map`, `filter`, `for_each`, `any`, `all`, `find` | 1 | closure |
| `zip` | 1 | arity |
| `set`, `slice` | 2 | typed |
| `fold` | 2 | arity |
| `len`, `count`, `pop`, `clear`, `enumerate`, `is_empty` | 0 | none |

### Str

| method | args | reads |
|---|---|---|
| `contains`, `starts_with`, `ends_with`, `concat`, `byte_at`, `index_of`, `char_at`, `split` | 1 | typed |
| `replace`, `substring`, `substr`, `slice` | 2 | typed |
| `len`, `as_cstr`, `trim`, `trim_left`, `trim_right`, `to_lower`, `to_upper`, `to_int`, `lines`, `parse_float`, `parse_int`, `is_empty` | 0 | none |

### Int, Float, Char, sized ints

| method | args | reads |
|---|---|---|
| `Int.min`, `Int.max` | 1 | none |
| sized `wrapping_add`, `wrapping_sub`, `wrapping_mul`, `wrapping_div`, `wrapping_rem` | 1 | none |
| `Int.to_str`, `Int.to_string`, `Int.to_float`, `Int.abs`, `Int.to_i8` … `Int.to_u64` | 0 | none |
| `Float.to_string`, `Float.to_int` | 0 | none |
| `Char.to_int`, `Char.to_str` | 0 | none |
| sized `to_int`, `to_i8` … `to_u64`, `wrapping_neg` | 0 | none |

The 1-argument rows here read nothing at all: the arm returns a type without
looking at the argument, so today `x.min()` and `x.wrapping_add()` are both
accepted and reach codegen short.

### Option, Result

| method | args | reads |
|---|---|---|
| `Option.unwrap`, `Option.is_some`, `Option.is_none` | 0 | none |
| `Result.unwrap`, `Result.unwrap_err`, `Result.is_ok`, `Result.is_err` | 0 | none |

### Map, Set, Channel

| method | args | reads |
|---|---|---|
| `Map.get`, `Map.contains_key`, `Map.contains`, `Map.remove` | 1 | typed |
| `Map.insert` | 2 | typed |
| `Map.len`, `Map.clear`, `Map.is_empty`, `Map.keys`, `Map.values` | 0 | none |
| `Set.contains`, `Set.insert`, `Set.remove`, `Set.union` | 1 | typed |
| `Set.len`, `Set.is_empty` | 0 | none |
| `Channel.send` | 1 | typed |
| `Channel.recv`, `Channel.close` | 0 | none |

### Bytes

| method | args | reads |
|---|---|---|
| `get`, `push`, `concat`, `read_u16_be`, `read_u32_be`, `read_i32_be`, `read_i64_be`, `read_u16_le`, `read_u32_le`, `read_i32_le`, `read_i64_le`, `write_u16_be`, `write_u32_be`, `write_i32_be`, `write_i64_be`, `write_u16_le`, `write_u32_le`, `write_i32_le`, `write_i64_le` | 1 | typed |
| `with_ptr` | 1 | raw |
| `set`, `slice` | 2 | typed |
| `set_u16_be`, `set_u32_be`, `set_u64_be`, `set_i16_be`, `set_i32_be`, `set_i64_be`, `set_u16_le`, `set_u32_le`, `set_u64_le`, `set_i16_le`, `set_i32_le`, `set_i64_le` | 2 | arity |
| `len`, `is_empty`, `to_str`, `to_hex` | 0 | none |

### StringBuilder, Ptr, Template, ffi scope

| method | args | reads |
|---|---|---|
| `StringBuilder.write`, `StringBuilder.write_char` | 1 | raw |
| `StringBuilder.clear`, `to_str`, `len`, `capacity`, `is_empty` | 0 | none |
| `Ptr.write` | 1 | raw |
| `Ptr.offset` | 1 | typed |
| `Ptr.is_null`, `Ptr.addr`, `Ptr.deref`, `Ptr.to_str` | 0 | none |
| `Template.type_tag`, `get_int`, `get_float`, `get_bool`, `get_str` | 1 | typed |
| `Template.parts`, `Template.count` | 0 | none |
| `scope.cstr`, `scope.alloc_n` | 1 | typed |
| `scope.take` | 1 | arity |
| `scope.alloc` | 0 | none |

## What the survey decides

`check_builtin_arity` is called at six sites today: `Iterator.zip`,
`Iterator.fold`, `List.zip`, `List.fold`, the `Bytes.set_*` family and
`scope.take`. Every other row is unchecked.

Two conclusions follow, and they are what the enforcement step is built on.

**A counter fed by `check_builtin_arg` cannot do the job.** It sees `typed` rows
only. That is 64 of the rows above and none of the four MVCEs on the ticket:
`xs.len(1, 2, 3)`, `"abc".len(9)`, `sb.clear(1)` and `tpl.count(1, 2, 3)` are
all `args = 0, reads = none`, where there is no index for a counter to record.
It would also miss every HOF row (`closure`), every `raw` row, and all seven
1-argument rows on `Int` and the sized ints, whose arms read nothing.

**The count is a fact about the method name, not about the arm.** It is fixed
(no defaults, no variadics), it is knowable before any arm runs, and three arms
already cover mixed counts. So the check belongs in one place, ahead of the
dispatch, driven by a lookup on the receiver kind and the method name — not
distributed over the arms, where the next method added is the next one to
forget.
