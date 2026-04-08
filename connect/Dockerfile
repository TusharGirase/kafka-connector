FROM confluentinc/cp-kafka-connect:7.5.0

# JDBC Source connector
RUN confluent-hub install --no-prompt confluentinc/kafka-connect-jdbc:10.7.4

# Oracle JDBC driver
RUN curl -L https://download.oracle.com/otn-pub/otn_software/jdbc/233/ojdbc11.jar \
    -o /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/ojdbc11.jar

# MongoDB Kafka Connector (uber-jar with all deps)
RUN mkdir -p /usr/share/confluent-hub-components/mongodb-kafka-connect && \
    curl -L "https://repo1.maven.org/maven2/org/mongodb/kafka/mongo-kafka-connect/1.11.0/mongo-kafka-connect-1.11.0-all.jar" \
    -o /usr/share/confluent-hub-components/mongodb-kafka-connect/mongo-kafka-connect-1.11.0-all.jar

# Debezium Oracle CDC connector (full plugin tar with all deps)
RUN mkdir -p /usr/share/confluent-hub-components/debezium-oracle && \
    curl -L "https://repo1.maven.org/maven2/io/debezium/debezium-connector-oracle/2.4.1.Final/debezium-connector-oracle-2.4.1.Final-plugin.tar.gz" \
    -o /tmp/debezium-oracle.tar.gz && \
    tar -xzf /tmp/debezium-oracle.tar.gz -C /usr/share/confluent-hub-components/debezium-oracle --strip-components=1 && \
    rm /tmp/debezium-oracle.tar.gz && \
    cp /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/ojdbc11.jar \
       /usr/share/confluent-hub-components/debezium-oracle/ojdbc11.jar
