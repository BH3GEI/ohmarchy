// kmsgl: GPU rendering straight on KMS (GBM + EGL + GLES2), for the Oseasy
// probe. Draws a rotating triangle on an animated background on the first
// connected connector, page-flips, and prints frames per second once a second
// plus the colour of the centre pixel of the first frame (a readback through
// the GPU, so it shows whether rendering itself works).
//   kmsgl [SECONDS] [/dev/dri/cardN]
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <gbm.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>

static double now(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

static int flip_pending;
static void on_flip(int fd, unsigned int seq, unsigned int s, unsigned int us, void *data)
{
	(void)fd; (void)seq; (void)s; (void)us; (void)data;
	flip_pending = 0;
}

static uint32_t fb_for_bo(int fd, struct gbm_bo *bo)
{
	uint32_t *fb = gbm_bo_get_user_data(bo);
	if (fb)
		return *fb;
	fb = malloc(sizeof(*fb));
	uint32_t handles[4] = { gbm_bo_get_handle(bo).u32 }, pitches[4] = { gbm_bo_get_stride(bo) }, offsets[4] = { 0 };
	if (drmModeAddFB2(fd, gbm_bo_get_width(bo), gbm_bo_get_height(bo), gbm_bo_get_format(bo),
			  handles, pitches, offsets, fb, 0)) {
		perror("drmModeAddFB2");
		exit(1);
	}
	gbm_bo_set_user_data(bo, fb, NULL);
	return *fb;
}

static GLuint shader(GLenum type, const char *src)
{
	GLuint s = glCreateShader(type);
	GLint ok;
	glShaderSource(s, 1, &src, NULL);
	glCompileShader(s);
	glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	if (!ok) {
		char log[512];
		glGetShaderInfoLog(s, sizeof(log), NULL, log);
		fprintf(stderr, "shader: %s\n", log);
		exit(1);
	}
	return s;
}

int main(int argc, char **argv)
{
	double secs = argc > 1 ? atof(argv[1]) : 20;
	const char *path = argc > 2 ? argv[2] : "/dev/dri/card0";
	int fd = open(path, O_RDWR | O_CLOEXEC);
	if (fd < 0) { perror(path); return 1; }

	drmModeRes *res = drmModeGetResources(fd);
	drmModeConnector *conn = NULL;
	for (int i = 0; res && i < res->count_connectors; i++) {
		conn = drmModeGetConnector(fd, res->connectors[i]);
		if (conn && conn->connection == DRM_MODE_CONNECTED && conn->count_modes)
			break;
		drmModeFreeConnector(conn);
		conn = NULL;
	}
	if (!conn) { fprintf(stderr, "no connected connector\n"); return 1; }
	drmModeModeInfo mode = conn->modes[0];
	drmModeEncoder *enc = drmModeGetEncoder(fd, conn->encoder_id ? conn->encoder_id : conn->encoders[0]);
	uint32_t crtc = enc && enc->crtc_id ? enc->crtc_id : res->crtcs[0];
	printf("kmsgl: %s %ux%u@%u crtc %u\n", mode.name, mode.hdisplay, mode.vdisplay, mode.vrefresh, crtc);

	struct gbm_device *gbm = gbm_create_device(fd);
	struct gbm_surface *gs = gbm_surface_create(gbm, mode.hdisplay, mode.vdisplay, GBM_FORMAT_XRGB8888,
						     GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING);
	if (!gs) { fprintf(stderr, "gbm_surface_create failed\n"); return 1; }

	PFNEGLGETPLATFORMDISPLAYEXTPROC get_dpy = (void *)eglGetProcAddress("eglGetPlatformDisplayEXT");
	EGLDisplay dpy = get_dpy ? get_dpy(EGL_PLATFORM_GBM_KHR, gbm, NULL) : eglGetDisplay((EGLNativeDisplayType)gbm);
	EGLint maj, min;
	if (!eglInitialize(dpy, &maj, &min)) { fprintf(stderr, "eglInitialize failed\n"); return 1; }
	eglBindAPI(EGL_OPENGL_ES_API);
	EGLint cfg_attr[] = { EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
			      EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE };
	EGLConfig cfgs[64], cfg = NULL;
	EGLint n = 0;
	eglChooseConfig(dpy, cfg_attr, cfgs, 64, &n);
	for (int i = 0; i < n; i++) {
		EGLint id;
		eglGetConfigAttrib(dpy, cfgs[i], EGL_NATIVE_VISUAL_ID, &id);
		if (id == GBM_FORMAT_XRGB8888) { cfg = cfgs[i]; break; }
	}
	if (!cfg) { fprintf(stderr, "no XRGB8888 EGL config\n"); return 1; }
	EGLint ctx_attr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctx_attr);
	EGLSurface surf = eglCreateWindowSurface(dpy, cfg, (EGLNativeWindowType)gs, NULL);
	if (!eglMakeCurrent(dpy, surf, surf, ctx)) { fprintf(stderr, "eglMakeCurrent failed\n"); return 1; }
	printf("kmsgl: EGL %d.%d, GL_RENDERER %s, GL_VERSION %s\n", maj, min,
	       glGetString(GL_RENDERER), glGetString(GL_VERSION));

	GLuint prog = glCreateProgram();
	glAttachShader(prog, shader(GL_VERTEX_SHADER,
		"attribute vec2 p; uniform float a; void main() {"
		" mat2 r = mat2(cos(a), sin(a), -sin(a), cos(a)); gl_Position = vec4(r * p, 0.0, 1.0); }"));
	glAttachShader(prog, shader(GL_FRAGMENT_SHADER,
		"precision mediump float; void main() { gl_FragColor = vec4(1.0, 0.85, 0.2, 1.0); }"));
	glBindAttribLocation(prog, 0, "p");
	glLinkProgram(prog);
	glUseProgram(prog);
	GLint ua = glGetUniformLocation(prog, "a");
	static const GLfloat tri[] = { 0.0f, 0.7f, -0.6f, -0.5f, 0.6f, -0.5f };
	glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, tri);
	glEnableVertexAttribArray(0);
	glViewport(0, 0, mode.hdisplay, mode.vdisplay);

	drmEventContext ev = { .version = 2, .page_flip_handler = on_flip };
	struct gbm_bo *prev = NULL;
	double t0 = now(), tlast = t0;
	int frames = 0, total = 0;
	for (;;) {
		double t = now() - t0;
		glClearColor(0.15f + 0.15f * sinf(t), 0.2f, 0.45f + 0.3f * sinf(t * 0.7f), 1.0f);
		glClear(GL_COLOR_BUFFER_BIT);
		glUniform1f(ua, (float)t * 2.0f);
		glDrawArrays(GL_TRIANGLES, 0, 3);
		if (total == 0) {
			unsigned char px[4];
			glReadPixels(mode.hdisplay / 2, mode.vdisplay / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
			printf("kmsgl: first frame centre pixel %u %u %u\n", px[0], px[1], px[2]);
		}
		eglSwapBuffers(dpy, surf);
		struct gbm_bo *bo = gbm_surface_lock_front_buffer(gs);
		uint32_t fb = fb_for_bo(fd, bo);
		if (total == 0) {
			uint32_t cid = conn->connector_id;
			if (drmModeSetCrtc(fd, crtc, fb, 0, 0, &cid, 1, &mode)) { perror("drmModeSetCrtc"); return 1; }
		} else {
			flip_pending = 1;
			if (drmModePageFlip(fd, crtc, fb, DRM_MODE_PAGE_FLIP_EVENT, NULL)) {
				perror("drmModePageFlip");
				return 1;
			}
			while (flip_pending)
				drmHandleEvent(fd, &ev);
		}
		if (prev)
			gbm_surface_release_buffer(gs, prev);
		prev = bo;
		frames++, total++;
		double tn = now();
		if (tn - tlast >= 1.0) {
			printf("kmsgl: %.1f fps\n", frames / (tn - tlast));
			fflush(stdout);
			frames = 0, tlast = tn;
		}
		if (tn - t0 >= secs)
			break;
	}
	printf("kmsgl: %d frames in %.1f s\n", total, now() - t0);
	return 0;
}
