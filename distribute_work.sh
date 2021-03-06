#!/bin/bash

#TODO: Make debug flag that could enable specific logs (like --debug flag)
#https://stackoverflow.com/questions/5972491/how-to-enable-or-disable-multiple-echo-statements-in-bash-ecript

#TODO: getopts for parameters
#TODO: Difference between author date and commiter date?
#TODO: Exit in case of lack of arguments (or print help and exit)
#TODO: Restrict the arguments to be SHA or SHA convertible ("HEAD", tag, branch and so on)

#print the usage of this script
help()
{
   echo "Usage: ./distribute_work.sh [SHA1] [SHA2] [starting hour] [seconds to distribute]"
}

##if there is a lack of exactly two arguments that have been passed to the script
#if ! [ -n "$1" ] || ! [ -n "$2" ]; then
#   help
#   exit
#fi


#check the arguments first - if don't match then
# call something like evaluate_input_parameters...
# print help if they don't match
# if okay, then go to main

# Params: $1 being SHA of top commit, $2 is SHA of bottom commit
main()
{
  functionCallPreamble

  #Reading the input parameters
  declare -r sha1=$1
  declare -r sha2=$2
  declare -r staring_hour=$3
  declare -r duration_in_seconds=$4

  #The map for holding SHA and weight pair
  declare -A weights

  #Holding the old dates...
  declare -A dates

  # Holding new dates...
  declare -A newDates

  declare -A normalizedWeights
  declare -A normalizedHourOffsets

  # The array of SHAs in the range of requested commits (first index is the parent of the first commit that is processed)
  declare -a shas

  echo "Main function called..."
  # Check the range of commits to be processed
  git_commitRange "$sha1" "$sha2"

  #Firstly, extract the commits to be processed
  git_storeShas "$sha1" "$sha2"

  #The next operation is to get the weights of the commits #TODO:Wrap it in a function...
  for i in "${!shas[@]}"
  do
    if [[ $i -eq 0 ]]; then # [[ "$i" == '0' ]] less efficient because needs expanding the variable?
      continue
    fi
    echo "Calling git_checkLines() with: ""${shas[$i]}" "(commit)" "${shas[$i-1]}" "(the parent of that commit)"
    git_checkLines "${shas[$i]}" "${shas[$i-1]}"
  done

  normalizeWeights

  # Here we calculate will modify the dates of commits...
  # TODO: Instead of iterating over all SHAs and skipping the first one write an expression to start from the second one...
  for i in "${!shas[@]}"
  do
    if [[ $i == 0 ]]; then
      continue
    fi
    echo "Calling calculateDate with: ""${shas[$i]}"
    calculateDate "${shas[$i]}"
  done

  numOfShas=${#shas[*]}
  echo $numOfShas >&2 # Need to print somewhere else than the stdout
  for (( shaNumber=$(($numOfShas-1)); (( $shaNumber > 0 )) ; shaNumber-- )); do
    echo "Calling git_changeDates with: ""${shas[$shaNumber]}"
    git_changeDates "${shas[$shaNumber]}"
  done
}


decomposeStartingHour()
{
  declare -a startingHourDecomposed
  IFS=":" read -a startingHourDecomposed <<< $staring_hour
  echo "Decomposed starting hour is: "${startingHourDecomposed[@]}""
}


# Checks the number of commits given by SHA range
git_commitRange()
{
  functionCallPreamble
  # Shift to disallow the usage of input argument
  declare -r sha=$1; shift
  declare -r parentSha=$1; shift

  number_of_commits=$(git log --oneline $parentSha...$sha | wc -l)

  #debug
  trace_echo "Number of commits is: "$number_of_commits
  trace_echo $number_of_commits
}


# Checks the number of lines added in between commits given by SHA arguments, third argument is a
git_checkLines()
{
  functionCallPreamble
  # Shift to disallow the usage of input argument
  declare -r sha=$1; shift
  declare -r parentSha=$1; shift

  trace_echo "Checking lines..."
  number_of_deleted_lines=$(git diff $parentSha...$sha | grep "^\-[^-].*" | wc -l)
  number_of_added_lines=$(git diff $parentSha...$sha | grep "^\+[^+].*" | wc -l)

  #debug
  trace_echo "Number of deleted lines is: "$number_of_deleted_lines
  trace_echo "Number of added lines is: "$number_of_added_lines

  #generate a random integer of interval [0, 32] #TODO: Random factor should probably be added later
  let random_factor=$RANDOM/1000

  #the importance of the commit - base is 100 - is not normalized currently
  let weight=20*number_of_deleted_lines+80*number_of_added_lines+$random_factor

  #add weight to the map
  weights[$sha]=$weight

  #debug
  trace_echo "Weight of the commit $1 is: ""${weights["$1"]}" #does it need to be in parentheses?
}


#input parameters should be a range of commits
git_storeShas()
{
  functionCallPreamble
  # Shift to disallow the usage of input argument
  declare -r sha=$1; shift
  declare -r parentSha=$1; shift

  trace_echo "Storing SHAs..."

  #Get the parent of the first commit to be processed
  parent=$(git log --pretty=tformat:"%H" --shortstat $parentSha~1...$parentSha | sed 'N;N;y/\n/ /' | awk '{print $1}')

  #Read the SHAs to the array in reverse order, so the last element in the array is the commit on the top
  commits=($(git log --reverse --pretty=tformat:"%H" --shortstat $parentSha...$sha | sed 'N;N;y/\n/ /' | awk '{print $1}'))

  #Merge the parent and commits to be processed into one array
  shas=("$parent" "${commits[@]}")

  #Get the parent of the first commit and push it into the begining of the array
  #git log --oneline ae0bd2f096ab2d14f5bf982dd7433fc57c7ee081~1..ae0bd2f096ab2d14f5bf982dd7433fc57c7ee081

  trace_echo "The processed commits are: "${shas[@]}" (first ${shas[0]} is a parent of all the changes, ${shas[-1]} is the latest, top commit)"
}


# For example supported format ISO 8601 2005-04-07T22:13:13
# Params: $1 being SHA of commit
git_changeDates()
{
  functionCallPreamble

  trace_echo "Call git_changeDates()"

  # Shift to disallow the usage of input arguments
  declare -r sha=$1; shift

  #https://stackoverflow.com/questions/43006278/change-git-author-date-git-committer-date-date-of-a-specific-previous-commit-on/43008328#43008328
  #https://linux.die.net/man/1/git-filter-branch
  #for every commit in the weights or for the number of commits

  #https://stackoverflow.com/questions/454734/how-can-one-change-the-timestamp-of-an-old-commit-in-git

  # To expand the variables, see:
  # https://stackoverflow.com/questions/57469553/running-git-filter-branch-from-bash-shell
  #NOTE: This works and changes the commit!
  git filter-branch -f --env-filter \
     'if [ $GIT_COMMIT = '"$(echo $sha)"' ]
     then
        export GIT_AUTHOR_DATE="'"${newDates[$sha]}"'"
        export GIT_COMMITTER_DATE="'"${newDates[$sha]}"'"
     fi'
}


# TODO: Have a global option of redirect the logging output somewhere...
# Params: $1 being SHA of commit
getCommitDate()
{
  functionCallPreamble
  # For the problem of having all the, so called "return value" return
  # all of the content the command (function) produces to stdout
  # https://superuser.com/questions/1320691/print-echo-and-return-value-in-bash-function

  trace_echo "Call getCommitDate()"

  # Shift to disallow the usage of input arguments
  declare -r sha=$1; shift

  dateLinePosition=3 # Parameter to change if 'git show HEAD' output would change...

  commitDate=$(git --no-pager show $sha |
                 sed "${dateLinePosition}q;d" |
                   awk '{first = $1; $1 = ""; print $0 }' |
                     sed "s/^ //g")
  trace_echo "The commit $sha date is:" $commitDate

  echo $commitDate # "Return" the value
}


getCurrentDate()
{
  functionCallPreamble
  trace_echo "Call getCurrentDate()" >&2

  # TODO: Could be interpreted as THIS hour + the timeshift
  # Calculate the current date for git format UTC
  time_localization=" +0100" # CET is +1 hour in comparison to UTC base
  currentDate=$(LC_TIME=en_US date | sed -e 's/CET //')$time_localization

  # Example:
  # "Sun Feb 14 14:01:04 2021 +0100"
  echo $currentDate
}


# TODO: Pass an array to function - how to refer to the arguments then in a function?
# Params: $1 the date in getCurrentDate() or getCommitDate() returning format
getHourFromDate()
{
  functionCallPreamble
  declare -a dateDecomposed

  # Decompose the columns (parts) of the date and assign as entries of an array
  dateDecomposed=($commitDate)
  hourPosition=3

  trace_echo "Decomposed date is: "${dateDecomposed[@]}""

  echo ${dateDecomposed[$hourPosition]]}
}


# TODO: The old hour is not even needed...
# Params: $1 starting hour (the base hour from CLI params), $2 share in percents, $3 seconds to distribute
# TODO: In current case it would be - TODO: We do not know whoch commit in the order it is - needs a base hour!
# TODO: $startingHour would be the last hour!!!! OF the bottom, parent commit
calculateNewHour()
{
  functionCallPreamble
  # Shift to disallow the usage of input argument
  declare -r startingHour=$1; shift
  declare -r share=$1; shift
  declare -r secondsToDistribute=$1; shift

  # Decompose the hour to get an array of hours, minutes and seconds
  declare -a hourDecomposed
  IFS=":" read -a hourDecomposed <<< $startingHour

  trace_echo "Decomposed hour is: "${hourDecomposed[@]}""

  # $share / 100 to get unitary value instead of percents
  local leftSecondsToDistribute=$(bc <<< "$secondsToDistribute * $share / 100")

  # If the leftSecondsToDistribute are equal to zero
  # then use some artificial value from $RANDOM over [1-42]
  if [[ $leftSecondsToDistribute -eq 0 ]]; then
    leftSecondsToDistribute=$(bc <<< "$RANDOM % 42 + 1")
    exit
  fi

  trace_echo "Starting seconds to distribute is" $leftSecondsToDistribute

  hours=$(bc <<< "$leftSecondsToDistribute / 3600")
  let "leftSecondsToDistribute -= hours * 3600"
  trace_echo "Hours:" $hours
  trace_echo "Left seconds:" $leftSecondsToDistribute

  minutes=$(bc <<< "$leftSecondsToDistribute / 60")
  let "leftSecondsToDistribute -= minutes * 60"
  trace_echo "Minutes:" $minutes
  trace_echo "Left seconds:" $leftSecondsToDistribute


  seconds=$(bc <<< "$leftSecondsToDistribute")
  let "leftSecondsToDistribute -= seconds"
  trace_echo "Seconds:" $seconds
  trace_echo "Left seconds:" $leftSecondsToDistribute

  # Assert that all the second have been distributed and no negative value result
  if [ $leftSecondsToDistribute -ne 0 ]; then
    trace_echo "Arithmetic error, $leftSecondsToDistribute seconds that are left for distrubution!"
    exit
  fi

  # Now, we have the values of hour, minutes and seconds - add them to the startingHour
  # If any of those overflow - then upgrade the "higher" counter...
  let "hourDecomposed[2] += seconds"
  if [[ ${hourDecomposed[2]} -ge 60 ]]; then
  # Increment the higher level counter (minutes) and subtract 60
    let "hourDecomposed[1] += 1"
    let "hourDecomposed[2] -= 60" #[[left]] - fill with zeros here...
  fi
  # If the value if less than 10, then it is a single-digit value, add leading zero
  if [[ ${hourDecomposed[2]} -lt 10 ]]; then
    hourDecomposed[2]="0${hourDecomposed[2]}"
  fi


  let "hourDecomposed[1] += minutes"
  if [[ ${hourDecomposed[1]} -ge 60 ]]; then
    # Increment the higher level counter (hours) and subtract 60
      let "hourDecomposed[0] += 1"
      let "hourDecomposed[1] -= 60"
  fi
  # If the value if less than 10, then it is a single-digit value, add leading zero
  if [[ ${hourDecomposed[1]} -lt 10 ]]; then
    hourDecomposed[1]="0${hourDecomposed[1]}"
  fi

  let "hourDecomposed[0] += hours"
  if [[ ${hourDecomposed[0]} -ge 24 ]]; then
    trace_echo "Overflow on hours, should be next day!"
    exit
  fi

  trace_echo "zkamtar New decomposed hour is: "${hourDecomposed[@]}""

  echo "${hourDecomposed[@]}" #Tested and it is always (on one case of CLI) okay...
}


#need to call it with $1 equal to commit SHA
calculateDate() #getting the current date not the date of the commit...
{
  functionCallPreamble
  # currentDate is the current date - do we need that?
  currentDate="$(getCurrentDate)"
  echo $currentDate

  # Get the date of the commit
  commitDate="$(getCommitDate "$1")"

  # Get the hour from the commit date
  commitHour="$(getHourFromDate "$commitDate")"

  # Calculate the share in percent of current commit
  local shareInPercent=$(bc <<< "scale=2; 100 * ${weights[$1]} / $accumulatedWeights")

  # Calculate the new hour of commit
  declare -r commitHourNew=("$(calculateNewHour "$commitHour" "$shareInPercent" "$duration_in_seconds")")
  IFS=" " read -a commitHourNewDecomposed <<< $commitHourNew

  #  var="Sun Feb 14 14:01:04 2021 +0100"
  #  echo $var | awk '{gsub($4, "15:01:04"); print}' - BEGIN in awk was the problem...
  newDate=$(echo $commitDate |
    awk -v hour="${commitHourNewDecomposed[0]}" -v minutes="${commitHourNewDecomposed[1]}" -v seconds="${commitHourNewDecomposed[2]}" '
      {gsub($4, hour":"minutes":"seconds); print}')

  #add date to the map #TODO: Needs calculations of the new date!!!
  dates[$1]=$commitDate

  newDates[$1]=$newDate

  #debug
  trace_echo "The date of the commit is :""${dates["$1"]}"
  trace_echo "The modified date of the commit is :""${newDates["$1"]}"
}


#pass date as $1
modifyDate()
{
  #$ date -u -d @360 +'%-Mm %-Ss'
  #6m 0s

  #This is extracting the hour currently
  hour=$(echo $1 | awk '{print $4}')
  echo $hour
}


#passed is the timeframe offset set by the user
normalizeWeights() # or make it a normalize weight for one commit?
{
   functionCallPreamble

   # Search for the highest and the lowest and spread it across the given time-window
   # Accumulate weights across all weights
   for i in "${!weights[@]}"
   do
      let "accumulatedWeights+=${weights[$i]}"
      echo "Accumulated weight during iteration $i is: "$accumulatedWeights
   done

   #debug
   trace_echo "The final results for weight accululation is: "$accumulatedWeights

   #Print the share of every commit in the total workload #TODO: Add it into the -A map of normalized weights?
   for i in "${!weights[@]}"
   do
     local normalizedWeight=$(bc <<< "scale=2; 100*${weights[$i]}/$accumulatedWeights")
     echo "The share of weight of $i commit in total weight is $(echo "scale=2;
          (100*${weights[$i]}/$accumulatedWeights)" | bc -l)%"
     echo "The share of weight of $i commit in total weight is" $normalizedWeight"%"

     # Put the results into normalizedWeights map
     normalizedWeights[$i]=$normalizedWeight
     echo ${normalizedWeights[$i]}
   done
}


trace_echo()
{
  local numOfFunctionsOnStack=${#FUNCNAME[*]}
  echo $numOfFunctionsOnStack >&2 # Need to print somewhere else than the stdout
  for (( i=$(($numOfFunctionsOnStack-1)); (( $i > 0 )) ; i-- )); do
    echo -n ${FUNCNAME[$i]}"()->" >&2
  done
  echo $@ >&2
}


functionCallPreamble()
{
  echo "Calling" ${FUNCNAME[1]}"()" "from" ${FUNCNAME[2]}"()" "contained in script" $0 >&2
}


# Starting the script
main "$@"
