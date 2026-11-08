#!/usr/bin/env python3
import sys, os, re, random
import urllib.request, urllib.parse
import concurrent.futures

MAX_WORKERS = 10

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
}

EXCLUDE_PREFIXES = ("/tag:", "/page/")
EXCLUDE_EXACT = {"/4k", "/mobile", "/gifs", "/2"}
PAGES_PER_CALL = 15
PAGE_BATCH_SIZE = 8


def fetch(url, timeout=5):
    req = urllib.request.Request(url, headers=HEADERS)
    return urllib.request.urlopen(req, timeout=timeout).read().decode("utf-8", errors="ignore")


def extract_links(html):
    links = re.findall(r'href=(/[a-z0-9][a-z0-9-]*)(?=[ >])', html)
    seen = []
    for l in links:
        if l.startswith(EXCLUDE_PREFIXES) or l in EXCLUDE_EXACT:
            continue
        if l not in seen:
            seen.append(l)
    return seen


def main():
    if len(sys.argv) < 2:
        return
    query = sys.argv[1].strip()
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 24
    exclude_ids = set()
    if len(sys.argv) > 3 and sys.argv[3].strip():
        exclude_ids = {s.strip() for s in sys.argv[3].split(",") if s.strip()}
    offset_file = sys.argv[4].strip() if len(sys.argv) > 4 and sys.argv[4].strip() else None
    page_offset = 0
    if offset_file:
        try:
            with open(offset_file, "r") as f:
                page_offset = int(f.read().strip())
        except Exception:
            page_offset = 0

    browse_all = query == ""
    search_url = "https://motionbgs.com/4k/" if browse_all else ("https://motionbgs.com/search?" + urllib.parse.urlencode({"q": query}))
    try:
        req = urllib.request.Request(search_url, headers=HEADERS)
        resp = urllib.request.urlopen(req, timeout=5)
        tag_path = resp.geturl()
        html1 = resp.read().decode("utf-8", errors="ignore")
    except Exception as e:
        print(f"[motionbgs] ERREUR requete de recherche pour '{query}': {type(e).__name__}: {e}", file=sys.stderr)
        return

    is_tag_page = browse_all or "/tag:" in tag_path
    base = tag_path.rstrip("/")

    def page_url(p):
        if is_tag_page:
            return f"{base}/{p}/"
        sep = "&" if "?" in tag_path else "?"
        return f"{tag_path}{sep}page={p}"

    if page_offset == 0:
        all_links = extract_links(html1)
        covered_before = 1
    else:
        all_links = []
        covered_before = page_offset
    page_range_start = covered_before + 1
    page_range_end = covered_before + PAGES_PER_CALL
    advanced_offset = page_range_end
    print(f"[motionbgs] page 1 ({tag_path}, tag_page={is_tag_page}, offset={page_offset}) -> {len(all_links)} liens, explore pages {page_range_start}-{page_range_end}", file=sys.stderr)

    def fetch_page(p):
        try:
            return (p, extract_links(fetch(page_url(p))), None)
        except Exception as e:
            return (p, None, e)

    remaining_pages = list(range(page_range_start, page_range_end + 1))
    with concurrent.futures.ThreadPoolExecutor(max_workers=PAGE_BATCH_SIZE) as executor:
        while remaining_pages:
            batch = remaining_pages[:PAGE_BATCH_SIZE]
            remaining_pages = remaining_pages[PAGE_BATCH_SIZE:]
            results = list(executor.map(fetch_page, batch))
            batch_had_links = False
            for p, page_links, err in sorted(results, key=lambda r: r[0]):
                if err is not None or not page_links:
                    continue
                batch_had_links = True
                all_links.extend(page_links)
            if not batch_had_links:
                break
    print(f"[motionbgs] pages {page_range_start}-{advanced_offset} explorees", file=sys.stderr)

    deduped = []
    for l in all_links:
        if l not in deduped:
            deduped.append(l)

    print(f"[motionbgs] {len(deduped)} liens uniques, exclude_ids={len(exclude_ids)}", file=sys.stderr)

    random.shuffle(deduped)
    candidates = deduped[: max(limit * 3, 30)]

    def fetch_detail(link):
        detail_url = "https://motionbgs.com" + link
        try:
            return (link, fetch(detail_url), None)
        except Exception as e:
            return (link, None, e)

    found = 0
    detail_errors = 0
    no_video_meta = 0
    excluded = 0

    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = {executor.submit(fetch_detail, link) for link in candidates}
        for future in concurrent.futures.as_completed(futures):
            if found >= limit:
                for f in futures:
                    f.cancel()
                break

            link, html, err = future.result()
            if err is not None:
                detail_errors += 1
                if detail_errors <= 3:
                    print(f"[motionbgs] echec fetch {link}: {type(err).__name__}: {err}", file=sys.stderr)
                continue

            video_m = re.search(r'content=(\S+?\.mp4) property=og:video', html)
            image_m = re.search(r'content=(\S+?\.(?:jpg|jpeg|png)) property=og:image', html)
            if not video_m:
                no_video_meta += 1
                continue

            id_m = re.search(r'/media/(\d+)/', video_m.group(1))
            if not id_m:
                continue
            media_id = id_m.group(1)

            if media_id in exclude_ids:
                excluded += 1
                continue
            exclude_ids.add(media_id)

            video_url_4k = f"https://motionbgs.com/dl/4k/{media_id}"
            video_url_fallback = video_m.group(1)
            poster_url = image_m.group(1) if image_m else video_m.group(1)

            try:
                sys.stdout.write(f"{poster_url}|{video_url_4k}|{video_url_fallback}|motionbgs:{media_id}\n")
                sys.stdout.flush()
            except BrokenPipeError:
                os._exit(0)

            found += 1

    print(f"[motionbgs] fini: found={found} detail_errors={detail_errors} no_video_meta={no_video_meta} deja_exclus={excluded} candidats_total={len(candidates)}", file=sys.stderr)

    window_exhausted = found < limit
    final_offset = advanced_offset if window_exhausted else page_offset
    print(f"[motionbgs] fenetre epuisee={window_exhausted}, offset final={final_offset}", file=sys.stderr)
    if offset_file:
        try:
            with open(offset_file, "w") as f:
                f.write(str(final_offset))
        except Exception:
            pass


if __name__ == "__main__":
    try:
        main()
        sys.stdout.flush()
    except BrokenPipeError:
        os._exit(0)
    except KeyboardInterrupt:
        os._exit(1)
    except Exception:
        os._exit(1)
