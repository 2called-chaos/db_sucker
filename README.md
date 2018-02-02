# DB Sucker

**DB Sucker – Sucks DBs as sucking DBs sucks!**

`db_sucker` is an executable which allows you to "suck"/pull remote MySQL databases to your local server.
You configure your hosts via an YAML configuration in which you can define multiple variations to add constraints on what to dump (and pull).

This tool is meant for pulling live data into your development environment. **It is not designed for backups!**


**BETA product, use at your own risk, always have a backup!**



## Requirements

Currently `db_sucker` only handles the following constellation:

  - local -> SSH -> MySQL

On the local side you will need:
  - unixoid OS
  - Ruby (>= 2)
  - MySQL client (`mysql` command will be used for importing)

On the remote side you will need:
  - unixoid OS
  - SSH access + sftp subsystem (password and/or keyfile)
  - any folder with write permissions (for the temporary dumps)
  - mysqldump executable


## Installation

Simple as:

    $ gem install db_sucker

At the moment you are required to adjust the MaxConnections limit on your remote SSH server (from default 10 to around 30).
Each table requires a connection to download + a few others. See Caveats.

You will also need at least one configuration, see Configuration.


## Usage

To get a list of available options invoke `db_sucker` with the `--help` or `-h` option:

    Usage: db_sucker [options] [identifier] [variation]
    # Application options
        -n, --no-deffer                  Don't use deferred import for files > 50 MB SQL data size.
        -l, --list-databases             List databases for given identifier.
        -t, --list-tables [DATABASE]     List tables for given identifier and database.
                                         If used with --list-databases the DATABASE parameter is optional.
            --stat-tmp                   Show information about the remote temporary directory.
                                         If no identifier is given check local temp directory instead.
            --cleanup-tmp                Remove all temporary files from db_sucker in target directory.
            --simulate                   To use with --cleanup-tmp to not actually remove anything.

    # General options
        -d, --debug                      Debug output
        -m, --monochrome                 Don't colorize output
        -h, --help                       Shows this help
        -v, --version                    Shows version and other info
        -z                               Do not check for updates on GitHub (with -v/--version)

    The current config directory is /Users/chaos/.db_sucker


## Configuration
Create a file with a `.yml` extension in your config path. It defaults to `~/.db_sucker` and can be changed
with the `DBS_CFGDIR` enviromental variable. This is a template configuration you can use:

```
my_identifier:
  # definition of the remote
  source:
    ssh:
      hostname: my.server.net

      # If left blank use username of current logged in user (SSH default behaviour)
      username: my_dump_user

      # If you login via password you must declare it here (prompt will break).
      # Consider using key authentication and leave the password blank.
      password: my_secret

      # Can be a string or an array of strings.
      # Can be absolute or relative to the _location of this file_ (or start with ~)
      # If left blank Net::SSH will attempt to use your ~/.ssh/id_rsa automatically.
      keyfile: ~/.ssh/id_rsa

      # The remote temp directory to place dumpfiles in. Must be writable by the
      # SSH user and should be exclusively used for this tool though cleanup only
      # removes .dbsc files. The directory must exist!
      tmp_location: /home/my_dump_user/db_sucker_tmp

    # Remote database settings. DON'T limit tables via arguments!
    hostname: 127.0.0.1
    username: my_dump_user
    password: my_secret
    database: my_database
    args: --single-transaction # for innoDB

  # define as many variations here as you want.
  variations:
    # define your local database settings, args will be passed to the `mysql` command for import.
    all:
      database: tomatic
      hostname: localhost
      username: root
      password:
      args:

    # you can inherit all settings from another variation with the `base` setting.
    quick:
      base: all
      only: [this_table, and_that_table]

    # you can use `only` or `except` to limit the tables you want to suck but not both at the same time.
    unheavy:
      base: all
      except: [orders, order_items, activities]

    # NOT YET IMPLEMENTED
    # limit data by passing SQL constraints to mysqldump
    recent_orders:
      base: all
      only: [orders, order_items]
      constraints:
        orders: "WHERE created_at BETWEEN date_sub(now(), INTERVAL 1 WEEK) and now()"
        order_items: "WHERE created_at BETWEEN date_sub(now(), INTERVAL 1 WEEK) and now()"
```

## Program workflow

  1. Establish SSH connection to remote
  1. Check temporary directory
  1. *(async)* Invoke `mysqldump` for each table of the target database
  1. *(async)* Compress each file with gzip
  1. *(async)* Establish SFTP connection and download file to local temp directory
  1. *(async)* Uncompress the file on the local side
  1. *(async)* Import file into database server


## Deffered import

Tables with an uncompressed filesize of over 50MB will be queued up for import. Files smaller than 50MB will
be imported concurrently with other tables. When all those have finished the large ones will import one after
another. You can skip this behaviour with the `-n` resp. `--no-deffer` option.


## Importer

Currently there are two (well three) importers to choose from.

* **void10** Used for development/testing. Sleeps for 10 seconds and then exit.
* **default** Default import using `mysql` executable
* **dirty** Same as default but the dump will get wrapped:
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


## Caveats  / Bugs

* Under certain conditions the program might softlock when the remote unexpectedly closes the SSH connection or stops responding to it (bad packet error). The same might happen when the remote denies a new connection (e.g. to many connections). Since the INT signal is trapped you must kill the process. If you did kill it make sure to run the cleanup task to get rid of potentially big dump files.
  The issue is that I cannot download multiple files over the same connection at the same time. Until I figured it out there are typically
  2 connections + 1 for each download. With (atm hardcoded) 20 workers you will reach, with one process of db_sucker, 22 connections in the worst case.
* Ruby 2.3.0 has a bug that might segfault your ruby if some exceptions occur, this is fixed since 2.3.1 and later
* Consumers that are waiting (e.g. deferred or slot pool) won't release it's task, if you have to few consumers you might softlock


## Todo

* Download pooling (currently each download requires it's own SSH session due to concurrency problems I was unable to figure out)
* Attempt to read the max_connections setting from the remote SSH and avoid exceeding it.
* Better error handling for SSH errors.


## Contributing

1. Fork it ( http://github.com/2called-chaos/db_sucker/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
