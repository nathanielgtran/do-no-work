---
name: call
description: Transcribe the latest call recording locally (Parakeet, CPU) and turn it into notes. Use when the user says "transcribe the last call", "summarise the call", "/call", or points at a recording file. Optional arg = a specific file path instead of the newest recording.
---

# call

Recording → local transcript → summary. Audio never leaves the machine; only the transcript text reaches the model.

## Steps

1. **Transcribe.**
   - No arg: `transcribe --last` (newest media file in your Windows `Recordings` folder, where OBS saves).
   - Arg given: `transcribe "<path>"`.
   - Prints the `.txt` path, written next to the recording. Takes ~minutes per hour of audio on CPU, so run with a generous timeout (600000) or in the background for long calls.
   - If a `.txt` for that recording already exists and is newer than the recording, reuse it instead of re-transcribing.
2. **Read** the transcript. Lines are `[mm:ss] text`, no speaker labels (single mixed track). Infer speakers from context only where obvious; don't invent attributions.
3. **Fix obvious mis-hearings** of known names/terms when quoting (keep your own list of names here). Check personal-kb if a name is unfamiliar.
4. **Summarise** in chat:
   - Who/what (one line), date from the file mtime.
   - Key points / decisions.
   - Action items, owner if clear, with `[mm:ss]` refs.
   - Open questions.
5. **Ask** whether to file it. If yes, save to the matching personal-kb spot (a project's notes if it matches one; otherwise `personal-kb/reference/calls/YYYY-MM-DD-<slug>.md`), add action items to `todo.md` if asked, then `engraph-enqueue <file>...` on what was written (instant; never call `mcp__engraph__reindex_file` directly, it times out).

## Notes

- Tool: `~/parakeet/transcribe.py` via `~/.local/bin/transcribe` (onnx-asr, parakeet-tdt-0.6b-v3 int8, silero VAD). ~1.5GB RAM.
- Only the first audio track is read. If OBS is ever set to 2 tracks (mic / desktop), the script needs updating to transcribe each track separately for speaker names.
- Never move/delete recordings without asking.
