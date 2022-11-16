# Environment builder tool.

This is a script-based tool ment to quickly start a multi-machine environment at Linode compute-provider.  When multiple servers in an environment are needed, there is some manual work involved for spawning them, and the script does these well-defined mundane tasks for you.  Below you will find the description of the process the tool off-loads from you.

## What process does it cover

Creating an environment of several machines typically involves the following tasks, which are all processed by this tool:

1. Spawning the nodes.  It requires selecting an image, machine size, datacenter location, machine name in the interface.
2. Obtaining the metadata about the machine.  At this point you only need public and private IP adresses.
3. Networking the nodes properly, which includes:
  * set up known_hosts and certificate: ssh-copy-id
  * populate /etc/hosts and update /etc/hostname
  * reboot (for the static hostname to update)
  
## System prerequisites

Runs on bash.

### On your terminal box

1. Ensure you have some directory with rw access for your activities here. Probably it is preferred to run the script from this directory: `./spawn.sh`.  
2. Obtain the script, e.g. `git clone https://github.com/patricos/linodeapi.git`.
3. Have sshpass installed, e.g. `sudo yum install sshpass -y`.
4. Obtain an API token from Linode: `https://www.linode.com/docs/guides/getting-started-with-the-linode-api/#get-an-access-token`.

### On your remote machines aka nodes

A Linode account needed.

And this is what you get at the nodes (at the time of writing this manual), and you don't have to do anything here:

1. Root access to the nodes.
2. Services up and running: sshd, ntpd.

## Manpage

Also available when the script triggered without parameters: `./spawn.sh`.

```
Usage:
$(basename "${0}") -t <TOKEN> -n <NODE LIST> -s <SIZE LIST> [-c <CERT PATH>] [-p <ROOT PASS>] [-l <LOCATION>]
$(basename "${0}") -t <TOKEN> -q

Node creation:
    REQUIRED
    -t | --token          token for Linode API calls
    -n | --nodelist       list of node names, whitespace separated, characters allowed:
                            small letters, non-leading non-tailing single dash, non-leading nums
    -s | --sizes          list of node sizes, in the same order as nodes on the name list. See -q

    OPTIONAL
    -l | --location       label of the datacenter location. Note: all nodes in one location. See -q
                            Default: us-central # i.e. Texas/Dallas
    -c | --certfile       full path to your certificate public file
                            Default: ~/.ssh/id_rsa.pub
    -p | --password       root password to newly created nodes.  All nodes the same password
                            Default is a 16-character pseudo-random hex number which is not saved
                            Therefore, provide correctly one of the arguments following -p or -c
    -o | --output-file    filename of the process log
                            Default: YYMMDD-hhmm--linode-setup.log
    -r | --ready-timeout  timeout for the node to come alive after spawning and before ssh login attempt
                            Default: 300 seconds.  Required is an integer

Query Linode:
    -q | --query-linode   query Linode API for availabe node sizes and datacenter locations

Other:
    -v | --verbose        enable verbose output
    -h | --help           display this information

Example:
    spawn.sh -t 1234567890abcdefgh1234567890 -c /home/patryk/.ssh/id_rsa.pub \
    -n ems data-stores engines data-procs prov-apps web-portals \
    -s g6-standard-2 g6-standard-6 g6-standard-4 g6-standard-2 g6-standard-4 g6-standard-2
```