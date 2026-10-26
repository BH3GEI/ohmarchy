// In-process GPU renderer (gpu.cpp).
#pragma once
#include <native_window/external_window.h>
#include <cstdint>

// Give the renderer the window; the first time vtest-broker is there, start its
// thread. Returns whether the renderer owns the window (then leave it alone).
bool GpuStart(OHNativeWindow *window);
// The renderer owns the window; the CPU frame path must leave it alone.
bool GpuActive();
// Frames presented by the renderer so far.
uint64_t GpuPresents();
// Make vtest-broker run its --on-app hook (`omarchy desktop restart`) as if the
// app had just opened: a connection of our own takes the app's place, the
// broker drops the renderer's connection, the renderer reconnects.
void BrokerKick();
