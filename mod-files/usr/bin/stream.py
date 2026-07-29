#!/usr/bin/env python3
# =============================================================================
# EZ-Modmium streaming recovery-image downloader
# =============================================================================
# Original by lxrd. Refactored by EZ-Modmium to use only the Python standard
# library (urllib.request) so it runs on ChromeOS's bundled Python without
# needing `pip install requests` or a virtualenv.
#
# Functionality is identical to the original:
#   * Reads the ZIP central directory via HTTP Range requests
#   * Streams KERN-B and ROOT-A partitions directly from the remote ZIP
#     (stored or deflate-compressed) to local block devices / files
#   * Reports per-partition progress
#
# Usage:
#   stream.py --recovery-url <url> --kern-output <dev> --root-output <dev>
# =============================================================================

import sys
import struct
import subprocess
import tempfile
import os
import zlib
import time
import argparse
import urllib.request
import urllib.error


# ---------------------------------------------------------------------------
# HTTP helpers (stdlib only — replaces `requests`)
# ---------------------------------------------------------------------------

def _open_range(url, start, length=None, accept_identity=True, timeout=60):
    """Open a ranged GET request. Returns a live HTTPResponse.
    Raises RuntimeError if the server ignores the Range header (returns 200)."""
    headers = {}
    if accept_identity:
        headers["Accept-Encoding"] = "identity"
    if length is not None:
        headers["Range"] = "bytes={}-{}".format(start, start + length - 1)
    else:
        headers["Range"] = "bytes={}-".format(start)
    req = urllib.request.Request(url, headers=headers)
    r = urllib.request.urlopen(req, timeout=timeout)
    if r.status not in (206, 200):
        r.close()
        raise RuntimeError("unexpected HTTP status {} for range request".format(r.status))
    if r.status == 200:
        r.close()
        raise RuntimeError("server ignored Range header (got 200, expected 206); "
                           "cannot stream partial content from {}".format(url))
    return r


def range_get(url, start, length):
    """Fetch a byte range and return the full bytes. Raises IOError on short read."""
    r = _open_range(url, start, length)
    try:
        chunks = []
        remaining = length
        while remaining > 0:
            chunk = r.read(min(65536, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        if remaining > 0:
            raise IOError("short read: requested {} bytes from offset {}, got {}".format(
                length, start, length - remaining))
        return b"".join(chunks)
    finally:
        r.close()


def get_file_size(url):
    """HEAD request to get total Content-Length."""
    req = urllib.request.Request(url, method="HEAD",
                                 headers={"Accept-Encoding": "identity"})
    with urllib.request.urlopen(req, timeout=60) as r:
        cl = r.headers.get("Content-Length")
        if cl is None:
            raise RuntimeError("server did not return Content-Length")
        return int(cl)


def open_range_stream(url, start, chunk_size=2 * 1024 * 1024):
    """Open a streaming ranged GET from `start` to EOF.
    Returns (response, iterator)."""
    r = _open_range(url, start, length=None)

    def iter_chunks():
        while True:
            chunk = r.read(chunk_size)
            if not chunk:
                break
            yield chunk

    return r, iter_chunks()


# ---------------------------------------------------------------------------
# ZIP parsing (unchanged logic from upstream)
# ---------------------------------------------------------------------------

def find_eocd64(url, file_size):
    tail = range_get(url, file_size - 512, 512)
    loc = tail.rfind(b'PK\x06\x07')
    if loc == -1:
        raise ValueError("no ZIP64 EOCD locator")
    eocd64_off = struct.unpack_from("<Q", tail, loc + 8)[0]
    p = tail.rfind(b'PK\x06\x06')
    if p != -1 and len(tail) - p >= 56:
        eocd64 = tail[p:]
    else:
        eocd64 = range_get(url, eocd64_off, 56)
    if eocd64[:4] != b'PK\x06\x06':
        raise ValueError("bad EOCD64")
    return struct.unpack_from("<Q", eocd64, 48)[0], struct.unpack_from("<Q", eocd64, 40)[0]


def find_eocd(url, file_size):
    tail = range_get(url, file_size - 512, 512)
    p = tail.rfind(b'PK\x05\x06')
    if p == -1:
        raise ValueError("no EOCD")
    eocd = tail[p:] if len(tail) - p >= 22 else range_get(url, file_size - 22, 22)
    if eocd[:4] != b'PK\x05\x06':
        raise ValueError("bad EOCD")
    return struct.unpack_from("<I", eocd, 16)[0], struct.unpack_from("<I", eocd, 12)[0]


def parse_central_directory(url, cd_offset, cd_size):
    cd = range_get(url, cd_offset, cd_size)
    entries = []
    pos = 0
    while pos < len(cd):
        if cd[pos:pos + 4] != b'PK\x01\x02':
            break
        compress_type = struct.unpack_from("<H", cd, pos + 10)[0]
        compressed_size = struct.unpack_from("<I", cd, pos + 20)[0]
        uncompressed_size = struct.unpack_from("<I", cd, pos + 24)[0]
        fname_len = struct.unpack_from("<H", cd, pos + 28)[0]
        extra_len = struct.unpack_from("<H", cd, pos + 30)[0]
        comment_len = struct.unpack_from("<H", cd, pos + 32)[0]
        lh_offset = struct.unpack_from("<I", cd, pos + 42)[0]
        fname = cd[pos + 46:pos + 46 + fname_len].decode("utf-8", errors="replace")
        extra = cd[pos + 46 + fname_len:pos + 46 + fname_len + extra_len]
        if lh_offset == 0xFFFFFFFF or compressed_size == 0xFFFFFFFF:
            epos = 0
            while epos < len(extra) - 4:
                tag = struct.unpack_from("<H", extra, epos)[0]
                size = struct.unpack_from("<H", extra, epos + 2)[0]
                if tag == 0x0001:
                    vals, vpos = [], epos + 4
                    while vpos + 8 <= epos + 4 + size:
                        vals.append(struct.unpack_from("<Q", extra, vpos)[0])
                        vpos += 8
                    idx = 0
                    if uncompressed_size == 0xFFFFFFFF and idx < len(vals):
                        uncompressed_size = vals[idx]; idx += 1
                    if compressed_size == 0xFFFFFFFF and idx < len(vals):
                        compressed_size = vals[idx]; idx += 1
                    if lh_offset == 0xFFFFFFFF and idx < len(vals):
                        lh_offset = vals[idx]; idx += 1
                    break
                epos += 4 + size
        entries.append({
            "name": fname,
            "compress_type": compress_type,
            "uncompressed_size": uncompressed_size,
            "local_header_offset": lh_offset,
        })
        pos += 46 + fname_len + extra_len + comment_len
    return entries


def get_data_offset(url, lh_offset):
    lh = range_get(url, lh_offset, 30)
    if lh[:4] != b'PK\x03\x04':
        raise ValueError("bad local file header")
    return lh_offset + 30 + struct.unpack_from("<H", lh, 26)[0] + struct.unpack_from("<H", lh, 28)[0]


def stream_stored(url, data_offset, partitions):
    for skip, length, outfile, label in sorted(partitions, key=lambda x: x[0]):
        fetched = 0
        with open(outfile, 'wb') as f:
            while fetched < length:
                chunk = range_get(url, data_offset + skip + fetched,
                                  min(4 * 1024 * 1024, length - fetched))
                if not chunk:
                    break
                f.write(chunk)
                fetched += len(chunk)
                print("\r  {}: {}MB / {}MB".format(
                    label, fetched // (1024 * 1024), length // (1024 * 1024)),
                    end="", flush=True, file=sys.stderr)
        if fetched < length:
            raise IOError("short stream for {}: wrote {} of {} bytes".format(
                label, fetched, length))
        print(file=sys.stderr)


def stream_deflate(url, data_offset, partitions):
    partitions = sorted(partitions, key=lambda x: x[0])
    r, iter_chunks = open_range_stream(url, data_offset)
    dec = zlib.decompressobj(wbits=-15)
    decompressed = http_bytes = 0
    handles = [(skip, length, open(outfile, 'wb'), label, 0)
               for skip, length, outfile, label in partitions]
    try:
        for chunk in iter_chunks:
            http_bytes += len(chunk)
            out = dec.decompress(chunk)
            if not out:
                continue
            new_handles = []
            for skip, length, f, label, written in handles:
                if decompressed + len(out) > skip:
                    s = max(0, skip - decompressed)
                    data = out[s:s + length - written]
                    if data:
                        f.write(data)
                        written += len(data)
                        print("\r  {}: {}MB / {}MB  ({}MB downloaded)".format(
                            label, written // (1024 * 1024),
                            length // (1024 * 1024),
                            http_bytes // (1024 * 1024)),
                            end="", flush=True, file=sys.stderr)
                if written < length:
                    new_handles.append((skip, length, f, label, written))
                else:
                    print(file=sys.stderr)
                    f.close()
            handles = new_handles
            decompressed += len(out)
            if not handles:
                break
    finally:
        for _, _, f, _, _ in handles:
            f.close()
        r.close()


def fetch_partitions(url, data_offset, compress_type, partitions):
    parts = [(s * 512, n * 512, o, l) for s, n, o, l in partitions]
    if compress_type == 0:
        stream_stored(url, data_offset, parts)
    else:
        stream_deflate(url, data_offset, parts)


def get_partition_table(url, data_offset, compress_type):
    if compress_type == 0:
        return range_get(url, data_offset, 10 * 1024 * 1024)
    r, iter_chunks = open_range_stream(url, data_offset)
    try:
        dec = zlib.decompressobj(wbits=-15)
        buf = b""
        for chunk in iter_chunks:
            buf += dec.decompress(chunk)
            if len(buf) >= 10 * 1024 * 1024:
                break
    finally:
        r.close()
    return buf[:10 * 1024 * 1024]


def tpm_version(kernel_path):
    try:
        out = subprocess.check_output(["futility", "show", kernel_path],
                                       stderr=subprocess.DEVNULL, timeout=120).decode()
        for line in out.splitlines():
            if "Kernel version:" in line:
                return line.split()[-1]
    except Exception:
        pass
    return None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Stream ChromeOS recovery image partitions directly from a remote ZIP.")
    parser.add_argument("--recovery-url", required=True,
                        help="URL of the recovery image ZIP")
    parser.add_argument("--kern-output", default="kern.bin",
                        help="Output path/device for KERN-B")
    parser.add_argument("--root-output", default="root.bin",
                        help="Output path/device for ROOT-A")
    args = parser.parse_args()

    url = args.recovery_url
    kern_out = args.kern_output
    root_out = args.root_output

    t0 = time.time()
    print("Fetching remote file size...", file=sys.stderr)
    try:
        file_size = get_file_size(url)
    except Exception as e:
        sys.exit("error: could not get file size: {}".format(e))
    print("size: {}MB".format(file_size // (1024 * 1024)), file=sys.stderr)

    try:
        cd_offset, cd_size = find_eocd64(url, file_size)
    except ValueError:
        try:
            cd_offset, cd_size = find_eocd(url, file_size)
        except ValueError as e:
            sys.exit("error: {}".format(e))

    entries = parse_central_directory(url, cd_offset, cd_size)
    if not entries:
        sys.exit("error: empty zip")

    entry = entries[0]
    ctype = entry['compress_type']
    if ctype not in (0, 8):
        sys.exit("error: unsupported compress type {}".format(ctype))

    print("{}  {}  {}MB".format(
        entry['name'],
        'stored' if ctype == 0 else 'deflate',
        entry['uncompressed_size'] // (1024 * 1024)), file=sys.stderr)

    data_offset = get_data_offset(url, entry['local_header_offset'])

    pt = get_partition_table(url, data_offset, ctype)
    with tempfile.NamedTemporaryFile(delete=False, suffix=".bin") as f:
        f.write(pt)
        pt_tmp = f.name
    try:
        subprocess.run(["truncate", "-s", "10G", pt_tmp], check=True, timeout=120)
        def find_part(label):
            out = subprocess.check_output(["cgpt", "show", pt_tmp],
                                           stderr=subprocess.DEVNULL, timeout=60).decode()
            for line in out.splitlines():
                if label in line:
                    p = line.split()
                    num = int(p[2])
                    start = int(subprocess.check_output(
                        ["cgpt", "show", "-b", "-i", str(num), pt_tmp],
                        stderr=subprocess.DEVNULL, timeout=60).decode().strip())
                    size = int(subprocess.check_output(
                        ["cgpt", "show", "-s", "-i", str(num), pt_tmp],
                        stderr=subprocess.DEVNULL, timeout=60).decode().strip())
                    return start, size
            return None, None

        kern_start, kern_sectors = find_part("KERN-B")
        root_start, root_sectors = find_part("ROOT-A")
    finally:
        os.unlink(pt_tmp)

    if not kern_start:
        sys.exit("error: KERN-B not found")
    if not root_start:
        sys.exit("error: ROOT-A not found")
    print("ROOT-A: {}MB  KERN-B: {}MB".format(
        root_sectors * 512 // (1024 * 1024),
        kern_sectors * 512 // (1024 * 1024)), file=sys.stderr)

    fetch_partitions(url, data_offset, ctype, [
        (root_start, root_sectors, root_out, "ROOT-A"),
        (kern_start, kern_sectors, kern_out, "KERN-B"),
    ])

    tpm = tpm_version(kern_out)
    if tpm:
        print("tpm version: {}".format(tpm))
    print("done in {:.1f}s".format(time.time() - t0), file=sys.stderr)


if __name__ == "__main__":
    main()
