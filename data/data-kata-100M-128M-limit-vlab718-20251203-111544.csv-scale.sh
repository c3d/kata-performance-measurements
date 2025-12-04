#!/bin/bash
DATA=data-${2:-default}-$(hostname)-$(date +'%Y%m%d-%H%M%S').csv
CLUSTER=kata420
WORKERS=4
TARGET_COUNT=${1:-100}

cp workload.yaml ${DATA}-workload.yaml
cp $0 ${DATA}-scale.sh

echo "Start,GetPodsTime,Wanted,Running,Creating,Pending,Terminating,Error,Total Active Memory,Total Free Memory,Total Available,Total Buffers,Total Cached,Active,0,1,2,3,Free,0,1,2,3,Available,0,1,2,3,Buffers,0,1,2,3,Cached,0,1,2,3" > $DATA

oc login -u kubeadmin -p $(cat ~/.kcli/clusters/$CLUSTER/auth/kubeadmin-password)

for ((I = 0; I < $TARGET_COUNT; I++))
do
    START=$SECONDS
    echo "Iteration $I starting at $START, $(date)"
    oc scale --replicas=$I -f workload.yaml || (oc login -u kubeadmin -p $(cat ~/.kcli/clusters/$CLUSTER/auth/kubeadmin-password) && oc scale --replicas=$I -f workload.yaml)
    while ! (oc get pods > pods); do
	echo -n .
    done
    ELAPSED=$(($SECONDS - $START))
    RUNNING=$(grep Running pods | wc -l)
    CREATING=$(grep ContainerCreating pods | wc -l)
    PENDING=$(grep Pending pods | wc -l)
    TERMINATING=$(grep Terminating pods | wc -l)
    ERRORING=$(grep Error\\\|Crash pods | wc -l)
    echo "  Containers started at $(date) in $ELAPSED seconds"
    echo "  Want $I containers: $RUNNING running, $CREATING creating, $PENDING pending, $TERMINATING terminating, $ERRORING in error"
    ALL_ACTIVE=""
    ALL_FREE=""
    ALL_AVAILABLE=""
    ALL_BUFFERS=""
    ALL_CACHED=""

    TOTAL_ACTIVE=0
    TOTAL_FREE=0
    TOTAL_AVAILABLE=0
    TOTAL_BUFFERS=0
    TOTAL_CACHED=0
    for ((W=0; W<$WORKERS; W++))
    do
	while ! kcli ssh ${CLUSTER}-worker-$W cat /proc/meminfo > meminfo
        do
            echo "kcli ssh failed, retrying"
            sleep 1
        done
        ACTIVE=$(grep Active: meminfo | awk '{ print $2 }')
        FREE=$(grep MemFree: meminfo | awk '{ print $2 }')
        AVAILABLE=$(grep MemAvailable: meminfo | awk '{ print $2 }')
        BUFFERS=$(grep Buffers: meminfo | awk '{ print $2 }')
        CACHED=$(grep '^Cached:' meminfo | awk '{ print $2 }')
        ALL_ACTIVE="$ALL_ACTIVE,$ACTIVE"
        ALL_FREE="$ALL_FREE,$FREE"
        ALL_AVAILABLE="$ALL_AVAILABLE,$AVAILABLE"
        ALL_BUFFERS="$ALL_BUFFERS,$BUFFERS"
        ALL_CACHED="$ALL_CACHED,$CACHED"
        TOTAL_ACTIVE=$(($TOTAL_ACTIVE + $ACTIVE))
        TOTAL_FREE=$(($TOTAL_FREE + $FREE))
        TOTAL_AVAILABLE=$(($TOTAL_AVAILABLE + $AVAILABLE))
        TOTAL_BUFFERS=$(($TOTAL_BUFFERS + $BUFFERS))
        TOTAL_CACHED=$(($TOTAL_CACHED + $CACHED))
    done
    echo "$START,$ELAPSED,$I,$RUNNING,$CREATING,$PENDING,$TERMINATING,$ERRORING,$TOTAL_ACTIVE,$TOTAL_FREE,$TOTAL_AVAILABLE,$TOTAL_BUFFERS,$TOTAL_CACHED,$ALL_ACTIVE,$ALL_FREE,$ALL_AVAILABLE,$ALL_BUFFERS,$ALL_CACHED" >> $DATA
done

oc scale --replicas=1 -f workload.yaml || (oc login -u kubeadmin -p $(cat ~/.kcli/clusters/$CLUSTER/auth/kubeadmin-password) && oc scale --replicas=1 -f workload.yaml)
