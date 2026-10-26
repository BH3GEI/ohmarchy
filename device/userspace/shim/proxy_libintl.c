/* proxy-libintl for OHOS musl: glib references g_libintl_* (its bundled proxy-libintl
   subproject, absent in the tarball) AND OHOS musl's libc has NO gettext family. So
   implement the identity (C-locale, no-translation) behavior directly: gettext returns
   the msgid unchanged. Correct for a build with no message catalogs. */
char *g_libintl_gettext(const char *m) { return (char *)m; }
char *g_libintl_dgettext(const char *d, const char *m) { (void)d; return (char *)m; }
char *g_libintl_dcgettext(const char *d, const char *m, int c) { (void)d; (void)c; return (char *)m; }
char *g_libintl_ngettext(const char *m, const char *p, unsigned long n) { return (char *)(n == 1 ? m : p); }
char *g_libintl_dngettext(const char *d, const char *m, const char *p, unsigned long n) { (void)d; return (char *)(n == 1 ? m : p); }
char *g_libintl_dcngettext(const char *d, const char *m, const char *p, unsigned long n, int c) { (void)d; (void)c; return (char *)(n == 1 ? m : p); }
char *g_libintl_textdomain(const char *d) { return (char *)d; }
char *g_libintl_bindtextdomain(const char *d, const char *dir) { (void)d; return (char *)dir; }
char *g_libintl_bind_textdomain_codeset(const char *d, const char *cs) { (void)d; return (char *)cs; }
