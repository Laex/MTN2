"""Local WebDAV test server for the network plugin tests.

Usage: python serve_dav.py ROOT PORT
Basic login test / secret on 127.0.0.1.
"""
import sys

from cheroot import wsgi
from wsgidav.wsgidav_app import WsgiDAVApp


def main():
    root = sys.argv[1]
    port = int(sys.argv[2])
    config = {
        "host": "127.0.0.1",
        "port": port,
        "provider_mapping": {"/": root},
        "simple_dc": {"user_mapping": {"*": {"test": {"password": "secret"}}}},
        "http_authenticator": {"domain_controller": None, "accept_basic": True, "accept_digest": False,
                               "default_to_digest": False},
        "verbose": 0,
        "logging": {"enable": False},
        "lock_storage": False,
    }
    app = WsgiDAVApp(config)
    server = wsgi.Server(("127.0.0.1", port), app)
    print("ready", flush=True)
    try:
        server.start()
    finally:
        server.stop()


if __name__ == "__main__":
    main()
