#!/bin/bash
# defaults: user = ec2-user; identity = the SSH default
# example: ./ssh_ec2.sh i-12345678912345678 -u myUser -i ~/.ssh/myIdentity.pem
# example: ./ssh_ec2.sh i-12345678912345678 -u myUser -i ~/.ssh/myIdentity.pem --sshargs '-o StrictHostKeyChecking no'

# -allow a command to fail with !’s side effect on errexit
# -use return value from ${PIPESTATUS[0]}, because ! hosed $?
! getopt --test > /dev/null 
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    echo 'I’m sorry, `getopt --test` failed in this environment. Maybe install it with `brew install gnu-getopt`.'
    exit 1
fi

OPTIONS=u:i:vh
LONGOPTS=user:,identity:,verbose,help,sshargs:

# -regarding ! and PIPESTATUS see above
# -temporarily store output to be able to check for errors
# -activate quoting/enhanced mode (e.g. by writing out “--options”)
# -pass arguments only via   -- "$@"   to separate them correctly
! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    # e.g. return value is 1
    #  then getopt has complained about wrong arguments to stdout
    exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

# default options
verbose=false
instanceId=unset
sshIdentity=""
sshUser="ec2-user"
sshArgs=""

# now enjoy the options in order and nicely split until we see --
while true; do
    case "$1" in
        -h|--help)
            echo "Usage: $0 urlsFile"
            exit 0
            ;;
        -v|--verbose)
            verbose=true
            shift
            ;;
        -I|--instanceid)
            ="$2"
            shift 2
            ;;
        -i|--identity)
            sshIdentity="-i $2"
            shift 2
            ;;
        -u|--user)
            sshUser="$2"
            shift 2
            ;;
        --sshargs)
            sshArgs="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Programming error"
            exit 3
            ;;
    esac
done

# instanceId is an (optional) positional arguement
if [[ $# -ge 1 ]]; then
    instanceId=$1
fi

# check that url or urlsFile is set
if [[ $instanceId == "unset" ]]; then
    echo "Missing EC2 instance id"
    exit 4
fi

#################################################

QUERY="aws2 ec2 describe-instances --output text --instance-ids $instanceId --query Reservations[*].Instances[*]."
HOST_QUERY="$QUERY{Instance:PublicDnsName}"
STATE_QUERY="$QUERY{Instance:State.Name}"

# start instance
echo 'Starting instance...'
aws2 ec2 start-instances --instance-ids $instanceId > /dev/null || exit 5

# get ip address
echo 'Fetching hostname...'
host=$($HOST_QUERY) || exit 6

# wait for instance to start
printf 'Waiting for instance to start...'
state=$($STATE_QUERY) || exit 7
while [[ $state != "running" ]]; do
    sleep 2
    printf '.'
    state=$($STATE_QUERY) || exit 7
done
echo ' done!'

# ssh into instance
echo 'Waiting 10 secs for SSH to start...'
sleep 10

echo 'Running SSH...'
ssh "$sshUser@$host" $sshIdentity "$sshArgs" || exit 8

# stop instance
echo 'You have 3 seconds to cancel the EC2 shutdown... Press CTRL+C to cancel!'
sleep 3

echo 'Stopping instance...'
aws2 ec2 stop-instances --instance-ids $instanceId > /dev/null || exit 9
