/* Minimal standalone XCursor file API for OHOS musl — no libX11/libXcursor.
   Provides exactly what Hyprland's CXCursorManager uses: the XCursor binary file
   reader, plus trivial stubs for the library-path / shape-font entry points. */
#ifndef OHM_XCURSOR_SHIM_H
#define OHM_XCURSOR_SHIM_H
#include <stdio.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef int           XcursorBool;
typedef unsigned int  XcursorUInt;
typedef XcursorUInt   XcursorDim;
typedef XcursorUInt   XcursorPixel;
typedef struct _XcursorImage {
    XcursorUInt   version;
    XcursorDim    size;    /* nominal size */
    XcursorDim    width, height;
    XcursorDim    xhot, yhot;
    XcursorUInt   delay;   /* ms */
    XcursorPixel* pixels;  /* ARGB, width*height */
} XcursorImage;
typedef struct _XcursorImages {
    int            nimage;
    XcursorImage** images;
    char*          name;
} XcursorImages;
XcursorImages* XcursorFileLoadImages(FILE* file, int size);
XcursorImages* XcursorShapeLoadImages(unsigned int shape, const char* theme, int size);
void           XcursorImagesDestroy(XcursorImages* images);
const char*    XcursorLibraryPath(void);
#ifdef __cplusplus
}
#endif
#endif
