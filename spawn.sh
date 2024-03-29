#!/bin/bash

#################
# Help function #
#################

function helpme() {
    echo "Helpme function" # ; exit 1

    echo "Creates Linode nodes and configures them:"
    echo "    - adds SSL certs: your cert to all and all-to-all between nodes,"
    echo "    - acknowledges nodes in \"known hosts\" (all-to-all),"
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
    echo "    -f | --firewall       ID of an existing firewall to add new linodes to. It's a user's responsibility"
    echo "                            to configure the firewall, and obtain its ID"
    echo "    -o | --output-file    filename of the process log"
    echo "                            Default: YYMMDD-hhmm--linode-setup.log"
    echo "    -r | --ready-timeout  timeout for the node to come alive after spawning and before ssh login attempt"
    echo "                            Default: 300 seconds.  Required is an integer"
    echo "    -g | --tag            adds a tag to machines. This helps grouping machines in Linode's GUI"
    echo
    echo "Node removal:"
    echo "    REQUIRED"
    echo "    -d | --delete         list of ID nubmers of nodes to be deleted.  Token is also required (see -t )."
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
FIREWALL_ID=""
#REGIO=us-central       # legacy site, don't use for development
REGIO=nl-ams
#IMAGE=linode/centos7   # v.19.1.x
IMAGE=linode/rocky8     # v.19.2
TYPE=g6-nanode-1
PASSW=`echo $RANDOM-$RANDOM | md5sum | head -c 18`      # two $RANDOM ~ 32bit of information at most ~ representable with 8-digit hex
CERT_FILE=~/.ssh/id_rsa.pub                             # this has to be the private part for login, and public part for copying
LOG_FILE=`date +%y%m%d-%H%M%S-linode-setup.log`
HOSTFILE_TMP=`date +%y%m%d-%H%M%S-etc-hostfile.tmp`
KNOWNHST_TMP=`date +%y%m%d-%H%M%S-home-ssh-knownhosts.tmp`
ACC_KEYS_TMP=`date +%y%m%d-%H%M%S-home-ssh-authorizedkeys.tmp`

## ARRAYS:
#  arrays are commented-out since they shall not be initiated in bash (because following initiation they'd have an undesired zero-elmement)
#NODES_ARRAY=("")       # host names from input
#SIZES_ARRAY=("")
#LINODE_ID_ARRAY=("")
#PUBLIC_IP_ARRAY=("")
#PRVATE_IP_ARRAY=("")
#SSH_FINGERPRT_A=("")   # ssh finger print array
####SSH_PUBL_CERT_A=("")  # pub certs contain space-characters, therefore not usefull in the same way as like SSH_FINGERPRT_A
#IDS_TO_DELETE=("")


## INTEGERS:
NODE_LAST_INDEX=-1      # after parsing the input, will contain last node input; for loops. 

## BOOLEANS:
VERBOSE=false
QUERY=false
DELETING=false
FIREWALL=false

####################
# Argument parsing #
####################

echo -e "`date +%y%m%d-%H%M`\t${0} $@"  | sed 's/--token\ [0-9a-h]*/--token\ XXXXXXXXXXXXXXXX/1' >> $LOG_FILE

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
        -f | --firewall)
            FIREWALL_ID="${2}"
            FIREWALL=true
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
            echo -e "\n   == List of IMAGES ==\n" 
            curl -s https://api.linode.com/v4/images | python -mjson.tool | grep -A 2 \"id\":
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
        -d | --delete)
            DELETING=true
            while [[ ! -z ${2} ]] && [[ ! ${2:0:1} == "-" ]]; do
                IDS_TO_DELETE+=("${2}")
                shift
            done             
            echo "DELETING..."
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



########################
# Initial common tests #
########################

# no token? get help
if [ -z "${TOKEN}" ];  then echo "ERROR: No token provided.  See the help page.";  helpme;  fi
if $VERBOSE; then echo "<<"$TOKEN">>"; fi
# TODO: bad token? notify!


NODE_LAST_INDEX=$(( ${#NODES_ARRAY[@]} - 1 ))
DELE_LAST_INDEX=$(( ${#IDS_TO_DELETE[@]} - 1 ))

if $VERBOSE; then set -x; fi



################
# Delete nodes #
################

if [ ${DELETING} = "true" ]; then

    for ANINDEX in $(seq 0 $DELE_LAST_INDEX); do

        NODE_ID_NUM=${IDS_TO_DELETE[$ANINDEX]}

        # curl generates 1-liner yaml  |  sed splits into lines  |  grep choses label-line only  |  sed then cuts all before label-text and after label-text
        NODE_NAME=`curl -s -H "Authorization: Bearer $TOKEN" https://api.linode.com/v4/linode/instances/${NODE_ID_NUM} | sed 's/,/\n/g' | grep label | sed 's/^.*:\ "//1' | sed 's/".*//1'`

        echo "-->   == DELETING  id=$NODE_ID_NUM  label=$NODE_NAME... =="
        read -p "         You sure? (yes/no, default: no) " yn

        case $yn in 
            yes )
                OUTPUT=`curl -s -H "Authorization: Bearer $TOKEN" -X DELETE https://api.linode.com/v4/linode/instances/$NODE_ID_NUM`;
                echo ${OUTPUT};
                echo -e "`date +%y%m%d-%H%M`\tdeleting ${NODE_ID_NUM}, ${OUTPUT}" >> $LOG_FILE;;
            * ) echo "Skiped.";
                echo -e "`date +%y%m%d-%H%M`\tskipping ${NODE_ID_NUM}" >> $LOG_FILE;;
        esac

    done

    exit 0;
fi


#######################
# More specific tests #
#######################

if [ ${DELETING} = "false" ]; then

    # in case of incorrect node-size (a.k.a. node-type) array length, populate the array with defaults
    if ! [ ${#NODES_ARRAY[@]} = ${#SIZES_ARRAY[@]} ]; then
        echo "WARNINIG: Assuming the default nod size/type of: ${TYPE} because \"--sizes\" array is not the same length as \"--nodelist\" array."
        for ANINDEX in $(seq 0 $NODE_LAST_INDEX); do
            SIZES_ARRAY+=("${TYPE}")
        done
    fi


    echo -e "\n\n" > ${HOSTFILE_TMP}
    if ! [ -f ${HOSTFILE_TMP} ]; then          echo "ERROR: Temporary hostfile ${HOSTFILE_TMP} cannot be written or read.  Fix that, please.";  exit 1;  fi
    echo -e "\n\n" > ${KNOWNHST_TMP}
    if ! [ -f ${KNOWNHST_TMP} ]; then          echo "ERROR: Temporary known_hosts ${KNOWNHST_TMP} cannot be written or read.  Fix that, please.";  exit 1;  fi
    if ! [ -f ${CERT_FILE} ]; then             echo "WARNINIG: Certificate file cannot be read. If you provided no password, you will have troubles logging into your new nodes."; fi

fi





###############
# Spawn nodes #
###############

CERT_ESCAPED=`cat $CERT_FILE | sed 's:\/:\\\/:g'`

echo -e "LINODE_ID\tNODENAME\tLI_PUB_IP\tLI_PRV_IP\tNODESIZE\tIMAGE\tREGIO" >> $LOG_FILE

echo -e "\n\n"

for ANINDEX in $(seq 0 $NODE_LAST_INDEX); do

    NODENAME=${NODES_ARRAY[$ANINDEX]}
    NODESIZE=${SIZES_ARRAY[$ANINDEX]}
    
    echo -e "\n-->   == Rolling out $NODENAME ==\n"

    YAML_PAYLOAD="{\"type\": \""$NODESIZE"\", \"region\": \""$REGIO"\", \"image\": \""$IMAGE"\", \"root_pass\": \""$PASSW"\", \"label\": \""$NODENAME"\", \"authorized_keys\": [\""$CERT_ESCAPED"\"] }"

    OUTPUT=`curl --progress-bar -X POST https://api.linode.com/v4/linode/instances -H "Authorization: Bearer $TOKEN" -H "Content-type: application/json" -d "$YAML_PAYLOAD"`

    # Temp debug
    # echo "$OUTPUT" >> temp.debug.output.log

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

    # Temp debug
    # echo "$OUTPUT" >> temp.debug.output.log

    # add a hostsfile entry for that machine
    echo -e "${LI_PRV_IP}\t${NODENAME}" >> ${HOSTFILE_TMP}
    echo "created " $LINODE_ID $NODENAME $LI_PUB_IP $LI_PRV_IP >> ${LOG_FILE}
    echo "Server pas: $PASSW"

    # a wait period being a dirty fix for keeping the command queue (server creation queue)
    # from filling up to more than 10.  A rule of thumb. UNOFFICIAL, DIRTY FIX.
    sleep 8

done



###################
# Readiness check #
#  and data scan  #
###################

echo -e "\n-->   == Readiness check and data collection =="

for ANINDEX in $(seq 0 $NODE_LAST_INDEX); do

    IP_PRIV=${PRVATE_IP_ARRAY[$ANINDEX]}
    IP_PUBL=${PUBLIC_IP_ARRAY[$ANINDEX]}
    NODE_ID=${LINODE_ID_ARRAY[$ANINDEX]}
    NODNAME=${NODES_ARRAY[$ANINDEX]}
    IS_REDY=false

    echo -n -e "\nWaiting for ${NODNAME} to get ready: "
    
    while ! ${IS_REDY}; do  # IS_REDY contains function name as used for calling: functionName=false() xor functionName=true(), which always finishes with (bool)true xor (bool)false.
    
        OUTPUT=`curl -s -X GET https://api.linode.com/v4/linode/instances/$NODE_ID -H "Authorization: Bearer ${TOKEN}"`
        STATUS=`echo $OUTPUT | grep -E -o status.*$ | cut -d\" -f3`
        
        if [ ${STATUS} = "running" ]; then
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
        echo " \- wait some more for ecdsa signature of $IP_PUBL ($NODNAME)..."
        sleep 12
        OUTPUT=`ssh-keyscan -t ecdsa ${IP_PUBL} 2>&1 | grep ecdsa`  # not the best practice to write functions (despite inline!) TWICE (2)
    done
    SSH_FP_COMPLETE="${NODNAME},${IP_PRIV},${OUTPUT}"           # IP_PUB is included anyway in the ssh-keyscan output, at the beginning
    SSH_FINGERPRT_A+=(${SSH_FP_COMPLETE})

    echo ${SSH_FP_COMPLETE}                                     #
    echo ${SSH_FP_COMPLETE} >> ${KNOWNHST_TMP}                  # ecdsa fingerprint: to OPERATOR CONSOLE, and to TEMP_FILE
    echo ${NODNAME},${OUTPUT} >> ~/.ssh/known_hosts             #                    and to LOCAL known_hosts file
    
    # generate ssh key-pair on nodes.  BEWARE: the entrophy on all newly created nodes may be "the same", with little difference,
    # based on the image used for the node, which brings SECURITY QUESTIONS about the quality of such ssh keys

    ssh root@${IP_PUBL} "ssh-keygen -f ~/.ssh/id_rsa -q -P ''"
    # and record public keys
    SERVER_PUB_CERT=`ssh root@${IP_PUBL} "cat ~/.ssh/id_rsa.pub"`
    echo $SERVER_PUB_CERT >> $ACC_KEYS_TMP
    #SSH_PUBL_CERT_A+=(${SERVER_PUB_CERT})                       # pub keys for saving later in use in ~/.ssh/authorized_keys of all nodes, so all-to-all have the connectivity
        
    echo "Sever $NODENAME .ssh/rsa_id.pub is: $SERVER_PUB_CERT"
    
done


##############################
# Propagate stuff to servers #
##############################
#
# create hostsfile entries
# create known_hosts entries
#
# copy-ssh-key # i.e. add all to known_hosts
# 

# looping the nodes
for ANINDEX in $(seq 0 $NODE_LAST_INDEX); do

    IP_PUBL=${PUBLIC_IP_ARRAY[$ANINDEX]}
    NODNAME=${NODES_ARRAY[$ANINDEX]}

    echo -e "\n-->   == Propagating data to $NODENAME =="

    # propagate hostsfile
    cat ${HOSTFILE_TMP} | ssh root@${IP_PUBL} "dd >> /etc/hosts; dd >> /etc/hosts"
    echo "${NODNAME} received HOSTS-FILE."

    # propagate .ssh/known_hosts
    cat ${KNOWNHST_TMP} | ssh root@${IP_PUBL} "dd >> /root/.ssh/known_hosts; dd >> /root/.ssh/known_hosts"
    echo "${NODNAME} received KNOWN_HOSTS."
    
    # create autorized_keys if it's missing
    # cat >> auth_k # is in order to add a possibly missing tailing eol.
    ssh root@${IP_PUBL} "mkdir -p ~/.ssh/; echo >> ~/.ssh/authorized_keys; chmod 700 ~/.ssh/; chmod 600 ~/.ssh/authorized_keys"
    cat ${ACC_KEYS_TMP} | ssh root@${IP_PUBL} "dd >> /root/.ssh/authorized_keys"
    echo "${NODNAME} received SSH CERTs of all other nodes."

    # yum install object storage tools
    # LOL, maybe: ssh help or cowasy greeting on remote node installed

    echo -n "${NODNAME}: Populate the /etc/hostname... "
    ssh root@${IP_PUBL} "echo $NODNAME > /etc/hostname"
    echo "Done."

    echo -n "${NODNAME}: Creating swap space... "
    ssh root@${IP_PUBL} "swapoff -a; dd if=/dev/zero of=/swapfile bs=1MiB count=2048; chmod 0600 /swapfile; mkswap /swapfile; echo '/swapfile swap swap defaults 0 0' >> /etc/fstab; swapon -a"
    echo "The swap created."

    echo -n "${NODNAME}: Disabling selinux (enforcing-->permissive)... "
    ssh root@${IP_PUBL} "sed 's/^SELINUX=enforcing$/SELINUX=permissive/1' /etc/selinux/config -i"
    echo "Done.  REMEMBER TO REBOOT."

    echo "ONLY FOR SOME VERSIONS 9.2"
    ssh root@${IP_PUBL} 'echo -e "\nmodule(load=\"imudp\")\ninput(type=\"imudp\" port=\"514\")" >> /etc/rsyslog.conf; systemctl restart rsyslog'
    echo -n "${NODNAME}: syslog UDP reception setup done."

    echo -n "${NODNAME}: CPU performance adjusting... "
    ssh root@${IP_PUBL} "tuned-adm profile throughput-performance"
    echo "Now is \"throughput-performance\"."

    echo "${NODNAME}: NOT disabling firewall untill the node is added to a fw-aas firewall above (TODO) or manually."
    ### ssh root@${IP_PUBL} "systemctl stop firewalld; systemctl disable firewalld"

    echo -n "${NODNAME}: Rebooting... "
    ssh root@${IP_PUBL} "reboot"
    echo "Done!"

done

echo;
echo -e "\n-->   == All DONE. Temp files summary below ==\n"

echo -e "\n-->   == Summary for hosts file ==               hosts-file to propagate:"
cat ${HOSTFILE_TMP}
echo -e "\n-->   == Summary for known hosts file ==         known_hosts-file to propagate:"
cat ${KNOWNHST_TMP}
echo -e "\n-->   == Summary of authorized keys file ==      authorized_keys-file to propagate:"
cat ${ACC_KEYS_TMP}
echo -e "\n"

    
    # ssh ${IP_ADDR} "reboot"

exit

#  | python -mjson.tool
