#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["faster-whisper>=1.1", "numpy"]
# ///
"""Transcribe an audio or video file on this machine with faster-whisper.

Usage: get-transcript FILE [-o OUT | --stdout] [--format txt|srt|vtt|json]
                           [--model NAME] [--language CODE] [--device auto|cpu|cuda]
       get-transcript --dry-run FILE [options]
       get-transcript --self-test
  FILE        Audio or video file (anything ffmpeg reads: mp4, mkv, mov, m4a, mp3, wav)
  -o OUT      Write to OUT. Default: FILE with the format's extension, next to FILE
  --stdout    Print the transcript to stdout instead of writing a file
  --format    txt (default, "[mm:ss] text" lines), srt, vtt, or json (start, end, text)
  --model     faster-whisper model. Default: distil-large-v3 (English only).
              Use large-v3 for other languages
  --language  Language code. Default: en. Use "auto" to detect the language
  --device    auto (default) uses cuda when a GPU works, else cpu
  --dry-run   Show the duration, model, device, and output path; transcribe nothing
  --self-test Check the timestamp, srt, and vtt formatters
"""
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

FORMATS = ("txt", "srt", "vtt", "json")
VALUE_FLAGS = {"-o": "out", "--format": "format", "--model": "model",
               "--language": "language", "--device": "device"}
SAMPLE_RATE = 16000


def clock(seconds, sep=","):
    """Return HH:MM:SS<sep>mmm for srt (sep ",") and vtt (sep ".")."""
    ms = round(seconds * 1000)
    h, ms = divmod(ms, 3_600_000)
    m, ms = divmod(ms, 60_000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d}{sep}{ms:03d}"


def short(seconds):
    """Return mm:ss, or h:mm:ss when the time passes one hour."""
    s = int(seconds)
    h, s = divmod(s, 3600)
    m, s = divmod(s, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"


def header(fmt):
    return {"vtt": "WEBVTT\n\n", "json": "[\n"}.get(fmt, "")


def footer(fmt, count):
    return ("\n]\n" if count else "]\n") if fmt == "json" else ""


def render(fmt, index, start, end, text):
    """Return one segment in the given format. index starts at 1."""
    if fmt == "txt":
        return f"[{short(start)}] {text}\n"
    if fmt == "srt":
        return f"{index}\n{clock(start)} --> {clock(end)}\n{text}\n\n"
    if fmt == "vtt":
        return f"{clock(start, '.')} --> {clock(end, '.')}\n{text}\n\n"
    item = json.dumps({"start": round(start, 2), "end": round(end, 2), "text": text},
                      ensure_ascii=False)
    return ("" if index == 1 else ",\n") + "  " + item


def self_test():
    assert clock(3725.5) == "01:02:05,500", clock(3725.5)
    assert clock(2.0, ".") == "00:00:02.000"
    assert short(65.9) == "01:05" and short(3725) == "1:02:05"
    assert render("txt", 1, 5.2, 9, "Hi") == "[00:05] Hi\n"
    assert render("srt", 3, 0, 2, "Hi") == "3\n00:00:00,000 --> 00:00:02,000\nHi\n\n"
    assert render("vtt", 1, 0, 2, "Hi") == "00:00:00.000 --> 00:00:02.000\nHi\n\n"
    body = header("json") + render("json", 1, 0, 1, "a") + render("json", 2, 1, 2, "b")
    assert json.loads(body + footer("json", 2))[1] == {"start": 1, "end": 2, "text": "b"}
    assert json.loads(header("json") + footer("json", 0)) == []
    print("ok")


def parse_args(args):
    opts = {"out": None, "format": "txt", "model": "distil-large-v3",
            "language": "en", "device": "auto", "stdout": False, "dry_run": False}
    files = []
    i = 0
    while i < len(args):
        a = args[i]
        if a in VALUE_FLAGS:
            if i + 1 >= len(args):
                sys.exit(f"error: {a} needs a value\n" + __doc__)
            opts[VALUE_FLAGS[a]] = args[i + 1]
            i += 2
            continue
        if a == "--stdout":
            opts["stdout"] = True
        elif a == "--dry-run":
            opts["dry_run"] = True
        elif a in ("-h", "--help"):
            print(__doc__)
            sys.exit(0)
        elif a.startswith("-"):
            sys.exit(f"error: unknown option {a}\n" + __doc__)
        else:
            files.append(a)
        i += 1
    if len(files) != 1:
        sys.exit("error: give exactly one FILE\n" + __doc__)
    if opts["format"] not in FORMATS:
        sys.exit(f"error: --format must be one of {', '.join(FORMATS)}")
    if opts["device"] not in ("auto", "cpu", "cuda"):
        sys.exit("error: --device must be auto, cpu, or cuda")
    if opts["out"] and opts["stdout"]:
        sys.exit("error: use -o or --stdout, not both")
    return Path(files[0]), opts


def duration(path):
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True)
    try:
        return float(result.stdout.strip())
    except ValueError:
        sys.exit(f"error: ffprobe cannot read {path}: {result.stderr.strip() or 'no duration'}")


def load_audio(path):
    """Decode the file to 16 kHz mono float32 samples with ffmpeg (no PyAV)."""
    import numpy as np
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-nostdin", "-i", str(path), "-vn", "-ac", "1",
         "-ar", str(SAMPLE_RATE), "-f", "s16le", "-"],
        capture_output=True)
    if result.returncode != 0 or not result.stdout:
        sys.exit(f"error: ffmpeg cannot decode {path}: {result.stderr.decode().strip() or 'no audio'}")
    return np.frombuffer(result.stdout, np.int16).astype(np.float32) / 32768.0


def cuda_works():
    try:
        import ctranslate2
        return ctranslate2.get_cuda_device_count() > 0
    except Exception:
        return False


def load_model(name, device):
    from faster_whisper import WhisperModel
    if device in ("auto", "cuda") and (device == "cuda" or cuda_works()):
        try:
            return WhisperModel(name, device="cuda", compute_type="float16"), "cuda"
        except Exception as e:
            if device == "cuda":
                sys.exit(f"error: cannot load {name} on cuda: {e}")
            print(f"cuda failed ({e}); using cpu", file=sys.stderr)
    return WhisperModel(name, device="cpu", compute_type="int8",
                        cpu_threads=os.cpu_count() or 4), "cpu"


def main():
    args = sys.argv[1:]
    if args == ["--self-test"]:
        return self_test()
    path, opts = parse_args(args)
    for tool in ("ffmpeg", "ffprobe"):
        if not shutil.which(tool):
            sys.exit(f"error: {tool} is not on PATH")
    if not path.is_file():
        sys.exit(f"error: no such file: {path}")

    fmt = opts["format"]
    out = None if opts["stdout"] else Path(opts["out"] or path.with_suffix("." + fmt))
    total = duration(path)
    if opts["dry_run"]:
        device = opts["device"]
        if device == "auto":
            device = "cuda" if cuda_works() else "cpu"
        print(f"file:     {path}\nduration: {short(total)} ({total:.0f} s)\n"
              f"model:    {opts['model']}\nlanguage: {opts['language']}\n"
              f"device:   {device}\noutput:   {out or 'stdout'} ({fmt})")
        return

    start_time = time.time()
    samples = load_audio(path)
    model, device = load_model(opts["model"], opts["device"])
    print(f"Transcribing {short(total)} of audio with {opts['model']} on {device}...", file=sys.stderr)
    segments, _ = model.transcribe(
        samples, language=None if opts["language"] == "auto" else opts["language"],
        beam_size=5, vad_filter=True, condition_on_previous_text=False)

    sink = open(out, "w", encoding="utf-8") if out else sys.stdout
    count = 0
    try:
        sink.write(header(fmt))
        for seg in segments:
            text = seg.text.strip()
            if not text:
                continue
            count += 1
            sink.write(render(fmt, count, seg.start, seg.end, text))
            sink.flush()
            if sys.stderr.isatty():
                print(f"\r  {short(seg.end)} / {short(total)}", end="", file=sys.stderr, flush=True)
        sink.write(footer(fmt, count))
    finally:
        if out:
            sink.close()
    if sys.stderr.isatty():
        print(file=sys.stderr)
    where = f"Wrote {count} segments to {out}" if out else f"Printed {count} segments"
    print(f"{where} in {time.time() - start_time:.0f} s", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("\nstopped; the output file keeps the segments written so far")
