use std::io::{self, BufRead, BufReader, ErrorKind, Write};
use std::net::{TcpListener, TcpStream};
use std::thread;
use std::time::{Duration, Instant};

use tauri::Url;
use tauri::ipc::Channel;

/// The server for the redirect after Google's consent (see ListenForRedirect
/// in packages/crdt-file-sync-google-drive) - on the desktop, where the app
/// signs in through the user's browser. Returns its port; `on_redirect` gets
/// the target of the first request carrying `state`, or None after
/// `timeout_ms`.
#[tauri::command]
pub fn loopback_listen(state: String, timeout_ms: u64, on_redirect: Channel<Option<String>>) -> Result<u16, String> {
    listen(state, Duration::from_millis(timeout_ms), move |target| {
        let _ = on_redirect.send(target);
    })
    .map_err(|error| error.to_string())
}

fn listen(state: String, timeout: Duration, on_done: impl FnOnce(Option<String>) + Send + 'static) -> io::Result<u16> {
    let listener = TcpListener::bind("127.0.0.1:0")?;
    let port = listener.local_addr()?.port();
    // Polled, so the server stops at the deadline even when nobody comes back.
    listener.set_nonblocking(true)?;
    let deadline = Instant::now() + timeout;
    thread::spawn(move || {
        let target = loop {
            if Instant::now() >= deadline {
                break None;
            }
            match listener.accept() {
                Ok((stream, _)) => {
                    if let Some(target) = answer(stream, &state) {
                        break Some(target);
                    }
                }
                Err(error) if error.kind() == ErrorKind::WouldBlock => thread::sleep(Duration::from_millis(100)),
                Err(_) => break None,
            }
        };
        on_done(target);
    });
    Ok(port)
}

/// Answers one request: the redirect (it carries `state`) with a page for the
/// browser tab, anything else with a 404. The redirect's target if it was one.
fn answer(mut stream: TcpStream, state: &str) -> Option<String> {
    stream.set_nonblocking(false).ok()?;
    stream.set_read_timeout(Some(Duration::from_secs(5))).ok()?;
    let mut request_line = String::new();
    BufReader::new(&stream).read_line(&mut request_line).ok()?;
    let target = request_line.split(' ').nth(1)?.to_owned();
    let url = Url::parse(&format!("http://127.0.0.1{target}")).ok()?;
    let param = |name: &str| url.query_pairs().find(|(key, _)| key == name).map(|(_, value)| value);
    if param("state").as_deref() != Some(state) {
        stream
            .write_all(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            .ok();
        return None;
    }
    let body = if param("code").is_some() {
        "<p>Signed in to turtle-base. You can close this tab.</p>"
    } else {
        "<p>Signing in to turtle-base was cancelled. You can close this tab.</p>"
    };
    let response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    stream.write_all(response.as_bytes()).ok();
    Some(target)
}

#[cfg(test)]
mod tests {
    use std::io::Read;
    use std::sync::mpsc;

    use super::*;

    fn get(port: u16, target: &str) -> String {
        let mut stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
        write!(stream, "GET {target} HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n").unwrap();
        let mut response = String::new();
        stream.read_to_string(&mut response).unwrap();
        response
    }

    #[test]
    fn hands_over_the_redirect_with_the_state() {
        let (sender, receiver) = mpsc::channel();
        let port = listen("s1".into(), Duration::from_secs(5), move |target| {
            sender.send(target).unwrap()
        })
        .unwrap();

        let favicon = get(port, "/favicon.ico");
        let redirect = get(port, "/?state=s1&code=c1");

        assert!(favicon.starts_with("HTTP/1.1 404"));
        assert!(redirect.contains("Signed in to turtle-base"));
        assert_eq!(receiver.recv().unwrap().as_deref(), Some("/?state=s1&code=c1"));
    }

    #[test]
    fn gives_up_after_the_timeout() {
        let (sender, receiver) = mpsc::channel();
        listen("s1".into(), Duration::from_millis(200), move |target| {
            sender.send(target).unwrap()
        })
        .unwrap();

        assert_eq!(receiver.recv().unwrap(), None);
    }
}
