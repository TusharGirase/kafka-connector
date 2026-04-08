package com.poc;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.*;
import org.apache.kafka.streams.kstream.*;

import java.util.Properties;

/**
 * Reads Debezium CDC events from:
 *   oracle.APPUSER.EMPLOYEES    (after-image: ID, NAME, DEPT_ID, SALARY)
 *   oracle.APPUSER.DEPARTMENTS  (after-image: ID, NAME, LOCATION)
 *
 * Joins on EMPLOYEES.DEPT_ID == DEPARTMENTS.ID
 *
 * Produces enriched document to topic: enriched.employees
 * {
 *   "employeeId": 1,
 *   "name": "Alice",
 *   "salary": 90000,
 *   "department": "Engineering",
 *   "location": "Pune"
 * }
 */
public class EmployeeEnrichmentApp {

    static final ObjectMapper MAPPER = new ObjectMapper();

    public static void main(String[] args) {
        Properties props = new Properties();
        props.put(StreamsConfig.APPLICATION_ID_CONFIG, "employee-enrichment");
        props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG,
                System.getenv().getOrDefault("KAFKA_BOOTSTRAP", "localhost:9092"));
        props.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String().getClass());
        props.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, Serdes.String().getClass());

        StreamsBuilder builder = new StreamsBuilder();

        // ── DEPARTMENTS table → KTable keyed by dept ID ──────────────────────
        // Re-key from Debezium key {"ID":1} to plain "1"
        KTable<String, String> deptTable = builder
                .stream("oracle.APPUSER.DEPARTMENTS")
                .filter((k, v) -> v != null)                          // drop tombstones
                .map((k, v) -> {
                    try {
                        JsonNode payload = MAPPER.readTree(v).path("payload");
                        JsonNode after = payload.path("after");
                        if (after.isMissingNode() || after.isNull()) return null;
                        String deptId = String.valueOf((int) after.path("ID").asDouble());
                        return KeyValue.pair(deptId, after.toString());
                    } catch (Exception e) { return null; }
                })
                .filter((k, v) -> k != null)
                .toTable(Materialized.as("dept-store"));

        // ── EMPLOYEES stream re-keyed by DEPT_ID for the join ─────────────────
        KStream<String, String> empStream = builder
                .stream("oracle.APPUSER.EMPLOYEES")
                .filter((k, v) -> v != null)
                .map((k, v) -> {
                    try {
                        JsonNode payload = MAPPER.readTree(v).path("payload");
                        String op = payload.path("op").asText();
                        JsonNode after = payload.path("after");
                        if (after.isMissingNode() || after.isNull()) return null;
                        String deptId = String.valueOf((int) after.path("DEPT_ID").asDouble());
                        // carry op in value so we can handle deletes downstream
                        ((ObjectNode) after).put("_op", op);
                        return KeyValue.pair(deptId, after.toString());
                    } catch (Exception e) { return null; }
                })
                .filter((k, v) -> k != null);

        // ── JOIN: enrich employee with department info ─────────────────────────
        empStream
                .join(deptTable,
                        (empJson, deptJson) -> {
                            try {
                                JsonNode emp  = MAPPER.readTree(empJson);
                                JsonNode dept = MAPPER.readTree(deptJson);
                                ObjectNode out = MAPPER.createObjectNode();
                                out.put("employeeId",  (int) emp.path("ID").asDouble());
                                out.put("name",        emp.path("NAME").asText());
                                out.put("salary",      emp.path("SALARY").asLong());
                                out.put("department",  dept.path("NAME").asText());
                                out.put("location",    dept.path("LOCATION").asText());
                                out.put("_op",         emp.path("_op").asText());
                                return out.toString();
                            } catch (Exception e) { return null; }
                        },
                        Joined.with(Serdes.String(), Serdes.String(), Serdes.String()))
                // Re-key by employeeId so MongoDB sink can upsert by it
                .map((deptId, v) -> {
                    try {
                        JsonNode doc = MAPPER.readTree(v);
                        return KeyValue.pair(
                                String.valueOf(doc.path("employeeId").asInt()), v);
                    } catch (Exception e) { return KeyValue.pair(deptId, v); }
                })
                .to("enriched.employees");

        KafkaStreams streams = new KafkaStreams(builder.build(), props);
        Runtime.getRuntime().addShutdownHook(new Thread(streams::close));
        streams.start();
        System.out.println("Employee enrichment stream started.");
    }
}
