pub type NetError {
    Timeout(msg: Str)
    ConnectionRefused(msg: Str)
    DnsFailure(msg: Str)
    TlsError(msg: Str)
    InvalidUrl(msg: Str)
    BindError(msg: Str)
    ProtocolError(msg: Str)
}

/// Convert a NetError to a human-readable string
pub fn net_error_display(err: NetError) -> Str {
    match err {
        NetError.Timeout(msg) => "timeout: {msg}"
        NetError.ConnectionRefused(msg) => "connection_refused: {msg}"
        NetError.DnsFailure(msg) => "dns_failure: {msg}"
        NetError.TlsError(msg) => "tls: {msg}"
        NetError.InvalidUrl(msg) => "invalid_url: {msg}"
        NetError.BindError(msg) => "bind_error: {msg}"
        NetError.ProtocolError(msg) => "protocol_error: {msg}"
    }
}
