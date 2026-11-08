#!/usr/bin/env python3
"""Produce screen-sized copies of video wallpapers.

A hardware decoder allocates its surface pool from the video's encoded
resolution, not from the size it ends up drawn at, so feeding it a 4K file on a
2880x1800 panel costs ~260MB of GTT/VRAM for pixels that are scaled away before
they reach the screen. Transcoding once, to the smallest size that still covers
the panel, buys that memory back for every later playback.

Usage:
    transcode.py resolve <source> <cache_dir> <screen_w> <screen_h> <fps>
        Print the path to play: the cached copy when it is ready, otherwise the
        original. Never blocks.

    transcode.py build <source> <cache_dir> <screen_w> <screen_h> <fps>
        Produce the cached copy (slow). Prints its path.

    transcode.py prune <cache_dir> <screen_w> <screen_h> <fps>
        Drop cached copies that no longer match these settings.
"""

import hashlib
import json
import os
import subprocess
import sys

# Transcoding to something barely smaller costs minutes of CPU to save a few MB.
MIN_PIXEL_GAIN = 0.90

VAAPI_DEVICE = os.environ.get("QS_VAAPI_DEVICE", "/dev/dri/renderD128")

# Only used when the GPU encoder refuses a file. Capped so a background rebuild
# can never monopolise the machine or cook a laptop the way an unbounded x264
# run over 4K does.
CPU_FALLBACK_THREADS = max(1, min(4, (os.cpu_count() or 4) // 4))


def cache_root(cache_dir):
    return os.path.join(cache_dir, "transcoded")


def probe(source):
    try:
        out = subprocess.check_output([
            "ffprobe", "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height,r_frame_rate",
            "-of", "json", source,
        ], stderr=subprocess.DEVNULL, timeout=20)
        stream = json.loads(out)["streams"][0]
        num, _, den = stream["r_frame_rate"].partition("/")
        den = float(den) if den else 1.0
        fps = float(num) / den if den else 0.0
        return int(stream["width"]), int(stream["height"]), fps
    except Exception:
        return None


def even(n):
    """H.264 needs even dimensions."""
    return max(2, int(n) // 2 * 2)


def target_geometry(src_w, src_h, screen_w, screen_h):
    """Crop the source to the panel's aspect ratio, then size it to the panel.

    The engine draws wallpapers with PreserveAspectCrop, so whatever falls
    outside the panel's aspect ratio is discarded at display time anyway. Baking
    that crop into the file means those pixels are never decoded: a 16:9 source
    on this 16:10 panel drops to the panel's exact resolution instead of the
    larger size needed to cover it, which is another ~10% off the surface pool.

    Returns (crop_w, crop_h, out_w, out_h), or None when the source is already
    small enough that re-encoding would only cost quality.
    """
    if src_w <= 0 or src_h <= 0 or screen_w <= 0 or screen_h <= 0:
        return None

    src_ar = src_w / src_h
    screen_ar = screen_w / screen_h
    if src_ar > screen_ar:
        crop_h, crop_w = src_h, src_h * screen_ar  # trim the sides
    else:
        crop_w, crop_h = src_w, src_w / screen_ar  # trim top and bottom
    crop_w, crop_h = even(crop_w), even(crop_h)

    # Never upscale: a source smaller than the panel gains nothing from a re-encode.
    if crop_w <= screen_w or crop_h <= screen_h:
        return None
    return crop_w, crop_h, even(screen_w), even(screen_h)


def plan(source, screen_w, screen_h, fps_cap):
    """Return (crop_w, crop_h, out_w, out_h, out_fps), or None when not worth it."""
    info = probe(source)
    if not info:
        return None
    src_w, src_h, src_fps = info

    geom = target_geometry(src_w, src_h, screen_w, screen_h)
    if geom:
        crop_w, crop_h, out_w, out_h = geom
    else:
        crop_w, crop_h, out_w, out_h = src_w, src_h, src_w, src_h
    out_fps = min(src_fps, fps_cap) if src_fps > 0 else fps_cap

    # Compare against the pixels the panel actually shows, not the whole source:
    # the cropped-away part costs nothing at display time either way.
    shown_before = min(src_w * src_h, (crop_w * crop_h))
    pixel_ratio = (out_w * out_h) / shown_before if shown_before else 1.0
    fps_ratio = (out_fps / src_fps) if src_fps > 0 else 1.0
    if pixel_ratio * fps_ratio > MIN_PIXEL_GAIN:
        return None
    return crop_w, crop_h, out_w, out_h, out_fps


def cache_key(source, crop_w, crop_h, out_w, out_h, out_fps):
    try:
        st = os.stat(source)
        stamp = f"{int(st.st_mtime)}:{st.st_size}"
    except OSError:
        stamp = "0:0"
    raw = f"{os.path.abspath(source)}|{stamp}|{crop_w}x{crop_h}->{out_w}x{out_h}@{out_fps}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:20]


def cached_path(cache_dir, key):
    return os.path.join(cache_root(cache_dir), f"{key}.mp4")


def settings_tag(screen_w, screen_h, fps):
    return hashlib.sha256(f"{screen_w}x{screen_h}@{fps}".encode("utf-8")).hexdigest()[:8]


def resolve(source, cache_dir, screen_w, screen_h, fps):
    spec = plan(source, screen_w, screen_h, fps)
    if not spec:
        return source
    out = cached_path(cache_dir, cache_key(source, *spec))
    # A build in flight writes to <out>.part, so a bare <out> is always complete.
    if os.path.exists(out) and os.path.getsize(out) > 4096:
        return out
    return source


def build(source, cache_dir, screen_w, screen_h, fps):
    spec = plan(source, screen_w, screen_h, fps)
    if not spec:
        return source
    crop_w, crop_h, out_w, out_h, out_fps = spec
    key = cache_key(source, *spec)
    out = cached_path(cache_dir, key)
    if os.path.exists(out) and os.path.getsize(out) > 4096:
        return out

    os.makedirs(cache_root(cache_dir), exist_ok=True)
    marker = os.path.join(cache_root(cache_dir), f"{key}.{settings_tag(screen_w, screen_h, fps)}.tag")
    part = f"{out}.part"

    # H.264 is the one codec every VCN/VAAPI generation decodes in hardware; a
    # denser codec that fell back to software decoding would cost far more RAM at
    # playback than the smaller file ever saves.
    #
    # Encoding runs on the GPU's video engine, never on the CPU. An x264 pass over
    # 4K saturates all 16 cores and heats a thin laptop hard enough to trip a
    # thermal cutoff; the VAAPI path costs about one core and ~1C, and is roughly
    # 5x faster. The CPU fallback below is deliberately throttled for the same
    # reason and only runs if the GPU refuses the file.
    gpu_cmd = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-hwaccel", "vaapi", "-hwaccel_device", VAAPI_DEVICE,
        "-hwaccel_output_format", "vaapi",
        "-i", source,
        "-vf", (f"fps={out_fps},"
                f"crop={crop_w}:{crop_h},"
                f"scale_vaapi=w={out_w}:h={out_h}"),
        "-c:v", "h264_vaapi", "-qp", "22",
        # The ".part" suffix hides the container from ffmpeg's extension sniffing.
        "-an", "-f", "mp4", part,
    ]
    cpu_cmd = [
        "nice", "-n", "19",
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-threads", str(CPU_FALLBACK_THREADS),
        "-i", source,
        "-vf", (f"fps={out_fps},"
                f"crop={crop_w}:{crop_h},"
                f"scale={out_w}:{out_h}:flags=bilinear"),
        "-c:v", "libx264", "-crf", "22", "-preset", "veryfast",
        "-x264-params", f"threads={CPU_FALLBACK_THREADS}",
        "-pix_fmt", "yuv420p",
        "-an", "-f", "mp4", part,
    ]

    for cmd in (gpu_cmd, cpu_cmd):
        try:
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=1800)
            break
        except Exception:
            if os.path.exists(part):
                os.remove(part)
    else:
        return source

    if not os.path.exists(part):
        return source

    os.replace(part, out)
    open(marker, "w").close()
    return out


def prune(cache_dir, screen_w, screen_h, fps):
    root = cache_root(cache_dir)
    if not os.path.isdir(root):
        return 0
    keep_tag = settings_tag(screen_w, screen_h, fps)
    live = {n[:20] for n in os.listdir(root) if n.endswith(f".{keep_tag}.tag")}
    removed = 0
    for name in os.listdir(root):
        if name.endswith(".tag"):
            if not name.endswith(f".{keep_tag}.tag"):
                os.remove(os.path.join(root, name))
                removed += 1
            continue
        if name.endswith(".mp4") and name[:-4] not in live:
            os.remove(os.path.join(root, name))
            removed += 1
    return removed


VIDEO_EXTS = (".mp4", ".mkv", ".mov", ".webm")


def worker(src_dir, cache_dir, screen_w, screen_h, fps, index_cache_dir=None):
    """Build every missing copy, one at a time, then let the indexer republish.

    Encoding a 4K clip takes a minute or two, so this never runs inline with a
    folder scan; the picker keeps working off the originals until copies land.
    """
    lock_path = os.path.join(cache_root(cache_dir), ".worker.lock")
    os.makedirs(cache_root(cache_dir), exist_ok=True)
    import fcntl
    with open(lock_path, "w") as lock_fd:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except (BlockingIOError, OSError):
            return 0  # another worker is already chewing through the queue

        built = 0
        for scan in (src_dir, os.path.join(src_dir, "photo"), os.path.join(src_dir, "video")):
            try:
                names = sorted(os.listdir(scan))
            except OSError:
                continue
            for name in names:
                if not name.lower().endswith(VIDEO_EXTS):
                    continue
                path = os.path.join(scan, name)
                if not os.path.isfile(path):
                    continue
                if resolve(path, cache_dir, screen_w, screen_h, fps) != path:
                    continue  # already built
                if build(path, cache_dir, screen_w, screen_h, fps) != path:
                    built += 1

        prune(cache_dir, screen_w, screen_h, fps)
        if built and index_cache_dir:
            # Re-annotate the published index so the running shell picks the
            # new copies up (it watches current_index.json).
            published = os.path.join(index_cache_dir, "current_index.json")
            try:
                with open(published, encoding="utf-8") as f:
                    data = json.load(f)
                annotate_items(data, cache_dir, screen_w, screen_h, fps)
                tmp = published + ".tmp"
                with open(tmp, "w", encoding="utf-8") as f:
                    json.dump(data, f)
                os.replace(tmp, published)
            except (OSError, ValueError):
                pass
        return built


def annotate_items(data, per_dir_cache, screen_w, screen_h, fps):
    """Point video items at their screen-sized copy; True if one is missing."""
    missing = False
    for item in data.get("items", []):
        if not item.get("isVideo") or not item.get("filePath"):
            continue
        playable = resolve(item["filePath"], per_dir_cache, screen_w, screen_h, fps)
        if playable != item["filePath"]:
            item["transcodedPath"] = playable
        else:
            item.pop("transcodedPath", None)
            missing = True
    return missing


def annotate(src_dir, cache_root, screen_w, screen_h, fps):
    """Filter for serpantinum-core's wallpaper index (stdin -> stdout): adds
    transcodedPath to videos, republishes current_index.json, and starts the
    background worker for videos that have no copy yet. The old Python
    indexer did this before serpantinum-core replaced it."""
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except ValueError:
        sys.stdout.write(raw)
        return 0
    if screen_w <= 0 or screen_h <= 0:
        for item in data.get("items", []):
            item.pop("transcodedPath", None)
        sys.stdout.write(json.dumps(data))
        return 0
    dir_hash = data.get("dirHash") or hashlib.sha256(os.path.abspath(src_dir).encode("utf-8")).hexdigest()[:16]
    per_dir_cache = os.path.join(cache_root, "dirs", dir_hash)
    missing = annotate_items(data, per_dir_cache, screen_w, screen_h, fps)
    out = json.dumps(data)
    try:
        published = os.path.join(cache_root, "current_index.json")
        with open(published + ".tmp", "w", encoding="utf-8") as f:
            f.write(out)
        os.replace(published + ".tmp", published)
    except OSError:
        pass
    if missing:
        subprocess.Popen(
            [sys.executable, os.path.abspath(__file__), "worker", src_dir, per_dir_cache,
             str(screen_w), str(screen_h), str(fps), cache_root],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True)
    sys.stdout.write(out)
    return 0


def main():
    if len(sys.argv) < 2:
        return 1
    action = sys.argv[1]

    if action == "annotate":
        return annotate(sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), float(sys.argv[6]))

    if action == "worker":
        src_dir, cache_dir = sys.argv[2], sys.argv[3]
        sw, sh, fps = int(sys.argv[4]), int(sys.argv[5]), float(sys.argv[6])
        root_cache = sys.argv[7] if len(sys.argv) > 7 else None
        print(worker(src_dir, cache_dir, sw, sh, fps, root_cache))
        return 0

    if action == "prune":
        cache_dir, sw, sh, fps = sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5])
        print(prune(cache_dir, sw, sh, fps))
        return 0

    source, cache_dir = sys.argv[2], sys.argv[3]
    sw, sh, fps = int(sys.argv[4]), int(sys.argv[5]), float(sys.argv[6])

    if action == "resolve":
        print(resolve(source, cache_dir, sw, sh, fps))
    elif action == "build":
        print(build(source, cache_dir, sw, sh, fps))
    else:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
