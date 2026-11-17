/* pyo-dock: the desktop's dock, centered at the bottom of the screen.
 *
 *   pyo-dock APP.desktop...
 *
 * The apps given are pinned, in that order. Each one's icon is also its
 * windows': a dot under it says it runs, a white dot that it's in front.
 * A click starts it when it doesn't run, and brings its window to the
 * front when it does (the next one, when it's in front already). Apps
 * that aren't pinned get an icon of their own while they run, after a
 * separator. A clock ends the dock.
 *
 * An app's windows are the ones whose WM_CLASS (class or instance) is the
 * StartupWMClass of its .desktop file, or its executable's name.
 *
 * The dock reserves its height at the bottom of the screen (a strut), so
 * maximized windows end above it. It never takes the focus. voxl rounds
 * its corners (--round-windows pyo-dock:R in desktop.py), as nothing
 * composites the screen.
 */
#include <gdk/gdkx.h>
#include <gio/gdesktopappinfo.h>
#include <gtk/gtk.h>
#include <string.h>
#include <time.h>
#define WNCK_I_KNOW_THIS_IS_UNSTABLE
#include <libwnck/libwnck.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>

#define ICON 40   /* pixels */
#define MARGIN 10 /* between the dock and the screen's bottom edge */

typedef struct {
	GDesktopAppInfo *app; /* NULL for an app that isn't pinned */
	char *klass;          /* the WM_CLASS it matches, lower case */
	char *exe;            /* its executable's name, lower case */
	GtkWidget *button, *dot;
	GList *windows; /* its windows, the one in front first */
} Item;

static GtkWidget *win, *pinned_box, *running_box, *running_sep, *clock_time, *clock_date, *clock_box;
static GPtrArray *pinned, *running;
static WnckScreen *screen;
static guint refresh_id;

static const char *CSS =
	"window#pyo-dock { background: #131313; border: 1px solid #242424;"
	"  border-radius: 18px; }"
	"#items { padding: 6px 8px 3px 8px; }"
	"button.item { background: none; border: none; box-shadow: none; outline: none;"
	"  padding: 4px 4px 2px 4px; margin: 0 1px; border-radius: 12px; min-width: 0; min-height: 0; }"
	"button.item:hover { background: rgba(255,255,255,0.08); }"
	"button.item:active { background: rgba(255,255,255,0.14); }"
	".dot { min-width: 4px; min-height: 4px; border-radius: 2px; margin-top: 3px; background: transparent; }"
	".dot.running { background: rgba(255,255,255,0.45); }"
	".dot.active { background: #ffffff; }"
	"separator.dock { background: rgba(255,255,255,0.12); min-width: 1px; margin: 12px 6px 10px 6px; }"
	"#clock { padding: 0 10px 2px 8px; }"
	"#clock .time { color: #f5f5f5; font-weight: 600; font-size: 13px; }"
	"#clock .date { color: #ababab; font-size: 11px; }";

static char *lower(const char *s) {
	return s ? g_ascii_strdown(s, -1) : NULL;
}

/* "google-chrome (/root/.config/browser)" is Chrome's instance name with
 * a profile of its own: the part before " (". */
static char *instance_of(WnckWindow *w) {
	const char *s = wnck_window_get_class_instance_name(w);
	if (!s)
		return NULL;
	const char *p = strstr(s, " (");
	return g_ascii_strdown(s, p ? p - s : -1);
}

static gboolean same(const char *a, const char *b) {
	return a && b && !strcmp(a, b);
}

static gboolean matches(Item *it, WnckWindow *w) {
	char *klass = lower(wnck_window_get_class_group_name(w));
	char *inst = instance_of(w);
	gboolean yes = same(it->klass, klass) || same(it->klass, inst) || same(it->exe, klass) || same(it->exe, inst);
	g_free(klass);
	g_free(inst);
	return yes;
}

static gboolean listed(WnckWindow *w) {
	return !wnck_window_is_skip_tasklist(w) && wnck_window_get_window_type(w) == WNCK_WINDOW_NORMAL;
}

static void place(void) {
	GtkRequisition size;
	gtk_widget_get_preferred_size(win, NULL, &size);
	GdkScreen *s = gtk_widget_get_screen(win);
	G_GNUC_BEGIN_IGNORE_DEPRECATIONS
	int sw = gdk_screen_get_width(s), sh = gdk_screen_get_height(s);
	G_GNUC_END_IGNORE_DEPRECATIONS
	int x = (sw - size.width) / 2, y = sh - size.height - MARGIN;
	gtk_window_resize(GTK_WINDOW(win), size.width, size.height);
	gtk_window_move(GTK_WINDOW(win), x, y);
	GdkWindow *gw = gtk_widget_get_window(win);
	if (!gw)
		return;
	/* Maximized windows end above the dock, with the same gap. */
	long bottom = size.height + 2 * MARGIN;
	long strut[12] = {0, 0, 0, bottom, 0, 0, 0, 0, 0, 0, x, x + size.width - 1};
	Display *d = GDK_WINDOW_XDISPLAY(gw);
	Window xid = GDK_WINDOW_XID(gw);
	XChangeProperty(d, xid, XInternAtom(d, "_NET_WM_STRUT_PARTIAL", False), XA_CARDINAL, 32,
	                PropModeReplace, (unsigned char *)strut, 12);
	XChangeProperty(d, xid, XInternAtom(d, "_NET_WM_STRUT", False), XA_CARDINAL, 32,
	                PropModeReplace, (unsigned char *)strut, 4);
}

static void activate(GtkButton *b, Item *it);

static GtkWidget *item_widget(Item *it, GtkWidget *image, const char *tip) {
	GtkWidget *b = gtk_button_new();
	gtk_style_context_add_class(gtk_widget_get_style_context(b), "item");
	gtk_widget_set_can_focus(b, FALSE);
	gtk_button_set_relief(GTK_BUTTON(b), GTK_RELIEF_NONE);
	GtkWidget *col = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
	gtk_box_pack_start(GTK_BOX(col), image, FALSE, FALSE, 0);
	it->dot = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
	gtk_style_context_add_class(gtk_widget_get_style_context(it->dot), "dot");
	gtk_widget_set_halign(it->dot, GTK_ALIGN_CENTER);
	gtk_box_pack_start(GTK_BOX(col), it->dot, FALSE, FALSE, 0);
	gtk_container_add(GTK_CONTAINER(b), col);
	if (tip)
		gtk_widget_set_tooltip_text(b, tip);
	g_signal_connect(b, "clicked", G_CALLBACK(activate), it);
	it->button = b;
	return b;
}

static void set_dot(Item *it, WnckWindow *active) {
	GtkStyleContext *c = gtk_widget_get_style_context(it->dot);
	gboolean runs = it->windows != NULL, front = active && g_list_find(it->windows, active);
	(runs ? gtk_style_context_add_class : gtk_style_context_remove_class)(c, "running");
	(front ? gtk_style_context_add_class : gtk_style_context_remove_class)(c, "active");
}

static void free_item(gpointer p) {
	Item *it = p;
	g_list_free(it->windows);
	g_free(it->klass);
	g_free(it->exe);
	if (it->button)
		gtk_widget_destroy(it->button);
	g_free(it);
}

static gboolean refresh(gpointer data) {
	refresh_id = 0;
	for (guint i = 0; i < pinned->len; i++) {
		Item *it = g_ptr_array_index(pinned, i);
		g_list_free(it->windows);
		it->windows = NULL;
	}
	g_ptr_array_set_size(running, 0);
	/* Bottom to top: prepending puts the one in front first. */
	for (GList *l = wnck_screen_get_windows_stacked(screen); l; l = l->next) {
		WnckWindow *w = l->data;
		if (!listed(w))
			continue;
		Item *it = NULL;
		for (guint i = 0; !it && i < pinned->len; i++)
			if (matches(g_ptr_array_index(pinned, i), w))
				it = g_ptr_array_index(pinned, i);
		for (guint i = 0; !it && i < running->len; i++)
			if (matches(g_ptr_array_index(running, i), w))
				it = g_ptr_array_index(running, i);
		if (!it) {
			it = g_new0(Item, 1);
			it->klass = lower(wnck_window_get_class_group_name(w));
			it->exe = instance_of(w);
			GdkPixbuf *icon = wnck_window_get_icon(w);
			GdkPixbuf *scaled = icon ? gdk_pixbuf_scale_simple(icon, ICON, ICON, GDK_INTERP_BILINEAR) : NULL;
			GtkWidget *image = scaled ? gtk_image_new_from_pixbuf(scaled)
			                          : gtk_image_new_from_icon_name("application-x-executable", GTK_ICON_SIZE_DIALOG);
			gtk_image_set_pixel_size(GTK_IMAGE(image), ICON);
			if (scaled)
				g_object_unref(scaled);
			WnckClassGroup *g = wnck_window_get_class_group(w);
			gtk_box_pack_start(GTK_BOX(running_box), item_widget(it, image, g ? wnck_class_group_get_name(g) : NULL),
			                   FALSE, FALSE, 0);
			g_ptr_array_add(running, it);
		}
		it->windows = g_list_prepend(it->windows, w);
	}
	WnckWindow *active = wnck_screen_get_active_window(screen);
	for (guint i = 0; i < pinned->len; i++)
		set_dot(g_ptr_array_index(pinned, i), active);
	for (guint i = 0; i < running->len; i++)
		set_dot(g_ptr_array_index(running, i), active);
	gtk_widget_show_all(running_box);
	gtk_widget_set_visible(running_sep, running->len > 0);
	place();
	return G_SOURCE_REMOVE;
}

static void changed(void) {
	if (!refresh_id)
		refresh_id = g_timeout_add(50, refresh, NULL);
}

static void activate(GtkButton *b, Item *it) {
	guint32 t = gtk_get_current_event_time();
	if (!it->windows) {
		if (it->app) {
			GdkAppLaunchContext *ctx = gdk_display_get_app_launch_context(gtk_widget_get_display(win));
			GError *err = NULL;
			if (!g_app_info_launch(G_APP_INFO(it->app), NULL, G_APP_LAUNCH_CONTEXT(ctx), &err)) {
				g_printerr("pyo-dock: %s\n", err->message);
				g_error_free(err);
			}
			g_object_unref(ctx);
		}
		return;
	}
	WnckWindow *w = it->windows->data, *active = wnck_screen_get_active_window(screen);
	/* In front already: the next of its windows, the one furthest back. */
	if (active && g_list_find(it->windows, active)) {
		if (!it->windows->next)
			return;
		w = g_list_last(it->windows)->data;
	}
	if (wnck_window_is_minimized(w))
		wnck_window_unminimize(w, t);
	wnck_window_activate(w, t);
}

static void window_opened(WnckScreen *s, WnckWindow *w, gpointer data) {
	g_signal_connect(w, "class-changed", G_CALLBACK(changed), NULL);
	g_signal_connect(w, "state-changed", G_CALLBACK(changed), NULL);
	changed();
}

static gboolean tick(gpointer data) {
	time_t now = time(NULL);
	struct tm tm;
	localtime_r(&now, &tm);
	char buf[64];
	strftime(buf, sizeof buf, "%H:%M", &tm);
	gtk_label_set_text(GTK_LABEL(clock_time), buf);
	strftime(buf, sizeof buf, "%a %-d %b", &tm);
	gtk_label_set_text(GTK_LABEL(clock_date), buf);
	strftime(buf, sizeof buf, "%A, %-d %B %Y", &tm);
	gtk_widget_set_tooltip_text(clock_box, buf);
	/* Again at the next minute. */
	g_timeout_add_seconds(60 - tm.tm_sec, tick, NULL);
	return G_SOURCE_REMOVE;
}

int main(int argc, char **argv) {
	gdk_set_allowed_backends("x11");
	gtk_init(&argc, &argv);
	/* As a pager: the window manager does what it asks. */
	WnckHandle *wnck = wnck_handle_new(WNCK_CLIENT_TYPE_PAGER);
	wnck_handle_set_default_icon_size(wnck, 48);

	GtkCssProvider *css = gtk_css_provider_new();
	gtk_css_provider_load_from_data(css, CSS, -1, NULL);
	gtk_style_context_add_provider_for_screen(gdk_screen_get_default(), GTK_STYLE_PROVIDER(css),
	                                          GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

	win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
	gtk_widget_set_name(win, "pyo-dock");
	gtk_window_set_title(GTK_WINDOW(win), "pyo-dock");
	gtk_window_set_type_hint(GTK_WINDOW(win), GDK_WINDOW_TYPE_HINT_DOCK);
	gtk_window_set_decorated(GTK_WINDOW(win), FALSE);
	gtk_window_set_resizable(GTK_WINDOW(win), FALSE);
	gtk_window_set_accept_focus(GTK_WINDOW(win), FALSE);
	gtk_window_set_skip_taskbar_hint(GTK_WINDOW(win), TRUE);
	gtk_window_set_skip_pager_hint(GTK_WINDOW(win), TRUE);
	gtk_window_set_keep_above(GTK_WINDOW(win), TRUE);
	gtk_window_stick(GTK_WINDOW(win));

	GtkWidget *items = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
	gtk_widget_set_name(items, "items");
	gtk_container_add(GTK_CONTAINER(win), items);
	pinned_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
	running_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
	running_sep = gtk_separator_new(GTK_ORIENTATION_VERTICAL);
	gtk_style_context_add_class(gtk_widget_get_style_context(running_sep), "dock");
	GtkWidget *clock_sep = gtk_separator_new(GTK_ORIENTATION_VERTICAL);
	gtk_style_context_add_class(gtk_widget_get_style_context(clock_sep), "dock");
	clock_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
	gtk_widget_set_name(clock_box, "clock");
	gtk_widget_set_valign(clock_box, GTK_ALIGN_CENTER);
	clock_time = gtk_label_new(NULL);
	clock_date = gtk_label_new(NULL);
	gtk_style_context_add_class(gtk_widget_get_style_context(clock_time), "time");
	gtk_style_context_add_class(gtk_widget_get_style_context(clock_date), "date");
	gtk_box_pack_start(GTK_BOX(clock_box), clock_time, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(clock_box), clock_date, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(items), pinned_box, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(items), running_sep, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(items), running_box, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(items), clock_sep, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(items), clock_box, FALSE, FALSE, 0);

	pinned = g_ptr_array_new();
	running = g_ptr_array_new_with_free_func(free_item);
	for (int i = 1; i < argc; i++) {
		GDesktopAppInfo *app = g_desktop_app_info_new_from_filename(argv[i]);
		if (!app) {
			g_printerr("pyo-dock: can't read %s\n", argv[i]);
			continue;
		}
		Item *it = g_new0(Item, 1);
		it->app = app;
		it->klass = lower(g_desktop_app_info_get_startup_wm_class(app));
		const char *exe = g_app_info_get_executable(G_APP_INFO(app));
		char *base = exe ? g_path_get_basename(exe) : NULL;
		it->exe = lower(base);
		g_free(base);
		GIcon *icon = g_app_info_get_icon(G_APP_INFO(app));
		GtkWidget *image = icon ? gtk_image_new_from_gicon(icon, GTK_ICON_SIZE_DIALOG)
		                        : gtk_image_new_from_icon_name("application-x-executable", GTK_ICON_SIZE_DIALOG);
		gtk_image_set_pixel_size(GTK_IMAGE(image), ICON);
		gtk_box_pack_start(GTK_BOX(pinned_box), item_widget(it, image, g_app_info_get_name(G_APP_INFO(app))),
		                   FALSE, FALSE, 0);
		g_ptr_array_add(pinned, it);
	}

	tick(NULL);
	gtk_widget_show_all(win);
	gtk_widget_hide(running_sep);
	place();
	g_signal_connect(gtk_widget_get_screen(win), "size-changed", G_CALLBACK(changed), NULL);

	screen = wnck_handle_get_default_screen(wnck);
	wnck_screen_force_update(screen);
	for (GList *l = wnck_screen_get_windows(screen); l; l = l->next)
		window_opened(screen, l->data, NULL);
	g_signal_connect(screen, "window-opened", G_CALLBACK(window_opened), NULL);
	g_signal_connect(screen, "window-closed", G_CALLBACK(changed), NULL);
	g_signal_connect(screen, "active-window-changed", G_CALLBACK(changed), NULL);
	g_signal_connect(screen, "window-stacking-changed", G_CALLBACK(changed), NULL);
	changed();
	gtk_main();
	return 0;
}
