// Sound from the Linux session (audio.cpp).
#pragma once
#include <cstdint>

// Start the thread that plays the session's sound output; once.
void AudioStart();
// The desktop's uid, from the compositor's export socket (-1 until connected): the
// sound server must run as the same user.
int64_t DesktopUid();
