// This file is part of GNOME Boxes. License: LGPLv2+
using Config;
using Posix;

private static bool version;
private static bool checks;
private static string[] uris;

private const OptionEntry[] options = {
    { "version", 0, 0, OptionArg.NONE, ref version, N_("Display version number"), null },
    // FIXME: make it translatable after string freeze
    { "checks", 0, 0, OptionArg.NONE, ref checks, "Check virtualization capabilities", null },
    // A 'broker' is a virtual-machine manager (could be local or remote). Currently libvirt is the only one supported.
    { "", 0, 0, OptionArg.STRING_ARRAY, ref uris, N_("URI to display, broker or installer media"), null },
    { null }
};

private static void parse_args (ref unowned string[] args) {
    var parameter_string = _("- A simple application to access remote or virtual machines");
    var opt_context = new OptionContext (parameter_string);
    opt_context.set_help_enabled (true);
    opt_context.set_ignore_unknown_options (true);
    opt_context.add_main_entries (options, null);
    opt_context.add_group (Gtk.get_option_group (true));
    opt_context.add_group (Cogl.get_option_group ());
    opt_context.add_group (Clutter.get_option_group_without_init ());
    opt_context.add_group (GtkClutter.get_option_group ());
    // FIXME: add spice

    try {
        opt_context.parse (ref args);
    } catch (OptionError.BAD_VALUE err) {
        GLib.stdout.printf (opt_context.get_help (true, null));
        exit (1);
    } catch (OptionError error) {
        warning (error.message);
    }

    if (version) {
        GLib.stdout.printf ("%s\n", Config.BUILD_VERSION);
        exit (0);
    }

    if (checks) {
        var loop = new GLib.MainLoop ();
        run_checks.begin ((obj, res) => {
            run_checks.end (res);
            loop.quit ();
        });
        loop.run ();
        exit (0);
    }
}

private async void run_checks () {
    var cpu = yield Boxes.check_cpu_vt_capability ();
    var kvm = yield Boxes.check_module_kvm_loaded ();

    // FIXME: make it translatable after string freeze, and add proper UI & docs
    GLib.stdout.printf ("The CPU is capable of virtualization: %s\n".printf (Boxes.yes_no (cpu)));
    GLib.stdout.printf ("The KVM module is loaded: %s\n".printf (Boxes.yes_no (kvm)));
}

public int main (string[] args) {
    Intl.bindtextdomain (GETTEXT_PACKAGE, GNOMELOCALEDIR);
    Intl.bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");
    Intl.textdomain (GETTEXT_PACKAGE);
    GLib.Environment.set_application_name (_("Boxes"));

    parse_args (ref args);

    try {
        GVir.init_object_check (ref args);
    } catch (GLib.Error err) {
        error (err.message);
    }

    Gtk.Window.set_default_icon_name ("gnome-boxes");
    Gtk.Settings.get_default ().gtk_application_prefer_dark_theme = true;
    var provider = new Gtk.CssProvider ();
    try {
        var sheet = Boxes.get_style ("gtk-style.css");
        provider.load_from_path (sheet);
        Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (),
                                                  provider,
                                                  600);
    } catch (GLib.Error error) {
        warning (error.message);
    }

    var app = new Boxes.App ();

    app.ready.connect ((first_time) => {
        if (uris != null) {
            // FIXME: We only handle a single URI from commandline
            var file = File.new_for_commandline_arg (uris[0]);
            app.wizard.open_with_uri (file.get_uri ());
        } else if (first_time) {
            app.ui_state = Boxes.UIState.WIZARD;
        }
    });

    return app.run ();
}

