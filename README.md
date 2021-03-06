# distribute_work
distribute_work is a Bash shell script that would change the dates of your commits based on the calculated workload needed to develop them.

## Usage
distribute_work is able to work on a defined range of commits, to use the script you need to pass the starting (top, latest) SHA of the comit, the last (bottom, oldest) SHA you want the script to work on, the starting hour - the hour you want the script to start distributing the work and the seconds (amount of workload) you want to distruibute over the range of commits. The result is changed dates of commits based on the artificial (and estimated) caclulated workload needed to develop them.

Usage:
```bash
./distribute_work.sh [SHA1] [SHA2] [starting hour] [seconds to distribute]
```

For example:
```bash
./distribute_work.sh 1e17200de5 dab17a71ee 20:00 3600
```
Will distribute 3600 seconds (1 hour) over the range of commits (staring from top 1e17200de5, ending on the bottom dab17a71ee, inclusively) starting from 20:00.
