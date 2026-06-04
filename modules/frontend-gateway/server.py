import datetime
import hashlib
import hmac
import os
import posixpath
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ENDPOINT = os.environ["S3_ENDPOINT"].rstrip("/")
REGION = os.environ["S3_REGION"]
BUCKET = os.environ["S3_BUCKET"]
PREFIX = os.environ.get("S3_PREFIX", "").strip("/")
ACCESS_KEY = os.environ["S3_ACCESS_KEY"]
SECRET_KEY = os.environ["S3_SECRET_KEY"]
ORIGIN = urllib.parse.urlparse(ENDPOINT)
HOST = ORIGIN.netloc
EMPTY_HASH = hashlib.sha256(b"").hexdigest()
SKIP_HEADERS = {
    "connection",
    "content-encoding",
    "transfer-encoding",
    "www-authenticate",
}


def sign(key, msg):
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def signing_key(secret, date):
    key = ("AWS4" + secret).encode("utf-8")
    key = sign(key, date)
    key = sign(key, REGION)
    key = sign(key, "s3")
    return sign(key, "aws4_request")


def normalize_key(path):
    clean = urllib.parse.unquote(path.split("?", 1)[0])
    clean = posixpath.normpath("/" + clean).lstrip("/")
    if clean in ("", "."):
        clean = "index.html"
    if PREFIX:
        clean = f"{PREFIX}/{clean}"
    return clean


def signed_request(key):
    now = datetime.datetime.utcnow()
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    date_stamp = now.strftime("%Y%m%d")
    canonical_uri = urllib.parse.quote(f"/{BUCKET}/{key}", safe="/~")
    canonical_headers = (
        f"host:{HOST}\n"
        f"x-amz-content-sha256:{EMPTY_HASH}\n"
        f"x-amz-date:{amz_date}\n"
    )
    signed_headers = "host;x-amz-content-sha256;x-amz-date"
    canonical_request = "\n".join([
        "GET",
        canonical_uri,
        "",
        canonical_headers,
        signed_headers,
        EMPTY_HASH,
    ])
    scope = f"{date_stamp}/{REGION}/s3/aws4_request"
    string_to_sign = "\n".join([
        "AWS4-HMAC-SHA256",
        amz_date,
        scope,
        hashlib.sha256(canonical_request.encode("utf-8")).hexdigest(),
    ])
    signature = hmac.new(
        signing_key(SECRET_KEY, date_stamp),
        string_to_sign.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    auth = (
        "AWS4-HMAC-SHA256 "
        f"Credential={ACCESS_KEY}/{scope}, "
        f"SignedHeaders={signed_headers}, "
        f"Signature={signature}"
    )
    url = f"{ENDPOINT}{canonical_uri}"
    return urllib.request.Request(url, headers={
        "Authorization": auth,
        "Host": HOST,
        "x-amz-content-sha256": EMPTY_HASH,
        "x-amz-date": amz_date,
    })


def fetch(key):
    return urllib.request.urlopen(signed_request(key), timeout=20)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/nginx-health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok\n")
            return

        key = normalize_key(self.path)
        try:
            response = fetch(key)
        except urllib.error.HTTPError as err:
            if err.code in (403, 404) and not key.endswith("index.html"):
                response = fetch(f"{PREFIX}/index.html" if PREFIX else "index.html")
            else:
                self.send_response(err.code)
                self.end_headers()
                self.wfile.write(err.read())
                return

        with response:
            self.send_response(response.status)
            for header, value in response.headers.items():
                if header.lower() not in SKIP_HEADERS:
                    self.send_header(header, value)
            self.end_headers()
            self.wfile.write(response.read())

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)


ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
