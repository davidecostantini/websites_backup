This script is able to manage websites backup for a single website or in a shared host.
It iterate inside the configured folder and create a tar archive of the folder that is stored in a proper folder with well recognisable naming convention including date.
it is also able to backup a database which has to be specified in a file called "dbname.backup" inside the main website folder which include just the DB name.
It's also able to ship the logs to an FTP server or over SSH, to do so just specify an FTP or SSH hosts.
