#!/usr/bin/env python3
import sys, os, re, random
import urllib.request, urllib.parse
import concurrent.futures

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
}

PAGES_PER_CALL = 15
PAGE_BATCH_SIZE = 8
MAX_WORKERS = 10
DOWNLOAD_BASE = "https://go.moewalls.com/download.php?video="


def fetch(url, timeout=5):
    req = urllib.request.Request(url, headers=HEADERS)
    return urllib.request.urlopen(req, timeout=timeout).read().decode("utf-8", errors="ignore")


def extract_detail_links(html):
    links = re.findall(r'href="(https://moewalls\.com/[a-z0-9-]+/[a-z0-9-]+-live-wallpaper/)"', html)
    seen = []
    for l in links:
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
    search_url = "https://moewalls.com/" if browse_all else ("https://moewalls.com/?" + urllib.parse.urlencode({"s": query}))
    try:
        html1 = fetch(search_url)
    except Exception as e:
        print(f"[moewalls] ERREUR requete de recherche pour '{query}': {type(e).__name__}: {e}", file=sys.stderr)
        return

    if page_offset == 0:
        all_links = extract_detail_links(html1)
        covered_before = 1
    else:
        all_links = []
        covered_before = page_offset
    page_range_start = covered_before + 1
    page_range_end = covered_before + PAGES_PER_CALL
    advanced_offset = page_range_end
    print(f"[moewalls] page 1 (offset={page_offset}) -> {len(all_links)} liens, explore pages {page_range_start}-{page_range_end}", file=sys.stderr)

    def build_page_url(p):
        if browse_all:
            return f"https://moewalls.com/page/{p}/"
        return f"https://moewalls.com/page/{p}/?" + urllib.parse.urlencode({"s": query})

    def fetch_page(p):
        try:
            return (p, extract_detail_links(fetch(build_page_url(p))), None)
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
    print(f"[moewalls] pages {page_range_start}-{advanced_offset} explorees", file=sys.stderr)

    deduped = list(dict.fromkeys(all_links))
    print(f"[moewalls] {len(deduped)} liens uniques, exclude_ids={len(exclude_ids)}", file=sys.stderr)

    random.shuffle(deduped)
    candidates = deduped[: max(limit * 3, 30)]

    def fetch_detail(link):
        try:
            return (link, fetch(link), None)
        except Exception as e:
            return (link, None, e)

    found = 0
    detail_errors = 0
    no_download_meta = 0
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
                    print(f"[moewalls] echec fetch {link}: {type(err).__name__}: {err}", file=sys.stderr)
                continue

            dl_m = re.search(r'id="moe-download"\s+data-id\s*=\s*"(\d+)"\s+data-url\s*=\s*"([^"]+)"', html)
            if not dl_m:
                no_download_meta += 1
                continue

            media_id = dl_m.group(1)
            data_url = dl_m.group(2)

            if media_id in exclude_ids:
                excluded += 1
                continue
            exclude_ids.add(media_id)

            image_m = re.search(r'property="og:image"\s+content="([^"]+)"', html)
            poster_url = image_m.group(1) if image_m else ""
            if not poster_url:
                continue

            video_url = DOWNLOAD_BASE + data_url

            try:
                sys.stdout.write(f"{poster_url}|{video_url}|{video_url}|moewalls:{media_id}\n")
                sys.stdout.flush()
            except BrokenPipeError:
                os._exit(0)

            found += 1

    print(f"[moewalls] fini: found={found} detail_errors={detail_errors} no_download_meta={no_download_meta} deja_exclus={excluded} candidats_total={len(candidates)}", file=sys.stderr)

    window_exhausted = found < limit
    final_offset = advanced_offset if window_exhausted else page_offset
    print(f"[moewalls] fenetre epuisee={window_exhausted}, offset final={final_offset}", file=sys.stderr)
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
