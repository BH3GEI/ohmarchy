// Sound from the Linux session: PipeWire in the session mixes everything into the
// sink "HarmonyOS" (native/desktop/ohmarchy-audio.conf), and
// native/desktop/ohmarchy-audio-relay streams that sink's monitor as raw PCM
// (S16LE, 48 kHz, stereo) over the abstract socket @ohmarchy-audio, to this app's
// uid only. This plays it with OHAudio, and only from a server running as the
// desktop's user (the compositor's uid, DesktopUid()).
//
// Latency: a ring of at most kMaxMs between the socket and the renderer; when the
// session runs ahead of the speaker clock the oldest audio is dropped back to
// kTargetMs. The session sends in bursts (one PipeWire quantum at a time), so the
// renderer starts reading only once kStartMs is queued, and again after running dry.
//
// For latency tests the first sound after kOnsetQuietMs of silence is timed: when
// the speaker plays it (the renderer's timestamp), on CLOCK_MONOTONIC, which the
// Linux session shares; the log line "onset played at" carries it. The renderer runs only while there is sound: after kIdleMs of silence
// it stops, so an idle desktop holds no audio focus.
#include "ohm_names.h"
#include <hilog/log.h>
#include <ohaudio/native_audiorenderer.h>
#include <ohaudio/native_audiostreambuilder.h>

#include <stddef.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <ctime>
#include <mutex>
#include <thread>
#include <vector>

#include "audio.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0D0D
#define LOG_TAG "ohdisp-audio"
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, __VA_ARGS__)

namespace {

const char *kName = OHM_NAME_PREFIX "-audio";
const int kRate = 48000;
const int kFrameBytes = 4;  // S16LE stereo
const int kStartMs = 20, kTargetMs = 30, kMaxMs = 80, kIdleMs = 2000;

size_t MsBytes(int ms) { return static_cast<size_t>(kRate) * ms / 1000 * kFrameBytes; }

// Ring between the socket thread and the renderer callback.
std::mutex g_mu;
std::vector<uint8_t> g_ring(MsBytes(500));
size_t g_head = 0, g_level = 0;  // read position, bytes queued
bool g_primed = false;            // kStartMs queued since the ring last ran dry
uint64_t g_underruns = 0, g_droppedBytes = 0;
const int kOnsetQuietMs = 300;
int64_t g_fedFrames = 0;      // frames handed to the renderer, silence included
int64_t g_quietFrames = 0;    // trailing silent frames fed
int64_t g_onsetFrame = -1;    // renderer position of the pending onset

void Push(const uint8_t *p, size_t n)
{
    std::lock_guard<std::mutex> lk(g_mu);
    size_t cap = g_ring.size();
    for (size_t i = 0; i < n; i++) {
        g_ring[(g_head + g_level + i) % cap] = p[i];
    }
    g_level += n;
    if (g_level > MsBytes(kMaxMs)) {
        size_t drop = g_level - MsBytes(kTargetMs);
        drop -= drop % kFrameBytes;
        g_head = (g_head + drop) % cap;
        g_level -= drop;
        g_droppedBytes += drop;
    }
}

OH_AudioData_Callback_Result OnWrite(OH_AudioRenderer *, void *, void *data, int32_t size)
{
    auto *out = static_cast<uint8_t *>(data);
    std::lock_guard<std::mutex> lk(g_mu);
    if (!g_primed && g_level < MsBytes(kStartMs)) {
        memset(out, 0, size);
        g_fedFrames += size / kFrameBytes;
        g_quietFrames += size / kFrameBytes;
        return AUDIO_DATA_CALLBACK_RESULT_VALID;
    }
    g_primed = true;
    size_t n = g_level < static_cast<size_t>(size) ? g_level : static_cast<size_t>(size);
    size_t cap = g_ring.size();
    for (size_t i = 0; i < n; i++) {
        out[i] = g_ring[(g_head + i) % cap];
    }
    g_head = (g_head + n) % cap;
    g_level -= n;
    auto *s16 = reinterpret_cast<const int16_t *>(out);
    for (size_t i = 0; i < n / 2; i++) {
        if (s16[i] > 64 || s16[i] < -64) {
            if (g_quietFrames >= static_cast<int64_t>(kRate) * kOnsetQuietMs / 1000 && g_onsetFrame < 0) {
                g_onsetFrame = g_fedFrames + static_cast<int64_t>(i / 2);
            }
            g_quietFrames = 0;
        } else if (i % 2 == 1) {
            g_quietFrames++;
        }
    }
    g_fedFrames += size / kFrameBytes;
    if (n < static_cast<size_t>(size)) {
        g_quietFrames += (size - n) / kFrameBytes;
        memset(out + n, 0, size - n);
        g_underruns++;
        g_primed = false;
    }
    return AUDIO_DATA_CALLBACK_RESULT_VALID;
}

OH_AudioRenderer *NewRenderer()
{
    OH_AudioStreamBuilder *b = nullptr;
    if (OH_AudioStreamBuilder_Create(&b, AUDIOSTREAM_TYPE_RENDERER) != AUDIOSTREAM_SUCCESS) {
        return nullptr;
    }
    OH_AudioStreamBuilder_SetSamplingRate(b, kRate);
    OH_AudioStreamBuilder_SetChannelCount(b, 2);
    OH_AudioStreamBuilder_SetSampleFormat(b, AUDIOSTREAM_SAMPLE_S16LE);
    OH_AudioStreamBuilder_SetEncodingType(b, AUDIOSTREAM_ENCODING_TYPE_RAW);
    OH_AudioStreamBuilder_SetRendererInfo(b, AUDIOSTREAM_USAGE_MUSIC);
    OH_AudioStreamBuilder_SetLatencyMode(b, AUDIOSTREAM_LATENCY_MODE_FAST);
    OH_AudioStreamBuilder_SetRendererWriteDataCallback(b, OnWrite, nullptr);
    OH_AudioRenderer *r = nullptr;
    if (OH_AudioStreamBuilder_GenerateRenderer(b, &r) != AUDIOSTREAM_SUCCESS) {
        // fast mode is not available on every output; normal mode always is
        OH_AudioStreamBuilder_SetLatencyMode(b, AUDIOSTREAM_LATENCY_MODE_NORMAL);
        if (OH_AudioStreamBuilder_GenerateRenderer(b, &r) != AUDIOSTREAM_SUCCESS) {
            r = nullptr;
        }
    }
    OH_AudioStreamBuilder_Destroy(b);
    return r;
}

// Audio written to the renderer but not yet played, in ms.
double RendererQueuedMs(OH_AudioRenderer *r)
{
    int64_t written = 0, pos = 0, ts = 0;
    if (OH_AudioRenderer_GetFramesWritten(r, &written) != AUDIOSTREAM_SUCCESS ||
        OH_AudioRenderer_GetTimestamp(r, CLOCK_MONOTONIC, &pos, &ts) != AUDIOSTREAM_SUCCESS) {
        return -1;
    }
    timespec now{};
    clock_gettime(CLOCK_MONOTONIC, &now);
    double played = pos + (now.tv_sec * 1e9 + now.tv_nsec - ts) * kRate / 1e9;
    return (written - played) * 1000.0 / kRate;
}

void CheckOnset(OH_AudioRenderer *r)
{
    int64_t onset;
    {
        std::lock_guard<std::mutex> lk(g_mu);
        onset = g_onsetFrame;
    }
    int64_t pos = 0, ts = 0;
    if (onset < 0 || OH_AudioRenderer_GetTimestamp(r, CLOCK_MONOTONIC, &pos, &ts) != AUDIOSTREAM_SUCCESS ||
        pos < onset) {
        return;
    }
    int64_t played = ts - (pos - onset) * 1000000000LL / kRate;
    LOGI("onset played at %{public}lld ns (CLOCK_MONOTONIC)", static_cast<long long>(played));
    std::lock_guard<std::mutex> lk(g_mu);
    g_onsetFrame = -1;
}

bool Silent(const uint8_t *p, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        if (p[i] != 0) {
            return false;
        }
    }
    return true;
}

int Connect()
{
    int64_t desktop = DesktopUid();
    if (desktop < 0) {
        return -1;  // not until the desktop is there to vouch for the server
    }
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    sockaddr_un a{};
    a.sun_family = AF_UNIX;
    size_t len = strlen(kName);
    memcpy(a.sun_path + 1, kName, len);  // abstract namespace
    if (connect(fd, reinterpret_cast<sockaddr *>(&a), offsetof(sockaddr_un, sun_path) + 1 + len) != 0) {
        close(fd);
        return -1;
    }
    ucred cr{};
    socklen_t crlen = sizeof(cr);
    if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cr, &crlen) != 0 || static_cast<int64_t>(cr.uid) != desktop) {
        LOGE("sound server uid %{public}u is not the desktop's (%{public}lld): refused", cr.uid,
             static_cast<long long>(desktop));
        close(fd);
        return -1;
    }
    // The session sends nothing while nothing plays; the timeout lets the renderer
    // stop then.
    timeval tv{0, 500000};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    return fd;
}

void AudioLoop()
{
    std::vector<uint8_t> buf(MsBytes(10));
    for (;;) {
        int fd = Connect();
        if (fd < 0) {
            sleep(2);
            continue;
        }
        LOGI("session audio connected");
        OH_AudioRenderer *r = nullptr;
        auto lastSound = std::chrono::steady_clock::now();
        auto lastLog = lastSound;
        size_t partial = 0;  // bytes of an incomplete frame at the start of buf
        for (;;) {
            ssize_t n = recv(fd, buf.data() + partial, buf.size() - partial, 0);
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                n = 0;  // nothing playing: counts as silence below
            } else if (n <= 0) {
                if (n < 0) {
                    LOGE("session audio: %{public}s", strerror(errno));
                }
                break;
            }
            size_t have = partial + static_cast<size_t>(n);
            size_t whole = have - have % kFrameBytes;
            auto now = std::chrono::steady_clock::now();
            if (!Silent(buf.data(), whole)) {
                lastSound = now;
                if (r == nullptr) {
                    {
                        std::lock_guard<std::mutex> lk(g_mu);
                        g_fedFrames = 0;
                        g_quietFrames = static_cast<int64_t>(kRate) * kOnsetQuietMs / 1000;
                        g_onsetFrame = -1;
                    }
                    r = NewRenderer();
                    if (r == nullptr || OH_AudioRenderer_Start(r) != AUDIOSTREAM_SUCCESS) {
                        LOGE("audio renderer did not start");
                    } else {
                        OH_AudioStream_LatencyMode mode = AUDIOSTREAM_LATENCY_MODE_NORMAL;
                        int32_t frames = 0;
                        OH_AudioRenderer_GetLatencyMode(r, &mode);
                        OH_AudioRenderer_GetFrameSizeInCallback(r, &frames);
                        LOGI("playing: %{public}s latency mode, %{public}d frames per callback",
                             mode == AUDIOSTREAM_LATENCY_MODE_FAST ? "fast" : "normal", frames);
                    }
                }
            }
            if (r != nullptr) {
                Push(buf.data(), whole);
                CheckOnset(r);
                if (now - lastSound > std::chrono::milliseconds(kIdleMs)) {
                    OH_AudioRenderer_Stop(r);
                    OH_AudioRenderer_Release(r);
                    r = nullptr;
                    std::lock_guard<std::mutex> lk(g_mu);
                    g_level = 0;
                    g_primed = false;
                    LOGI("idle, renderer stopped");
                } else if (now - lastLog > std::chrono::seconds(5)) {
                    lastLog = now;
                    size_t level;
                    uint64_t underruns, dropped;
                    {
                        std::lock_guard<std::mutex> lk(g_mu);
                        level = g_level;
                        underruns = g_underruns;
                        dropped = g_droppedBytes;
                    }
                    LOGI("latency: ring %{public}.1f ms + renderer %{public}.1f ms; underruns %{public}llu, "
                         "dropped %{public}.1f ms",
                         level * 1000.0 / (kRate * kFrameBytes), RendererQueuedMs(r),
                         static_cast<unsigned long long>(underruns), dropped * 1000.0 / (kRate * kFrameBytes));
                }
            }
            partial = have - whole;
            memmove(buf.data(), buf.data() + whole, partial);
        }
        if (r != nullptr) {
            OH_AudioRenderer_Stop(r);
            OH_AudioRenderer_Release(r);
        }
        {
            std::lock_guard<std::mutex> lk(g_mu);
            g_level = 0;
            g_primed = false;
        }
        close(fd);
        LOGE("session audio disconnected");
        sleep(1);
    }
}

}  // namespace

void AudioStart()
{
    static std::atomic<bool> started{false};
    bool expected = false;
    if (started.compare_exchange_strong(expected, true)) {
        std::thread(AudioLoop).detach();
    }
}
