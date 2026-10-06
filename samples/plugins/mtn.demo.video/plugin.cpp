// Demo plugin in C++: plays a video file in a viewer tab of MTN2.
//
// F3 on a video file opens a picture surface. Media Foundation (an
// IMFSourceReader) decodes the file: the video frames go to the host with
// surface_set_frame, the sound goes to the sound card through waveOut and sets
// the clock the frames are paced against. The host's timer (surface_set_timer)
// drives everything on the main thread. Space pauses, Left / Right seek by ten
// seconds, Esc closes the tab.
//
// Shows: a surface fed with video frames, the surface timer, key handling,
// closing cleanly when the tab goes.

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <mmsystem.h>
#include <propvarutil.h>

#include <chrono>
#include <cstdio>
#include <cstring>
#include <deque>
#include <memory>
#include <string>
#include <vector>

#include "mtn_plugin.h"

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "winmm.lib")
#pragma comment(lib, "propsys.lib")
#pragma comment(lib, "ole32.lib")

namespace {

constexpr const char *kPluginId = "mtn.demo.video";
constexpr int kTickMs = 10;
constexpr int kAudioRate = 44100;
constexpr int kAudioChannels = 2;
constexpr size_t kAudioQueue = 8;           // buffers kept ahead in the sound card
constexpr LONGLONG kSeekStep = 10LL * 10000000;  // ten seconds, in 100 ns units

const MtnHostApi *g_host = nullptr;
int64_t g_surface = 0;

template <class T>
void release(T *&p) {
    if (p != nullptr) {
        p->Release();
        p = nullptr;
    }
}

// file:///C:/dir/a%20b.mp4 -> C:\dir\a b.mp4 (UTF-8 escapes decoded).
std::wstring uri_to_path(const char *uri) {
    const std::string prefix = "file:///";
    std::string text = uri;
    if (text.compare(0, prefix.size(), prefix) != 0) {
        return L"";
    }
    text.erase(0, prefix.size());
    std::string bytes;
    for (size_t i = 0; i < text.size(); ++i) {
        if (text[i] == '%' && i + 2 < text.size() && isxdigit(static_cast<unsigned char>(text[i + 1])) &&
            isxdigit(static_cast<unsigned char>(text[i + 2]))) {
            bytes += static_cast<char>(std::stoi(text.substr(i + 1, 2), nullptr, 16));
            i += 2;
        } else {
            bytes += text[i] == '/' ? '\\' : text[i];
        }
    }
    const int len = MultiByteToWideChar(CP_UTF8, 0, bytes.c_str(), -1, nullptr, 0);
    if (len <= 0) {
        return L"";
    }
    std::wstring path(len - 1, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, bytes.c_str(), -1, &path[0], len);
    return path;
}

std::string to_utf8(const std::wstring &text) {
    const int len = WideCharToMultiByte(CP_UTF8, 0, text.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (len <= 0) {
        return "";
    }
    std::string out(len - 1, '\0');
    WideCharToMultiByte(CP_UTF8, 0, text.c_str(), -1, &out[0], len, nullptr, nullptr);
    return out;
}

// One block of PCM handed to the sound card.
struct AudioBlock {
    WAVEHDR header{};
    std::vector<BYTE> data;
};

class Player {
public:
    ~Player() { close(); }

    bool open(const std::wstring &path) {
        close();
        IMFAttributes *attrs = nullptr;
        MFCreateAttributes(&attrs, 1);
        if (attrs != nullptr) {
            attrs->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
        }
        HRESULT hr = MFCreateSourceReaderFromURL(path.c_str(), attrs, &reader_);
        release(attrs);
        if (FAILED(hr) || !setup_video()) {
            close();
            return false;
        }
        audio_present_ = setup_audio();
        has_audio_ = audio_present_;
        name_ = path.substr(path.find_last_of(L'\\') + 1);
        PROPVARIANT dur;
        PropVariantInit(&dur);
        if (SUCCEEDED(reader_->GetPresentationAttribute(MF_SOURCE_READER_MEDIASOURCE,
                                                        MF_PD_DURATION, &dur)) &&
            dur.vt == VT_UI8) {
            duration_ = static_cast<LONGLONG>(dur.uhVal.QuadPart);
        }
        PropVariantClear(&dur);
        start_clock(0);
        return true;
    }

    void close() {
        stop_audio();
        release(pending_);
        release(reader_);
        has_audio_ = false;
        audio_present_ = false;
        video_eos_ = false;
        ended_ = false;
    }

    bool is_open() const { return reader_ != nullptr; }
    const std::wstring &name() const { return name_; }

    void toggle_pause() {
        if (!is_open()) {
            return;
        }
        paused_ = !paused_;
        if (paused_) {
            if (wave_ != nullptr && audio_started_) {
                waveOutPause(wave_);
            }
            paused_at_ = Clock::now();
        } else {
            if (wave_ != nullptr && audio_started_) {
                waveOutRestart(wave_);
            }
            wall_base_ += Clock::now() - paused_at_;
        }
    }

    bool paused() const { return paused_; }
    bool ended() const { return ended_; }

    void seek(LONGLONG delta) {
        if (!is_open()) {
            return;
        }
        LONGLONG target = clock_pts() + delta;
        if (target < 0) {
            target = 0;
        }
        if (duration_ > 0 && target > duration_) {
            target = duration_;
        }
        PROPVARIANT pos;
        InitPropVariantFromInt64(target, &pos);
        reader_->SetCurrentPosition(GUID_NULL, pos);
        PropVariantClear(&pos);
        release(pending_);
        ended_ = false;
        video_eos_ = false;
        stop_audio();
        has_audio_ = audio_present_ && open_wave();
        start_clock(target);
    }

    // Decodes what is due now; true when a new frame was handed to the host.
    bool tick() {
        if (!is_open() || ended_) {
            return false;
        }
        feed_audio();
        if (video_eos_ && pending_ == nullptr &&
            (!has_audio_ || (audio_eos_ && queue_.empty()))) {
            ended_ = true;
            return false;
        }
        if (paused_) {
            return false;
        }
        const LONGLONG now = clock_pts();
        bool shown = false;
        // Several late frames may be due at once: show only the newest.
        for (int guard = 0; guard < 6; ++guard) {
            if (pending_ == nullptr && !read_video()) {
                break;
            }
            if (pending_ == nullptr || pending_pts_ > now) {
                break;
            }
            publish(pending_);
            release(pending_);
            shown = true;
        }
        return shown;
    }

    std::string status() const {
        const LONGLONG pos = clock_pts();
        char text[96];
        std::snprintf(text, sizeof(text), "%s / %s  %dx%d%s", format_time(pos).c_str(),
                      format_time(duration_).c_str(), width_, height_,
                      ended_ ? "  Ended" : (paused_ ? "  Paused" : ""));
        return text;
    }

private:
    using Clock = std::chrono::steady_clock;

    static std::string format_time(LONGLONG pts) {
        const long long s = pts / 10000000;
        char text[24];
        std::snprintf(text, sizeof(text), "%lld:%02lld", s / 60, s % 60);
        return text;
    }

    bool setup_video() {
        IMFMediaType *type = nullptr;
        if (FAILED(MFCreateMediaType(&type))) {
            return false;
        }
        type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
        HRESULT hr = reader_->SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, type);
        release(type);
        if (FAILED(hr)) {
            return false;
        }
        reader_->SetStreamSelection(MF_SOURCE_READER_FIRST_VIDEO_STREAM, TRUE);
        IMFMediaType *current = nullptr;
        if (FAILED(reader_->GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, &current))) {
            return false;
        }
        UINT32 w = 0, h = 0;
        MFGetAttributeSize(current, MF_MT_FRAME_SIZE, &w, &h);
        LONG stride = 0;
        UINT32 raw = 0;
        if (SUCCEEDED(current->GetUINT32(MF_MT_DEFAULT_STRIDE, &raw))) {
            stride = static_cast<LONG>(raw);
        } else if (FAILED(MFGetStrideForBitmapInfoHeader(MFVideoFormat_RGB32.Data1, w, &stride))) {
            stride = static_cast<LONG>(w) * 4;
        }
        release(current);
        if (w == 0 || h == 0) {
            return false;
        }
        width_ = static_cast<int>(w);
        height_ = static_cast<int>(h);
        bottom_up_ = stride < 0;
        frame_.assign(static_cast<size_t>(w) * h * 4, 0);
        return true;
    }

    bool setup_audio() {
        IMFMediaType *type = nullptr;
        if (FAILED(MFCreateMediaType(&type))) {
            return false;
        }
        type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
        type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
        type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
        type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, kAudioChannels);
        type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, kAudioRate);
        type->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, kAudioChannels * 2);
        type->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, kAudioRate * kAudioChannels * 2);
        HRESULT hr = reader_->SetCurrentMediaType(MF_SOURCE_READER_FIRST_AUDIO_STREAM, nullptr, type);
        release(type);
        if (FAILED(hr)) {
            return false;
        }
        reader_->SetStreamSelection(MF_SOURCE_READER_FIRST_AUDIO_STREAM, TRUE);
        return open_wave();
    }

    bool open_wave() {
        WAVEFORMATEX fmt = {};
        fmt.wFormatTag = WAVE_FORMAT_PCM;
        fmt.nChannels = kAudioChannels;
        fmt.nSamplesPerSec = kAudioRate;
        fmt.wBitsPerSample = 16;
        fmt.nBlockAlign = kAudioChannels * 2;
        fmt.nAvgBytesPerSec = kAudioRate * fmt.nBlockAlign;
        if (waveOutOpen(&wave_, WAVE_MAPPER, &fmt, 0, 0, CALLBACK_NULL) != MMSYSERR_NOERROR) {
            wave_ = nullptr;
            return false;
        }
        waveOutPause(wave_);
        audio_started_ = false;
        audio_base_set_ = false;
        audio_eos_ = false;
        return true;
    }

    void stop_audio() {
        if (wave_ != nullptr) {
            waveOutReset(wave_);
            for (auto &block : queue_) {
                waveOutUnprepareHeader(wave_, &block->header, sizeof(WAVEHDR));
            }
            queue_.clear();
            waveOutClose(wave_);
            wave_ = nullptr;
        }
        queue_.clear();
        audio_started_ = false;
    }

    // Wall clock for a file without sound, and the zero point of the stream.
    void start_clock(LONGLONG start_pts) {
        start_pts_ = start_pts;
        wall_base_ = Clock::now();
        paused_at_ = wall_base_;
        if (paused_) {
            // A paused player stays paused across a seek; the clock keeps still.
            if (wave_ != nullptr) {
                waveOutPause(wave_);
            }
        }
    }

    // Presentation time of the sound being played (or the wall clock).
    LONGLONG clock_pts() const {
        if (has_audio_ && wave_ != nullptr && audio_started_ && audio_base_set_) {
            MMTIME t = {};
            t.wType = TIME_SAMPLES;
            if (waveOutGetPosition(wave_, &t, sizeof(t)) == MMSYSERR_NOERROR && t.wType == TIME_SAMPLES) {
                return audio_base_ + static_cast<LONGLONG>(t.u.sample) * 10000000 / kAudioRate;
            }
        }
        if (has_audio_ && !audio_started_ && !audio_eos_) {
            return start_pts_;
        }
        auto elapsed = (paused_ ? paused_at_ : Clock::now()) - wall_base_;
        return start_pts_ + std::chrono::duration_cast<std::chrono::nanoseconds>(elapsed).count() / 100;
    }

    // Keeps the sound card supplied with decoded audio.
    void feed_audio() {
        if (!has_audio_ || wave_ == nullptr) {
            return;
        }
        while (!queue_.empty() && (queue_.front()->header.dwFlags & WHDR_DONE)) {
            waveOutUnprepareHeader(wave_, &queue_.front()->header, sizeof(WAVEHDR));
            queue_.pop_front();
        }
        int reads = 0;
        while (!audio_eos_ && queue_.size() < kAudioQueue && reads++ < 4) {
            DWORD flags = 0;
            LONGLONG pts = 0;
            IMFSample *sample = nullptr;
            HRESULT hr = reader_->ReadSample(MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0, nullptr, &flags,
                                             &pts, &sample);
            if (FAILED(hr) || (flags & MF_SOURCE_READERF_ENDOFSTREAM)) {
                audio_eos_ = true;
                if (!audio_started_ && !queue_.empty()) {
                    start_audio();
                }
                release(sample);
                break;
            }
            if (sample == nullptr) {
                continue;
            }
            if (!audio_base_set_) {
                audio_base_ = pts;
                audio_base_set_ = true;
            }
            IMFMediaBuffer *buffer = nullptr;
            if (SUCCEEDED(sample->ConvertToContiguousBuffer(&buffer))) {
                BYTE *bytes = nullptr;
                DWORD len = 0;
                if (SUCCEEDED(buffer->Lock(&bytes, nullptr, &len)) && len > 0) {
                    auto block = std::make_unique<AudioBlock>();
                    block->data.assign(bytes, bytes + len);
                    block->header.lpData = reinterpret_cast<LPSTR>(block->data.data());
                    block->header.dwBufferLength = len;
                    waveOutPrepareHeader(wave_, &block->header, sizeof(WAVEHDR));
                    waveOutWrite(wave_, &block->header, sizeof(WAVEHDR));
                    queue_.push_back(std::move(block));
                    buffer->Unlock();
                }
                release(buffer);
            }
            release(sample);
        }
        if (!audio_started_ && queue_.size() >= kAudioQueue / 2) {
            start_audio();
        }
        if (audio_eos_ && queue_.empty() && !video_eos_) {
            // Sound over; the wall clock carries on for the video that is left.
            const LONGLONG now = clock_pts();
            has_audio_ = false;
            start_pts_ = now;
            wall_base_ = Clock::now();
            paused_at_ = wall_base_;
        }
    }

    void start_audio() {
        audio_started_ = true;
        wall_base_ = Clock::now();
        if (!paused_) {
            waveOutRestart(wave_);
        }
    }

    // Reads the next video sample into pending_; false at the end of the stream.
    bool read_video() {
        if (video_eos_) {
            return false;
        }
        DWORD flags = 0;
        LONGLONG pts = 0;
        IMFSample *sample = nullptr;
        HRESULT hr = reader_->ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, nullptr, &flags, &pts,
                                         &sample);
        if (FAILED(hr) || (flags & MF_SOURCE_READERF_ENDOFSTREAM)) {
            video_eos_ = true;
            release(sample);
            return false;
        }
        if (sample == nullptr) {
            return true;  // a gap in the stream; try again next tick
        }
        pending_ = sample;
        pending_pts_ = pts;
        return true;
    }

    // Copies a decoded sample into the BGRA frame (opaque) and gives it to the host.
    void publish(IMFSample *sample) {
        IMFMediaBuffer *buffer = nullptr;
        if (FAILED(sample->ConvertToContiguousBuffer(&buffer))) {
            return;
        }
        BYTE *bytes = nullptr;
        DWORD len = 0;
        if (SUCCEEDED(buffer->Lock(&bytes, nullptr, &len)) &&
            len >= static_cast<DWORD>(width_) * height_ * 4) {
            const size_t row = static_cast<size_t>(width_) * 4;
            for (int y = 0; y < height_; ++y) {
                const BYTE *src = bytes + static_cast<size_t>(bottom_up_ ? height_ - 1 - y : y) * row;
                BYTE *dst = frame_.data() + static_cast<size_t>(y) * row;
                std::memcpy(dst, src, row);
                for (size_t x = 3; x < row; x += 4) {
                    dst[x] = 255;
                }
            }
            buffer->Unlock();
            g_host->surface_set_frame(g_surface, width_, height_, frame_.data(),
                                      static_cast<int64_t>(frame_.size()));
        }
        release(buffer);
    }

    IMFSourceReader *reader_ = nullptr;
    IMFSample *pending_ = nullptr;
    LONGLONG pending_pts_ = 0;
    std::vector<BYTE> frame_;
    std::wstring name_;
    int width_ = 0;
    int height_ = 0;
    bool bottom_up_ = false;
    LONGLONG duration_ = 0;

    HWAVEOUT wave_ = nullptr;
    std::deque<std::unique_ptr<AudioBlock>> queue_;
    bool audio_present_ = false;
    bool has_audio_ = false;
    bool audio_started_ = false;
    bool audio_base_set_ = false;
    bool audio_eos_ = false;
    LONGLONG audio_base_ = 0;

    bool video_eos_ = false;
    bool ended_ = false;
    bool paused_ = false;
    LONGLONG start_pts_ = 0;
    Clock::time_point wall_base_ = Clock::now();
    Clock::time_point paused_at_ = Clock::now();
};

std::unique_ptr<Player> g_player;
bool g_mf_started = false;

void update_info() {
    if (g_player == nullptr || !g_player->is_open()) {
        return;
    }
    const std::string title = to_utf8(g_player->name());
    const std::string status = g_player->status();
    g_host->surface_set_info(g_surface, title.c_str(), status.c_str());
}

void stop_playback() {
    g_player.reset();
}

void on_tick(void *) {
    if (g_player == nullptr) {
        return;
    }
    const bool shown = g_player->tick();
    static int counter = 0;
    if (shown || ++counter >= 25) {
        counter = 0;
        update_info();
    }
}

int64_t on_key(void *, const char *key) {
    if (g_player == nullptr) {
        return 0;
    }
    const std::string name = key;
    if (name == "Space") {
        g_player->toggle_pause();
    } else if (name == "Right") {
        g_player->seek(kSeekStep);
    } else if (name == "Left") {
        g_player->seek(-kSeekStep);
    } else {
        return 0;
    }
    update_info();
    return 1;
}

void on_closed(void *) {
    stop_playback();
    g_surface = 0;
}

// Handled (1) when playback started; 0 lets the next provider try.
int64_t on_document(void *, const char *uri, const char *mode, char *, int64_t) {
    (void)mode;
    const std::wstring path = uri_to_path(uri);
    if (path.empty() || g_host->surface_open == nullptr) {
        return 0;
    }
    if (!g_mf_started) {
        if (FAILED(MFStartup(MF_VERSION))) {
            return 0;
        }
        g_mf_started = true;
    }
    auto player = std::make_unique<Player>();
    if (!player->open(path)) {
        return 0;
    }
    if (g_surface == 0) {
        g_surface = g_host->surface_open(kPluginId, "Video", on_key, on_tick, on_closed, nullptr);
        if (g_surface <= 0) {
            g_surface = 0;
            return 0;
        }
    }
    g_player = std::move(player);
    g_host->surface_set_timer(g_surface, kTickMs);
    update_info();
    return 1;
}

}  // namespace

extern "C" {

MTN_EXPORT int64_t mtn_plugin_get_abi_version(void) { return MTN_ABI_VERSION; }

MTN_EXPORT int64_t mtn_plugin_init(const MtnHostApi *host) {
    if (host == nullptr || host->abi_version < 2 || host->register_document_provider == nullptr ||
        host->surface_open == nullptr || host->surface_set_frame == nullptr ||
        host->surface_set_info == nullptr || host->surface_set_timer == nullptr) {
        return -1;
    }
    g_host = host;
    host->register_document_provider(kPluginId, ".mp4;.mkv;.avi;.mov;.wmv;.webm;.m4v", 1,
                                     on_document, nullptr, 100);
    return 0;
}

// The host has closed the tab by now; release the decoder and Media Foundation.
MTN_EXPORT void mtn_plugin_shutdown(void) {
    stop_playback();
    g_surface = 0;
    if (g_mf_started) {
        MFShutdown();
        g_mf_started = false;
    }
    g_host = nullptr;
}

}  // extern "C"
