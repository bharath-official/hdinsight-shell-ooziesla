#!/bin/bash

USERNAME=$1
PASSWORD=$2
CLUSTERNAME=$3
ACTIVEAMBARIHOST=headnodehost
AMBARICONFIGS_SH=/var/lib/ambari-server/resources/scripts/configs.sh
PORT=8080

#Download ActiveMQ
downloadActiveMQ() {
        sudo mkdir /opt/ActiveMQ
        cd /opt/ActiveMQ
        sudo wget https://archive.apache.org/dist/activemq/5.14.3/apache-activemq-5.14.3-bin.tar.gz
        if [[ $? -ne 0 ]]; then
                echo "Failed to download ActiveMQ"
                exit 100
        fi
        sudo tar -xvf apache-activemq-5.14.3-bin.tar.gz
}


#Start ActiveMQ
startActiveMQ() {
        sudo chmod -R 775 /opt/ActiveMQ
        sudo chown -R root:root /opt/ActiveMQ
        cd /opt/ActiveMQ/apache-activemq-5.14.3/bin/
        sudo ./activemq start
        if [[ $? -ne 0 ]]; then
                echo "Failed to start ActiveMQ"
                exit 101
        fi
        cd $HOME
}


#Build Oozie Configs for JMS and Event Handler
updateOozieConfigs() {
        updateResult=$(bash $AMBARICONFIGS_SH -u $USERNAME -p $PASSWORD set $ACTIVEAMBARIHOST $CLUSTERNAME oozie-site "oozie.services.ext" "org.apache.oozie.service.JMSAccessorService,org.apache.oozie.service.PartitionDependencyManagerService,org.apache.oozie.service.HCatAccessorService,org.apache.oozie.service.ZKLocksService,org.apache.oozie.service.ZKXLogStreamingService,org.apache.oozie.service.ZKJobsConcurrencyService,org.apache.oozie.service.ZKUUIDService,org.apache.oozie.service.JMSTopicService,org.apache.oozie.service.EventHandlerService,org.apache.oozie.sla.service.SLAService"
)

        if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
                        echo "[ERROR] Failed to update oozie-site for oozie-service.ext. Exiting!"
                        echo $updateResult
                        exit 102
        fi

        updateResult=$(bash $AMBARICONFIGS_SH -u $USERNAME -p $PASSWORD set $ACTIVEAMBARIHOST $CLUSTERNAME oozie-site "oozie.service.EventHandlerService.event.listeners" "org.apache.oozie.jms.JMSJobEventListener,org.apache.oozie.sla.listener.SLAJobEventListener,org.apache.oozie.jms.JMSSLAEventListener,org.apache.oozie.sla.listener.SLAEmailEventListener")

        if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
                        echo "[ERROR] Failed to update oozie-site for EventHandlerService.event.listeners. Exiting!"
                        echo $updateResult
                        exit 103
        fi

        updateResult=$(bash $AMBARICONFIGS_SH -u $USERNAME -p $PASSWORD set $ACTIVEAMBARIHOST $CLUSTERNAME oozie-site "oozie.service.SchedulerService.threads" "15")

        if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
                        echo "[ERROR] Failed to update oozie-site for SchedulerService.threads. Exiting!"
                        echo $updateResult
                        exit 104
        fi

        updateResult=$(bash $AMBARICONFIGS_SH -u $USERNAME -p $PASSWORD set $ACTIVEAMBARIHOST $CLUSTERNAME oozie-site "oozie.jms.producer.connection.properties" "default=java.naming.factory.initial#org.apache.activemq.jndi.ActiveMQInitialContextFactory;java.naming.provider.url#tcp://<ActiveMQ server>:61616")

        if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
                        echo "[ERROR] Failed to update oozie-site for jms.producer.connection.properties. Exiting!"
                        echo $updateResult
                        exit 105
        fi

        updateResult=$(bash $AMBARICONFIGS_SH -u $USERNAME -p $PASSWORD set $ACTIVEAMBARIHOST $CLUSTERNAME oozie-site "oozie.service.JMSTopicService.topic.prefix" "")

        if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
                        echo "[ERROR] Failed to update oozie-site for SchedulerService.threads. Exiting!"
                        echo $updateResult
                        exit 106
        fi
}

#Stop Oozie Service
stopOozieServiceViaRest() {
    SERVICENAME=OOZIE
    echo "Stopping $SERVICENAME"
    curl -u $USERNAME:$PASSWORD -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Stop Oozie Service"}, "Body": {"ServiceInfo": {"state": "INSTALLED"}}}' http://$ACTIVEAMBARIHOST:$PORT/api/v1/clusters/$CLUSTERNAME/services/$SERVICENAME
}

#Start Oozie Service
startOozieServiceViaRest() {
        SERVICENAME=OOZIE
    echo "Starting $SERVICENAME"
    startResult=$(curl -u $USERNAME:$PASSWORD -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start Oozie Service"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' http://$ACTIVEAMBARIHOST:$PORT/api/v1/clusters/$CLUSTERNAME/services/$SERVICENAME)
    if [[ $startResult == *"500 Server Error"* || $startResult == *"internal system exception occurred"* ]]; then
        sleep 60
        echo "Retry starting $SERVICENAME"
        startResult=$(curl -u $USERNAME:$PASSWORD -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Retrying to start Oozie Service"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' http://$ACTIVEAMBARIHOST:$PORT/api/v1/clusters/$CLUSTERNAME/services/$SERVICENAME)
    fi
    echo $startResult
}

nodename=$(hostname -f | head -c 3)
if [ "$nodename" = "hn0" ]
then
        downloadActiveMQ
        startActiveMQ
        updateOozieConfigs
        stopOozieServiceViaRest
        sleep 60
        startOozieServiceViaRest
fi
