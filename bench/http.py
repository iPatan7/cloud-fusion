"""Sends HTTP requests to one URL with several parallel clients and reports the
throughput and the latency percentiles.

    python3 bench/http.py http://192.168.122.242:8000/ --clients 8 --requests 800
"""
import argparse
import http.client
import statistics
import threading
import time
import urllib.parse

ap = argparse.ArgumentParser()
ap.add_argument("url")
ap.add_argument("--clients", type=int, default=8)
ap.add_argument("--requests", type=int, default=800)
ap.add_argument("--label", default="")
a = ap.parse_args()
u = urllib.parse.urlsplit(a.url)
path = u.path or "/"
lat, errors, lock = [], [0], threading.Lock()
per_client = a.requests // a.clients


def client():
    conn = http.client.HTTPConnection(u.hostname, u.port or 80, timeout=30)
    for _ in range(per_client):
        t = time.perf_counter()
        try:
            conn.request("GET", path)
            r = conn.getresponse()
            r.read()
            ok = r.status == 200
        except OSError:
            ok = False
            conn.close()
            conn = http.client.HTTPConnection(u.hostname, u.port or 80, timeout=30)
        dt = time.perf_counter() - t
        with lock:
            (lat.append(dt) if ok else None)
            errors[0] += 0 if ok else 1
    conn.close()


# warm-up: let every gunicorn worker load the application once
for _ in range(4):
    c = http.client.HTTPConnection(u.hostname, u.port or 80, timeout=30)
    c.request("GET", path); c.getresponse().read(); c.close()

threads = [threading.Thread(target=client) for _ in range(a.clients)]
t0 = time.perf_counter()
for t in threads:
    t.start()
for t in threads:
    t.join()
wall = time.perf_counter() - t0
lat.sort()
q = lambda p: lat[min(len(lat) - 1, int(p * len(lat)))] * 1000
print(f"{a.label or a.url}: {len(lat)} OK, {errors[0]} failed, {len(lat) / wall:.1f} req/s, "
      f"p50 {q(0.50):.1f} ms, p95 {q(0.95):.1f} ms, mean {statistics.mean(lat) * 1000:.1f} ms")
