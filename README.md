# wpkgreports
awk script to format the wpkg debug files from machines on our network into an email report

process a wpkg report or a folder of reports into a helpful output, this version runs on Linux, but the code is designed to "JustWork" on Windows too.

show:

* summary
* failed installs today
* successfull installs today
* failed OLD installs
* successful OLD installs

call as:

`awk -v date="$(date +"%Y-%m-%d")" -f $scriptpath/wpkgreports.awk $reportpath/*.log > /tmp/wpkgreports.txt`

A sample wpkg package definition (logfile.xml) shows how we can add the value of LastLoggedOnUser to the logfile copied to the server, which allows us to include this in the report.
