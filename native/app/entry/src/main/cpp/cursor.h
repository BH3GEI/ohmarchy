#pragma once
// The desktop's cursor as the window's pointer (cursor.cpp).
#include <cstdint>

void CursorSetWindow(int32_t windowId);
// a new cursor image (map null: none); rgb: ABGR8888 (R,G,B,A in memory), else ARGB8888
void CursorUpdate(const uint8_t *map, int w, int h, int stride, bool rgb, int hotspotX, int hotspotY);
void CursorReapply();  // the pointer came back into the window
void CursorRetryIfRefused();  // a pointer event here: set again if the last set was refused
void CursorReset();    // the desktop is gone: the system's pointer again
// the sandbox's helper makes the desktop draw its cursor (ohdisp.cpp)
void CursorSoftFallback();
