#!/bin/bash
mv -f data.csv data-$(date +%Y%m%d-%H%M%S).csv

kill $(ps -ef | grep "ssh ph ssh" | awk ' { print $2 } ')

for ((W=0; W<5; W++))
do
    ssh ph "ssh core@worker-0-$W 'while true; do cat /proc/meminfo; sleep 5; done' " > memory$W.out &
done

echo "Iteration,Elapsed,Running,Creating,Terminating,Evicted,Total Active Memory,Total Free Memory, Active,0,1,2,3,4,Free,0,1,2,3,4" > data.csv

for ((I = 1; I < 1000; I++))
do
    START=$SECONDS
    echo "Iteration $I starting after $START seconds, date $(date)"
    oc login -s $CLUSTER -u kubeadmin --password $PASSWORD
    oc scale --replicas=$I -f workload.yaml
    sleep 5
    ELAPSED=$SECONDS
    echo "Done"
    echo "  Containers started at $(date) in $ELAPSED seconds"
    echo "  Running: $RUNNING, Creating: $CREATING, Terminating: $TERMINATING, Evicted: $EVICTED"
    ALL_ACTIVE=""
    ALL_FREE=""
    TOTAL_ACTIVE=0
    TOTAL_FREE=0
    for ((W=0; W<5; W++))
    do
        ACTIVE=$(tail -50 memory$W.out | grep Active: | awk '{ print $2 }')
        FREE=$(tail -50 memory$W.out | grep MemFree: | awk '{ print $2 }')
	ACTIVE=${ACTIVE:-0}
	FREE=${FREE:-0}
        ALL_ACTIVE="$ALL_ACTIVE,$ACTIVE"
        ALL_FREE="$ALL_FREE,$FREE"
        TOTAL_ACTIVE=$(($TOTAL_ACTIVE + $ACTIVE))
        TOTAL_FREE=$(($TOTAL_FREE + $FREE))
    done
    oc get pods > pods.out
    RUNNING=$(grep Running pods.out | wc -l)
    CREATING=$(grep ContainerCreating pods.out | wc -l)
    TERMINATING=$(grep Terminating pods.out | wc -l)
    EVICTED=$(grep Evicted pods.out | wc -l)
    echo "$I,$ELAPSED,$RUNNING,$CREATING,$TERMINATING,$EVICTED,$TOTAL_ACTIVE,$TOTAL_FREE,$ALL_ACTIVE,$ALL_FREE" >> data.csv
done
