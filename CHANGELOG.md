## 3.0.0

### Updates

* **Complete rewrite** using curses for status drawing, way better code structure and more features

  * DbSucker is now structured to be DBMS agnostic but each DBMS will require it's API implementation.<br>
    Mysql is the only supported adapter for now but feel free to add support for other DBMS.
  * Note that the SequelImporter has been temporarily removed since I need to work on it some more.
  * Added integrity checking (checksum checking of transmitted files)
  * Added a lot of status displays
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
