pub trait Sized {
    fn len(self) -> Int
    fn is_empty(self) -> Bool
}

pub trait Contains[T] {
    fn contains(self, value: T) -> Bool
}

pub trait StrOps {
    fn char_at(self, index: Int) -> Int
    fn contains(self, needle: Str) -> Bool
    fn starts_with(self, prefix: Str) -> Bool
    fn ends_with(self, suffix: Str) -> Bool
    fn index_of(self, needle: Str) -> Int
    fn substring(self, start: Int, len: Int) -> Str
    fn concat(self, other: Str) -> Str
    fn split(self, separator: Str) -> List[Str]
    fn lines(self) -> List[Str]
    fn to_upper(self) -> Str
    fn to_lower(self) -> Str
    fn trim(self) -> Str
    fn replace(self, needle: Str, replacement: Str) -> Str
    fn parse_int(self) -> Int
    fn parse_float(self) -> Float
    fn slice(self, start: Int, end: Int) -> Str
    fn to_int(self) -> Int
}

pub trait ListOps[T] {
    fn get(self, index: Int) -> Option[T]
    fn push(self, value: T)
    fn pop(self) -> Option[T]
    fn set(self, index: Int, value: T)
    fn concat(self, other: List[T]) -> List[T]
    fn slice(self, start: Int, end: Int) -> List[T]
}

pub trait MapOps[K, V] {
    fn get(self, key: K) -> V
    fn set(self, key: K, value: V)
    fn has(self, key: K) -> Bool
    fn remove(self, key: K) -> Bool
    fn keys(self) -> List[K]
    fn values(self) -> List[V]
}

pub trait SetOps[T] {
    fn insert(self, value: T) -> Bool
    fn remove(self, value: T) -> Bool
    fn union(self, other: Set[T]) -> Set[T]
}

pub trait BytesOps {
    fn push(self, byte: Int)
    fn get(self, index: Int) -> Option[Int]
    fn set(self, index: Int, byte: Int)
    fn len(self) -> Int
    fn is_empty(self) -> Bool
    fn slice(self, start: Int, end: Int) -> Bytes
    fn concat(self, other: Bytes) -> Bytes
    fn to_str(self) -> Result[Str, Str]
    fn to_hex(self) -> Str
}

pub trait StringBuildOps {
    fn write(self, s: Str)
    fn write_char(self, c: Char)
    fn to_str(self) -> Str
    fn len(self) -> Int
    fn capacity(self) -> Int
    fn clear(self)
    fn is_empty(self) -> Bool
}

pub trait Joinable {
    fn join(self, separator: Str) -> Str
}

pub trait Closeable {
    fn close(self)
}
