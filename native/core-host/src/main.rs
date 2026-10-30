use std::io::{self, BufRead, Read, Write};

use flvp_host::{Host, MAX_REQUEST_BYTES, init_logging};

fn main() -> io::Result<()> {
    init_logging();
    let mut host = Host::default();
    let stdin = io::stdin();
    let mut input = stdin.lock();
    let stdout = io::stdout();
    let mut output = stdout.lock();
    loop {
        let mut bytes = Vec::new();
        let read = input
            .by_ref()
            .take((MAX_REQUEST_BYTES + 1) as u64)
            .read_until(b'\n', &mut bytes)?;
        if read == 0 {
            break;
        }
        if bytes.len() > MAX_REQUEST_BYTES || !bytes.ends_with(b"\n") {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Invalid protocol frame",
            ));
        }
        let text = std::str::from_utf8(&bytes)
            .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "Invalid UTF-8"))?;
        let response = host.request(text);
        let quit = serde_json::from_str::<serde_json::Value>(text)
            .ok()
            .is_some_and(|r| r["operation"] == "quit")
            && response["ok"] == true;
        serde_json::to_writer(&mut output, &response)?;
        output.write_all(b"\n")?;
        output.flush()?;
        if quit {
            break;
        }
    }
    // Drop shuts down only this process's core; it never invokes a route cleaner.
    Ok(())
}
