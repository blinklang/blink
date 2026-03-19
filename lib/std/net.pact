/// TCP networking — connect, listen, accept, read, write.
///
/// Facade module that re-exports all public items from submodules.
/// Users import this with: import std.net

@module("net")
@capabilities(Net)

pub import std.net_error
pub import std.net_tcp
