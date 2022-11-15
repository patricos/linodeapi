#!/bin/bash

#################
# Help function #
#################

function helpme() {
    echo "Helpme function" # ; exit 1

    echo "Creates Linode nodes and configures them for further use in SIA deployment:"
    echo "    - adds SSL certs: your cert to all and the cert of the first node to all other nodes,"
    echo "    - acknoledges the first host as \"known host\" with all nodes from the list,"
    echo "    - populates /etc/hosts,"
    echo "    - updates /etc/hostname."
    echo
    echo "Usage:"
    echo "$(basename "${0}") -t <TOKEN> -n <NODE LIST> -s <SIZE LIST> [-c <CERT PATH>] [-p <ROOT PASS>] [-l <LOCATION>]"
    echo "$(basename "${0}") -t <TOKEN> -q"
    echo
    echo "Node creation:"
    echo "    REQUIRED"
    echo "    -t | --token          token for Linode API calls"
    echo "    -n | --nodelist       list of node names, whitespace separated, characters allowed:"
    echo "                            small letters, non-leading non-tailing single dash, non-leading nums"
    echo "    -s | --sizes          list of node sizes, in the same order as nodes on the name list. See -q"
    echo
    echo "    OPTIONAL"
    echo "    -l | --location       label of the datacenter location. Note: all nodes in one location. See -q"
    echo "                            Default: ${REGIO}"
    echo "    -c | --certfile       full path to your certificate public file"
    echo "                            Default: ${CERT_FILE} (iff exists or empty elsewise)"
    echo "    -p | --password       root password to newly created nodes.  All nodes the same password"
    echo "                            Default is a 16-character pseudo-random hex number which is not saved"
    echo "                            Therefore, provide correctly one of the arguments following -p or -c"
    echo "    -o | --output-file    filename of the process log"
    echo "                            Default: YYMMDD-hhmm--linode-setup.log"
    echo "    -r | --ready-timeout  timeout for the node to come alive after spawning and before ssh login attempt"
    echo "                            Default: 300 seconds.  Required is an integer"
    echo
    echo "Query Linode:"
    echo "    -q | --query-linode   query Linode API for availabe node sizes and datacenter locations"
    echo
    echo "Other:"
    echo "    -v | --verbose        enable verbose output"
    echo "    -h | --help           display this information"
    echo
    echo "Example:"
    echo "$(basename "${0}") -t 1234567890abcdefgh1234567890 -c /home/patryk/.ssh/id_rsa.pub \\"
    echo "    -n ems data-stores engines data-procs prov-apps web-portals \\"
    echo "    -s g6-standard-2 g6-standard-6 g6-standard-4 g6-standard-2 g6-standard-4 g6-standard-2"

    exit 1
}


############
# Defaults #
############

TOKEN=""
REGIO=us-central
IMAGE=linode/centos7
TYPE=g6-nanode-1
PASSW=`echo $RANDOM-$RANDOM | md5sum | head -c 18`   # two $RANDOM ~ 32bit of information at most ~ representable with 8-digit hex

CERT_FILE=~/.ssh/id_rsa.pub
LOG_FILE=`date +%y%m%d-%H%M%S-linode-setup.log`

# arrays shall not be initiated this way in bash as they will have a zero-elmement at the first index
#NODES_ARRAY=("")
#SIZES_ARRAY=("")
#LINODE_ID_ARRAY=("")
#PUBLIC_IP_ARRAY=("")
#PRVATE_IP_ARRAY=("")
#SSH_F_PRT_ARRAY=("")
NODE_LAST_INDEX=-1

VERBOSE=false
QUERY=false

####################
# Argument parsing #
####################

while [[ $# -gt 0 ]]; do

    SWITCH=${1}

    case "${SWITCH}" in
        -t | --token)
            [ ${#2} -le 5 ] && (echo -e "ERORR: token too short\n"; helpme) || TOKEN="${2}"
            shift
            shift
            ;;
        -n | --nodelist)
            while [[ ! -z ${2} ]] && [[ ! ${2:0:1} == "-" ]]; do
                NODES_ARRAY+=("${2}")
                shift
            done 
            shift
            ;;
        -s | --sizes)
            while [[ ! -z ${2} ]] && [[ ! ${2:0:1} == "-" ]]; do
                SIZES_ARRAY+=("${2}")
                shift
            done 
            shift
            ;;
        -l | --location)
            [ ${#2} -le 5 ] && echo -e "WARNING: region too short, assuming the default" || REGIO="${2}"
            shift
            shift
            ;;
        -c | --certfile)
            CERT_FILE="${2}"
            shift
            shift
            ;;
        -p | --password)
            shift
            shift
            ;;
        -r | --ready-timeout)
            shift
            shift
            ;;
        -o | --output-file)
            ;;
        -q | --query)
            echo -e "\n   == List of REGIONS ==\n" 
            curl -s https://api.linode.com/v4/regions | python -mjson.tool | grep -B 1 \"id\":
            echo -e "\n   == List of NODE SIZE/TYPE ==\n" 
            curl -s https://api.linode.com/v4/linode/types | python -mjson.tool | grep -A 1 \"id\": | sed 's/label/human\ readable\ label/1'
            exit 2
            ;;
        -v | --verbose)
            VERBOSE=true
            echo "Verbose."
            shift
            ;;
        -h | --help)
            helpme
            ;;
        *)
            helpme
            ;;
    esac
done


######################
# Intermediate tests #
######################

# no token? get help
if [ -z "${TOKEN}" ]; then helpme; fi
echo "<<"$TOKEN">>"

# TODO: bad token? notify!

# ONE MORE: [node_array length>0] and [${#NODES_ARRAY[@]} == ${#SIZES_ARRAY[@]}]  iff its not a query
# for value in "${NODES_ARRAY[@]}"; do echo $value; done
# for value in "${SIZES_ARRAY[@]}"; do echo $value; done
NODE_LAST_INDEX=$(( ${#NODES_ARRAY[@]} - 1 ))

if ! [ -f ${CERT_FILE} ]; then
    echo "WARNINIG: Certificate file cannot be read. If you provided no password, you will have troubles logging into your new nodes."; fi
if ! command -v sshpass &> /dev/null; then echo "sshpass could not be found.  Install epel-release and sshpass"; fi

if $VERBOSE; then set -x; fi


###################
# Spawn the nodes #
###################

for ANINDEX in $(seq 0 $NODE_LAST_INDEX); do

    NODENAME=${NODES_ARRAY[$ANINDEX]}
    echo -e "\n-->   == Rolling out $NODENAME =="

    OUTPUT=` curl --progress-bar -X POST https://api.linode.com/v4/linode/instances \
             -H "Authorization: Bearer $TOKEN" -H "Content-type: application/json" \
             -d '{"type": "'$TYPE'", "region": "'$REGIO'", "image": "linode/centos7", "root_pass": "'$PASSW'", "label": "'$NODENAME'"}' `

    LINODE_ID=`echo $OUTPUT | grep -E -o "id\":\ [0-9]+" | sed 's/id\":\ //g'`
    LINODE_ID_ARRAY+=($LINODE_ID)
    echo "Linode ID:  $LINODE_ID"
    if $VERBOSE; then echo $OUTPUT; fi

    LI_PUB_IP=`echo $OUTPUT | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}"`
    PUBLIC_IP_ARRAY+=($LI_PUB_IP)
    echo "Public IP:  $LI_PUB_IP"

    OUTPUT=` curl --progress-bar -X POST https://api.linode.com/v4/linode/instances/${LINODE_ID}/ips \
             -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
             -d '{"type": "ipv4", "public": false}'`

    LI_PRV_IP=`echo $OUTPUT | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | head -n1`
    PRVATE_IP_ARRAY+=($LI_PRV_IP)
    echo "Private IP: $LI_PRV_IP"
    if $VERBOSE; then echo $OUTPUT; fi

    echo "Server pas: $PASSW"

done

# curl https://api.linode.com/v4/linode/instances/40210707 -H "Authorization: Bearer `cat ~/token2210master`"

#    sleep 15
#    ssh-keyscan -t ecdsa ${LI_PUB_IP} 2>&1 | grep ecdsa >> ~/.ssh/known_hosts
#    sshpass -p $PASSW ssh-copy-id root@${LI_PUB_IP}

# what else we want to achieve


exit

OUTPUT=\
`curl -X POST https://api.linode.com/v4/linode/instances \
-H "Authorization: Bearer $TOKEN" -H "Content-type: application/json" \
-d '{"type": "'$TYPE'", "region": "'$REGIO'", "image": "linode/centos7", "root_pass": "'$PASSW'", "label": "'$LABEL'"}'`

echo -e "\n\n$OUTPUT\n"

exit


#'{"type": "'$TYPE'", "region": "'$REGIO'", "image": "linode/centos7", "root_pass": "'$PASSW'", "label": "'$LABEL'"}' \
# -d '{"type": "'$TYPE'", "region": "'$REGIO'", "image": "linode/centos7", "root_pass": "'$PASSW'", "label": "'$LABEL'"}' \

echo
echo
#output='. '

#ipaddress=$( \
#echo '{"id": 37453543, "label": "auto-test", "group": "", "status": "provisioning", "created": "2022-07-15T11:34:45", "updated": "2022-07-15T11:34:45",'\
#     ' "type": "g6-nanode-1", "ipv4": ["45.79.16.121"], "ipv6": "2600:3c00::f03c:93ff:febd:3391/128", "image": "linode/centos7", "region": "us-central",'\
#     ' "specs": {"disk": 25600, "memory": 1024, "vcpus": 1, "gpus": 0, "transfer": 1000}, "alerts": {"cpu": 90, "network_in": 10, "network_out": 10,'\
#     ' "transfer_quota": 80, "io": 10000}, "backups": {"enabled": false, "schedule": {"day": null, "window": null}, "last_successful": null},'\
#     ' "hypervisor": "kvm", "watchdog_enabled": true, "tags": []}' \
#| grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}"  ) # | read ipaddress; echo $ipaddress

# | (read output ; echo $output; echo ${#output} ) > out.txt | (read output ; echo ${#output} ) >> out.txt # grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | read ipaddress; echo $output)

#echo "And the IP address is $ipaddress - DONE."
#echo $output


#  | python -mjson.tool
