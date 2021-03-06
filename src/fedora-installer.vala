// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.FedoraInstaller: UnattendedInstaller {
    private bool mounted;

    private File source_dir;
    private File kernel_file;
    private File initrd_file;

    private string kernel_path;
    private string initrd_path;

    // F16 ships buggly QXL package and spice-vdagent package won't be shipped until F17 so we install from
    // up2date remote repos for anything less than F17.
    private bool use_remote_repos { get { return express_install && uint64.parse (os.version) < 17; } }

    private static Regex repo_regex;

    static construct {
        try {
            repo_regex = new Regex ("BOXES_FEDORA_REPOS");
        } catch (RegexError error) {
            // This just can't fail
            assert_not_reached ();
        }
    }

    public FedoraInstaller.copy (InstallerMedia media) throws GLib.Error {
        var source_path = get_unattended_dir ("fedora.ks");

        base.copy (media, source_path, "ks.cfg");
        password_mandatory = true;
    }

    public override void set_direct_boot_params (GVirConfig.DomainOs os) {
        if (kernel_path == null || initrd_path == null)
            return;

        os.set_kernel (kernel_path);
        os.set_ramdisk (initrd_path);
        os.set_cmdline ("ks=hd:sdb:" + unattended_dest_name);
    }

    public override void check_needed_info () throws UnattendedInstallerError.SETUP_INCOMPLETE {
        base.check_needed_info ();

        if (!use_remote_repos)
            return;

        try {
            var client = new SocketClient ();
            client.connect_to_host ("fedoraproject.org", 80);
        } catch (GLib.Error error) {
            var message = _("Internet access required for express installation of Fedora 16 and older");

            throw new UnattendedInstallerError.SETUP_INCOMPLETE (message);
        }
    }

    protected override async void prepare_direct_boot (Cancellable? cancellable) throws GLib.Error {
        if (!express_toggle.active)
            return;

        if (os_media.kernel_path == null || os_media.initrd_path == null)
            return;

        yield mount_media (cancellable);

        yield extract_boot_files (cancellable);

        yield normal_clean_up (cancellable);
    }

    protected override void clean_up () throws GLib.Error {
        base.clean_up ();

        if (kernel_file != null) {
            debug ("Removing '%s'..", kernel_path);
            kernel_file.delete ();
            debug ("Removed '%s'.", kernel_path);
        }

        if (initrd_file != null) {
            debug ("Removing '%s'..", initrd_path);
            initrd_file.delete ();
            debug ("Removed '%s'.", initrd_path);
        }
    }

    protected override string fill_unattended_data (string data) throws RegexError {
        var str = base.fill_unattended_data (data);

        var repos = (use_remote_repos) ? "repo --name=fedora\nrepo --name=updates" : "";

        return repo_regex.replace (str, str.length, 0, repos);
    }

    private async void normal_clean_up (Cancellable? cancellable) throws GLib.Error {
        if (!mounted)
            return;

        debug ("Unmounting '%s'..", mount_point);
        string[] argv = { "fusermount", "-u", mount_point };
        yield exec (argv, cancellable);
        debug ("Unmounted '%s'.", mount_point);

        source_dir.delete ();
        debug ("Removed '%s'.", mount_point);
    }

    private async void mount_media (Cancellable? cancellable) throws GLib.Error {
        if (mount_point != null) {
            source_dir = File.new_for_path (mount_point);

            return;
        }

        mount_point = get_user_unattended_dir (os.short_id);
        var dir = File.new_for_path (mount_point);
        try {
            dir.make_directory (null);
        } catch (IOError.EXISTS error) {}
        source_dir = dir;

        debug ("Mounting '%s' on '%s'..", device_file, mount_point);
        string[] argv = { "fuseiso", device_file, mount_point };
        yield exec (argv, cancellable);
        debug ("'%s' now mounted on '%s'.", device_file, mount_point);

        mounted = true;
    }

    private async void extract_boot_files (Cancellable? cancellable) throws GLib.Error {
        kernel_path = Path.build_filename (mount_point, os_media.kernel_path);
        kernel_file = File.new_for_path (kernel_path);
        initrd_path = Path.build_filename (mount_point, os_media.initrd_path);
        initrd_file = File.new_for_path (initrd_path);

        if (!mounted)
            return;

        kernel_path = get_user_unattended_dir (os.short_id + "-kernel");
        kernel_file = yield copy_file (kernel_file, kernel_path, cancellable);
        initrd_path = get_user_unattended_dir (os.short_id + "-initrd");
        initrd_file = yield copy_file (initrd_file, initrd_path, cancellable);
    }

    private async File copy_file (File file, string dest_path, Cancellable? cancellable) throws GLib.Error {
        var dest_file = File.new_for_path (dest_path);

        try {
            debug ("Copying '%s' to '%s'..", file.get_path (), dest_path);
            yield file.copy_async (dest_file, 0, Priority.DEFAULT, cancellable);
            debug ("Copied '%s' to '%s'.", file.get_path (), dest_path);
        } catch (IOError.EXISTS error) {}

        return dest_file;
    }
}
