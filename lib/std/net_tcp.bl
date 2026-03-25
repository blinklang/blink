import std.net_error

pub type TcpSocket {
    fd: Int
}

pub type TcpListener {
    fd: Int
}

pub trait TcpSocketOps {
    fn read(self, max_bytes: Int) -> Str
    fn read_all(self) -> Str
    fn write(self, data: Str)
    fn close(self)
    fn set_timeout(self, ms: Int)
}

pub trait TcpListenerOps {
    fn close(self)
}

impl TcpSocketOps for TcpSocket {
    fn read(self, max_bytes: Int) -> Str {
        net.read(self.fd, max_bytes)
    }

    fn read_all(self) -> Str {
        net.read_all(self.fd)
    }

    fn write(self, data: Str) {
        net.write(self.fd, data)
    }

    fn close(self) {
        net.close(self.fd)
    }

    fn set_timeout(self, ms: Int) {
        net.set_timeout(self.fd, ms)
    }
}

impl TcpListenerOps for TcpListener {
    fn close(self) {
        net.close(self.fd)
    }
}

/// Accept an incoming connection on a TcpListener. Returns a TcpSocket.
pub fn listener_accept(listener: TcpListener) -> Result[TcpSocket, NetError] {
    tcp_accept(listener.fd)
}

/// Connect to a TCP host:port. Returns a TcpSocket on success.
pub fn tcp_connect(host: Str, port: Int) -> Result[TcpSocket, NetError] {
    let fd = net.connect(host, port)
    if fd == -2 {
        return Err(NetError.DnsFailure("DNS resolution failed for {host}"))
    }
    if fd == -3 {
        return Err(NetError.Timeout("connection timed out"))
    }
    if fd < 0 {
        return Err(NetError.ConnectionRefused("connection refused"))
    }
    Ok(TcpSocket { fd: fd })
}

/// Bind and listen on host:port. Returns a TcpListener on success.
pub fn tcp_listen(host: Str, port: Int) -> Result[TcpListener, NetError] {
    let fd = net.listen(host, port)
    if fd < 0 {
        return Err(NetError.BindError("failed to listen on {host}:{port.to_string()}"))
    }
    Ok(TcpListener { fd: fd })
}

/// Accept an incoming connection on a listener fd. Returns a TcpSocket.
pub fn tcp_accept(listener_fd: Int) -> Result[TcpSocket, NetError] {
    let conn = net.accept(listener_fd)
    if conn < 0 {
        return Err(NetError.BindError("accept failed"))
    }
    Ok(TcpSocket { fd: conn })
}

/// Read up to max_bytes from a socket. Returns the data read (empty string on EOF).
pub fn tcp_read(fd: Int, max_bytes: Int) -> Str {
    net.read(fd, max_bytes)
}

/// Read all available data from a socket until EOF.
pub fn tcp_read_all(fd: Int) -> Str {
    net.read_all(fd)
}

/// Write data to a socket.
pub fn tcp_write(fd: Int, data: Str) {
    net.write(fd, data)
}

/// Close a socket.
pub fn tcp_close(fd: Int) {
    net.close(fd)
}

/// Set send/receive timeout in milliseconds on a socket.
pub fn tcp_set_timeout(fd: Int, ms: Int) {
    net.set_timeout(fd, ms)
}
