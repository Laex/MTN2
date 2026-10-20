# Network connections

The plugin opens remote servers as folders of the panels: **FTP**, **FTPS**, **SFTP**, **SCP**, **WebDAV** (HTTP and HTTPS) and **S3** (Amazon S3 and compatible services). Everything the panels do with folders works on them: browsing, F3 / F4, copy and move (F5 / F6) in both directions and between two servers, rename, delete, make folder.

## Opening a connection

* **Alt+F1 / Alt+F2** – the Change Drive list now has the item **Network connections** (the next free digit). **Ctrl+Shift+B** and **Commands > Network connections** open the same list.
* In the list of connections: **F7** adds a connection, **F4** edits the one under the cursor, **F8** removes it. **Enter** opens it.
* A saved connection can be typed as an address too: `net://Name/folder`, or the direct form `ftp://user@host:21/folder`, `ftps://`, `nsftp://`, `scp://`, `dav://`, `davs://`, `s3://bucket/key`. A direct address uses the saved connection of the same server for the login. Do not put a password into an address: addresses are kept in the folder history.

## The connection dialog

| Field | Meaning |
|---|---|
| Protocol | FTP, FTPS (explicit TLS; implicit TLS under *More*), SFTP and SCP (SSH), WebDAV, WebDAV over HTTPS, S3 |
| Server, port | Host name or address; the port is empty for the usual one |
| User / access key | Login name. For S3 the access key id; the secret key goes into the password field |
| Log in with | Password, key file (with its passphrase), the SSH agent, anonymous (FTP) |
| Start folder | Where the connection opens. For S3 start with `/bucket` |
| Save the password | Keeps the password sealed for the Windows user; without it the password is asked once per run |

*More...* holds the passive mode of FTP, implicit TLS, certificate checking, the code page of file names, a proxy (`socks5h://host:1080`, `http://host:3128`), the timeout, the S3 region and path style, and the base path of a WebDAV share.

## Trust questions

* **Unknown server key** (SFTP / SCP): the SHA-256 fingerprint is shown; compare it with the one of the server and trust it once. The key is saved with the connection and checked on every login. A **changed** key is a warning: someone may be between you and the server.
* **Untrusted certificate** (FTPS, HTTPS): you may continue for this run; fix the certificate or turn the check off in the connection if the server is yours.

## Notes

* SFTP here is separate from the built-in `sftp://` of the program (which uses the system `ssh` and keys only): connections of this plugin ask for passwords, check host keys and show progress. Use `nsftp://` for a direct address.
* SCP moves file data over SCP; folders are listed through the SFTP service of the same server.
* S3 folders are key prefixes: renaming a folder moves every key under it. Big files go up in parts of 32 MB.
* Permissions can be changed over FTP and SFTP. Free space is shown for WebDAV servers that report a quota.
* Needs `libcurl` next to the plugin (`plugins\mtn.net`). If it is missing, a connection says so.
