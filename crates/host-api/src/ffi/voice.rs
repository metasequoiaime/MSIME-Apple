//! Voice provider wire formats and the streaming recognition exchange.
//!
//! Part of the C ABI; see the parent module for what these shims guarantee.

use crate::*;

/// Decode one Doubao v1 response frame for Apple hosts. The returned payload
/// is UTF-8 JSON text; no frame bytes or credentials are retained.
///
/// # Safety
/// `frame` must reference a readable buffer for the duration of this call.
#[no_mangle]
pub unsafe extern "C" fn msime_client_doubao_decode_frame(
    frame: *const u8,
    frame_length: usize,
) -> *mut c_char {
    response(|| {
        if frame.is_null() || frame_length == 0 || frame_length > 1_048_576 {
            return Err("invalid Doubao frame buffer".into());
        }
        let bytes = unsafe { std::slice::from_raw_parts(frame, frame_length) };
        if let Some((last, _sequence, payload)) = decode_json_frame(bytes) {
            let text = String::from_utf8(payload).map_err(|_| "Doubao payload is not UTF-8")?;
            return Ok(json!({ "last": last, "payload": text }));
        }
        if let Some(code) = decode_error_code(bytes) {
            return Ok(json!({ "error_code": code }));
        }
        Err("invalid Doubao response frame".into())
    })
}

unsafe fn write_doubao_frame(
    frame: Vec<u8>,
    output: *mut u8,
    output_capacity: usize,
    output_length: *mut usize,
) -> bool {
    if output.is_null() || output_length.is_null() {
        return false;
    }
    *output_length = frame.len();
    if frame.len() > output_capacity {
        return false;
    }
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    true
}

/// Build a Doubao start request into caller-owned storage.
///
/// # Safety
/// `boosting_table_id` must point to `boosting_table_id_length` readable bytes when the length is
/// nonzero. `output` must point to `output_capacity` writable bytes and `output_length` must point
/// to a writable `usize`.
#[no_mangle]
pub unsafe extern "C" fn msime_client_doubao_start_frame(
    enable_itn: bool,
    enable_punc: bool,
    enable_ddc: bool,
    boosting_table_id: *const u8,
    boosting_table_id_length: usize,
    output: *mut u8,
    output_capacity: usize,
    output_length: *mut usize,
) -> bool {
    if boosting_table_id_length > 4096
        || (boosting_table_id.is_null() && boosting_table_id_length != 0)
    {
        return false;
    }
    let boosting = if boosting_table_id_length == 0 {
        ""
    } else {
        let bytes =
            unsafe { std::slice::from_raw_parts(boosting_table_id, boosting_table_id_length) };
        match std::str::from_utf8(bytes) {
            Ok(value) => value,
            Err(_) => return false,
        }
    };
    unsafe {
        write_doubao_frame(
            start_frame(enable_itn, enable_punc, enable_ddc, boosting),
            output,
            output_capacity,
            output_length,
        )
    }
}

/// Build a Doubao PCM or final audio frame into caller-owned storage.
///
/// # Safety
/// `pcm` must point to `pcm_length` readable bytes when the length is nonzero. `output` must point
/// to `output_capacity` writable bytes and `output_length` must point to a writable `usize`.
#[no_mangle]
pub unsafe extern "C" fn msime_client_doubao_audio_frame(
    sequence: i32,
    pcm: *const u8,
    pcm_length: usize,
    final_chunk: bool,
    output: *mut u8,
    output_capacity: usize,
    output_length: *mut usize,
) -> bool {
    if pcm_length > 1_048_576 || (pcm.is_null() && pcm_length != 0) {
        return false;
    }
    let bytes = if pcm_length == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(pcm, pcm_length) }
    };
    unsafe {
        write_doubao_frame(
            audio_frame(sequence, bytes, final_chunk),
            output,
            output_capacity,
            output_length,
        )
    }
}

/// Run one bounded voice capture/ASR request through a user-owned Unix socket.
/// The socket service owns microphone access, credentials and network policy.
/// The query is a bounded JSON object containing `language`, `generation`,
/// and optional non-sensitive voice behavior `options`.
///
/// # Safety
/// All pointers must reference readable buffers of the stated lengths for
/// the duration of this call; the buffers are not retained.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_voice_provider_request(
    query: *const u8,
    query_length: usize,
    socket_path: *const u8,
    socket_length: usize,
) -> *mut c_char {
    response(|| {
        if query.is_null() || socket_path.is_null() || query_length > 16_384 || socket_length > 4096
        {
            return Err("invalid voice provider buffer".into());
        }
        #[derive(Deserialize)]
        struct VoiceQuery {
            language: String,
            generation: u64,
            #[serde(default)]
            options: Value,
        }
        let query = serde_json::from_slice::<VoiceQuery>(unsafe {
            std::slice::from_raw_parts(query, query_length)
        })
        .map_err(|_| "invalid voice query document")?;
        let path =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(socket_path, socket_length) })
                .map_err(|_| "socket path is not UTF-8")?;
        if !std::path::Path::new(path).is_absolute() {
            return Err("socket path must be absolute".into());
        }
        Ok(UnixSocketProvider::new(path)
            .voice_with_options(&query.language, query.generation, &query.options)
            .map(|text| json!({"text": text}))
            .unwrap_or(Value::Null))
    })
}

/// Stream bounded interim/final voice provider updates from a user-owned
/// Unix socket. The callback is invoked synchronously on the calling thread.
///
/// # Safety
/// Buffers must remain readable for the duration of this call. The callback
/// must remain valid and must copy the text before returning.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_voice_provider_stream(
    query: *const u8,
    query_length: usize,
    socket_path: *const u8,
    socket_length: usize,
    callback: Option<unsafe extern "C" fn(*const u8, usize, bool, *mut c_void)>,
    context: *mut c_void,
) -> *mut c_char {
    unsafe {
        msime_client_voice_provider_stream_events(
            query,
            query_length,
            socket_path,
            socket_length,
            callback,
            None,
            context,
        )
    }
}

/// Stream voice text and optional phase notifications (0 recording, 1 recognizing, 2 polishing).
///
/// # Safety
/// Buffers and callbacks must remain valid for this synchronous call. Callbacks must not unwind.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_voice_provider_stream_events(
    query: *const u8,
    query_length: usize,
    socket_path: *const u8,
    socket_length: usize,
    callback: Option<unsafe extern "C" fn(*const u8, usize, bool, *mut c_void)>,
    status_callback: Option<unsafe extern "C" fn(u8, *mut c_void)>,
    context: *mut c_void,
) -> *mut c_char {
    unsafe {
        msime_client_voice_provider_stream_feedback(
            query,
            query_length,
            socket_path,
            socket_length,
            callback,
            status_callback,
            None,
            context,
        )
    }
}

/// Stream voice text, phases and optional normalized microphone levels.
///
/// # Safety
/// Buffers and callbacks must remain valid for this synchronous call. Callbacks must not unwind.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_voice_provider_stream_feedback(
    query: *const u8,
    query_length: usize,
    socket_path: *const u8,
    socket_length: usize,
    callback: Option<unsafe extern "C" fn(*const u8, usize, bool, *mut c_void)>,
    status_callback: Option<unsafe extern "C" fn(u8, *mut c_void)>,
    level_callback: Option<unsafe extern "C" fn(f32, *mut c_void)>,
    context: *mut c_void,
) -> *mut c_char {
    response(|| {
        if query.is_null() || socket_path.is_null() || query_length > 16_384 || socket_length > 4096
        {
            return Err("invalid voice provider buffer".into());
        }
        #[derive(Deserialize)]
        struct VoiceQuery {
            language: String,
            generation: u64,
            #[serde(default)]
            options: Value,
        }
        let query = serde_json::from_slice::<VoiceQuery>(unsafe {
            std::slice::from_raw_parts(query, query_length)
        })
        .map_err(|_| "invalid voice query document")?;
        let path =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(socket_path, socket_length) })
                .map_err(|_| "socket path is not UTF-8")?;
        if !std::path::Path::new(path).is_absolute() {
            return Err("socket path must be absolute".into());
        }
        let mut update = |text: &str, final_result: bool| {
            if let Some(callback) = callback {
                unsafe {
                    callback(text.as_ptr(), text.len(), final_result, context);
                }
            }
        };
        let mut status = |phase: &str| {
            if let Some(callback) = status_callback {
                let value = match phase {
                    "recording" => 0,
                    "recognizing" => 1,
                    "polishing" => 2,
                    _ => return,
                };
                unsafe {
                    callback(value, context);
                }
            }
        };
        let mut level = |value: f32| {
            if let Some(callback) = level_callback {
                unsafe {
                    callback(value, context);
                }
            }
        };
        let value = UnixSocketProvider::new(path).voice_stream_with_options_feedback(
            &query.language,
            query.generation,
            &query.options,
            None,
            &mut update,
            if status_callback.is_some() {
                Some(&mut status)
            } else {
                None
            },
            if level_callback.is_some() {
                Some(&mut level)
            } else {
                None
            },
        );
        Ok(value
            .map(|text| json!({"text": text}))
            .unwrap_or(Value::Null))
    })
}

/// Ask a user-owned Unix socket to stop voice capture for one generation.
///
/// # Safety
/// `socket_path` must reference a readable UTF-8 buffer for this call.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_voice_provider_cancel(
    socket_path: *const u8,
    socket_length: usize,
    generation: u64,
) -> *mut c_char {
    response(|| {
        if socket_path.is_null() || socket_length > 4096 {
            return Err("invalid voice provider socket buffer".into());
        }
        let path =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(socket_path, socket_length) })
                .map_err(|_| "socket path is not UTF-8")?;
        if !std::path::Path::new(path).is_absolute() {
            return Err("socket path must be absolute".into());
        }
        Ok(json!(UnixSocketProvider::new(path).voice_cancel(generation)))
    })
}

/// Ask a user-owned voice socket to finish capture and return its final stream
/// result. The streaming connection remains responsible for delivering text.
///
/// # Safety
/// `socket_path` must reference a readable UTF-8 buffer for this call.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_voice_provider_stop(
    socket_path: *const u8,
    socket_length: usize,
    generation: u64,
) -> *mut c_char {
    response(|| {
        if socket_path.is_null() || socket_length > 4096 {
            return Err("invalid voice provider socket buffer".into());
        }
        let path =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(socket_path, socket_length) })
                .map_err(|_| "socket path is not UTF-8")?;
        if !std::path::Path::new(path).is_absolute() {
            return Err("socket path must be absolute".into());
        }
        Ok(json!(UnixSocketProvider::new(path).voice_stop(generation)))
    })
}
