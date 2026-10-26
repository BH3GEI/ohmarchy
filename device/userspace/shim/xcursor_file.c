/* XCursor binary file reader (format: https://www.x.org/.../Xcursor). Standalone, no X11. */
#include "X11/Xcursor/Xcursor.h"
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define XC_MAGIC      0x72756358u     /* "Xcur" LE */
#define XC_IMAGE_TYPE 0xfffd0002u
#define XC_MAX_IMGS   1024

static int rd32(FILE* f, uint32_t* v) {
    unsigned char b[4];
    if (fread(b, 1, 4, f) != 4) return 0;
    *v = (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
    return 1;
}

const char* XcursorLibraryPath(void) {
    const char* p = getenv("XCURSOR_PATH");
    if (p && *p) return p;
    return "~/.local/share/icons:~/.icons:/usr/share/icons:/usr/share/pixmaps";
}

/* Legacy cursor-font shapes need the X server/font; unsupported here. */
XcursorImages* XcursorShapeLoadImages(unsigned int shape, const char* theme, int size) {
    (void)shape; (void)theme; (void)size; return NULL;
}

void XcursorImagesDestroy(XcursorImages* imgs) {
    if (!imgs) return;
    for (int i = 0; i < imgs->nimage; i++) {
        if (imgs->images[i]) { free(imgs->images[i]->pixels); free(imgs->images[i]); }
    }
    free(imgs->images); free(imgs->name); free(imgs);
}

typedef struct { uint32_t type, subtype, position; } TocEntry;

XcursorImages* XcursorFileLoadImages(FILE* f, int size) {
    if (!f) return NULL;
    rewind(f);
    uint32_t magic, hdrsize, version, ntoc;
    if (!rd32(f, &magic) || magic != XC_MAGIC) return NULL;
    if (!rd32(f, &hdrsize) || !rd32(f, &version) || !rd32(f, &ntoc)) return NULL;
    if (ntoc == 0 || ntoc > 1u << 20) return NULL;
    TocEntry* toc = (TocEntry*)calloc(ntoc, sizeof(TocEntry));
    if (!toc) return NULL;
    for (uint32_t i = 0; i < ntoc; i++) {
        if (!rd32(f, &toc[i].type) || !rd32(f, &toc[i].subtype) || !rd32(f, &toc[i].position)) { free(toc); return NULL; }
    }
    /* pick the nominal size (subtype) closest to the requested size */
    uint32_t best = 0; int found = 0;
    for (uint32_t i = 0; i < ntoc; i++) {
        if (toc[i].type != XC_IMAGE_TYPE) continue;
        if (!found || (uint32_t)abs((int)toc[i].subtype - size) < (uint32_t)abs((int)best - size)) { best = toc[i].subtype; found = 1; }
    }
    if (!found) { free(toc); return NULL; }
    XcursorImage** list = (XcursorImage**)calloc(XC_MAX_IMGS, sizeof(XcursorImage*));
    int n = 0;
    for (uint32_t i = 0; i < ntoc && n < XC_MAX_IMGS; i++) {
        if (toc[i].type != XC_IMAGE_TYPE || toc[i].subtype != best) continue;
        if (fseek(f, (long)toc[i].position, SEEK_SET) != 0) continue;
        uint32_t chdr, ctype, csub, cver, w, h, xh, yh, delay;
        if (!rd32(f, &chdr) || !rd32(f, &ctype) || !rd32(f, &csub) || !rd32(f, &cver)) continue;
        if (ctype != XC_IMAGE_TYPE) continue;
        if (!rd32(f, &w) || !rd32(f, &h) || !rd32(f, &xh) || !rd32(f, &yh) || !rd32(f, &delay)) continue;
        if (w == 0 || h == 0 || w > 1024 || h > 1024) continue;
        XcursorImage* img = (XcursorImage*)calloc(1, sizeof(XcursorImage));
        if (!img) break;
        img->version = cver; img->size = csub; img->width = w; img->height = h;
        img->xhot = xh; img->yhot = yh; img->delay = delay;
        size_t px = (size_t)w * h;
        img->pixels = (XcursorPixel*)malloc(px * sizeof(XcursorPixel));
        if (!img->pixels) { free(img); break; }
        for (size_t p = 0; p < px; p++) { uint32_t v; if (!rd32(f, &v)) { v = 0; } img->pixels[p] = v; }
        list[n++] = img;
    }
    free(toc);
    if (n == 0) { free(list); return NULL; }
    XcursorImages* imgs = (XcursorImages*)calloc(1, sizeof(XcursorImages));
    imgs->nimage = n; imgs->images = list; imgs->name = NULL;
    return imgs;
}
