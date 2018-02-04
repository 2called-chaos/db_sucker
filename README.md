# DbSucker

**DbSucker – Sucks DBs as sucking DBs sucks!**

`db_sucker` is an executable which allows you to "suck"/pull remote MySQL (others may follow) databases to your local server.
You configure your hosts via an YAML configuration in which you can define multiple variations to add constraints on what to dump (and pull).

This tool is meant for pulling live data into your development environment. **It is not designed for backups!** but you might get away with it.

![screenshot](https://imgur.com/EAjWrEd)

---
## Alpha product (v3 is a rewrite), use at your own risk, always have a backup!
---

## Features

* independent parallel dump / download / import cycle for each table
* verifies file integrity via SHA
* flashy and colorful curses based interface with keyboard shortcuts
* more status indications than you would ever want (even more if the remote has a somewhat recent `pv` (pipeviewer) installed)
* limit concurrency of certain type of tasks (e.g. limit downloads, imports, etc.)
* uses more threads than any application should ever use (seriously it's a nightmare)


## Requirements

Currently `db_sucker` only handles the following data-flow constellation:

  - Remote MySQL -> [SSH] -> local MySQL

On the local side you will need:
  - unixoid OS
  - Ruby (>= 2.0, != 2.3.1 see gotchas)
  - mysql2 gem
  - MySQL client (`mysql` command will be used for importing)

On the remote side you will need:
  - unixoid OS
  - Probably SSH access + sftp subsystem (password and/or keyfile)
  - any folder with write permissions (for the temporary dumps)
  - mysqldump executable
  - MySQL credentials :)


## Installation

Simple as:

    $ gem install db_sucker

At the moment you are advised to adjust the MaxSessions limit on your remote SSH server if you run into issues, see Caveats.

You will also need at least one configuration, see Configuration.


## Usage

To get a list of available options invoke `db_sucker` with the `--help` or `-h` option:

    Usage: db_sucker [options] [identifier [variation]]

    # Application options
            --new NAME                   Generates new container config in /Users/chaos/.db_sucker
        -a, --action ACTION              Dispatch given action
        -m, --mode MODE                  Dispatch action with given mode
        -n, --no-deffer                  Don't use deferred import for files > 50 MB SQL data size.
        -l, --list-databases             List databases for given identifier.
        -t, --list-tables [DATABASE]     List tables for given identifier and database.
                                         If used with --list-databases the DATABASE parameter is optional.
        -o, --only table,table2          Only suck given tables. Identifier is required, variation is optional (defaults to default).
                                         WARNING: ignores ignore_always option
        -e, --except table,table2        Don't suck given tables. Identifier is required, variation is optional (defaults to default).
        -c, --consumers NUM=10           Maximal amount of tasks to run simultaneously
            --stat-tmp                   Show information about the remote temporary directory.
                                         If no identifier is given check local temp directory instead.
            --cleanup-tmp                Remove all temporary files from db_sucker in target directory.
            --simulate                   To use with --cleanup-tmp to not actually remove anything.

    # General options
        -d, --debug [lvl=1]              Enable debug output
            --monochrome                 Don't colorize output (does not apply to curses)
            --no-window                  Disables curses window alltogether (no progress)
        -h, --help                       Shows this help
        -v, --version                    Shows version and other info
        -z                               Do not check for updates on GitHub (with -v/--version)

    The current config directory is /Users/chaos/.db_sucker

To get a list of available interface options and shortcuts press `?` or type `:help` while the curses interface is running (if you just want to see the help without running a task use `db_sucker -a cloop`).

    Key Bindings (case sensitive):

        ?  shows this help
        ^  eval prompt (app context, synchronized)
        L  show latest spooled log entries (no scrolling)
        P  kill SSH polling (if it stucks)
        T  create core dump and open in editor
        q  quit prompt
        Q  same as ctrl-c
        :  main prompt

    Main prompt commands:

        :? :h(elp)                      shows this help
        :q(uit)                         quit prompt
        :q! :quit!                      same as ctrl-c
        :kill                           (dirty) interrupts all workers
        :kill!                          (dirty) essentially SIGKILL (no cleanup)
        :dump                           create and open coredump
        :eval       [code]              executes code or opens eval prompt (app context, synchronized)
        :c(ancel)   <table_name|--all>  cancels given or all workers
        :p(ause)    <table_name|--all>  pauses given or all workers
        :r(esume)   <table_name|--all>  resumes given or all workers

## Configuration (for sucking) - YAML format

* Note: The name is just for the filename, how you address it later is defined within the file.
* Create a new configuration with `db_sucker --new <name>`, the name should optimally consist of `a-z_-`.
* If `ENV["EDITOR"]` is set, the newly generated config file will be opened with that, i.e. `EDITOR=vim db_sucker --new <name>`.
* Change the file to your liking and be aware that YAML is indendation sensitive (don't mix spaces with tabs).
* If you want to DbSucker to ignore a certain configuration, rename it to start with two underscores, e.g. `__foo.yml`.
* The default destination for configuration files is `~/.db_sucker` (indicated in --help) but can be changed with the `DBS_CFGDIR` enviromental variable.

## Configuration (application) - Ruby format

DbSucker has a lot of settings and other mechanisms which you can tweak and utilize by creating a `~/.db_sucker/config.rb` file. You can change settings, add hooks or define own actions. For more information please take a look at the [documented example config](https://github.com/2called-chaos/db_sucker/blob/master/doc/config_example.rb) and/or [complete list of all settings](https://github.com/2called-chaos/db_sucker/blob/master/lib/db_sucker/application.rb#L58-L129).


## Deferred import

Tables with an uncompressed filesize of over 50MB will be queued up for import. Files smaller than 50MB will be imported concurrently with other tables. When all those have finished the large ones will import one after another. You can skip this behaviour with the `-n` resp. `--no-deffer` option. The threshold is changeable in your `config.rb`, see Configuration.


## Importer

Currently there is only the "binary" importer which will use the mysql client binary. A [sequel](https://github.com/jeremyevans/sequel) importer has yet to be ported from v2.

* **void10** Used for development/testing. Sleeps for 10 seconds and then exits.
* **binary** Default import using `mysql` executable
  * **+dirty** Same as default but the dump will get wrapped:
    ```
      (
        echo "SET AUTOCOMMIT=0;"
        echo "SET UNIQUE_CHECKS=0;"
        echo "SET FOREIGN_KEY_CHECKS=0;"
        cat dumpfile.sql
        echo "SET FOREIGN_KEY_CHECKS=1;"
        echo "SET UNIQUE_CHECKS=1;"
        echo "SET AUTOCOMMIT=1;"
        echo "COMMIT;"
      ) | mysql -u... -p... target_database
    ```
    **The wrapper will only be used on deferred imports (since it alters global MySQL sever variables)!**
* **sequel** Not yet implemented

## Caveats  / Bugs

### General

* Ruby 2.3.0 has a bug that might segfault your ruby if some exceptions occur, this is fixed since 2.3.1 and later
* Consumers that are waiting (e.g. deferred or slot pool) won't release their tasks, if you have to few consumers you might softlock

### SSH errors / MaxSessions

Under certain conditions the program might softlock when the remote unexpectedly closes the SSH connection or stops responding to it (bad packet error). The same might happen when the remote denies a new connection (e.g. to many connections/sessions). If you think it stalled, try `:kill` (semi-clean) or `:kill!` (basically SIGKILL). If you did kill it make sure to run the cleanup task to get rid of potentially big dump files.

**DbSucker typically needs 2 sessions + 1 for each download and you should have some spare for canceling remote processes**

If you get warnings that SSH errors occured (and most likely tasks fail), please do any of the following to prevent the issue:

  * Raise the MaxSession setting on the remote SSHd server if you can (recommended)
  * Lower the amount of slots for concurrent downloads (see Configuration)
  * Lower the amount of consumers (not recommended, use slots instead)

You can run basic SSH diagnosis tests with `db_sucker <config_identifier> -a sshdiag`.

## Todo

* Migrate sequel importer from v2
* Add dirty features again (partial dumps, dumps with SQL constraints)
* Figure out a way for consumers to release waiting tasks to prevent logical softlocks
* Optional encrypted HTTP(s) gateway for faster download of files (I can't figure out why Ruby SFTP is soooo slow)


## Contributing

1. Fork it ( http://github.com/2called-chaos/db_sucker/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
6. Get a psych, if you understand what I did here you deserve a medal!
