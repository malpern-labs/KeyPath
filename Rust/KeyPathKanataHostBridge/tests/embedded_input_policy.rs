#![cfg(all(feature = "passthru-output-spike", target_os = "macos"))]

use kanata_state_machine::oskbd::{KeyEvent, KeyValue};
use kanata_state_machine::{is_mapped_input, Kanata, OsCode, ValidatedArgs};
use std::time::{Duration, Instant};

// Use a separate test binary because Kanata's capture table is process-global.
#[test]
fn embedded_input_policy_is_reapplied_on_live_reload() {
    let path =
        std::env::temp_dir().join(format!("keypath-input-policy-{}.kbd", std::process::id()));
    let function_only = "(defcfg process-unmapped-keys yes)(defsrc f1)(deflayer base f1)";
    std::fs::write(&path, function_only).unwrap();
    let (output, _events) = std::sync::mpsc::channel();
    let runtime = Kanata::new_with_output_channel_and_input_policy(
        &ValidatedArgs {
            paths: vec![path.clone()],
            tcp_server_address: None,
            nodelay: true,
        },
        Some(output),
        Some(|cfg| {
            if !cfg.source_keys.contains(&OsCode::KEY_LEFTCTRL) {
                cfg.mapped_keys.remove(&OsCode::KEY_LEFTCTRL);
            }
        }),
    )
    .unwrap();
    let (tx, rx) = std::sync::mpsc::sync_channel(4);
    Kanata::start_processing_loop(runtime.clone(), rx, None, true);

    assert!(!is_mapped_input(OsCode::KEY_LEFTCTRL));
    for (source, expected) in [
        (
            "(defcfg process-unmapped-keys yes)(defsrc lctl f1)(deflayer base a f1)",
            true,
        ),
        (function_only, false),
    ] {
        std::fs::write(&path, source).unwrap();
        runtime.lock().request_live_reload();
        // Wake the idle loop with a key mapped in both configurations.
        for value in [KeyValue::Press, KeyValue::Release] {
            tx.send(KeyEvent::new(OsCode::KEY_F1, value)).unwrap();
        }
        let deadline = Instant::now() + Duration::from_secs(2);
        while is_mapped_input(OsCode::KEY_LEFTCTRL) != expected && Instant::now() < deadline {
            std::thread::yield_now();
        }
        assert_eq!(is_mapped_input(OsCode::KEY_LEFTCTRL), expected);
    }
    std::fs::remove_file(path).unwrap();
}
