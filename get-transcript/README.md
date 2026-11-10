# Get Transcript

A script that transcribes an audio or video file on your machine with [faster-whisper](https://github.com/SYSTRAN/faster-whisper). The file never leaves your machine. The only network access is the first download of the model from Hugging Face.

## Requirements

- [`uv`](https://docs.astral.sh/uv/). The script is a `uv` script with inline dependencies, so `uv` installs `faster-whisper` and `numpy` in a cached environment on the first run.
- `ffmpeg` and `ffprobe` on your `PATH`.
- About 1.5 GB of disk space for the default model, `distil-large-v3`.
- Optional: an NVIDIA GPU with a working driver. Without one, the script runs on the CPU.

## Usage

To transcribe a file, run the script with the file path:

```bash
./get-transcript.py "meeting.mp4"
```

The script writes `meeting.txt` next to the input. Each line starts with the segment start time:

```text
[00:00] Good morning, everyone. Let's start with the release status.
[00:06] The build passed last night, so we can ship today.
```

To write subtitles instead, set `--format`:

```bash
./get-transcript.py "meeting.mp4" --format srt
```

To check the duration, model, device, and output path without a transcription, use `--dry-run`:

```bash
./get-transcript.py --dry-run "meeting.mp4"
```

To run the script from anywhere, copy it to a directory on your `PATH`:

```bash
cp get-transcript.py ~/.local/bin/get-transcript
```

## Options

| Option | Default | Description |
| --- | --- | --- |
| `-o OUT` | `FILE` with the format's extension | The output file. |
| `--stdout` | Off | Print the transcript to stdout instead of a file. |
| `--format` | `txt` | `txt`, `srt`, `vtt`, or `json`. The `json` format is a list of objects with `start`, `end`, and `text`. |
| `--model` | `distil-large-v3` | Any faster-whisper model name. `distil-large-v3` is English only. Use `large-v3` for other languages. |
| `--language` | `en` | A language code, or `auto` to detect the language. |
| `--device` | `auto` | `auto` uses `cuda` when a GPU works, and `cpu` otherwise. |
| `--dry-run` | Off | Show the plan and transcribe nothing. |
| `--self-test` | Off | Check the timestamp, `srt`, and `vtt` formatters. |

## How it works

1. `ffprobe` reads the duration.
2. `ffmpeg` decodes the audio to 16 kHz mono PCM in memory. The script does not use PyAV, because some PyAV versions reject an argument that `faster_whisper.decode_audio` passes.
3. faster-whisper transcribes the samples with voice activity detection on. On the GPU it uses `float16`. On the CPU it uses `int8` and all CPU cores.
4. The script writes each segment as it arrives. If you stop the script with Ctrl+C, the output file keeps the segments written so far.

On a 20-core CPU, a 14-minute recording takes about 90 seconds after the model is in the cache.

## Limitations

- The transcript has no speaker labels.
- Names and product terms can come out wrong, for example "Kubernetes" as "Cooper Netties". Check names against the recording.
