# Voice cue sources

Derived from metasequoiaime/MSIME-Windows commit `7fa6fb1a7862c5ca1541b9cb839d9bea3a06e2c6`:

- `server/assets/audios/start.mp3` → `start.pcm`
- `server/assets/audios/end.mp3` → `end.pcm`

Converted with FFmpeg to mono 16000 Hz signed 16-bit little-endian PCM. Metadata is removed. The product audio is preserved without adding a runtime MP3 decoder dependency.
