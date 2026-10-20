"""Local FTP / FTPS test server for the network plugin tests.

Usage: python serve_ftp.py ROOT PORT [--tls]
Login test / secret; anonymous login is read only. Passive data ports 60000-60020 on 127.0.0.1.
"""
import os
import sys
import tempfile

from pyftpdlib.authorizers import DummyAuthorizer
from pyftpdlib.servers import FTPServer


def make_cert(directory):
    from OpenSSL import crypto
    key = crypto.PKey()
    key.generate_key(crypto.TYPE_RSA, 2048)
    cert = crypto.X509()
    cert.get_subject().CN = "localhost"
    cert.set_serial_number(1)
    cert.gmtime_adj_notBefore(0)
    cert.gmtime_adj_notAfter(24 * 3600)
    cert.set_issuer(cert.get_subject())
    cert.set_pubkey(key)
    cert.sign(key, "sha256")
    path = os.path.join(directory, "ftps.pem")
    with open(path, "wb") as f:
        f.write(crypto.dump_privatekey(crypto.FILETYPE_PEM, key))
        f.write(crypto.dump_certificate(crypto.FILETYPE_PEM, cert))
    return path


def main():
    root = sys.argv[1]
    port = int(sys.argv[2])
    use_tls = "--tls" in sys.argv
    authorizer = DummyAuthorizer()
    authorizer.add_user("test", "secret", root, perm="elradfmwMT")
    authorizer.add_anonymous(root, perm="elr")
    if use_tls:
        from pyftpdlib.handlers import TLS_FTPHandler
        handler = TLS_FTPHandler
        handler.certfile = make_cert(tempfile.gettempdir())
        handler.tls_control_required = True
        handler.tls_data_required = True
    else:
        from pyftpdlib.handlers import FTPHandler
        handler = FTPHandler
    handler.authorizer = authorizer
    handler.passive_ports = range(60000, 60021)
    handler.encoding = "utf-8"
    server = FTPServer(("127.0.0.1", port), handler)
    print("ready", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
