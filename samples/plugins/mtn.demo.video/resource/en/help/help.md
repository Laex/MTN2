# Video player (C++)

The plugin plays video files, with sound, in a viewer tab of MTN2.

## Use

- Put the cursor on a video file (`.mp4`, `.mkv`, `.avi`, `.mov`, `.wmv`, `.webm`, `.m4v`) and press **F3**.
- **Space** pauses and resumes. **Right** and **Left** seek ten seconds forward and back.
- **Esc** or **F10** closes the tab. The status line shows the position, the length and the frame size.
- A second file replaces the first in the same tab.
- Which formats play depends on the codecs installed in Windows. The picture is decoded in the main thread of MTN2, so a very large video may play with dropped frames.

## For authors

Source: `samples/plugins/mtn.demo.video/plugin.cpp`. The plugin uses the picture surface of the host API: a document provider opens a surface (`surface_open`), a Media Foundation source reader decodes the file, the frames go to the host with `surface_set_frame` and the sound to the sound card through waveOut. The sound is the clock the frames are paced against, and the host's timer (`surface_set_timer`) drives the decoding. See `docs/PLUGIN_DEVELOPMENT.md`.
