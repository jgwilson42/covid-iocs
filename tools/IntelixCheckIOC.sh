#!/bin/bash

# Copyright (c) 2020. Sophos Limited

# Print out messages to the console in a standard format
# Allow switch on/off of debug messages
output() {
    if [ "$1" == "e" ]; then
        echo "ERROR: ${2}"
    elif [ "$1" == "i" ]; then
        echo "INFO: ${2}"
    elif [ "$1" == "d" ]; then
        if [ $DEBUG -eq 1 ]; then
            echo "DEBUG: ${2}"
        fi
    fi
}

print_usage() {
    echo "Usage: $0 file_name [debug]"
    echo "  Check each URL in the file provided"
    echo "  Error if any of the URLs doesn't have a High risk"
    echo "  NOTE: Credentials for Intelix are expected in environment variable IntelixCredentials"
}

# URL is passed in as the first paramter
# Performs lookup against SXL4 and checks that the risk level is "HIGH"
check_url () {
    output i "Checking URL: ${1}"
    RESPONSE=`curl \
        -X GET \
        -H "Authorization: ${TOKEN}" \
        -s https://de.api.labs.sophos.com/lookup/urls/v1/${1}`
    output d "Response is: ${RESPONSE}"
    RISK=`echo ${RESPONSE} | jq '.riskLevel'`
    output i "Risk is: ${RISK}"
    if [ "$RISK" != "\"HIGH\"" ]; then
        # This is bad, the URL is not a high risk one
        # Add as a comma seperated list to the URLERRORS variable for processing later
        URLERRORS="${URLERRORS}${1} has risk: ${RISK},"
    fi
}

# Ensure that the URL has the correct format for SXL
check_format() {
    output d "Parsing URL: ${1}"
    PARSEDLINE=${1}
    # Remove the leading hxxp://
    PARSEDLINE="${1//hxxp:\/\//}"
    
    # Change any /'s to %2F
    PARSEDLINE="${PARSEDLINE//\//%2F}"
    output d "Parsed URL is: ${PARSEDLINE}"

    #Remove parameters
    PARSEDLINE="$(cut -d'?' -f1 <<< ${PARSEDLINE})"
    PARSEDLINE="$(cut -d'&' -f1 <<< ${PARSEDLINE})"
    output d "URL without parameters is: ${PARSEDLINE}"
}

# Check correct number of paramters
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    print_usage
    exit 1
fi

#Enable debug if set on the command line
if [ "$2" == "debug" ]; then
    DEBUG=1
else
    DEBUG=0
fi

# Check that the credentials are set in the correct environmnet variable
# Setting in env variable allows for easy integration with CI and maintaining the secret
if [[ -z "${IntelixCredentials}" ]]; then
    output e "Intelix credentials not specified"
    print_usage
    exit 1
fi

output i Authenticate
RESPONSE=`curl \
    -X POST \
    -H "Authorization: Basic ${IntelixCredentials}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -s https://api.labs.sophos.com/oauth2/token \
    -d "grant_type=client_credentials"`
TOKEN=`echo ${RESPONSE} | jq '.access_token' | sed 's|"||g'`

output i "File being processed is ${1}"
URLERRORS=""

# Itterate over the lines in the file
while read -r line; do
    output d "Line is: $line"
    # Files contain a descriptive line that is obvious by spaces between words
    if [[ "$line" == *" "* ]]; then
        #Do nothing, this is a header line
        output d "Line contains spaces, is a header: $line"
    elif [ "$line" == "" ]; then
        #Do nothing, blank line
        output d "Blank line"
    else
        check_format $line
        check_url $PARSEDLINE
    fi
done < "${1}"

# Parse the results and print out errors for all that don't have the correct risk level
Backup_of_internal_field_separator=$IFS
IFS=,
for item in $URLERRORS; 
  do
    output e $item
  done
IFS=$Backup_of_internal_field_separator

if [ -z "$URLERRORS" ]; then
    # No errors
    exit 0;
else
    # Errors
    exit 1
fi
