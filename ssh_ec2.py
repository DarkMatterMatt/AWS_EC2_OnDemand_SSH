#!/usr/bin/env python3
# defaults: user = ec2-user; identity = the SSH default
# example: ./ssh_ec2.sh i-12345678912345678 -u myUser -i ~/.ssh/myIdentity.pem
# example: ./ssh_ec2.sh i-12345678912345678 -u myUser -i ~/.ssh/myIdentity.pem --sshargs '-o StrictHostKeyChecking no'

import argparse
import boto3
import os
import subprocess
import sys
from time import sleep

def start(ec2, instance_id):
    ec2.start_instances(InstanceIds=[instance_id])

def stop(ec2, instance_id):
    ec2.stop_instances(InstanceIds=[instance_id])

def get_public_dns_name(ec2, instance_id):
    response = ec2.describe_instances(InstanceIds=[instance_id])
    return response["Reservations"][0]["Instances"][0]["PublicDnsName"]

def get_state(ec2, instance_id):
    response = ec2.describe_instances(InstanceIds=[instance_id])
    return response["Reservations"][0]["Instances"][0]["State"]["Name"]

def flush_dns():
    # Needs to flush DNS to get the new DDNS ip
    if sys.platform == "win32":
        print("** Flushing DNS cache")
        subprocess.call("ipconfig /flushdns", shell=True, stdout=subprocess.DEVNULL)

    #elif sys.platform == "darwin":
    #    subprocess.call("sudo killall -HUP mDNSResponder", shell=True, stdout=subprocess.DEVNULL)
    #    subprocess.call("sudo killall mDNSResponderHelper", shell=True, stdout=subprocess.DEVNULL)
    #    subprocess.call("sudo dscacheutil -flushcache", shell=True, stdout=subprocess.DEVNULL)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("instance_id")
    parser.add_argument("-u", "--user", help="The user to SSH as", default="ec2-user")
    parser.add_argument("-H", "--host", help="An override SSH hostname (EC2 with DDNS)")
    parser.add_argument("-i", "--identity", help="The SSH identity file")
    parser.add_argument("--sshargs", help="Extra args to pass to SSH", default="")
    args = parser.parse_args()

    instance_id = args.instance_id
    user        = args.user
    identity    = f"-i {args.identity}" if args.identity else ""
    ssh_args    = args.sshargs

    ec2 = boto3.client("ec2")

    # check if instance is running
    print("** Checking if instance is already running")
    state = get_state(ec2, args.instance_id)

    if state != "running":
        # start instance
        print("** Starting instance", flush=True)
        start(ec2, args.instance_id)

        # wait for instance to start
        print("** Waiting for instance to start..", end="", flush=True)
        while state != "running":
            print(".", end="", flush=True)
            sleep(2)
            state = get_state(ec2, args.instance_id)
        print(" done!")

        # wait for SSH to start
        print("** Waiting 10 secs for SSH to start")
        sleep(10)

    # get ip address
    if args.host:
        dns = args.host
    else:
        print("** Fetching public DNS name")
        dns = get_public_dns_name(ec2, args.instance_id)

    # log in with SSH
    print("** Running SSH")
    for i in range(5):
        flush_dns()
        return_code = subprocess.call(f"ssh  -o ConnectTimeout=5 -o ConnectionAttempts=1 {user}@{dns} {identity} {ssh_args}", shell=True)
        if return_code == 0:
            break
        sleep(3)

    # stop instance
    print("** You have 3 seconds to cancel the EC2 shutdown, press CTRL+C to cancel!", flush=True)
    try:
        sleep(3)
        print("** Stopping instance...")
        stop(ec2, instance_id)
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
