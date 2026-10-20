"""Local SFTP test server for the network plugin tests.

Usage: python serve_sftp.py ROOT PORT
Password login test / secret on 127.0.0.1; the host key is fixed per run and
its SHA-256 fingerprint is printed after "ready". SCP is served as well.
"""
import asyncio
import base64
import hashlib
import os
import sys

import asyncssh


class Server(asyncssh.SSHServer):
    def begin_auth(self, username):
        return True

    def password_auth_supported(self):
        return True

    def validate_password(self, username, password):
        return username == "test" and password == "secret"


def make_sftp_server(root):
    def factory(conn):
        return asyncssh.SFTPServer(conn, chroot=root.encode())
    return factory


async def main():
    root = os.path.abspath(sys.argv[1])
    port = int(sys.argv[2])
    key = asyncssh.generate_private_key(os.environ.get("SFTP_KEY_TYPE", "ssh-rsa"), key_size=2048)
    blob = key.export_public_key("openssh").split()[1]
    fingerprint = base64.b64encode(hashlib.sha256(base64.b64decode(blob)).digest()).decode().rstrip("=")
    await asyncssh.create_server(
        Server, "127.0.0.1", port, server_host_keys=[key],
        sftp_factory=make_sftp_server(root), allow_scp=True)
    print("ready", fingerprint, flush=True)
    await asyncio.Event().wait()


if __name__ == "__main__":
    asyncio.run(main())
