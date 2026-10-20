"""Local SFTP test server that accepts a key, for the network plugin tests.

Usage: python serve_sftp_keys.py ROOT PORT CLIENT_KEY_FILE
A key pair is written to CLIENT_KEY_FILE (RSA, PEM) and CLIENT_KEY_FILE.pub; it
may log in as "test". The server lists the folder ROOT and nothing more.
"""
import os
import socket
import sys
import threading

import paramiko

root = sys.argv[1]
port = int(sys.argv[2])
client_key = paramiko.RSAKey.generate(2048)
client_key.write_private_key_file(sys.argv[3])
with open(sys.argv[3] + ".pub", "w") as f:
    f.write("%s %s\n" % (client_key.get_name(), client_key.get_base64()))
host_key = paramiko.RSAKey.generate(2048)


class Sftp(paramiko.SFTPServerInterface):
    def list_folder(self, path):
        out = []
        for name in os.listdir(root):
            attrs = paramiko.SFTPAttributes.from_stat(os.stat(os.path.join(root, name)))
            attrs.filename = name
            out.append(attrs)
        return out

    def stat(self, path):
        return paramiko.SFTPAttributes.from_stat(os.stat(root))

    lstat = stat


class Server(paramiko.ServerInterface):
    def check_auth_publickey(self, username, key):
        if username == "test" and key == client_key:
            return paramiko.AUTH_SUCCESSFUL
        return paramiko.AUTH_FAILED

    def get_allowed_auths(self, username):
        return "publickey"

    def check_channel_request(self, kind, chanid):
        return paramiko.OPEN_SUCCEEDED


def serve(conn):
    transport = paramiko.Transport(conn)
    transport.add_server_key(host_key)
    transport.set_subsystem_handler("sftp", paramiko.SFTPServer, Sftp)
    transport.start_server(server=Server())


listener = socket.socket()
listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
listener.bind(("127.0.0.1", port))
listener.listen(5)
print("ready", flush=True)
while True:
    connection, _ = listener.accept()
    threading.Thread(target=serve, args=(connection,), daemon=True).start()
