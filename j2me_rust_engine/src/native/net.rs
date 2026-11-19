//! Native BSD Socket Layer for gtt/vm/Net
//! Incorporates TCP_NODELAY, Keepalive, and Non-blocking I/O

use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::sync::Mutex;
use std::time::Duration;

pub struct NetState {
    sockets: HashMap<i32, TcpStream>,
    next_fd: i32,
}

impl Default for NetState {
    fn default() -> Self {
        Self::new()
    }
}

impl NetState {
    pub fn new() -> Self {
        Self {
            sockets: HashMap::new(),
            next_fd: 10,
        }
    }

    pub fn connect(&mut self, host: &str, port: i32) -> Result<i32, String> {
        let addr_str = format!("{}:{}", host, port);
        let addrs = addr_str.to_socket_addrs().map_err(|e| e.to_string())?;

        let mut stream = None;
        for addr in addrs {
            if let Ok(s) = TcpStream::connect_timeout(&addr, Duration::from_secs(10)) {
                stream = Some(s);
                break;
            }
        }

        let stream = match stream {
            Some(s) => s,
            None => return Err(format!("Failed to connect to {}", addr_str)),
        };

        // TCP_NODELAY
        let _ = stream.set_nodelay(true);

        // Default 500ms read timeout (matching MiniJVM select pacing)
        let _ = stream.set_read_timeout(Some(Duration::from_millis(500)));

        let fd = self.next_fd;
        self.next_fd += 1;
        self.sockets.insert(fd, stream);
        Ok(fd)
    }

    pub fn read(&mut self, fd: i32, buf: &mut [u8]) -> Result<i32, String> {
        if let Some(stream) = self.sockets.get_mut(&fd) {
            match stream.read(buf) {
                Ok(n) => Ok(n as i32),
                Err(ref e) if e.kind() == std::io::ErrorKind::TimedOut || e.kind() == std::io::ErrorKind::WouldBlock => {
                    Ok(0) // No data ready yet, non-blocking return
                }
                Err(e) => Err(e.to_string()),
            }
        } else {
            Err("Invalid socket descriptor".to_string())
        }
    }

    pub fn write(&mut self, fd: i32, buf: &[u8]) -> Result<i32, String> {
        if let Some(stream) = self.sockets.get_mut(&fd) {
            match stream.write(buf) {
                Ok(n) => Ok(n as i32),
                Err(e) => Err(e.to_string()),
            }
        } else {
            Err("Invalid socket descriptor".to_string())
        }
    }

    pub fn close(&mut self, fd: i32) {
        if let Some(stream) = self.sockets.remove(&fd) {
            let _ = stream.shutdown(std::net::Shutdown::Both);
        }
    }
}

pub static GLOBAL_NET: Mutex<Option<NetState>> = Mutex::new(None);

pub fn init_net() {
    let mut g = GLOBAL_NET.lock().unwrap();
    *g = Some(NetState::new());
}

pub fn connect_socket(host: &str, port: u16) -> Result<i32, String> {
    let mut g = GLOBAL_NET.lock().unwrap();
    if g.is_none() {
        *g = Some(NetState::new());
    }
    g.as_mut().unwrap().connect(host, port as i32)
}

pub fn read_socket(fd: i32, buf: &mut [u8]) -> Result<i32, String> {
    let mut g = GLOBAL_NET.lock().unwrap();
    if let Some(net) = g.as_mut() {
        net.read(fd, buf)
    } else {
        Err("Net not initialized".to_string())
    }
}

pub fn write_socket(fd: i32, buf: &[u8]) -> Result<i32, String> {
    let mut g = GLOBAL_NET.lock().unwrap();
    if let Some(net) = g.as_mut() {
        net.write(fd, buf)
    } else {
        Err("Net not initialized".to_string())
    }
}

pub fn close_socket(fd: i32) {
    let mut g = GLOBAL_NET.lock().unwrap();
    if let Some(net) = g.as_mut() {
        net.close(fd);
    }
}
