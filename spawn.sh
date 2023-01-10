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
    echo "    -g | --tag            adds a tag to machines. This helps grouping machines in Linode's GUI"
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


##########################
# Global data structures #
# and defaults           #
##########################

## STRINGS:
TOKEN=""
REGIO=us-central
IMAGE=linode/centos7
TYPE=g6-nanode-1
PASSW=`echo $RANDOM-$RANDOM | md5sum | head -c 18`   # two $RANDOM ~ 32bit of information at most ~ representable with 8-digit hex
CERT_FILE=~/.ssh/id_rsa.pub
LOG_FILE=`date +%y%m%d-%H%M%S-linode-setup.log`
HOSTFILE_TMP=`date +%y%m%d-%H%M%S-etc-hostfile.tmp`

## ARRAYS:
#  arrays shall not be initiated in bash as they will have a zero-elmement at first index
#NODES_ARRAY=("")       # host names from input
#SIZES_ARRAY=("")
#LINODE_ID_ARRAY=("")
#PUBLIC_IP_ARRAY=("")
#PRVATE_IP_ARRAY=("")
#SSH_FINGERPRT_A=("")   # ssh finger print array
#SSH_PUBLIC_CERT=("")   # node's pub cert

## INTEGERS:
NODE_LAST_INDEX=-1      # after parsing the input, will contain last node input; for loops. 

## BOOLEANS:
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
        -g | --tag)
            shift
            shift
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
if [ -z "${TOKEN}" ];  then echo "ERROR: No token provided.  See the help page.";  helpme;  fi
if $VERBOSE; then echo "<<"$TOKEN">>"; fi
# TODO: bad token? notify!


# ??? one more? : [node_array length>0] and [${#NODES_ARRAY[@]} == ${#SIZES_ARRAY[@]}]  iff its not a query
# test # for value in "${NODES_ARRAY[@]}"; do echo $value; done
# test # for value in "${SIZES_ARRAY[@]}"; do echo $value; done


NODE_LAST_INDEX=$(( ${#NODES_ARRAY[@]} - 1 ))


# in case of incorrect node-size (a.k.a. node-type) array length, populate the array with defaults
if ! [${#NODES_ARRAY[@]} == ${#SIZES_ARRAY[@]}]; then
    echo "WARNINIG: Assuming the default nod size/type of: ${TYPE} because \"--sizes\" array is not the same length as \"--nodelist\" array."
    for ANINDEX in $(seq 0 $NODE_LAST_INDEX); do
        SIZES_ARRAY+=("${TYPE}")
    done
fi


echo -e "\n\n" > ${HOSTFILE_TMP}
if ! [ -f ${HOSTFILE_TMP} ]; then          echo "ERROR: Temporary hostfile ${HOSTFILE_TMP} cannot be written or read.  Fix that, please.";  exit 1;  fi
if ! [ -f ${CERT_FILE} ]; then             echo "WARNINIG: Certificate file cannot be read. If you provided no password, you will have troubles logging into your new nodes."; fi
if ! command -v sshpass &> /dev/null; then echo "ERROR: sshpass could not be found.  Install epel-release and sshpass.";  exit 1;  fi


if $VERBOSE; then set -x; fi



###################
# Spawn the nodes #
###################

for ANINDEX in $(seq 0 $NODE_LAST_INDEX); do

    NODENAME=${NODES_ARRAY[$ANINDEX]}
    NODESIZE=${SIZES_ARRAY[$ANINDEX]}
    
    echo -e "\n-->   == Rolling out $NODENAME =="

    OUTPUT=` curl --progress-bar -X POST https://api.linode.com/v4/linode/instances \
             -H "Authorization: Bearer $TOKEN" -H "Content-type: application/json" \
             -d '{"type": "'$NODESIZE'", "region": "'$REGIO'", "image": "linode/centos7", "root_pass": "'$PASSW'", "label": "'$NODENAME'"}' `

    LINODE_ID=`echo $OUTPUT | grep -E -o "id\":\ [0-9]+" | sed 's/id\":\ //g'`
    LINODE_ID_ARRAY+=($LINODE_ID)
    echo "Linode ID:  $LINODE_ID"
    if $VERBOSE; then echo $OUTPUT; fi

    LI_PUB_IP=`echo $OUTPUT | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}"`
    PUBLIC_IP_ARRAY+=($LI_PUB_IP)
    echo "Public IP:  $LI_PUB_IP"

    OUTPUT=` curl --silent -X POST https://api.linode.com/v4/linode/instances/${LINODE_ID}/ips \
             -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
             -d '{"type": "ipv4", "public": false}'`

    LI_PRV_IP=`echo $OUTPUT | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | head -n1`
    PRVATE_IP_ARRAY+=(${LI_PRV_IP})
    echo "Private IP: $LI_PRV_IP"
    if $VERBOSE; then echo $OUTPUT; fi

    # add a hostsfile entry for that machine
    echo -e "${LI_PRV_IP}\t${NODENAME}" >> ${HOSTFILE_TMP}

    echo "Server pas: $PASSW"

done



###################
# Readiness check #
###################

echo -e "\n-->   == Readiness check and data collection =="

for ANINDEX in $(seq 0 $NODE_LAST_INDEX); do

    IP_PRIV=${PRVATE_IP_ARRAY[$ANINDEX]}
    IP_PUBL=${PUBLIC_IP_ARRAY[$ANINDEX]}
    NODE_ID=${LINODE_ID_ARRAY[$ANINDEX]}
    NODNAME=${NODES_ARRAY[$ANINDEX]}
    IS_REDY=false

    echo -n "Waiting for ${NODNAME} to get ready: "
    
    while ! ${IS_REDY}; do  # IS_REDY contains function name as used for calling: functionName=false() xor functionName=true(), which always finishes with (bool)true xor (bool)false.
    
        OUTPUT=`curl -s -X GET https://api.linode.com/v4/linode/instances/$NODE_ID -H "Authorization: Bearer ${TOKEN}"`
        STATUS=`echo $OUTPUT | grep -E -o status.*$ | cut -d\" -f3`
        
        if [ ${STATUS} == "running" ]; then
            IS_REDY=true
            echo " OK."
        else
            # if ${VERBOSE}; then echo ${STATUS}; else echo -n "."; fi
            echo -n "."
            sleep 5
        fi
    done

    # obtain fingerprint for known_hosts

    OUTPUT=`ssh-keyscan -t ecdsa ${IP_PUBL} 2>&1 | grep ecdsa`      # not the best practice to write functions (despite inline!) TWICE (1)
    while [ -z "$OUTPUT" ]; do
        echo "wait some more for ecdsa signature of $IP_PUBL ($NODNAME)..."
        sleep 5
        # ssh-keyscan -t ecdsa ${IP_PUBL}
        OUTPUT=`ssh-keyscan -t ecdsa ${IP_PUBL} 2>&1 | grep ecdsa`  # not the best practice to write functions (despite inline!) TWICE (2)
    done
    SSH_FP_COMPLETE="${NODNAME},${IP_PRIV},${OUTPUT}"
    SSH_FINGERPRT_A+=(${SSH_FP_COMPLETE})
    echo ${SSH_FP_COMPLETE}

    # obtain ssh-rsa public key for authorized_keys

done

    # populate .ssh/known_hosts
    # populate .ssh/authorized_keys (including the current localhost)
    # populate hostsfile
    
    # yum install object storage tools
    # LOL, maybe: ssh help or cowasy greeting on remote node installed
    
    # ssh ${IP_ADDR} "reboot"



#    sleep 15
#    ssh-keyscan -t ecdsa ${LI_PUB_IP} 2>&1 | grep ecdsa >> ~/.ssh/known_hosts
#    sshpass -p $PASSW ssh-copy-id root@${LI_PUB_IP}

# what else we want to achieve


exit

#  | python -mjson.tool
