"""Local S3 test server (moto) for the network plugin tests.

Usage: python serve_s3.py PORT
Any access key works; requests are not verified, which is enough to check that
the plugin builds correct S3 REST calls.
"""
import sys

from moto.server import ThreadedMotoServer


def main():
    port = int(sys.argv[1])
    server = ThreadedMotoServer(ip_address="127.0.0.1", port=port, verbose=False)
    server.start()
    print("ready", flush=True)
    try:
        server._thread.join()
    except KeyboardInterrupt:
        server.stop()


if __name__ == "__main__":
    main()
