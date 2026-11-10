#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["faster-whisper>=1.1", "numpy"]
# ///
"""Transcribe an audio or video file on this machine with faster-whisper."""
import argparse
import ctypes
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

FORMATS = ("txt", "srt", "vtt", "json")
SAMPLE_RATE = 16000
CUDA_LIBRARIES = ("libcublas.so.12", "libcudnn_ops.so.9")


def clock(seconds, sep=","):
    """Return HH:MM:SS<sep>mmm for srt (sep ",") and vtt (sep ".")."""
    ms = round(seconds * 1000)
    h, ms = divmod(ms, 3_600_000)
    m, ms = divmod(ms, 60_000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d}{sep}{ms:03d}"


def short(seconds):
    """Return mm:ss, or h:mm:ss when the time passes one hour. None gives "?"."""
    if seconds is None:
        return "?"
    s = int(seconds)
    h, s = divmod(s, 3600)
    m, s = divmod(s, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"


def header(fmt):
    return {"vtt": "WEBVTT\n\n", "json": "[\n"}.get(fmt, "")


def footer(fmt):
    return "\n]\n" if fmt == "json" else ""


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
    assert short(65.9) == "01:05" and short(3725) == "1:02:05" and short(None) == "?"
    assert render("txt", 1, 5.2, 9, "Hi") == "[00:05] Hi\n"
    assert render("srt", 3, 0, 2, "Hi") == "3\n00:00:00,000 --> 00:00:02,000\nHi\n\n"
    assert render("vtt", 1, 0, 2, "Hi") == "00:00:00.000 --> 00:00:02.000\nHi\n\n"
    body = header("json") + render("json", 1, 0, 1, "a") + render("json", 2, 1, 2, "b")
    assert json.loads(body + footer("json"))[1] == {"start": 1, "end": 2, "text": "b"}
    assert json.loads(header("json") + footer("json")) == []
    args = build_parser().parse_args(["--format=srt", "--", "-odd.mp4"])
    assert args.format == "srt" and args.file == "-odd.mp4", args
    print("ok")


def build_parser():
    p = argparse.ArgumentParser(
        prog="get-transcript", description=__doc__,
        epilog="The default model, distil-large-v3, is English only. Use --model large-v3 "
               "for other languages.")
    p.add_argument("file", nargs="?", metavar="FILE",
                   help="audio or video file (anything ffmpeg reads: mp4, mkv, mov, m4a, mp3, wav)")
    where = p.add_mutually_exclusive_group()
    where.add_argument("-o", dest="out", metavar="OUT",
                       help="output file (default: FILE with the format's extension, next to FILE)")
    where.add_argument("--stdout", action="store_true",
                       help="print the transcript to stdout instead of a file")
    p.add_argument("--format", choices=FORMATS, default="txt",
                   help='txt ("[mm:ss] text" lines), srt, vtt, or json (start, end, text). Default: txt')
    p.add_argument("--model", default="distil-large-v3", help="faster-whisper model. Default: distil-large-v3")
    p.add_argument("--language", default="en", help='language code, or "auto" to detect it. Default: en')
    p.add_argument("--device", choices=("auto", "cpu", "cuda"), default="auto",
                   help="auto uses cuda when a GPU and the CUDA libraries work, else cpu. Default: auto")
    p.add_argument("--dry-run", action="store_true",
                   help="show the duration, model, device, and output path; transcribe nothing")
    p.add_argument("--self-test", action="store_true", help="check the formatters and the parser")
    return p


def duration(path):
    """Return the duration in seconds, or None when the file header has none."""
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"error: ffprobe cannot read {path}: {result.stderr.strip()}")
    try:
        return float(result.stdout.strip())
    except ValueError:
        return None  # ffprobe prints N/A for streamed files, such as browser WebM recordings


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
    """Return True when a GPU, its driver, cuBLAS 12, and cuDNN 9 all load."""
    try:
        for library in CUDA_LIBRARIES:
            ctypes.CDLL(library)
        import ctranslate2
        return ctranslate2.get_cuda_device_count() > 0
    except Exception:
        return False


def load_model(name, device):
    from faster_whisper import WhisperModel
    if device == "cuda" or (device == "auto" and cuda_works()):
        try:
            return WhisperModel(name, device="cuda", compute_type="float16"), "cuda"
        except Exception as e:
            if device == "cuda":
                sys.exit(f"error: cannot load {name} on cuda: {e}")
            print(f"cuda failed ({e}); using cpu", file=sys.stderr)
    return WhisperModel(name, device="cpu", compute_type="int8",
                        cpu_threads=os.cpu_count() or 4), "cpu"


def main():
    parser = build_parser()
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if not args.file:
        parser.error("FILE is required")
    path = Path(args.file)
    for tool in ("ffmpeg", "ffprobe"):
        if not shutil.which(tool):
            sys.exit(f"error: {tool} is not on PATH")
    if not path.is_file():
        sys.exit(f"error: no such file: {path}")

    fmt = args.format
    out = None if args.stdout else Path(args.out or path.with_suffix("." + fmt))
    total = duration(path)
    length = "?" if total is None else f"{short(total)} ({total:.0f} s)"
    if args.dry_run:
        device = args.device
        if device == "auto":
            device = "cuda" if cuda_works() else "cpu"
        print(f"file:     {path}\nduration: {length}\n"
              f"model:    {args.model}\nlanguage: {args.language}\n"
              f"device:   {device}\noutput:   {out or 'stdout'} ({fmt})")
        return

    start_time = time.time()
    samples = load_audio(path)
    model, device = load_model(args.model, args.device)
    print(f"Transcribing {short(total)} of audio with {args.model} on {device}...", file=sys.stderr)
    segments, _ = model.transcribe(
        samples, language=None if args.language == "auto" else args.language,
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
    finally:
        sink.write(footer(fmt))  # closes the json array on Ctrl+C or an error, too
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
        sys.exit("\nstopped")
