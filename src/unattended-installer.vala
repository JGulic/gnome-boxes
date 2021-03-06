// This file is part of GNOME Boxes. License: LGPLv2+

using GVirConfig;

public errordomain UnattendedInstallerError {
    COMMAND_FAILED,
    SETUP_INCOMPLETE
}

private abstract class Boxes.UnattendedInstaller: InstallerMedia {
    public bool express_install {
        get { return express_toggle.active; }
    }

    public string username {
        get { return username_entry.text; }
    }

    public string password {
        owned get { return password_entry.text; }
    }

    public string hidden_password {
        owned get {
            return password_entry.text.length > 0 ?
                   string.nfill (password_entry.text_length, '*') : _("no password");
        }
    }

    public bool password_mandatory { get; protected set; }

    protected string unattended_src_path;
    protected string unattended_dest_name;
    protected DataStreamNewlineType newline_type;

    protected string disk_path;

    private bool created_disk;

    protected Gtk.Table setup_table;
    protected Gtk.Label setup_label;
    protected Gtk.HBox setup_hbox;
    protected Gtk.Switch express_toggle;
    protected Gtk.Entry username_entry;
    protected Gtk.Entry password_entry;

    protected string timezone;
    protected string kbd;
    protected string lang;

    private static Regex username_regex;
    private static Regex password_regex;
    private static Regex timezone_regex;
    private static Regex kbd_regex;
    private static Regex lang_regex;
    private static Fdo.Accounts accounts;

    static construct {
        try {
            username_regex = new Regex ("BOXES_USERNAME");
            password_regex = new Regex ("BOXES_PASSWORD");
            timezone_regex = new Regex ("BOXES_TZ");
            kbd_regex = new Regex ("BOXES_KBD");
            lang_regex = new Regex ("BOXES_LANG");
            try {
                accounts = Bus.get_proxy_sync (BusType.SYSTEM, "org.freedesktop.Accounts", "/org/freedesktop/Accounts");
            } catch (GLib.Error error) {
                warning ("Failed to connect to D-Bus service '%s': %s", "org.freedesktop.Accounts", error.message);
            }
        } catch (RegexError error) {
            // This just can't fail
            assert_not_reached ();
        }
    }

    public UnattendedInstaller.copy (InstallerMedia media,
                                     string         unattended_src_path,
                                     string         unattended_dest_name) throws GLib.Error {
        os = media.os;
        os_media = media.os_media;
        label = media.label;
        device_file = media.device_file;
        from_image = media.from_image;
        mount_point = media.mount_point;
        resources = media.resources;

        disk_path = get_pkgcache (os.short_id + "-unattended.img");
        this.unattended_src_path = unattended_src_path;
        this.unattended_dest_name = unattended_dest_name;
        newline_type = DataStreamNewlineType.LF;

        var time = TimeVal ();
        var date = new DateTime.from_timeval_local (time);
        timezone = date.get_timezone_abbreviation ();

        var settings = new GLib.Settings ("org.gnome.libgnomekbd.keyboard");
        var layouts = settings.get_strv ("layouts");
        kbd = layouts[0] ?? "us";

        var langs = Intl.get_language_names ();
        lang = langs[0];

        setup_ui ();
    }

    public async void setup (Cancellable? cancellable) throws GLib.Error {
        if (!express_toggle.active) {
            debug ("Unattended installation disabled.");

            return;
        }

        try {
            if (yield unattended_disk_exists (cancellable))
                debug ("Found previously created unattended disk image for '%s', re-using..", os.short_id);
            else
                yield create_disk_image (cancellable);

            yield copy_unattended_file (cancellable);
            yield prepare_direct_boot (cancellable);
        } catch (GLib.Error error) {
            clean_up ();

            throw error;
        }
    }

    public virtual void populate_setup_vbox (Gtk.VBox setup_vbox) {
        setup_vbox.pack_start (setup_label, false, false);
        setup_vbox.pack_start (setup_hbox, false, false);
    }

    public virtual void set_direct_boot_params (DomainOs os) {}

    public virtual DomainDisk? get_unattended_disk_config () {
        if (!express_toggle.active)
            return null;

        var disk = new DomainDisk ();
        disk.set_type (DomainDiskType.FILE);
        disk.set_guest_device_type (DomainDiskGuestDeviceType.DISK);
        disk.set_driver_name ("qemu");
        disk.set_driver_type ("raw");
        disk.set_source (disk_path);
        disk.set_target_dev ("sdb");

        return disk;
    }

    // Ensure needed information was provided by user
    public virtual void check_needed_info () throws UnattendedInstallerError.SETUP_INCOMPLETE {
        if (!express_toggle.active)
            return;

        if (username == "")
            throw new UnattendedInstallerError.SETUP_INCOMPLETE (_("No username provided"));

        if (password_mandatory && password == "")
            throw new UnattendedInstallerError.SETUP_INCOMPLETE
                        (_("Password required for express installation of %s"), label);
    }

    protected virtual void setup_ui () {
        setup_label = new Gtk.Label (_("Choose express install to automatically preconfigure the box with optimal settings."));
        setup_label.halign = Gtk.Align.START;
        setup_hbox = new Gtk.HBox (false, 20);
        setup_hbox.valign = Gtk.Align.START;
        setup_hbox.margin = 24;

        setup_table = new Gtk.Table (3, 3, false);
        setup_hbox.pack_start (setup_table, false, false);
        setup_table.column_spacing = 10;
        setup_table.row_spacing = 10;

        // First row
        var label = new Gtk.Label (_("Express Install"));
        label.halign = Gtk.Align.END;
        label.valign = Gtk.Align.CENTER;
        setup_table.attach_defaults (label, 1, 2, 0, 1);

        express_toggle = new Gtk.Switch ();
        express_toggle.active = !os_media.live;
        express_toggle.halign = Gtk.Align.START;
        express_toggle.valign = Gtk.Align.CENTER;
        setup_table.attach_defaults (express_toggle, 2, 3, 0, 1);

        // 2nd row (while user avatar spans over 2 rows)
        var avatar = new Gtk.Image.from_icon_name ("avatar-default", 0);
        avatar.pixel_size = 128;
        setup_table.attach_defaults (avatar, 0, 1, 1, 3);
        avatar.show_all ();
        fetch_user_avatar.begin (avatar);

        label = new Gtk.Label (_("Username"));
        label.halign = Gtk.Align.END;
        label.valign = Gtk.Align.CENTER;
        setup_table.attach_defaults (label, 1, 2, 1, 2);
        username_entry = new Gtk.Entry ();
        username_entry.text = Environment.get_user_name ();
        username_entry.halign = Gtk.Align.START;
        username_entry.valign = Gtk.Align.CENTER;
        setup_table.attach_defaults (username_entry, 2, 3, 1, 2);

        // 3rd row
        label = new Gtk.Label (_("Password"));
        label.halign = Gtk.Align.END;
        label.valign = Gtk.Align.CENTER;
        setup_table.attach_defaults (label, 1, 2, 2, 3);

        var notebook = new Gtk.Notebook ();
        notebook.show_tabs = false;
        notebook.show_border = false;
        notebook.halign = Gtk.Align.START;
        notebook.valign = Gtk.Align.CENTER;
        var button = new Gtk.Button.with_mnemonic (_("_Add Password"));
        button.visible = true;
        notebook.append_page (button);
        password_entry = new Gtk.Entry ();
        password_entry.visibility = false;
        password_entry.visible = true;
        password_entry.text = "";
        notebook.append_page (password_entry);
        button.clicked.connect (() => {
            notebook.next_page ();
            password_entry.is_focus = true;
        });
        setup_table.attach_defaults (notebook, 2, 3, 2, 3);

        foreach (var child in setup_table.get_children ())
            if (child != express_toggle)
                express_toggle.bind_property ("active", child, "sensitive", 0);
    }

    protected virtual void clean_up () throws GLib.Error {
        if (!created_disk)
            return;

        var disk_file = File.new_for_path (disk_path);

        disk_file.delete ();

        debug ("Removed '%s'.", disk_path);
    }

    protected virtual string fill_unattended_data (string data) throws RegexError {
        var str = username_regex.replace (data, data.length, 0, username_entry.text);
        str = password_regex.replace (str, str.length, 0, password);
        str = timezone_regex.replace (str, str.length, 0, timezone);
        str = kbd_regex.replace (str, str.length, 0, kbd);
        str = lang_regex.replace (str, str.length, 0, lang);

        return str;
    }

    protected virtual async void prepare_direct_boot (Cancellable? cancellable) throws GLib.Error {}

    protected async void exec (string[] argv, Cancellable? cancellable) throws GLib.Error {
        SourceFunc continuation = exec.callback;
        GLib.Error error = null;
        var context = MainContext.get_thread_default ();

        g_io_scheduler_push_job ((job) => {
            try {
                exec_sync (argv);
            } catch (GLib.Error err) {
                error = err;
            }

            var source = new IdleSource ();
            source.set_callback (() => {
                continuation ();

                return false;
            });
            source.attach (context);

            return false;
        });

        yield;

        if (error != null)
            throw error;
    }

    private async void create_disk_image (Cancellable? cancellable) throws GLib.Error {
        var disk_file = File.new_for_path (disk_path);
        var template_path = get_unattended_dir ("disk.img");
        var template_file = File.new_for_path (template_path);

        debug ("Creating disk image for unattended installation at '%s'..", disk_path);
        yield template_file.copy_async (disk_file, 0, Priority.DEFAULT, cancellable);
        debug ("Floppy image for unattended installation created at '%s'", disk_path);

        created_disk = true;
    }

    private async void copy_unattended_file (Cancellable? cancellable) throws GLib.Error {
        var unattended_src = File.new_for_path (unattended_src_path);
        var unattended_tmp_path = get_user_unattended_dir (unattended_dest_name);
        var unattended_tmp = File.new_for_path (unattended_tmp_path);

        yield create_unattended_file (unattended_src, unattended_tmp, cancellable);

        debug ("Copying unattended file '%s' into disk drive/image '%s'", unattended_dest_name, disk_path);
        // FIXME: Perhaps we should use libarchive for this?
        string[] argv = { "mcopy", "-n", "-o", "-i", disk_path,
                                   unattended_tmp_path,
                                   "::" + unattended_dest_name };
        yield exec (argv, cancellable);
        debug ("Copied unattended file '%s' into disk drive/image '%s'", unattended_dest_name, disk_path);

        debug ("Deleting temporary file '%s'", unattended_tmp_path);
        unattended_tmp.delete (cancellable);
        debug ("Deleted temporary file '%s'", unattended_tmp_path);
    }

    private async void create_unattended_file (File         source,
                                               File         destination,
                                               Cancellable? cancellable)  throws GLib.Error {
        debug ("Creating unattended file at '%s'..", destination.get_path ());
        var input_stream = yield source.read_async (Priority.DEFAULT, cancellable);
        var output_stream = yield destination.replace_async (null,
                                                             false,
                                                             FileCreateFlags.REPLACE_DESTINATION,
                                                             Priority.DEFAULT,
                                                             cancellable);
        var data_stream = new DataInputStream (input_stream);
        data_stream.newline_type = DataStreamNewlineType.ANY;
        string? str;
        while ((str = yield data_stream.read_line_async (Priority.DEFAULT, cancellable)) != null) {
            str = fill_unattended_data (str);

            str += (newline_type == DataStreamNewlineType.LF) ? "\n" : "\r\n";

            yield output_stream.write_async (str.data, Priority.DEFAULT, cancellable);
        }
        yield output_stream.close_async (Priority.DEFAULT, cancellable);
        debug ("Created unattended file at '%s'..", destination.get_path ());
    }

    private async bool unattended_disk_exists (Cancellable? cancellable) {
        var file = File.new_for_path (disk_path);

        try {
            yield file.read_async (Priority.DEFAULT, cancellable);
        } catch (IOError.NOT_FOUND not_found_error) {
            return false;
        } catch (GLib.Error error) {}

        return true;
    }

    private void exec_sync (string[] argv) throws GLib.Error {
        int exit_status = -1;

        Process.spawn_sync (null,
                            argv,
                            null,
                            SpawnFlags.SEARCH_PATH,
                            null,
                            null,
                            null,
                            out exit_status);
        if (exit_status != 0)
            throw new UnattendedInstallerError.COMMAND_FAILED ("Failed to execute: %s", string.joinv (" ", argv));
    }

    private async void fetch_user_avatar (Gtk.Image avatar) {
        if (accounts == null)
            return;

        var username = Environment.get_user_name ();
        var avatar_file = "/var/lib/AccountsService/icons/" + username;

        try {
            var path = yield accounts.FindUserByName (Environment.get_user_name ());
            Fdo.AccountsUser user = yield Bus.get_proxy (BusType.SYSTEM, "org.freedesktop.Accounts", path);
            avatar_file = user.IconFile;
        } catch (GLib.IOError error) {
            warning ("Failed to retrieve information about user '%s': %s", username, error.message);
        }

        var file = File.new_for_path (avatar_file);
        if (file.query_exists ())
            avatar.file = avatar_file;
    }
}
