pub trait Sized {
    fn len(self) -> Int
    fn is_empty(self) -> Bool
}

pub trait Contains[T] {
    fn contains(self, value: T) -> Bool
}

pub trait StrOps {
    fn char_at(self, index: Int) -> Option[Char]
    fn byte_len(self) -> Int
    fn byte_at(self, index: Int) -> U8
    fn contains(self, needle: Str) -> Bool
    fn starts_with(self, prefix: Str) -> Bool
    fn ends_with(self, suffix: Str) -> Bool
    fn index_of(self, needle: Str) -> Option[Int]
    fn substring(self, start: Int, end: Int) -> Str
    fn concat(self, other: Str) -> Str
    fn split(self, separator: Str) -> List[Str]
    fn lines(self) -> List[Str]
    fn to_upper(self) -> Str
    fn to_lower(self) -> Str
    fn trim(self) -> Str
    fn replace(self, needle: Str, replacement: Str) -> Str
    fn parse_int(self) -> Result[Int, Str]
    fn parse_float(self) -> Result[Float, Str]
}

pub trait ListOps[T] {
    fn get(self, index: Int) -> Option[T]
    fn last(self) -> Option[T]
    fn index_of(self, value: T) -> Option[Int]
    fn push(self, value: T)
    fn pop(self) -> Option[T]
    fn set(self, index: Int, value: T)
    fn insert(self, index: Int, value: T)
    fn remove(self, index: Int) -> T
    fn append(self, other: List[T]) -> List[T]
    fn reverse(self) -> List[T]
    fn sort(self) -> List[T]
}

pub trait MapOps[K, V] {
    fn get(self, key: K) -> Option[V]
    fn keys(self) -> List[K]
    fn values(self) -> List[V]
    fn entries(self) -> List[(K, V)]
    fn get_or_default(self, key: K, default: V) -> V
    fn insert(self, key: K, value: V)
    fn remove(self, key: K) -> Option[V]
    fn contains_key(self, key: K) -> Bool
}

pub trait SetOps[T] {
    fn insert(self, value: T) -> Bool
    fn remove(self, value: T) -> Bool
    fn union(self, other: Set[T]) -> Set[T]
}

pub trait StringBuildOps {
    fn write(self, s: Str)
    fn write_char(self, c: Char)
    fn to_str(self) -> Str
    fn len(self) -> Int
    fn capacity(self) -> Int
    fn clear(self)
}

pub trait Joinable {
    fn join(self, separator: Str) -> Str
}
