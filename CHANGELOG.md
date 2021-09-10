## 4.0.0-unreleased

### Updates

* Updated net-ssh and net-sftp by major versions

### Fixes

* native sftp downloads will immediately stop if worker is cancelled

-------------------

## 3.2.1

### Updates

* Added means to signal all threads in order to wake them up as they occasionally get stuck for some reason. Press `S` or use `:signal-threads` to execute. Have yet to find the culprint :)
* Slight UX improvements, silent commands briefly flash the screen, invalid commands ring the bell

### Fixes

* don't warn about orphaned concurrent-ruby threads, debug log trace of remaining threads
* join killed threads to ensure they are dead
* minor sshdiag fixes/enhancements

-------------------

## 3.2.0

### Updates

* Added support for native sftp command line utility (see application option `file_transport`) but it
  only works with non-interactive key authentication.

### Fixes

* Prevent application from crashing when eval produces non-StandardErrors (e.g. SyntaxErrors)

-------------------

## 3.1.1

### Fixes

* Prevent a single task (running in main thread) to summon workers (and fail) when getting deferred

-------------------

## 3.1.0

### Fixes

* Prevent app to run out of consumers when tasks are waiting for defer ready
* Prevent IO errors on Ruby < 2.3 in uncompress
* Prevent racing conditions in SSH diagnose task
* Minor fixes

-------------------

## 3.0.3

* no changes, fixed my tag screwup

-------------------

## 3.0.2

* no changes, github tags can't be altered, I screwed up

-------------------

## 3.0.1

### Fixes

* hotfix for 3.0.0 release

-------------------

## 3.0.0

### Updates

* **Complete rewrite** using curses for status drawing, way better code structure and more features

  * DbSucker is now structured to be DBMS agnostic but each DBMS will require it's API implementation.<br>
    Mysql is the only supported adapter for now but feel free to add support for other DBMS.
  * Note that the SequelImporter has been temporarily removed since I need to work on it some more.
  * Added integrity checking (checksum checking of transmitted files)
  * Added a lot of status displays
  * Added a vim-like command interface (press : and then a command, e.g. ":?"+enter but actually you could just press ?)
  * Configurations haven't changed *except*
    * an "adapter" option is now mandatory on both source and variations.
    * gzip option has been removed, if your "file" option ends with ".gz" we assume gzip
    * a lot of new options have been added, view example_config.yml to see them all

### Fixes

* lots of stuff I guess :)

-------------------

## 2.0.0

* Added option to skip deferred import
* Added DBS_CFGDIR environment variable to change configuration directory
* Added Sequel importer
* Added variation option "file" and "gzip" (will copy the downloaded file in addition to importing)
* Added variation option "ignore_always" (always excludes given tables)
* Added mysql dirty importer
* Make some attempts to catch mysql errors that occur while dumping tables
* lots of other small fixes/changes

-------------------

## 1.0.1

* Initial release

-------------------

## 1.0.0

* Unreleased
