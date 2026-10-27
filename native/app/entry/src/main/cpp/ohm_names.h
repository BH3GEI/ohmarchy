// Names the app shares with the Linux side: abstract sockets "<prefix>-display",
// "-vtest", "-audio" and "-ime". The demo build keeps "ohmarchy"; the sandbox build
// (native/sandbox/build-app.sh) sets "ohmsbx", so both apps can sit on one device.
#pragma once
#ifndef OHM_NAME_PREFIX
#define OHM_NAME_PREFIX "ohmarchy"
#endif
